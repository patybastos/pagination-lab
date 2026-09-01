require "rails_helper"

RSpec.describe "Posts pagination", type: :request do
  def create_posts(count)
    Array.new(count) { |i| Post.create!(title: "Post #{i}", body: "body") }
  end

  describe "GET /posts (offset strategy)" do
    it "paginates newest first and exposes the next offset" do
      create_posts(10)

      get "/posts", params: { strategy: "offset", offset: 0, limit: 3 }

      json = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(json["strategy"]).to eq("offset")
      expect(json["data"].size).to eq(3)
      expect(json["next_offset"]).to eq(3)
    end
  end

  describe "GET /posts (cursor strategy)" do
    it "paginates newest first and exposes the next cursor" do
      posts = create_posts(10)

      get "/posts", params: { strategy: "cursor", limit: 3 }

      json = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(json["strategy"]).to eq("cursor")
      expect(json["data"].size).to eq(3)
      expect(json["next_cursor"]).to eq(posts.last(3).reverse.last.id)
    end

    it "keeps returning older rows when a new post is created between requests" do
      create_posts(5)

      get "/posts", params: { strategy: "cursor", limit: 5 }
      first_page_ids = response.parsed_body["data"].map { |p| p["id"] }
      next_cursor = response.parsed_body["next_cursor"]

      create_posts(2) # a write arrives in between, like a live feed

      get "/posts", params: { strategy: "cursor", cursor: next_cursor, limit: 5 }
      second_page_ids = response.parsed_body["data"].map { |p| p["id"] }

      expect(first_page_ids & second_page_ids).to be_empty
    end
  end

  describe "limit clamping" do
    it "clamps limit to MAX_LIMIT" do
      create_posts(3)

      get "/posts", params: { limit: 9999 }

      expect(response.parsed_body["limit"]).to eq(PostsController::MAX_LIMIT)
    end
  end
end
