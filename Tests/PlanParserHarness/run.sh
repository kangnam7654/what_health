#!/usr/bin/env bash
# Offline regression harness for PlanParser / ChatResponseParser.
#
# Compiles the real app sources together with main.swift for macOS and runs
# the resulting binary. Uses only synthetic fixtures — no network, no model call.
# All build output (binary, module cache, compiler temp files) lives in a fresh
# temporary directory that is removed on exit. Works from any cwd.
#
# Usage: bash Tests/PlanParserHarness/run.sh
# Exit status: 0 if every check passes, nonzero on compile or test failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP="$REPO_ROOT/WhatHealthApp"

SOURCES=(
  "$APP/Models/Enums.swift"
  "$APP/Models/CodableTypes.swift"
  "$APP/Services/LLMService/LLMServiceProtocol.swift"
  "$APP/Services/PlanParser.swift"
  "$APP/Services/ChatResponseParser.swift"
  "$SCRIPT_DIR/main.swift"
)

for src in "${SOURCES[@]}"; do
  if [[ ! -f "$src" ]]; then
    echo "missing source: $src" >&2
    exit 2
  fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/planparser-harness.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

if command -v xcrun >/dev/null 2>&1; then
  SWIFTC=(xcrun --sdk macosx swiftc)
else
  SWIFTC=(swiftc)
fi

BINARY="$WORK_DIR/planparser-harness"

echo "Compiling harness in $WORK_DIR"
TMPDIR="$WORK_DIR" "${SWIFTC[@]}" \
  -swift-version 5 \
  -module-name PlanParserHarness \
  -module-cache-path "$WORK_DIR/module-cache" \
  -o "$BINARY" \
  "${SOURCES[@]}"

cd "$WORK_DIR"
"$BINARY"
