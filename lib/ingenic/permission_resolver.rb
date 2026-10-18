# frozen_string_literal: true

module Ingenic
  class PermissionResolver
    # The management screen a class belongs to. A class that is not here — a
    # download, say — is still reachable through a per-record grant, but has no
    # feature that says "all of them"; `IngenicDownload` is in the map because a
    # group trusted with the download screen is trusted with every resource on
    # it, and the listing has to agree.
    FEATURE_FOR_CLASS = {
      "IngenicDocProduct" => "documentation",
      "IngenicDocVersion" => "documentation",
      "IngenicDocPage" => "documentation",
      "IngenicBoard" => "boards",
      "IngenicDownload" => "downloads",
    }.freeze

    def initialize(user)
      @user = user
    end

    def admin?
      @user&.admin?
    end

    # Whether a group this account belongs to was given the whole screen. The
    # `everyone` auto-group is included for the same reason it is in `group_ids`
    # below: an administrator who grants it to everyone means it.
    def can_manage_feature?(feature)
      return true if admin?
      return false unless @user

      IngenicGroupPermission.where(group_id: group_ids, feature: feature).exists?
    end

    def can_manage?(record)
      return true if admin?
      return false unless @user

      feature = FEATURE_FOR_CLASS[record.class.name]
      return true if feature && can_manage_feature?(feature)

      scopes = permission_scopes(record)
      scopes.any? do |resource_type, resource_ids|
        IngenicPermission.where(
          permission: "manage",
          resource_type: resource_type,
          resource_id: resource_ids,
        ).where(
          "user_id = :user_id OR group_id IN (:group_ids)",
          user_id: @user.id,
          group_ids: group_ids,
        ).exists?
      end
    end

    def visible_ids(klass)
      return klass.all if admin?

      feature = FEATURE_FOR_CLASS[klass.name]
      return klass.all if feature && can_manage_feature?(feature)

      direct_ids = grants_for(klass.name).pluck(:resource_id)
      if klass == IngenicDocVersion
        product_ids = descendant_ids(
          IngenicDocProduct,
          grants_for("IngenicDocProduct").pluck(:resource_id),
        )
        product_version_ids = IngenicDocVersion.where(product_id: product_ids).pluck(:id)
        return klass.where(id: direct_ids + product_version_ids)
      elsif klass == IngenicDocPage
        product_ids = descendant_ids(IngenicDocProduct, grants_for("IngenicDocProduct").pluck(:resource_id))
        product_page_ids = IngenicDocPage.where(
          version_id: IngenicDocVersion.where(product_id: product_ids).select(:id),
        ).pluck(:id)
        page_ids = descendant_ids(IngenicDocPage, direct_ids)
        return klass.where(id: page_ids + product_page_ids)
      end

      return klass.none if direct_ids.empty?

      klass.where(id: descendant_ids(klass, direct_ids))
    end

    def can_manage_permissions?
      admin?
    end

    def can_manage_any_content?
      return true if admin?
      return false unless @user

      return true if IngenicGroupPermission.where(group_id: group_ids).exists?

      IngenicPermission.where(permission: "manage")
        .where("user_id = :user_id OR group_id IN (:group_ids)", user_id: @user.id, group_ids: group_ids)
        .exists?
    end

    private

    attr_reader :user

    def group_ids
      # `everyone` is an automatic group rather than a row anybody joins, and its
      # id is only known once Discourse has seeded its own groups — so the
      # constant to reach for is the one naming it. `Group::EVERYONE_GROUP_ID`
      # reads like it ought to exist and never has: written that way this raised
      # `NameError` on the first request that asked who may manage anything,
      # which is a 500 for a plain member opening a screen they should simply
      # have been kept out of.
      @group_ids ||= @user.groups.pluck(:id) + [Group::AUTO_GROUPS[:everyone]]
    end

    def grants_for(resource_type)
      IngenicPermission.where(permission: "manage", resource_type: resource_type)
        .where("user_id = :user_id OR group_id IN (:group_ids)", user_id: @user.id, group_ids: group_ids)
    end

    def permission_scopes(record)
      case record
      when IngenicDocProduct
        [["IngenicDocProduct", product_ancestors(record).map(&:id)]]
      when IngenicDocVersion
        [["IngenicDocProduct", product_ancestors(record.product).map(&:id)]]
      when IngenicDocPage
        [
          ["IngenicDocProduct", product_ancestors(record.version.product).map(&:id)],
          ["IngenicDocPage", page_ancestors(record).map(&:id)],
        ]
      when IngenicBoard
        [["IngenicBoard", [record.id]]]
      else
        [[record.class.name, [record.id]]]
      end
    end

    def product_ancestors(product)
      result = []
      while product
        result << product
        product = product.parent
      end
      result
    end

    def page_ancestors(page)
      result = []
      while page
        result << page
        page = page.parent
      end
      result
    end

    def descendant_ids(klass, ids)
      return ids if klass == IngenicBoard

      if klass == IngenicDocProduct
        products = IngenicDocProduct.where(id: ids).to_a
        loop do
          children = IngenicDocProduct.where(parent_id: products.map(&:id)).to_a
          break if children.empty?

          products.concat(children)
        end
        products.map(&:id).uniq
      elsif klass == IngenicDocPage
        pages = IngenicDocPage.where(id: ids).to_a
        loop do
          children = IngenicDocPage.where(parent_id: pages.map(&:id)).to_a
          break if children.empty?

          pages.concat(children)
        end
        pages.map(&:id).uniq
      else
        ids
      end
    end
  end
end
