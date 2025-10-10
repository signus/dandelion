class EventFeedback
  include Mongoid::Document
  include Mongoid::Timestamps
  include BelongsToWithoutParentValidation

  include Mongoid::Paranoia

  belongs_to_without_parent_validation :event, index: true, optional: true
  belongs_to_without_parent_validation :account, index: true

  has_many :account_contributions, dependent: :nullify

  has_many :notifications, as: :notifiable, dependent: :destroy

  field :answers, type: Array
  field :public, type: Boolean
  field :anonymise, type: Boolean
  field :public_answers, type: Array
  field :rating, type: Integer
  field :response, type: String

  def self.admin_fields
    {
      rating: :radio,
      public: :check_box,
      anonymise: :check_box,
      answers: { type: :text_area, disabled: true },
      public_answers: { type: :text_area, disabled: true },
      response: :text_area,
      event_id: :lookup,
      account_id: :lookup
    }
  end

  validates_uniqueness_of :event, scope: :account, allow_nil: true, conditions: -> { where(deleted_at: nil) }

  after_save do
    event.clear_cache if event
  end
  after_destroy do
    event.clear_cache if event
  end

  def circle
    account
  end

  after_create do
    notifications.create! circle: circle, type: 'left_feedback' unless anonymise
  end

  def self.average_rating
    ratings = self.and(:deleted_at => nil, :rating.ne => nil).pluck(:rating)
    return if ratings.empty?

    ratings = ratings.map(&:to_i)
    (ratings.inject(:+).to_f / ratings.length).round(1)
  end

  def self.ratings
    1.upto(5).to_h do |i|
      [i.times.map { '<i class="bi bi-star-fill"></i>' }.join, i]
    end
  end

  def self.update_event_feedbacks_as_facilitator_counts
    Account.and(:event_feedbacks_as_facilitator_count.ne => nil).set(event_feedbacks_as_facilitator_count: nil)
    Account.and(:id.in => EventFacilitation.pluck(:account_id)).each do |account|
      account.set(event_feedbacks_as_facilitator_count: account.unscoped_event_feedbacks_as_facilitator.count)
    end
  end

  after_create :send_feedback
  def send_feedback
    return unless event

    mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY'], ENV['MAILGUN_REGION']
    batch_message = Mailgun::BatchMessage.new(mg_client, ENV['MAILGUN_NOTIFICATIONS_HOST'])

    event_feedback = self
    event = event_feedback.event
    content = ERB.new(File.read(Padrino.root('app/views/emails/event_feedback.erb'))).result(binding)
    batch_message.from ENV['NOTIFICATIONS_EMAIL_FULL']
    batch_message.subject "#{event_feedback.rating.times.each.map { '★' }.join if event_feedback.rating} #{event.name}/#{event_feedback.anonymise? ? 'Anonymous' : event_feedback.account.name}"
    batch_message.body_html Premailer.new(ERB.new(File.read(Padrino.root('app/views/layouts/email.erb'))).result(binding), with_html_string: true, adapter: 'nokogiri', input_encoding: 'UTF-8').to_inline_css

    event.accounts_receiving_feedback.each do |account|
      batch_message.add_recipient(:to, account.email, { 'firstname' => account.firstname || 'there', 'token' => account.sign_in_token, 'id' => account.id.to_s })
    end

    batch_message.finalize if ENV['MAILGUN_API_KEY']
  end
  handle_asynchronously :send_feedback

  def send_response
    return if anonymise
    return unless response

    mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY'], ENV['MAILGUN_REGION']
    batch_message = Mailgun::BatchMessage.new(mg_client, ENV['MAILGUN_NOTIFICATIONS_HOST'])

    event_feedback = self
    event = event_feedback.event
    content = ERB.new(File.read(Padrino.root('app/views/emails/event_feedback_response.erb'))).result(binding)
    batch_message.from ENV['NOTIFICATIONS_EMAIL_FULL']
    batch_message.reply_to(event.email || event.organisation.try(:reply_to))
    batch_message.subject "#{event.organisation.name} responded to your feedback on #{event.name}"
    batch_message.body_html Premailer.new(ERB.new(File.read(Padrino.root('app/views/layouts/email.erb'))).result(binding), with_html_string: true, adapter: 'nokogiri', input_encoding: 'UTF-8').to_inline_css

    [account].each do |account|
      batch_message.add_recipient(:to, account.email, { 'firstname' => account.firstname || 'there', 'token' => account.sign_in_token, 'id' => account.id.to_s })
    end

    batch_message.finalize if ENV['MAILGUN_API_KEY']
  end
  handle_asynchronously :send_response

  def send_destroy_notification(destroyed_by)
    mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY'], ENV['MAILGUN_REGION']
    batch_message = Mailgun::BatchMessage.new(mg_client, ENV['MAILGUN_NOTIFICATIONS_HOST'])

    event_feedback = self
    event = event_feedback.event
    content = ERB.new(File.read(Padrino.root('app/views/emails/event_feedback_destroyed.erb'))).result(binding)
    batch_message.from ENV['NOTIFICATIONS_EMAIL_FULL']
    batch_message.subject "#{destroyed_by.name} deleted feedback for #{event.name}"
    batch_message.body_html Premailer.new(ERB.new(File.read(Padrino.root('app/views/layouts/email.erb'))).result(binding), with_html_string: true, adapter: 'nokogiri', input_encoding: 'UTF-8').to_inline_css

    event.accounts_receiving_feedback.each do |account|
      batch_message.add_recipient(:to, account.email, { 'firstname' => account.firstname || 'there', 'token' => account.sign_in_token, 'id' => account.id.to_s })
    end

    batch_message.finalize if ENV['MAILGUN_API_KEY']
  end
  handle_asynchronously :send_destroy_notification

  def self.joined(since: nil, base_header: '')
    event_feedbacks = order('created_at desc').and(:answers.ne => nil)
    event_feedbacks = event_feedbacks.and(:created_at.gte => since) if since

    event_feedbacks.map do |ef|
      next unless ef.event
      next if ef.answers.all? { |_q, a| a.blank? }

      "#{base_header}# Feedback on #{ef.event.name}, #{ef.event.when_details(ENV['DEFAULT_TIME_ZONE'])} at #{ef.event.location}\n\n#{ef.answers.map { |q, a| "#{base_header}## #{q}\n#{a}" }.join("\n\n")}"
    end.compact.join("\n\n")
  end
end
