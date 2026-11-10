#!/usr/bin/env bash
# The npm package in the SLICC kernel: pnpm add -g, and seven's tools root.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
npm install --prefix "$TMP/kernel" --ignore-scripts --no-audit --no-fund \
  @ai-ecoverse/slicc-kernel@1.177.0 \
  @ai-ecoverse/wasi-pnpm@12.9.1-21 \
  @ai-ecoverse/wasm-bash@5.3.0-23 \
  @ai-ecoverse/wasm-coreutils@9.12.0-15 \
  @ai-ecoverse/wasm-findutils@4.11.0-5 \
  @ai-ecoverse/wasm-sed@4.10.0-6 \
  @ai-ecoverse/wasm-grep@3.12.0-8 \
  @ai-ecoverse/wasm-gawk@5.4.1-6 \
  @ai-ecoverse/wasm-jq@1.8.2-6 >/dev/null
mkdir -p "$TMP/src"
(cd "$ROOT_DIR" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | tar -C "$TMP/src" -xf -
(cd "$TMP/src" && npm version 9.8.7 --no-git-tag-version --allow-same-version >/dev/null)
(cd "$TMP/src" && npm pack --silent --pack-destination "$TMP" >/dev/null)
KERNEL_NODE_MODULES="$TMP/kernel/node_modules" UPSKILL_TGZ="$TMP/ai-ecoverse-gh-upskill-9.8.7.tgz" \
  node "$ROOT_DIR/tests/test-package-kernel.mjs"
