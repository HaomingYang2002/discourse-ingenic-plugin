# frozen_string_literal: true

# The MCP landing page.
#
# Discourse's MCP server is core's, not this plugin's: the endpoint is
# `POST /mcp`, the setting is `mcp_server_enabled`, and the protocol details are
# documented by core. What this action is for is that `/ingenic/mcp` is a page a
# visitor can open, refresh and share — it hands back the application shell, and
# the theme explains the endpoint and how a client connects to it.
#
# The endpoint itself is not proxied here. A client talks to `/mcp` directly;
# putting this plugin in that path would add a hop without adding a check.
class IngenicMcpController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  # A direct navigation must reach the shell. The page fetches nothing, so
  # there is no JSON half for the XHR check to protect.
  skip_before_action :check_xhr, only: %i[index]

  def index
    render_app_shell
  end
end
