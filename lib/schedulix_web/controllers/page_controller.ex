defmodule SchedulixWeb.PageController do
  use SchedulixWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
