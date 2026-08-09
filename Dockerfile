# syntax=docker/dockerfile:1
ARG ELIXIR_VERSION=1.20.3
ARG OTP_VERSION=29.0.5
ARG DEBIAN_VERSION=bookworm-20260803-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git curl ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only $MIX_ENV
RUN mkdir -p lib
RUN mix deps.compile

COPY priv priv
# Domain catalog for assessment UI (release uses :code.priv_dir/:isomer).
COPY vocab/domains.yaml priv/vocab/domains.yaml
COPY assets assets
COPY lib lib

RUN mix compile
RUN mix assets.setup
RUN mix assets.deploy
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV=prod
ENV PHX_SERVER=true

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/isomer ./
# Keep cwd-relative vocab path working for Isomer.root() fallbacks.
COPY --from=builder --chown=nobody:root /app/priv/vocab ./vocab

USER nobody
CMD ["/app/bin/isomer", "start"]
