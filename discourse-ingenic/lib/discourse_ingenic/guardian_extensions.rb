# frozen_string_literal: true

module DiscourseIngenic
  module GuardianExtensions
    def can_manage_ingenic_permissions?
      is_admin?
    end

    def can_manage_ingenic_content?
      Ingenic::PermissionResolver.new(user).can_manage_any_content?
    end

    def can_manage_ingenic_doc_product?(product)
      Ingenic::PermissionResolver.new(user).can_manage?(product)
    end

    def can_manage_ingenic_doc_version?(version)
      Ingenic::PermissionResolver.new(user).can_manage?(version)
    end

    def can_manage_ingenic_doc_page?(page)
      Ingenic::PermissionResolver.new(user).can_manage?(page)
    end

    def can_manage_ingenic_board?(board)
      Ingenic::PermissionResolver.new(user).can_manage?(board)
    end
  end
end
