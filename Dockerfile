FROM golang:1.23-bookworm AS polycli-builder

WORKDIR /opt/polygon-cli
ARG POLYCLI_VERSION="v0.1.78"
RUN apt-get update --yes \
  && git clone --branch ${POLYCLI_VERSION} https://github.com/maticnetwork/polygon-cli.git . \
  && make build


FROM debian:bookworm-slim

COPY --from=polycli-builder /opt/polygon-cli/out/polycli /usr/local/bin/polycli
COPY --from=polycli-builder /opt/polygon-cli/bindings /opt/bindings

WORKDIR /opt/e2e
COPY . .

ARG FOUNDRY_VERSION="stable"
RUN apt-get update --yes \
  && apt-get install --yes bats curl git jq python3-pip \
  # Install foundry.
  && curl --silent --location --proto "=https" https://foundry.paradigm.xyz | bash \
  && /root/.foundry/bin/foundryup --install ${FOUNDRY_VERSION} \
  && cp -r /root/.foundry/bin/* /usr/local/bin \
  # Install yq.
  && pip3 install --break-system-packages yq
