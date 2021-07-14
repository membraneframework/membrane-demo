FROM elixir:1.12.2-alpine AS build

# install build dependencies
RUN \
    apk add --no-cache \
    build-base \
    npm \
    git \
    python3 \
    make \
    cmake \
    openssl-dev \ 
    libsrtp-dev \
    libnice-dev \
    ffmpeg-dev \
    opus-dev \
    clang-dev

# Create build workdir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix do deps.get, deps.compile

# build assets
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm --prefix ./assets ci --progress=false --no-audit --loglevel=error

COPY priv priv
COPY assets assets
RUN npm run --prefix ./assets deploy
RUN mix phx.digest

# compile and build release
COPY lib lib

RUN mix do compile, release

# prepare release image
FROM alpine:3.13 AS app

# install runtime dependencies
RUN \
    apk add --no-cache \
    openssl \
    ncurses-libs \
    libsrtp \
    libnice \
    ffmpeg \
    opus \
    clang \ 
    curl

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/membrane_videoroom_demo ./

ENV HOME=/app

EXPOSE 4000

HEALTHCHECK CMD curl --fail http://localhost:4000 || exit 1  

CMD ["bin/membrane_videoroom_demo", "start"]
