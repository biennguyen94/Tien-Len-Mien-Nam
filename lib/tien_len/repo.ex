defmodule TienLen.Repo do
  @moduledoc "PostgreSQL repository (decision A4): accounts and game results."
  use Ecto.Repo,
    otp_app: :tien_len,
    adapter: Ecto.Adapters.Postgres
end
