require "benchmark"

namespace :pagination do
  desc "Compare OFFSET vs cursor (keyset) pagination cost at increasing depth"
  task benchmark: :environment do
    total = Post.count
    if total < 10_000
      abort <<~MSG
        Only #{total} posts in the database. Seed a larger dataset first so the
        OFFSET cost is actually visible, e.g.:

          COUNT=200000 bin/rails db:seed
      MSG
    end

    limit = 20
    max_id = Post.maximum(:id)
    depths = [ 0, 1_000, 10_000, 50_000, total - limit ].select { |d| d >= 0 && d < total }.uniq

    puts "Post.count = #{total}, page size = #{limit}"
    puts
    printf("%-10s %14s %14s %10s\n", "depth", "offset (ms)", "cursor (ms)", "x slower")
    puts "-" * 52

    depths.each do |depth|
      # OFFSET N: the database walks and discards N rows before it can return the page.
      offset_time = Benchmark.realtime do
        Post.offset_page(offset: depth, limit: limit).load
      end

      # Cursor equivalent: seek straight to the row via the id index.
      # (id = max_id - depth is where that page would start in id-desc order,
      # since ids were inserted sequentially in db/seeds.rb)
      cursor = max_id - depth + 1
      cursor_time = Benchmark.realtime do
        Post.cursor_page(cursor: cursor, limit: limit).load
      end

      ratio = cursor_time.zero? ? Float::INFINITY : offset_time / cursor_time
      printf(
        "%-10d %14.2f %14.2f %9.1fx\n",
        depth, offset_time * 1000, cursor_time * 1000, ratio
      )
    end

    puts
    puts "OFFSET cost grows with depth; cursor cost stays flat because it seeks"
    puts "through the id index instead of counting rows from the start."
  end
end
