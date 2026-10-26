#!/bin/bash
# Build the Forms 12.2.1.4 image chain:
#   container-registry.oracle.com/java/serverjre:8  → oracle/serverjdk:8
#   images/fmw-infrastructure                       → oracle/fmw-infrastructure:12.2.1.4
#   images/formsreports                             → oracle/formsreports:12.2.1.4
#
#   docker login container-registry.oracle.com      # once, with your Oracle account
#   ./build-images.sh
#
# The Oracle installers must be in place first (see README.md). x86_64 only.
set -euo pipefail
cd "$(dirname "$0")"

need(){ [ -f "$1" ] || { echo "missing installer: $1 (see README.md)" >&2; exit 1; }; }
need images/fmw-infrastructure/fmw_12.2.1.4.0_infrastructure.jar
need images/formsreports/fmw_12.2.1.4.0_fr_linux64.bin
need images/formsreports/fmw_12.2.1.4.0_fr_linux64-2.zip

if [ "$(uname -m)" != x86_64 ]; then
  echo "WARNING: $(uname -m) host. These images are x86_64 (amd64) only." >&2
fi

if ! docker image inspect oracle/serverjdk:8 >/dev/null 2>&1; then
  docker pull container-registry.oracle.com/java/serverjre:8
  docker tag container-registry.oracle.com/java/serverjre:8 oracle/serverjdk:8
fi
docker build -t oracle/fmw-infrastructure:12.2.1.4 images/fmw-infrastructure
docker build -t oracle/formsreports:12.2.1.4 images/formsreports
docker image ls 'oracle/*'
