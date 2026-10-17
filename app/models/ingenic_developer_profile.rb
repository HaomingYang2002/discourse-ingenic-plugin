# frozen_string_literal: true

# The information a developer supplies once in exchange for access to gated
# downloads.
#
# A profile is filled in once and reused for every resource at the "login plus
# information" level and above, which is the point of the tier: the team wants
# to know who is downloading, not to interrogate them per file.
class IngenicDeveloperProfile < ActiveRecord::Base
  self.table_name = "ingenic_developer_profiles"

  # Required, and deleted with the account rather than kept without it. The
  # ledger keeps a deleted member's movements because the forum's books are not
  # about that person; a profile is the opposite — it is answers about somebody,
  # collected for the team to read, and there is no reading to be done once they
  # are gone.
  belongs_to :user

  validates :user_id, uniqueness: true

  def self.for(user)
    return nil if user.nil?

    find_by(user_id: user.id)
  end

  def value_for(key)
    data.to_h[key.to_s]
  end

  # A one-line summary for the admin queue, without assuming which fields the
  # form has: it walks the configured order and takes the first few answers.
  def summary(limit: 3)
    Ingenic::DeveloperForm.fields
      .filter_map { |field| value = value_for(field[:key]); "#{field[:label]}: #{value}" if value.present? }
      .first(limit)
      .join(" · ")
  end
end
