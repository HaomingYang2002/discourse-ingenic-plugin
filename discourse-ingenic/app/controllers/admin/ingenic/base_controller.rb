# frozen_string_literal: true

module Admin
  module Ingenic
    class BaseController < ::ApplicationController
      requires_login
      requires_plugin "discourse-ingenic"

      private

      def authorize_ingenic!(record = nil, permissions: false)
        allowed = if permissions
          guardian.can_manage_ingenic_permissions?
        else
          record && ::Ingenic::PermissionResolver.new(current_user).can_manage?(record)
        end
        raise Discourse::NotFound unless allowed
      end

      def authorize_create!(parent = nil)
        allowed = if parent
          ::Ingenic::PermissionResolver.new(current_user).can_manage?(parent)
        else
          current_user.admin?
        end
        raise Discourse::NotFound unless allowed
      end

      def render_record_error(record)
        render_json_error(record)
      end

      def boolean_param(value, default = false)
        return default if value.nil?

        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end
