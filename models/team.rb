class Team
  include Mongoid::Document
  include Mongoid::Timestamps
  include DandelionMongo

  belongs_to_without_parent_validation :gathering, index: true
  belongs_to_without_parent_validation :account, index: true

  field :name, type: String
  field :intro, type: String
  field :budget, type: Integer

  def self.admin_fields
    {
      name: :text,
      intro: :wysiwyg,
      gathering_id: :lookup,
      account_id: :lookup,
      teamships: :collection
    }
  end

  validates_presence_of :name, :gathering

  has_many :teamships, dependent: :destroy

  has_many :posts, as: :commentable, dependent: :destroy
  has_many :subscriptions, as: :commentable, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy
  has_many :comment_reactions, as: :commentable, dependent: :destroy

  has_many :spends, dependent: :nullify
  has_many :inventory_items, dependent: :nullify

  has_many_through :members, through: :teamships, class_name: 'Account'

  attr_accessor :prevent_notifications

  has_many :notifications, as: :notifiable, dependent: :destroy
  after_create do
    notifications.create! circle: circle, type: 'created_team' unless prevent_notifications
  end

  def circle
    gathering
  end

  def discussers
    gathering.discussers.and(:id.in => teamships.and(unsubscribed: false).pluck(:account_id))
  end

  def spent
    spends.pluck(:amount).sum
  end
end
