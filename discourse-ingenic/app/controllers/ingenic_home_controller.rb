# frozen_string_literal: true

# The forum's front page.
#
# There is nothing to fetch. The page is assembled in the browser from data the
# site already sends: the block list comes down with site.json, the categories
# come down with it too, and the section cards are drawn from those. What this
# action exists for is that a page has to be *served*: the moment
# `default_homepage` names this one, `/` is a request to a controller, and a
# visitor who opens or refreshes that address has to be handed the application
# shell rather than a 404.
#
# It answers the same way at `/ingenic/home`, which is the page's canonical
# path — what the client route is registered at, and what a link to the home
# page points at.
class IngenicHomeController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  # No JSON half to serve, so the XHR check has nothing to protect: a fetch of
  # this address would be answered with the shell instead of an empty body.
  skip_before_action :check_xhr

  def index
    render_app_shell
  end
end
