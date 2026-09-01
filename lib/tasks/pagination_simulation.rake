namespace :pagination do
  desc "Simulate concurrent inserts between two page fetches: OFFSET duplicates an item, cursor does not"
  task simulate_inconsistency: :environment do
    abort "Seed some data first: bin/rails db:seed" if Post.count < 10

    limit = 5

    ActiveRecord::Base.transaction do
      puts "== Fetching page 1 (before any new post arrives) =="
      page1_offset = Post.offset_page(offset: 0, limit: limit).load
      page1_cursor = Post.cursor_page(cursor: nil, limit: limit).load
      next_cursor  = page1_cursor.last.id

      puts "offset page 1 ids: #{page1_offset.map(&:id)}"
      puts "cursor page 1 ids: #{page1_cursor.map(&:id)} (next_cursor=#{next_cursor})"

      puts "\n== Meanwhile, 2 new posts arrive (a live feed keeps getting writes) =="
      new_posts = Array.new(2) { |i| Post.create!(title: "Breaking news #{i}", body: "...") }
      puts "inserted ids: #{new_posts.map(&:id)}"

      puts "\n== Fetching page 2 =="
      page2_offset = Post.offset_page(offset: limit, limit: limit).load
      page2_cursor = Post.cursor_page(cursor: next_cursor, limit: limit).load

      puts "offset page 2 ids: #{page2_offset.map(&:id)}"
      puts "cursor page 2 ids: #{page2_cursor.map(&:id)}"

      offset_dupes = page1_offset.map(&:id) & page2_offset.map(&:id)
      cursor_dupes = page1_cursor.map(&:id) & page2_cursor.map(&:id)

      puts "\n== Result =="
      if offset_dupes.any?
        puts "OFFSET: #{offset_dupes} appear on BOTH page 1 and page 2 (duplicate shown to the user)."
      else
        puts "OFFSET: no duplicates this run (try increasing inserted rows above `limit`)."
      end

      if cursor_dupes.empty?
        puts "CURSOR: no overlap between page 1 and page 2, regardless of the new inserts."
      else
        puts "CURSOR: unexpected overlap #{cursor_dupes} (should not happen)."
      end

      puts "\n(rolling back — this task never leaves data behind)"
      raise ActiveRecord::Rollback
    end
  end
end
