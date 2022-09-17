class Ticket
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Paranoia

  belongs_to :event, index: true
  belongs_to :account, index: true
  belongs_to :order, index: true, optional: true
  belongs_to :ticket_type, index: true, optional: true
  belongs_to :zoomship, index: true, optional: true

  field :price, type: Float
  field :show_attendance, type: Boolean
  field :subscribed_discussion, type: Boolean
  field :checked_in, type: Boolean
  field :checked_in_at, type: Time
  field :name, type: String
  field :email, type: String

  before_validation do
    if email
      e = EmailAddress.error(email)
      errors.add(:email, "- #{e}") if e
    end
  end

  def firstname
    unless name.blank?
      parts = name.split(' ')
      n = if parts.count > 1 && %w[mr mrs ms dr].include?(parts[0].downcase.gsub('.', ''))
            parts[1]
          else
            parts[0]
          end
      n.capitalize
    end
  end

  def self.admin_fields
    {
      summary: { type: :text, edit: false },
      price: :number,
      show_attendance: :check_box,
      checked_in: :check_box,
      name: :text,
      email: :email,
      event_id: :lookup,
      account_id: :lookup,
      order_id: :lookup,
      ticket_type_id: :lookup,
      zoomship_id: :lookup
    }
  end

  after_save do
    event.clear_cache if event
  end
  after_destroy do
    event.clear_cache if event
  end

  def discounted_price
    if price
      p = price.to_f
      p *= ((100 - (order.try(:percentage_discount) || 0)).to_f / 100)
      p *= ((100 - (order.try(:percentage_discount_monthly_donor) || 0)).to_f / 100)
      p.round(2)
    end
  end

  attr_accessor :complementary, :prevent_notifications

  def summary
    "#{event.try(:name)} : #{account.email} : #{ticket_type.try(:name)}"
  end

  has_many :notifications, as: :notifiable, dependent: :destroy

  def circle
    account
  end

  def self.email_viewer?(ticket, account)
    account && (!ticket.order || Order.email_viewer?(ticket.order, account))
  end

  before_validation do
    self.price = ticket_type.price if !price && ticket_type && !complementary

    if new_record?
      errors.add(:ticket_type, 'is full') if ticket_type && (ticket_type.number_of_tickets_available_in_single_purchase < 1)
      if ticket_type && ticket_type.minimum_monthly_donation && (
          !account ||
          !(organisationship = event.organisation.organisationships.find_by(account: account)) ||
          !organisationship.monthly_donation_amount ||
          !(Money.new(organisationship.monthly_donation_amount * 100, organisationship.monthly_donation_currency) >= Money.new(ticket_type.minimum_monthly_donation * 100, event.currency))
        )
        errors.add(:ticket_type, 'is not available to someone donating this amount')
      end
      errors.add(:account, 'already has a ticket to this event') if event && zoomship && event.tickets(true).find_by(account: account)
    end
  end

  after_create do
    # ticket might be destroyed again, so this should move
    event.waitships.find_by(account: account).try(:destroy)
    event.gathering.memberships.create(account: account) if event.gathering
  end

  after_create :update_zoomship_tickets_count, if: :zoomship
  after_destroy :update_zoomship_tickets_count, if: :zoomship
  def update_zoomship_tickets_count
    zoomship.update_attribute(:tickets_count, zoomship.tickets.count)
  end

  def send_ticket
    mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY'], 'api.eu.mailgun.net'
    batch_message = Mailgun::BatchMessage.new(mg_client, 'tickets.dandelion.earth')

    order = event.orders.new
    order.account = account
    account = self.account
    order.tickets = [self]

    content = ERB.new(File.read(Padrino.root('app/views/emails/tickets.erb'))).result(binding)
    batch_message.subject "Ticket to #{event.name}"

    if event.organisation.send_ticket_emails_from_organisation && event.organisation.reply_to && event.organisation.image
      header_image_url = event.organisation.image.url
      batch_message.from event.organisation.reply_to
      batch_message.reply_to event.email
    else
      header_image_url = "#{ENV['BASE_URI']}/images/black-on-transparent-sq.png"
      batch_message.from 'Dandelion <tickets@dandelion.earth>'
      batch_message.reply_to(event.email || event.organisation.reply_to)
    end

    batch_message.body_html Premailer.new(ERB.new(File.read(Padrino.root('app/views/layouts/email.erb'))).result(binding), with_html_string: true, adapter: 'nokogiri', input_encoding: 'UTF-8').to_inline_css

    filename = "dandelion-#{event.name.parameterize}-#{order.id}.pdf"
    tickets_pdf_file = File.new(filename, 'w+')
    tickets_pdf_file.write order.tickets_pdf.render
    tickets_pdf_file.rewind
    batch_message.add_attachment tickets_pdf_file, filename

    [account].each do |account|
      batch_message.add_recipient(:to, account.email, { 'firstname' => (account.firstname || 'there'), 'token' => account.sign_in_token, 'id' => account.id.to_s })
    end

    batch_message.finalize if ENV['MAILGUN_API_KEY']

    tickets_pdf_file.close
    File.delete(filename)
  end
  handle_asynchronously :send_ticket
end
