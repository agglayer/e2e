# Define the base image to use for the final image.
# Options: "base", "cdk", "pos".
ARG BASE_IMAGE="base"

# STAGE 1: Build the polygon-cli binary.
FROM golang:1.23-bookworm AS polycli-builder

WORKDIR /opt/polygon-cli
ARG POLYCLI_VERSION="v0.1.78"
RUN apt-get update --yes \
  && git clone --branch ${POLYCLI_VERSION} https://github.com/maticnetwork/polygon-cli.git . \
  && make build


# STAGE 2: Build the base image containing e2e tests.
FROM debian:bookworm-slim AS base

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
  && pip3 install --break-system-packages yq \
  # Create folder for antithesis tests.
  && mkdir -p /opt/antithesis/test/v1


# STAGE 3.1: Build a cdk base image including e2e tests as well as antithesis cdk tests.
FROM base AS cdk
RUN mv tests/antithesis/cdk /opt/antithesis/test/v1/


# STAGE 3.2: Build a pos base image including e2e tests as well as antithesis pos tests.
FROM base AS pos
WORKDIR /opt/e2e
RUN mv tests/antithesis/pos /opt/antithesis/test/v1/


# STAGE 4: Build the final image based on the selected type.
FROM ${BASE_IMAGE} AS final
