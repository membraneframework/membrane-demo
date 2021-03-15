defmodule VideoRoom.IntegrationTest do
  use ExUnit.Case, async: true
  use Wallaby.Feature
  alias Wallaby.Query

  @tag timeout: :infinity
  feature "integration", %{session: session} do
    session
    |> visit("room/room#test")
    |> assert_has(Query.css(".RoomForm"))
  end
end
