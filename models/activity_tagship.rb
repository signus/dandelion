class ActivityTagship
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :activity, index: true
  belongs_to :activity_tag, index: true

  def self.admin_fields
    {
      activity_id: :lookup,
      activity_tag_id: :lookup
    }
  end

  validates_uniqueness_of :activity_tag, scope: :activity

  def activity_tag_name
    activity_tag.name
  end
end
