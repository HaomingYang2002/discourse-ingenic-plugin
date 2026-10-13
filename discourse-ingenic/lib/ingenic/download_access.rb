# frozen_string_literal: true

module Ingenic
  # Answers one question: may this account download this resource right now, and
  # if not, what is the next thing they have to do?
  #
  # Every surface asks it the same way — the listing that decides which button
  # to draw, the endpoint that serves the bytes, and the admin queue — so there
  # is no path on which the button and the file disagree.
  class DownloadAccess
    # anonymous       not signed in
    # needs_profile   signed in, developer information not on file
    # needs_request   eligible to apply and has not
    # pending         applied, waiting on the team
    # rejected        applied, turned down
    # granted         may download
    STATES = %i[anonymous needs_profile needs_request pending rejected granted].freeze

    Result = Struct.new(:state, :download, :request, :grant, keyword_init: true) do
      def allowed?
        state == :granted
      end

      def gated?
        state != :granted
      end
    end

    # Everything the policy needs to know about one account, read once.
    #
    # A listing asks the same question about every resource on the page, and
    # answering it the ordinary way would be three queries per card. Loading the
    # facts up front keeps the page's cost independent of how many resources are
    # on it, without giving the listing its own copy of the rules.
    class Context
      attr_reader :profile

      def initialize(user)
        @user = user
        return if user.nil?

        @profile = IngenicDeveloperProfile.for(user)
        @grants = IngenicDownloadGrant.active.where(user_id: user.id).index_by(&:download_id)
        @requests =
          IngenicDownloadRequest
            .where(user_id: user.id)
            .recent
            .group_by(&:download_id)
            .transform_values(&:first)
      end

      def grant_for(download)
        @grants && @grants[download.id]
      end

      def request_for(download)
        @requests && @requests[download.id]
      end
    end

    # Every resource on a page, decided in one pass.
    def self.for_list(user, downloads)
      context = Context.new(user)
      downloads.map { |download| new(user, download, context: context).result }
    end

    def initialize(user, download, context: nil)
      @user = user
      @download = download
      @context = context
    end

    def result
      return Result.new(state: :anonymous, download: download) if user.nil?
      return Result.new(state: :granted, download: download) if download.login_only?
      return Result.new(state: :needs_profile, download: download) if profile.nil?
      return Result.new(state: :granted, download: download) if download.form_required?

      # Approval tier: an active grant is the whole answer. Everything below it
      # only describes where the applicant is in the queue.
      return Result.new(state: :granted, download: download, grant: grant) if grant

      request = latest_request

      state =
        case request&.status
        when IngenicDownloadRequest::PENDING then :pending
        when IngenicDownloadRequest::REJECTED then :rejected
        else :needs_request
        end

      Result.new(state: state, download: download, request: request)
    end

    private

    attr_reader :user, :download, :context

    def profile
      return context.profile if context

      @profile ||= IngenicDeveloperProfile.for(user)
    end

    def grant
      return context.grant_for(download) if context

      @grant ||= IngenicDownloadGrant.active.find_by(user_id: user.id, download_id: download.id)
    end

    # The most recent application, whatever its outcome. A rejection is
    # information the applicant is owed; hiding it behind a fresh "Apply" button
    # would let them reapply into a queue that already answered them.
    def latest_request
      return context.request_for(download) if context

      @latest_request ||=
        IngenicDownloadRequest.where(user_id: user.id, download_id: download.id).recent.first
    end
  end
end
