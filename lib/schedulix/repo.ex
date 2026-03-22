defmodule Schedulix.Repo do
  use Ecto.Repo,
    otp_app: :schedulix,
    adapter: Ecto.Adapters.Postgres
end
