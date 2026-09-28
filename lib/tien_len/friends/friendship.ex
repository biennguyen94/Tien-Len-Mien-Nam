defmodule TienLen.Friends.Friendship do
  @moduledoc "A friend request or friendship (FR1): `user_id` asked `friend_id`."
  use Ecto.Schema

  schema "friendships" do
    belongs_to :user, TienLen.Accounts.User
    belongs_to :friend, TienLen.Accounts.User
    field :status, :string, default: "pending"
    timestamps type: :utc_datetime
  end
end
