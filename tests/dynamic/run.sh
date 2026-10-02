#!/bin/sh
# Dynamic tests. Each package under tests/dynamic/ depends on this
# checkout (uploaded to a scratch copy of the repository first). It has
# a native binary `gen` that writes dist/pwa/ (bridge.js and app.wasm,
# with pwa) and a wasm binary `app` that drives the bridge; check.mjs runs the
# app in jsdom with the generated bridge.js and prints the resulting
# HTML, which must match the package's `expected` file exactly.
#
# usage: tests/dynamic/run.sh <repository-dir>
#   (bats and node on PATH; npm install run in tests/dynamic for jsdom)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp -R "$1" "$TMP/repo"
(cd "$ROOT" && bats upload --repository "$TMP/repo" >/dev/null)
# Keep only the archive just uploaded, so lock cannot pick a published
# version instead (an uncommitted checkout uploads as <version>dev1,
# which sorts below a release of the same commit).
PKG=$(sed -n 's/^name *= *"\(.*\)"/\1/p' "$ROOT/bats.toml" | head -1)
NEW=$(ls -t "$TMP/repo/$PKG"/*.bats | head -1)
for a in "$TMP/repo/$PKG"/*.bats; do
  [ "$a" = "$NEW" ] || rm -f "$a" "$a.sha256"
done

# A test that hangs must fail, not stall CI. `timeout` is GNU coreutils;
# where it is missing the programs run without a limit.
LIMIT=""
if command -v timeout >/dev/null 2>&1; then LIMIT="timeout 300"; fi

fail=0
for d in "$ROOT"/tests/dynamic/*/; do
  [ -f "$d/bats.toml" ] || continue
  n=$(basename "$d"); w="$TMP/w-$n"
  cp -R "$d" "$w"
  ln -s "$ROOT/tests/dynamic/node_modules" "$w/node_modules"
  # --dev: the checkout uploads as a dev version, which bats lock skips
  # without it (as the Rust bats does).
  if (cd "$w" && bats lock --dev --repository "$TMP/repo" && bats build --only debug --repository "$TMP/repo") > "$TMP/$n.log" 2>&1 \
     && (cd "$w" && $LIMIT ./dist/debug/gen && $LIMIT node check.mjs) > "$TMP/$n.out" 2>&1 \
     && diff -u "$d/expected" "$TMP/$n.out"; then
    echo "ok   $n"
  else
    echo "FAIL $n"; cat "$TMP/$n.log" "$TMP/$n.out" 2>/dev/null | grep -E 'error|Error|FAIL' | head -10; fail=1
  fi
done
exit $fail
