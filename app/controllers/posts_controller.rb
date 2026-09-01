class PostsController < ApplicationController
  DEFAULT_LIMIT = 20
  MAX_LIMIT = 100

  # GET /posts?strategy=offset&offset=0&limit=20
  # GET /posts?strategy=cursor&cursor=123&limit=20
  def index
    strategy == "cursor" ? render_cursor_page : render_offset_page
  end

  private

  def render_offset_page
    offset = params[:offset].to_i
    posts = Post.offset_page(offset: offset, limit: limit_param)

    render json: {
      strategy: "offset",
      offset: offset,
      limit: limit_param,
      next_offset: offset + limit_param,
      data: serialize(posts)
    }
  end

  def render_cursor_page
    cursor = params[:cursor]
    posts = Post.cursor_page(cursor: cursor, limit: limit_param)

    render json: {
      strategy: "cursor",
      cursor: cursor,
      limit: limit_param,
      next_cursor: posts.last&.id,
      data: serialize(posts)
    }
  end

  def strategy
    params[:strategy].presence || "offset"
  end

  def limit_param
    @limit_param ||= (params[:limit].presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
  end

  def serialize(posts)
    posts.as_json(only: %i[id title created_at])
  end
end
