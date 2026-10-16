# frozen_string_literal: true

class IngenicPermission < ActiveRecord::Base
  self.table_name = "ingenic_permissions"

  # One principal: a member or a group, exactly one of the two, which is what
  # the check constraint in the migration enforces. Both are optional here so a
  # row can name either, and both keys cascade — a permission granted to an
  # account or a group that no longer exists has nothing left to permit, and the
  # constraint means it cannot be kept with its principal blanked either.
  belongs_to :user, optional: true
  belongs_to :group, optional: true

  RESOURCE_TYPES = %w[IngenicDocProduct IngenicDocPage IngenicBoard].freeze
  PERMISSIONS = %w[manage].freeze

  validates :resource_type, inclusion: { in: RESOURCE_TYPES }
  validates :permission, inclusion: { in: PERMISSIONS }
  validates :user, presence: true, unless: :group
  validates :group, presence: true, unless: :user
  validates :resource_id, presence: true
  validate :resource_must_exist

  def resource
    resource_type.constantize.find_by(id: resource_id) if RESOURCE_TYPES.include?(resource_type)
  end

  private

  def resource_must_exist
    return if resource_type.blank? || resource_id.blank?
    return errors.add(:resource_type, :inclusion) unless RESOURCE_TYPES.include?(resource_type)

    errors.add(:resource_id, :invalid) if resource.nil?
  end
end
