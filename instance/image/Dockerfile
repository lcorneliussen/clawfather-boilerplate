# check=skip=InvalidDefaultArgInFrom
# Instance image: the core image plus this deployment's tools. Instance-owned.
#
# `bin/claw build` builds core/image first and passes it in as CORE_IMAGE, so
# this file only adds what this deployment needs — a language runtime, a
# vault CLI, a patch. Keep checksums on every download. The build context is
# the repository root.
ARG CORE_IMAGE
FROM ${CORE_IMAGE}

# USER root
# RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client \
#     && rm -rf /var/lib/apt/lists/*
# USER node
