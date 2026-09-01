require "rails_helper"

RSpec.describe Post, type: :model do
  def create_posts(count)
    Array.new(count) { |i| Post.create!(title: "Post #{i}", body: "body") }
  end

  describe ".offset_page" do
    it "returns `limit` rows starting after `offset` rows, newest first" do
      desc_ids = create_posts(10).map(&:id).reverse

      page1 = Post.offset_page(offset: 0, limit: 3)
      page2 = Post.offset_page(offset: 3, limit: 3)

      expect(page1.map(&:id)).to eq(desc_ids[0, 3])
      expect(page2.map(&:id)).to eq(desc_ids[3, 3])
    end
  end

  describe ".cursor_page" do
    it "returns the first `limit` rows when no cursor is given" do
      desc_ids = create_posts(10).map(&:id).reverse

      page = Post.cursor_page(cursor: nil, limit: 3)

      expect(page.map(&:id)).to eq(desc_ids[0, 3])
    end

    it "returns rows strictly older than the cursor" do
      desc_ids = create_posts(10).map(&:id).reverse
      cursor = desc_ids[2] # last id of the first 3-row page

      page = Post.cursor_page(cursor: cursor, limit: 3)

      expect(page.map(&:id)).to all(be < cursor)
      expect(page.map(&:id)).to eq(desc_ids[3, 3])
    end
  end

  describe "consistency under concurrent inserts" do
    it "duplicates an item across offset pages when a row is inserted between fetches" do
      create_posts(10)
      limit = 5

      page1 = Post.offset_page(offset: 0, limit: limit).map(&:id)
      create_posts(2) # simulate new writes arriving between the two page fetches
      page2 = Post.offset_page(offset: limit, limit: limit).map(&:id)

      expect(page1 & page2).not_to be_empty
    end

    it "never repeats an item across cursor pages, regardless of new inserts" do
      create_posts(10)
      limit = 5

      page1 = Post.cursor_page(cursor: nil, limit: limit)
      next_cursor = page1.last.id
      create_posts(2) # simulate new writes arriving between the two page fetches
      page2 = Post.cursor_page(cursor: next_cursor, limit: limit).map(&:id)

      expect(page1.map(&:id) & page2).to be_empty
    end
  end
end
