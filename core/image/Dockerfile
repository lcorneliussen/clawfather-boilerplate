# Core runtime image: the pinned upstream OpenClaw image plus the tools every
# team server needs — the GitHub CLI (bundled `github` / `gh-issues` skills) and
# a static Docker CLI (for gateways that create sandbox containers through a
# mounted socket; unused otherwise).
#
# Upstream-owned. Instance additions go in instance/image/Dockerfile, which is built
# FROM this image (`bin/claw build`). Bump OPENCLAW_IMAGE through
# instance/claw.env (OPENCLAW_IMAGE), not here, unless the boilerplate default moves.
ARG OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:2026.9.6-browser

FROM debian:bookworm-slim AS tool-fetch
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
ARG GH_VERSION=2.101.0
ARG GH_SHA256_AMD64=9bca2d1c16825f109907a23307628a2f0698fbf99662b73a5cf0b020293072b8
ARG GH_SHA256_ARM64=b57e8063f18862647c9d22727c32e9da1b963f8bf9db648fe123a6975695640f
ARG DOCKER_VERSION=28.5.1
ARG DOCKER_SHA256_AMD64=5c0d19f31fece1accd0358bb8cff591fe25d7b6cba19f0fd412cbfdc07f75ff6
ARG DOCKER_SHA256_ARM64=de54e37157f45a43f42f6271302372d95c0eb992cc35ecaee74989bb14058c94

# Every download is verified; a missing checksum fails the build. gh sums
# come from the release's checksums file; Docker publishes none, so its sums
# were taken from the pinned tarballs (bump both together).
RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
      amd64) gh_arch=amd64; docker_arch=x86_64; gh_sum="$GH_SHA256_AMD64"; docker_sum="$DOCKER_SHA256_AMD64" ;; \
      arm64) gh_arch=arm64; docker_arch=aarch64; gh_sum="$GH_SHA256_ARM64"; docker_sum="$DOCKER_SHA256_ARM64" ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl --fail --silent --show-error --location --output /tmp/gh.tar.gz \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${gh_arch}.tar.gz"; \
    echo "${gh_sum:?missing gh checksum}  /tmp/gh.tar.gz" | sha256sum --check --strict; \
    tar -xzf /tmp/gh.tar.gz -C /tmp; \
    install -D -m 0755 "/tmp/gh_${GH_VERSION}_linux_${gh_arch}/bin/gh" /out/gh; \
    curl --fail --silent --show-error --location --output /tmp/docker.tgz \
      "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${DOCKER_VERSION}.tgz"; \
    echo "${docker_sum:?missing docker checksum}  /tmp/docker.tgz" | sha256sum --check --strict; \
    tar -xzf /tmp/docker.tgz -C /tmp docker/docker; \
    install -D -m 0755 /tmp/docker/docker /out/docker

FROM ${OPENCLAW_IMAGE}
USER root
COPY --from=tool-fetch /out/gh /out/docker /usr/local/bin/
USER node
RUN gh --version && docker --version
