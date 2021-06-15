# Membrane WebRTC To HLS demo

## Dependencies

### Mac OS X

```
brew install srtp libnice clang-format ffmpeg opus
```

## Usage

Firstly, generate certificate, as described in the [signaling server readme](https://github.com/membraneframework/membrane_demo/tree/master/webrtc/simple#https). 

Install all dependencies:
```
mix deps.get
npm ci --prefix=assets
```

In order to run, type:
```
mix phx.server
```


Then, go to <https://localhost:8443/>.

## Copyright and License

Copyright 2020, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)
