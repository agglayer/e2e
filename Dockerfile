FROM golang:1.23-bookworm AS polycli-builder
ENV POLYCLI_VERSION="v0.1.75"

WORKDIR /opt/polygon-cli
RUN apt-get update --yes \
  && git clone --branch ${POLYCLI_VERSION} https://github.com/maticnetwork/polygon-cli.git . \
  && make build


FROM debian:bookworm-slim
ENV FOUNDRY_VERSION="stable"

COPY --from=polycli-builder /opt/polygon-cli/out/polycli /usr/local/bin/polycli
COPY --from=polycli-builder /opt/polygon-cli/bindings /opt/bindings

WORKDIR /opt/e2e
RUN apt-get update --yes \
  && apt-get install --yes bats curl git jq python3-pip \
  # Install foundry.
  && curl --silent --location --proto "=https" https://foundry.paradigm.xyz | bash \
  && /root/.foundry/bin/foundryup --install ${FOUNDRY_VERSION} \
  && cp -r /root/.foundry/bin/* /usr/local/bin \
  # Install yq.
  && pip3 install --break-system-packages yq

COPY . .

