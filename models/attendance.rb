class Attendance
  include Mongoid::Document
  include Mongoid::Timestamps
  extend Dragonfly::Model

  belongs_to :tactivity, index: true
  belongs_to :account, index: true
  belongs_to :gathering, index: true
  belongs_to :membership, index: true

  def self.admin_fields
    {
      tactivity_id: :lookup,
      account_id: :lookup,
      gathering_id: :lookup,
      membership_id: :lookup
    }
  end

  before_validation do
    self.gathering = tactivity.gathering if tactivity
    self.membership = gathering.memberships.find_by(account: account) if gathering && account && !membership
  end

  validates_uniqueness_of :tactivity, scope: :account
end
