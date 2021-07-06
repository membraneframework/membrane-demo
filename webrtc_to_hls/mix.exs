defmodule WebRTCToHLS.MixProject do
  use Mix.Project

  def project do
    [
      app: :membrane_webrtc_to_hls_demo,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {WebRTCToHLS.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:membrane_core, "~> 0.7.0", override: true},
      {:membrane_webrtc_plugin,
       github: "membraneframework/membrane_webrtc_plugin", override: true},
      {:membrane_sfu, github: "membraneframework/membrane_sfu", branch: "develop"},
      {:membrane_element_tee, "~> 0.4.1"},
      {:membrane_element_fake, "~> 0.4.0"},
      {:plug_cowboy, "~> 2.0"},
      {:phoenix, "~> 1.5"},
      {:phoenix_html, "~> 2.14"},
      {:phoenix_live_reload, "~> 1.2"},
      {:poison, "~> 3.1"},
      {:jason, "~> 1.2"},
      {:membrane_file_plugin, "~> 0.5.0"},
      {:membrane_h264_ffmpeg_plugin,
       github: "membraneframework/membrane_h264_ffmpeg_plugin", override: true},
      {:membrane_http_adaptive_stream_plugin,
       [
         github: "membraneframework/membrane_http_adaptive_stream_plugin",
         branch: "discontinuity-support"
       ]},
      {:membrane_mp4_plugin,
       [
         github: "membraneframework/membrane_mp4_plugin",
         branch: "detect-nalus-change"
       ]},
      {:membrane_opus_plugin, "~> 0.5.0"},
      {:membrane_aac_plugin, "~> 0.6.0"},
      {:membrane_aac_fdk_plugin, "~> 0.6.0"}
    ]
  end
end
