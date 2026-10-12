# frozen_string_literal: true

module ::DiscourseIngenic
  # Serves the Ember application shell for browser navigations to the plugin's
  # pages.
  #
  # Each public page answers two ways on the same URL: JSON when the frontend
  # components fetch it, and the SPA shell when a visitor opens or refreshes the
  # address bar directly. That keeps documentation, downloads and board links
  # shareable and bookmarkable instead of only reachable through in-app clicks.
  module AppShell
    def render_app_shell
      render html: "", layout: "application"
    end
  end
end
