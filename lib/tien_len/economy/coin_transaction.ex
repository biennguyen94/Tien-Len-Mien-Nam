defmodule TienLen.Economy.CoinTransaction do
  @moduledoc "One line of the append-only coin ledger (C10)."
  use Ecto.Schema

  schema "coin_transactions" do
    belongs_to :user, TienLen.Accounts.User
    belongs_to :counterparty, TienLen.Accounts.User
    field :amount, :integer
    field :balance_after, :integer
    field :reason, :string
    field :ref, :string
    field :inserted_at, :utc_datetime, read_after_writes: true
  end
end
