defmodule WebRTCToHLS.StorageCleanup do
  use GenServer

  alias WebRTCToHLS.Helpers

  @interval 5_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init(_) do
    send(self(), :cleanup)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    clean_unused_directories()

    Process.send_after(self(), :cleanup, @interval)
    {:noreply, state}
  end

  defp clean_unused_directories() do
    active_paths = list_running_pipelines_storage_paths() |> MapSet.new()
    all_paths = list_storage_directories() |> MapSet.new()

    MapSet.difference(all_paths, active_paths)
    |> Enum.map(&Helpers.hls_output_path(&1))
    |> Enum.each(&File.rm_rf!(&1))
  end

  defp list_running_pipelines_storage_paths() do
    Registry.select(WebRTCToHLS.Registry, [{{:_, :"$2", :_}, [], [:"$2"]}])
    |> Enum.map(fn pid ->
      pid |> Helpers.pid_hash()
    end)
  end

  defp list_storage_directories() do
    case Helpers.hls_output_mount_path() |> File.ls() do
      {:ok, dirs} -> dirs
      {:error, :enoent} -> []
    end
  end
end
