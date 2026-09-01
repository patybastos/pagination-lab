# pagination-lab

A hands-on Rails lab comparing **OFFSET pagination** vs **cursor (keyset) pagination** —
not just the theory, but a runnable benchmark and a runnable simulation that prove the
two real problems with OFFSET: it gets slower with depth, and it's inconsistent under
concurrent writes.

## Why this exists

`OFFSET` is the pagination everyone reaches for first, and it quietly breaks in two ways
once an app has real traffic:

1. **Performance degrades with depth.** `LIMIT 20 OFFSET 100000` still makes the database
   walk and discard 100,000 rows before it can return the 20 you asked for. Cost grows
   with the offset, even with an index on the sort column.
2. **Results are inconsistent under concurrent writes.** If a row is inserted or removed
   above the current offset between two page fetches, the window shifts: the client sees
   a duplicate item, or skips one entirely. In a live feed this happens constantly.

**Cursor (keyset) pagination** fixes both: instead of "skip N rows," it asks "give me rows
after the one I last saw" (`WHERE id < :last_seen_id`), which seeks directly through the
index. Cost stays flat regardless of depth, and a page already fetched is never affected
by rows inserted above it. The trade-off: you lose the ability to jump to an arbitrary
page number, and the cursor needs a stable, unique ordering (a composite cursor like
`(created_at, id)` when the sort column alone isn't unique).

| | OFFSET | Cursor |
|---|---|---|
| Cost at depth N | O(N) | O(1) (index seek) |
| Stable under concurrent writes | No — duplicates/skips rows | Yes |
| Jump to arbitrary page | Yes | No — sequential only |
| Best for | admin panels, small/static tables | feeds, timelines, infinite scroll |

## What's in this repo

- `Post#offset_page` / `Post#cursor_page` — the two pagination scopes, side by side
  ([app/models/post.rb](app/models/post.rb))
- `PostsController#index` — same endpoint, switchable strategy:
  `GET /posts?strategy=offset&offset=0&limit=20` or `GET /posts?strategy=cursor&cursor=123&limit=20`
- `db/seeds.rb` — seeds a large dataset (default 50k rows; the OFFSET cost is invisible on
  a small table)
- `lib/tasks/pagination_benchmark.rake` — times both strategies at increasing depth
- `lib/tasks/pagination_simulation.rake` — simulates writes landing between two page
  fetches and shows the duplicate OFFSET produces
- `spec/models/post_spec.rb` / `spec/requests/posts_spec.rb` — including a spec that
  reproduces the duplicate-under-concurrent-insert bug for OFFSET and proves cursor
  doesn't have it

## Running it

```bash
bin/setup
COUNT=2000000 bin/rails db:seed   # bigger = the OFFSET cost is easier to see
bin/rails pagination:benchmark
bin/rails pagination:simulate_inconsistency
bundle exec rspec
```

### Benchmark results (2,000,000 rows, page size 20, SQLite on a laptop)

```
depth         offset (ms)    cursor (ms)   x slower
----------------------------------------------------
0                    2.18           5.69       0.4x
1000                 0.33           0.27       1.2x
10000                0.32           0.25       1.3x
50000                1.13           0.40       2.8x
1999980             29.28           2.28      12.9x
```

OFFSET cost climbs with depth (13x slower at the far end of the table); cursor cost stays
flat because it seeks through the id index instead of counting rows from the start. Note:
SQLite keeps this dataset almost entirely in the page cache, so these absolute numbers are
small and a bit noisy at shallow depths — on Postgres/MySQL with disk-backed tables,
MVCC/visibility checks, and real concurrent load, the same query pattern shows a far
starker gap. The trend (flat vs growing) is what matters, not the exact milliseconds.

### Inconsistency simulation

```
== Fetching page 1 (before any new post arrives) ==
offset page 1 ids: [2000000, 1999999, 1999998, 1999997, 1999996]
cursor page 1 ids: [2000000, 1999999, 1999998, 1999997, 1999996]

== Meanwhile, 2 new posts arrive (a live feed keeps getting writes) ==
inserted ids: [2000001, 2000002]

== Fetching page 2 ==
offset page 2 ids: [1999997, 1999996, 1999995, 1999994, 1999993]
cursor page 2 ids: [1999995, 1999994, 1999993, 1999992, 1999991]

== Result ==
OFFSET: [1999997, 1999996] appear on BOTH page 1 and page 2 (duplicate shown to the user).
CURSOR: no overlap between page 1 and page 2, regardless of the new inserts.
```

Two new posts arrive between the two fetches. OFFSET's page 2 is computed by literally
skipping 5 rows from the *current* top of the table — but the top moved, so the window
shifts down and two rows that were already shown on page 1 show up again on page 2.
Cursor's page 2 is anchored to `id < 1999996` regardless of what got inserted above it, so
there's no overlap.

## Trade-offs of cursor pagination (being honest about the downsides)

- No "jump to page 7" — pagination is strictly sequential (prev/next cursor only).
- The sort column(s) must give a stable, unique ordering. Sorting by `created_at` alone
  breaks on ties; use a composite cursor instead:
  ```sql
  WHERE (created_at, id) > ('2026-01-01', 123)
  ORDER BY created_at, id
  LIMIT 20;
  ```
- Slightly more implementation complexity than `page.offset(...)`.

## When to use which

- **OFFSET** — admin panels, reports, anywhere the dataset is small or mutates rarely and
  "jump to page N" matters more than consistency under writes.
- **Cursor** — feeds, timelines, infinite scroll, anything with concurrent writes and no
  real need to jump to an arbitrary page.

---

This is one of a set of small labs exploring backend/Rails concepts in isolation before
combining them in a larger integrated project:

- `pagination-lab` (this repo) — offset vs cursor pagination
- `hotwire-realtime-demo` — Turbo Streams + ActionCable real-time UI
- `form-objects-playground` — Form Objects for multi-step/multi-model flows
- `db-locking-lab` — optimistic vs pessimistic locking under concurrency
