# syntax=docker/dockerfile:1
#
# Thin Navio full-node image.
#
# It ships the official, pre-built navio-core release binaries (downloaded and
# checksum-verified at build time) on top of debian-slim. The release binaries
# are statically linked against everything except glibc, so the runtime layer
# needs no extra libraries.
#
# Targets:
#   node (default) — naviod and the CLI tools only
#   i2p            — node plus a bundled i2pd router, wired to naviod via SAM
#   tor            — node plus a bundled Tor client and onion service

############################################
# Stage 1 — fetch + verify release binaries
############################################
FROM debian:bookworm-slim AS fetch-base

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl jq \
    && rm -rf /var/lib/apt/lists/*

FROM fetch-base AS fetch

# Which navio-core release to ship. "latest" resolves the newest release
# (including release candidates) from the GitHub API at build time. Override
# with e.g. --build-arg NAVIO_RELEASE_TAG=v0.1rc30 to pin.
ARG NAVIO_RELEASE_TAG=latest

# Provided automatically by buildx for each target platform.
ARG TARGETARCH
ARG TARGETVARIANT

ARG GITHUB_API=https://api.github.com/repos/nav-io/navio-core

WORKDIR /tmp/navio

# Map the Docker platform to the navio-core release triplet.
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT:+/${TARGETVARIANT}}" in \
        amd64)   TRIPLET="x86_64-linux-gnu" ;; \
        arm64)   TRIPLET="aarch64-linux-gnu" ;; \
        arm/v7)  TRIPLET="arm-linux-gnueabihf" ;; \
        ppc64le) TRIPLET="powerpc64le-linux-gnu" ;; \
        riscv64) TRIPLET="riscv64-linux-gnu" ;; \
        *) echo "unsupported platform: ${TARGETARCH}${TARGETVARIANT:-}" >&2; exit 1 ;; \
    esac; \
    echo "TRIPLET=${TRIPLET}" > /tmp/navio/triplet.env

# Resolve the release, download the matching tarball, verify it against
# SHA256SUMS, and extract the binaries to /opt/navio.
RUN set -eux; \
    . /tmp/navio/triplet.env; \
    # GitHub release bodies can contain raw control characters that stricter jq
    # builds reject; strip all of them before parsing (inter-token newlines are
    # not required for valid JSON).
    sanitize() { tr -d '\000-\037'; }; \
    if [ "${NAVIO_RELEASE_TAG}" = "latest" ]; then \
        # /releases/latest skips prereleases, and the newest tag may carry no
        # binaries yet, so pick the most recent release that actually ships an
        # asset for this triplet.
        REL="$(curl -fsSL "${GITHUB_API}/releases?per_page=30" | sanitize \
            | jq -c --arg t "${TRIPLET}.tar.gz" \
                'map(select(any(.assets[]?; .name | endswith($t)))) | .[0]')"; \
    else \
        REL="$(curl -fsSL "${GITHUB_API}/releases/tags/${NAVIO_RELEASE_TAG}" | sanitize)"; \
    fi; \
    if [ -z "${REL}" ] || [ "${REL}" = "null" ]; then \
        echo "no navio-core release with a ${TRIPLET} asset found" >&2; exit 1; \
    fi; \
    TAG="$(printf '%s' "${REL}" | jq -r '.tag_name')"; \
    echo "resolved release tag: ${TAG}"; \
    URL="$(printf '%s' "${REL}" | jq -r --arg t "${TRIPLET}.tar.gz" '.assets[] | select(.name | endswith($t)) | .browser_download_url')"; \
    SUMS_URL="$(printf '%s' "${REL}" | jq -r '.assets[] | select(.name == "SHA256SUMS") | .browser_download_url')"; \
    if [ -z "${URL}" ] || [ "${URL}" = "null" ]; then \
        echo "release ${TAG} has no ${TRIPLET} asset" >&2; exit 1; \
    fi; \
    ASSET="$(basename "${URL}")"; \
    echo "downloading ${ASSET}"; \
    curl -fsSL -o "${ASSET}" "${URL}"; \
    if [ -n "${SUMS_URL}" ] && [ "${SUMS_URL}" != "null" ]; then \
        curl -fsSL -o SHA256SUMS "${SUMS_URL}"; \
        # --ignore-missing limits the check to the one asset we downloaded.
        sha256sum --ignore-missing --check SHA256SUMS; \
    else \
        echo "WARNING: no SHA256SUMS asset for ${TAG} — skipping checksum verification" >&2; \
    fi; \
    mkdir -p /opt/navio; \
    tar -xzf "${ASSET}" --strip-components=1 -C /opt/navio; \
    rm -f "${ASSET}"; \
    ls -la /opt/navio/bin

############################################
# Stage 1b — fetch + verify the i2pd package (i2p target only)
############################################
FROM fetch-base AS fetch-i2pd

# i2pd release to bundle. Bump to pick up i2pd fixes independently of navio.
ARG I2PD_VERSION=2.61.0
ARG TARGETARCH
ARG TARGETVARIANT

WORKDIR /tmp/i2pd

# Upstream publishes a Debian bookworm .deb per architecture plus SHA512SUMS.
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT:+/${TARGETVARIANT}}" in \
        amd64)  DEB_ARCH="amd64" ;; \
        arm64)  DEB_ARCH="arm64" ;; \
        arm/v7) DEB_ARCH="armhf" ;; \
        *) echo "no i2pd bookworm package for platform: ${TARGETARCH}${TARGETVARIANT:-}" >&2; exit 1 ;; \
    esac; \
    BASE="https://github.com/PurpleI2P/i2pd/releases/download/${I2PD_VERSION}"; \
    DEB="i2pd_${I2PD_VERSION}-1bookworm1_${DEB_ARCH}.deb"; \
    curl -fsSL -o "${DEB}" "${BASE}/${DEB}"; \
    curl -fsSL -o SHA512SUMS "${BASE}/SHA512SUMS"; \
    sha512sum --ignore-missing --check SHA512SUMS; \
    mv "${DEB}" /tmp/i2pd.deb

############################################
# Stage 2 — thin runtime image
############################################
FROM debian:bookworm-slim AS base

LABEL org.opencontainers.image.title="navio" \
      org.opencontainers.image.description="Navio full node (naviod) — thin image built from official navio-core release binaries" \
      org.opencontainers.image.source="https://github.com/nav-io/navio-docker" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates tini \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --home-dir /home/navio --shell /usr/sbin/nologin navio

COPY --from=fetch /opt/navio/bin/ /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER navio
WORKDIR /home/navio
ENV HOME=/home/navio
RUN mkdir -p /home/navio/.navio
VOLUME ["/home/navio/.navio"]

# Mainnet P2P/RPC 48470/48471, testnet7 P2P/RPC 33670/33677.
# RPC ports are loopback-only by default — map them explicitly if you expose RPC.
EXPOSE 48470 48471 33670 33677

# -g sends `docker stop`'s SIGTERM to the whole process group, so a bundled
# router (i2p/tor targets) stops along with naviod.
ENTRYPOINT ["tini", "-g", "--", "entrypoint.sh"]
CMD ["naviod"]

############################################
# Target: i2p — node plus a bundled i2pd router
############################################
FROM base AS i2p

LABEL org.opencontainers.image.description="Navio full node (naviod) with a bundled i2pd router — built from official navio-core and i2pd releases"

USER root
# apt resolves the package's runtime libraries (boost, openssl, miniupnpc).
# Nothing runs the package's init/systemd units in a container; the entrypoint
# starts i2pd instead.
COPY --from=fetch-i2pd /tmp/i2pd.deb /tmp/i2pd.deb
RUN apt-get update && apt-get install -y --no-install-recommends /tmp/i2pd.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/i2pd.deb
COPY i2pd.conf /etc/i2pd/i2pd.conf

USER navio
RUN mkdir -p /home/navio/.i2pd
VOLUME ["/home/navio/.i2pd"]

# Tells the entrypoint to start i2pd and point naviod at its SAM bridge.
# Set NAVIO_I2P=0 at run time to run the node without it.
ENV NAVIO_I2P=1

# i2pd router transport (NTCP2 TCP + SSU2 UDP); see `port` in i2pd.conf.
EXPOSE 48480/tcp 48480/udp

############################################
# Target: tor — node plus a bundled Tor client
############################################
FROM base AS tor

LABEL org.opencontainers.image.description="Navio full node (naviod) with a bundled Tor client — built from official navio-core releases and Debian's tor package"

USER root
# Debian's tor package; bookworm receives new tor releases via stable updates.
# Nothing runs its init/systemd units in a container; the entrypoint starts tor.
RUN apt-get update && apt-get install -y --no-install-recommends tor \
    && rm -rf /var/lib/apt/lists/*
COPY torrc /etc/tor/torrc

USER navio
# Tor refuses a DataDirectory readable by anyone but its owner.
RUN mkdir -m 700 /home/navio/.tor
VOLUME ["/home/navio/.tor"]

# Tells the entrypoint to start tor and point naviod at it.
# Set NAVIO_TOR=0 at run time to run the node without it.
ENV NAVIO_TOR=1

############################################
# Target: node (default) — declared last so a plain `docker build` picks it
############################################
FROM base AS node
