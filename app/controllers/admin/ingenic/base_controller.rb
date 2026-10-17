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

      # Site-wide content — the homepage slots, the footer, the classification
      # list, the download record — is not filed under a product or a board, so
      # there is no scope for a content manager to be granted over it. It is an
      # administrator's, and this says so rather than leaving each action to
      # discover that a record it cannot describe falls through to nobody.
      def authorize_admin_only!
        raise Discourse::NotFound unless current_user.admin?
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
