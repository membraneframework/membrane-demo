defmodule WebRTCToHLS.MixProject do
  use Mix.Project

  def project do
    [
      app: :membrane_webrtc_to_hls_demo,
      version: "0.1.0",
      elixir: "~> 1.10",
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
      {:membrane_core, github: "membraneframework/membrane_core", override: true},
      {:membrane_webrtc_plugin, github: "membraneframework/membrane_webrtc_plugin"},
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
       [
         env: :prod,
         github: "membraneframework/membrane_h264_ffmpeg_plugin",
         branch: "propagate-caps",
         override: true
       ]},
      {:membrane_http_adaptive_stream_plugin,
       [
         github: "membraneframework/membrane_http_adaptive_stream_plugin",
         branch: "discontinuity-support",
         override: true
       ]},
      {:membrane_mp4_plugin,
       [
         github: "membraneframework/membrane_mp4_plugin",
         branch: "detect-nalus-change"
       ]},
      {:membrane_opus_plugin, "~> 0.4.0"},
      {:membrane_aac_plugin, "~> 0.6.0"},
      {:membrane_aac_fdk_plugin, "~> 0.5.0"}
    ]
  end
end
