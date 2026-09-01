# Seeds a large, realistic dataset so offset pagination's cost actually
# shows up (small tables hide the O(offset) problem completely).
#
# Usage:
#   bin/rails db:seed                 # 50_000 posts (default)
#   COUNT=200000 bin/rails db:seed    # custom size

count = (ENV["COUNT"] || 50_000).to_i
batch_size = 1_000

existing = Post.count
if existing >= count
  puts "Post already has #{existing} rows (>= #{count}), skipping seed."
else
  to_create = count - existing
  puts "Seeding #{to_create} posts (target #{count})..."

  now = Time.current
  (existing + 1..count).each_slice(batch_size) do |slice|
    rows = slice.map do |i|
      {
        title: "Post ##{i}",
        body: "Body of post #{i}",
        created_at: now,
        updated_at: now
      }
    end
    Post.insert_all(rows)
    print "."
  end

  puts "\nDone. Post.count = #{Post.count}"
end
