# frozen_string_literal: true

class IngenicBoardsController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  # Direct navigations to /ingenic/boards must reach the app shell; the homepage
  # block's fetch stays AJAX and keeps hitting JSON.
  skip_before_action :check_xhr, only: %i[index]

  def index
    return render_app_shell unless request.format.json?

    boards = IngenicBoard.published.where(locale: [locale, default_locale]).ordered

    render_json_dump(
      boards: ActiveModel::ArraySerializer.new(boards, each_serializer: IngenicBoardSerializer),
    )
  end

  private

  def locale
    @locale ||= I18n.locale.to_s
  end

  def default_locale
    SiteSetting.ingenic_default_locale
  end
end
