#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
npm install --prefix "$TMP" --ignore-scripts --no-audit --no-fund \
  @ai-ecoverse/slicc-kernel@1.21.1 \
  @ai-ecoverse/wasm-bash@5.3.0-8 \
  @ai-ecoverse/wasm-coreutils@9.12.0-3 \
  @ai-ecoverse/wasm-curl@8.22.0-1 \
  @ai-ecoverse/wasm-jq@1.8.2-1 \
  @ai-ecoverse/wasm-sed@4.10.0-1 \
  @ai-ecoverse/wasm-gawk@5.4.1-1 \
  @ai-ecoverse/wasm-grep@3.12.0-3 \
  @ai-ecoverse/wasm-findutils@4.11.0-1 \
  @ai-ecoverse/wasm-tls-engine@3.6.7-1
KERNEL_NODE_MODULES="$TMP/node_modules" node "$ROOT_DIR/tests/test-kernel.mjs"
