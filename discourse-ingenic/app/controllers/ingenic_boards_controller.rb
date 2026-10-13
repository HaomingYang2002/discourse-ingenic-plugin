# frozen_string_literal: true

# The development board catalogue.
#
# This page sells nothing and takes no orders: a board is applied for or bought
# from the Ingenic team, so every card ends in a link that leaves the forum.
class IngenicBoardsController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  # Direct navigations to /ingenic/boards must reach the app shell; the
  # homepage block's fetch stays AJAX and keeps hitting JSON.
  skip_before_action :check_xhr, only: %i[index]

  def index
    return render_app_shell unless request.format.json?

    render_json_dump(
      boards: ActiveModel::ArraySerializer.new(boards, each_serializer: IngenicBoardSerializer),
      filters: filters,
    )
  end

  private

  # Reading locale first, then the site default, with one row per board: a
  # translation that exists only in the default locale still shows up, and a
  # board that has both does not appear twice.
  def boards
    @boards ||=
      begin
        rows =
          IngenicBoard
            .published
            .includes(product: :parent)
            .where(locale: [locale, default_locale].uniq)

        rows = rows.for_series(params[:series]) if params[:series].present?
        rows = rows.for_chip(params[:chip]) if params[:chip].present?

        rows
          .ordered
          .group_by { |row| [row.slug, row.name] }
          .map { |_, group| group.find { |row| row.locale == locale } || group.first }
      end
  end

  # The filter options come from the tree, not from the boards on the page, so
  # choosing a series does not make the other series disappear from the control
  # that would undo the choice.
  def filters
    series =
      IngenicDocProduct.series.published.ordered.map do |record|
        { "slug" => record.slug, "name" => record.name }
      end

    chips =
      IngenicDocProduct.chips.published.ordered.map do |record|
        { "slug" => record.slug, "name" => record.name, "series_slug" => record.parent&.slug }
      end

    { series: series, chips: chips }
  end

  def locale
    @locale ||= I18n.locale.to_s
  end

  def default_locale
    SiteSetting.ingenic_default_locale
  end
end
