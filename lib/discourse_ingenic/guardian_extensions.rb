# frozen_string_literal: true

module DiscourseIngenic
  module GuardianExtensions
    def can_manage_ingenic_permissions?
      is_admin?
    end

    def can_manage_ingenic_content?
      Ingenic::PermissionResolver.new(user).can_manage_any_content?
    end

    def can_manage_ingenic_feature?(feature)
      Ingenic::PermissionResolver.new(user).can_manage_feature?(feature)
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

    # 高分悬赏. A bounty is opened on one's own topic and nowhere else: it is the
    # person asking the question who decides what an answer is worth, and the
    # person who pays is the person who asked.
    #
    # Whether one *already* stands is not asked here. That is a fact about the
    # topic rather than a permission of the viewer's, and the answer to it comes
    # with a sentence worth reading — "that topic already has a bounty standing"
    # — which belongs to `Ingenic::Bounties.open!` where the attempt is made.
    # This method answers the narrower question the button needs: may this member
    # offer a bounty on this topic at all.
    def can_open_ingenic_bounty?(topic)
      return false if !authenticated? || topic.blank? || !Ingenic::Bounties.available?
      return false if topic.user_id != current_user.id
      return false if topic.private_message?
      # A closed, archived or deleted topic is one where an answer can no longer
      # be accepted, and a bounty that cannot be settled is a promise the forum
      # cannot keep.
      return false if topic.closed? || topic.archived? || topic.trashed?
      return false unless can_see_topic?(topic)

      # The settlement is Discourse's own accepted answer, so the question has to
      # be one that *can* have one. `allow_accepted_answers?` comes from
      # discourse-solved; the `respond_to?` is for the forum where the plugin is
      # not installed at all, where `available?` above has already said no and
      # this is only belt and braces.
      respond_to?(:allow_accepted_answers?) && allow_accepted_answers?(topic)
    end

    # Withdrawing one's own offer, or a member of staff closing it down. Staff
    # are here because a bounty can turn out to have been opened on a topic that
    # should not have one, and the alternative to letting them close it is
    # editing the database.
    def can_cancel_ingenic_bounty?(bounty)
      return false if !authenticated? || bounty.nil? || !bounty.open?

      is_staff? || bounty.user_id == current_user.id
    end
  end
end
