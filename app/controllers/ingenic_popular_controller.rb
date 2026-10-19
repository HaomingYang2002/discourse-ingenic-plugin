# frozen_string_literal: true

# Popular posts: what the forum read and liked most in a recent window.
#
# Likes first, views second. A view is a click and a like is a decision, so a
# topic with forty likes outranks one that was merely opened four thousand
# times. Views break ties — between two topics the forum liked equally, the one
# more people came back to is the more useful.
#
# The window matters more than it looks. All-time popularity freezes: the same
# handful of threads sit at the top for years and the card stops being a reading
# of the forum. It is a setting, so an administrator can choose the season.
class IngenicPopularController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  skip_before_action :check_xhr, only: %i[index]

  def index
    return render_app_shell unless request.format.json?

    render_json_dump(
      window_days: window_days,
      topics: topics.map { |topic| json_for(topic) },
    )
  end

  private

  def window_days
    SiteSetting.ingenic_popular_window_days.to_i.clamp(1, 3650)
  end

  def limit
    requested = params[:limit].to_i
    requested.positive? ? [requested, 50].min : 5
  end

  # `secured` is the permission question — it drops categories the viewer may
  # not see before the ordering has a chance to leak their titles. Regular
  # topics only: a private message is not a popular post, and an uncategorized
  # topic is still one.
  def topics
    @topics ||=
      Topic
        .secured(guardian)
        .visible
        .where(archetype: Archetype.default)
        .where("topics.like_count > 0 OR topics.views > 0")
        .where("topics.created_at > ?", window_days.days.ago)
        .order(like_count: :desc, views: :desc, created_at: :desc)
        .limit(limit)
        .includes(:category, :tags)
  end

  def json_for(topic)
    category = topic.category

    {
      "id" => topic.id,
      "title" => topic.title,
      "slug" => topic.slug,
      "url" => topic.relative_url,
      "likes" => topic.like_count.to_i,
      "views" => topic.views.to_i,
      "posts_count" => topic.posts_count.to_i,
      "tags" => topic.tags.map { |tag| { "name" => tag.name, "slug" => tag.slug } },
      "category" => category&.name,
      "category_slug" => category&.slug,
      "category_url" => category&.url,
      "category_color" => category&.color,
      "created_at" => topic.created_at.iso8601,
      "last_posted_at" => topic.last_posted_at&.iso8601,
    }
  end
end
