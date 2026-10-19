# frozen_string_literal: true

require "rails_helper"

describe IngenicPopularController do
  fab!(:category) { Fabricate(:category) }
  fab!(:author) { Fabricate(:user) }

  before do
    SiteSetting.ingenic_enabled = true
    SiteSetting.ingenic_popular_window_days = 30
  end

  def topic(title:, likes:, views:, age: 1.day, category: nil)
    Fabricate(
      :topic,
      title: title,
      user: author,
      category: category || self.category,
      like_count: likes,
      views: views,
      created_at: age.ago,
    )
  end

  it "puts likes first and views second" do
    topic(title: "Liked a lot by the community", likes: 9, views: 10)
    topic(title: "Read a lot but liked less", likes: 3, views: 4000)
    topic(title: "Liked equally but read more", likes: 9, views: 800)

    get "/ingenic/popular.json"

    expect(response.status).to eq(200)
    titles = response.parsed_body["topics"].map { |row| row["title"] }
    expect(titles).to eq(
      [
        "Liked equally but read more",
        "Liked a lot by the community",
        "Read a lot but liked less",
      ],
    )
  end

  it "leaves out topics older than the window" do
    topic(title: "A topic from this month", likes: 2, views: 20)
    topic(title: "A topic from last year", likes: 500, views: 50_000, age: 400.days)

    get "/ingenic/popular.json"

    expect(response.parsed_body["topics"].map { |row| row["title"] }).to eq(
      ["A topic from this month"],
    )
  end

  it "carries the topic's tags so the card can label it" do
    tagged = topic(title: "A camera question with tags", likes: 4, views: 40)
    tagged.tags << Fabricate(:tag, name: "t33")

    get "/ingenic/popular.json"

    row = response.parsed_body["topics"].first
    expect(row["tags"]).to eq([{ "name" => "t33", "slug" => "t33" }])
    expect(row["category_url"]).to eq(category.url)
  end

  it "does not leak a restricted category's topics to a guest" do
    private_category = Fabricate(:category, read_restricted: true)
    topic(title: "Members only question", likes: 50, views: 500, category: private_category)
    topic(title: "A public question", likes: 1, views: 5)

    get "/ingenic/popular.json"

    expect(response.parsed_body["topics"].map { |row| row["title"] }).to eq(
      ["A public question"],
    )
  end

  it "serves the app shell to a browser navigation" do
    get "/ingenic/popular"

    expect(response.status).to eq(200)
    expect(response.body).to include("<!DOCTYPE html>")
  end
end
