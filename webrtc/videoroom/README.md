# Membrane WebRTC video room demo

This project demonstrates an example usage of Membrane SFU API defined in [membrane_sfu](https://github.com/membraneframework/membrane_sfu).

## Run manually

### Dependencies

In order to run phoenix application manually you will need to have `node` installed.
Demo has been tested with `node` version `v14.15.0`. You will also need some system dependencies.

#### Mac OS X

```
brew install srtp libnice clang-format ffmpeg opus
```

#### Ubuntu

```
sudo apt-get install libsrtp2-dev libnice-dev libavcodec-dev libavformat-dev libavutil-dev libopus-dev
```

### To run
First install all dependencies:
```
mix deps.get
npm ci --prefix=assets
```

In order to run, type:

```
mix phx.server 
```

Then go to <http://localhost:4000/>.

## Run with docker

Videoroom demo provides a `Dockerfile` that you can use to run videoroom application yourself without any additional setup and dependencies.

### To run:

```bash
docker run -p 4000:4000 membraneframework/demo_webrtc_videoroom:latest
```

Or build and run docker image from source:
```bash
docker build  -t membrane_videoroom .
docker run -p 4000:4000 membrane_videoroom 
```

Then go to <http://localhost:4000/>.

## Copyright and License

Copyright 2020, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)
