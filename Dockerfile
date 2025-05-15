FROM golang:1.23-bookworm AS polycli-builder
ENV POLYCLI_VERSION="v0.1.78"

WORKDIR /opt/polygon-cli
RUN apt-get update --yes \
  && git clone --branch ${POLYCLI_VERSION} https://github.com/maticnetwork/polygon-cli.git . \
  && make build


FROM debian:bookworm-slim
ENV FOUNDRY_VERSION="stable"
ENV ANTITHESIS_TESTS_PATH=""

COPY --from=polycli-builder /opt/polygon-cli/out/polycli /usr/local/bin/polycli
COPY --from=polycli-builder /opt/polygon-cli/bindings /opt/bindings
COPY . .

WORKDIR /opt/e2e
RUN apt-get update --yes \
  && apt-get install --yes bats curl git jq python3-pip \
  # Install foundry.
  && curl --silent --location --proto "=https" https://foundry.paradigm.xyz | bash \
  && /root/.foundry/bin/foundryup --install ${FOUNDRY_VERSION} \
  && cp -r /root/.foundry/bin/* /usr/local/bin \
  # Install yq.
  && pip3 install --break-system-packages yq \
  # If ANTITHESIS_TESTS_PATH is specified, copy test files to the correct location so that
  # antithesis test composer can find them.
  && if [[ -n "${ANTITHESIS_TESTS_PATH}" ]]; then \
  mkdir -p /opt/antithesis/test/v1; \
  cp -r ${ANTITHESIS_TESTS_PATH}/* /opt/antithesis/test/v1; \
  fi
