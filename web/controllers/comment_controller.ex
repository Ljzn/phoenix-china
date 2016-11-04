defmodule PhoenixChina.CommentController do
  use PhoenixChina.Web, :controller

  alias PhoenixChina.{Comment, Post, Notification}

  import PhoenixChina.ViewHelpers, only: [current_user: 1]
  import PhoenixChina.Ecto.Helpers, only: [increment: 2, update_field: 3]

  plug Guardian.Plug.EnsureAuthenticated, [handler: PhoenixChina.GuardianErrorHandler]
    when action in [:create, :edit, :update, :delete]

  def show(conn, %{"post_id" => post_id, "id" => comment_id}) do
    post = Post
    |> preload([:user, :latest_comment, latest_comment: :user])
    |> Repo.get!(post_id)

    comment = Comment
    |> preload(:user)
    |> Repo.get!(comment_id)

    conn
    |> assign(:title, comment.user.nickname <> "在帖子" <> post.title <> "的评论")
    |> assign(:post, post)
    |> assign(:comment, comment)
    |> render("show.html")
  end

  def create(conn, %{"post_id" => post_id, "comment" => comment_params}) do
    current_user = current_user(conn)
    post = Post |> preload([:user]) |> Repo.get!(post_id)

    comment_params = comment_params
    |> Map.put_new("index", post.comment_count + 1)
    |> Map.put_new("post_id", post.id)
    |> Map.put_new("user_id", current_user.id)

    changeset = Comment.changeset(%Comment{}, comment_params)

    case Repo.insert(changeset) do
      {:ok, comment} ->
        post
        |> update_field(:latest_comment_id, comment.id)
        |> update_field(:latest_comment_inserted_at, comment.inserted_at)
        |> increment(:comment_count)

        Notification.create(conn, comment)

        conn |> put_flash(:info, "评论创建成功.")
      {:error, _changeset} ->
        conn |> put_flash(:error, "评论创建失败, 评论不能超过1000字.")
    end
    |> redirect(to: post_path(conn, :show, post_id))
  end

  def edit(conn, %{"post_id" => post_id, "id" => id}) do
    current_user = current_user(conn)
    comment = Repo.get_by!(Comment, post_id: post_id, id: id, user_id: current_user.id)

    changeset = Comment.changeset(comment)

    conn
    |> assign(:title, "编辑评论")
    |> assign(:comment, comment)
    |> assign(:changeset, changeset)
    |> render("edit.html")
  end

  def update(conn, %{"post_id" => post_id, "id" => id, "comment" => comment_params}) do
    current_user = current_user(conn)
    comment = Repo.get_by!(Comment, post_id: post_id, id: id, user_id: current_user.id)

    changeset = Comment.changeset(comment, comment_params)

    case Repo.update(changeset) do
      {:ok, _comment} ->
        conn
        |> put_flash(:info, "评论更新成功！")
        |> redirect(to: post_path(conn, :show, post_id))
      {:error, changeset} ->
        conn
        |> assign(:title, "编辑评论")
        |> assign(:comment, comment)
        |> assign(:changeset, changeset)
        |> render("edit.html")
    end
  end

  def delete(conn, %{"post_id" => post_id, "id" => id}) do
    current_user = current_user(conn)
    post = Repo.get!(Post, post_id)
    comment = Repo.get_by!(Comment, post_id: post_id, id: id, user_id: current_user.id)

    latest_comment_id = Comment
    |> where([c], c.post_id == ^comment.post_id and c.id != ^comment.id)
    |> select([u], max(u.id))
    |> Repo.one

    post |> update_field(:latest_comment_id, latest_comment_id)

    comment |> update_field(:is_deleted, true)

    conn
    |> put_flash(:info, "评论删除成功！")
    |> redirect(to: post_path(conn, :show, post_id))
  end
end
