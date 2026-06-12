# syntax=docker/dockerfile:1
#
# Thin Navio full-node image.
#
# It ships the official, pre-built navio-core release binaries (downloaded and
# checksum-verified at build time) on top of debian-slim. The release binaries
# are statically linked against everything except glibc, so the runtime layer
# needs no extra libraries.

############################################
# Stage 1 — fetch + verify release binaries
############################################
FROM debian:bookworm-slim AS fetch

# Which navio-core release to ship. "latest" resolves the newest release
# (including release candidates) from the GitHub API at build time. Override
# with e.g. --build-arg NAVIO_RELEASE_TAG=v0.1rc30 to pin.
ARG NAVIO_RELEASE_TAG=latest

# Provided automatically by buildx for each target platform.
ARG TARGETARCH
ARG TARGETVARIANT

ARG GITHUB_API=https://api.github.com/repos/nav-io/navio-core

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl jq \
    && rm -rf /var/lib/apt/lists/*

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
# Stage 2 — thin runtime image
############################################
FROM debian:bookworm-slim

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

ENTRYPOINT ["tini", "--", "entrypoint.sh"]
CMD ["naviod"]
