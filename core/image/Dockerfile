# Core runtime image: the pinned upstream OpenClaw image plus the tools every
# team server needs — the GitHub CLI (bundled `github` / `gh-issues` skills) and
# a static Docker CLI (for gateways that create sandbox containers through a
# mounted socket; unused otherwise).
#
# Upstream-owned. Site additions go in site/image/Dockerfile, which is built
# FROM this image (`bin/claw build`). Bump OPENCLAW_IMAGE through
# site/claw.env (OPENCLAW_IMAGE), not here, unless the boilerplate default moves.
ARG OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:2026.9.6-browser

FROM debian:bookworm-slim AS tool-fetch
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
ARG GH_VERSION=2.101.0
ARG GH_SHA256_AMD64=9bca2d1c16825f109907a23307628a2f0698fbf99662b73a5cf0b020293072b8
ARG GH_SHA256_ARM64=
ARG DOCKER_VERSION=28.5.1
ARG DOCKER_SHA256_AMD64=5c0d19f31fece1accd0358bb8cff591fe25d7b6cba19f0fd412cbfdc07f75ff6
ARG DOCKER_SHA256_ARM64=

# Checksums are enforced for amd64 (the hosted profiles). arm64 is for local
# workstations; set the *_ARM64 checksums to enforce them there too.
RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
      amd64) gh_arch=amd64; docker_arch=x86_64; gh_sum="$GH_SHA256_AMD64"; docker_sum="$DOCKER_SHA256_AMD64" ;; \
      arm64) gh_arch=arm64; docker_arch=aarch64; gh_sum="$GH_SHA256_ARM64"; docker_sum="$DOCKER_SHA256_ARM64" ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl --fail --silent --show-error --location --output /tmp/gh.tar.gz \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${gh_arch}.tar.gz"; \
    if [ -n "$gh_sum" ]; then echo "${gh_sum}  /tmp/gh.tar.gz" | sha256sum --check --strict; fi; \
    tar -xzf /tmp/gh.tar.gz -C /tmp; \
    install -D -m 0755 "/tmp/gh_${GH_VERSION}_linux_${gh_arch}/bin/gh" /out/gh; \
    curl --fail --silent --show-error --location --output /tmp/docker.tgz \
      "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${DOCKER_VERSION}.tgz"; \
    if [ -n "$docker_sum" ]; then echo "${docker_sum}  /tmp/docker.tgz" | sha256sum --check --strict; fi; \
    tar -xzf /tmp/docker.tgz -C /tmp docker/docker; \
    install -D -m 0755 /tmp/docker/docker /out/docker

FROM ${OPENCLAW_IMAGE}
USER root
COPY --from=tool-fetch /out/gh /out/docker /usr/local/bin/
USER node
RUN gh --version && docker --version
