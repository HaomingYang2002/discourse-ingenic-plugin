# frozen_string_literal: true

module DiscourseIngenic
  class ManagementConstraint
    def matches?(request)
      user = CurrentUser.lookup_from_env(request.env)
      return false unless user

      user.admin? || ::Ingenic::PermissionResolver.new(user).can_manage_any_content?
    rescue Discourse::InvalidAccess, Discourse::ReadOnly
      false
    end
  end
end
