class Post < ApplicationRecord
  validates :title, presence: true

  # Classic OFFSET/LIMIT pagination.
  #
  # The database still has to walk and discard `offset` rows before it can
  # return the page, so cost grows linearly with how deep you paginate.
  # It is also *unstable*: if a row is inserted or removed above the current
  # offset between two page requests, the window shifts and the client sees
  # a duplicate or skips an item entirely (see PaginationInconsistency).
  scope :offset_page, ->(offset: 0, limit: 20) {
    order(id: :desc).limit(limit).offset(offset)
  }

  # Cursor (keyset) pagination: instead of counting rows from the start,
  # ask the database to seek directly to the row after the last one the
  # client already has, using the index. Cost stays flat no matter how deep
  # you go, and inserting/deleting rows above the cursor never affects a
  # page that has already been fetched.
  scope :cursor_page, ->(cursor: nil, limit: 20) {
    scope = order(id: :desc).limit(limit)
    cursor.present? ? scope.where("id < ?", cursor) : scope
  }
end
