defmodule WebRTCToHLS.Helpers do
  @moduledoc false

  @spec pid_hash(pid()) :: String.t()
  def pid_hash(pid) do
    pid |> pid_to_hash()
  end

  @spec hls_output_path(prefix :: String.t()) :: String.t()
  def hls_output_path(prefix) do
    [hls_output_mount_path(), prefix] |> Path.join()
  end

  @spec hls_output_path(prefix :: String.t(), filename :: String.t()) :: String.t()
  def hls_output_path(prefix, filename) do
    [hls_output_mount_path(), prefix, filename] |> Path.join()
  end

  @spec hls_output_mount_path() :: String.t()
  def hls_output_mount_path(),
    do: Application.fetch_env!(:membrane_webrtc_to_hls_demo, :hls_output_mount_path)

  defp pid_to_hash(pid) do
    :crypto.hash(:md5, :erlang.pid_to_list(pid)) |> Base.encode16(case: :lower)
  end
end
