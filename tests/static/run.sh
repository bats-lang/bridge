#!/bin/sh
# Static tests of bridge's typed handles and ids. Each package under
# tests/static/accept/ must pass `bats check`; each under
# tests/static/reject/ must fail it with the message in its `expect`
# file (so it is rejected for the right reason); each line of an
# `expect` is a message it may fail with.
# Fixtures depend on this checkout, which is uploaded to a scratch copy
# of the repository first.
#
# usage: tests/static/run.sh <repository-dir>   (bats must be on PATH)
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

fail=0

# Plugin names: the JS gets a Capacitor plugin's name only from the table
# in src/plugins.bats (put_plugin_call), so no atom can use a plugin the
# native app does not install (pwa writes its package.json from the same
# table). A capPlugin('...') written anywhere else is rejected; the
# fixture under tests/static/plugin-names must be.
plugin_names() { # dir -> the capPlugin('...') written outside the table
  grep -rn "capPlugin('" "$1" --include='*.bats' | grep -v "/plugins\.bats:" || true
}
if [ -n "$(plugin_names "$ROOT/src")" ]; then
  echo "FAIL plugin-names: a plugin named outside src/plugins.bats:"; plugin_names "$ROOT/src"; fail=1
else echo "ok   plugin-names"; fi
if [ -n "$(plugin_names "$ROOT/tests/static/plugin-names")" ]; then echo "ok   plugin-names/reject"
else echo "FAIL plugin-names/reject: should be rejected"; fail=1; fi

check() { # dir -> runs lock + check, log in $TMP/<name>.log
  w="$TMP/w-$(basename "$1")"
  rm -rf "$w"; cp -R "$1" "$w"
  # --dev: the checkout uploads as a dev version, which bats lock skips
  # without it (as the Rust bats does).
  (cd "$w" && bats lock --dev --repository "$TMP/repo" && bats check --repository "$TMP/repo") \
    > "$TMP/$(basename "$1").log" 2>&1
}

for d in "$ROOT"/tests/static/accept/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if check "$d"; then echo "ok   accept/$n"
  else echo "FAIL accept/$n: should type-check"; grep -E 'error' "$TMP/$n.log" | head -5; fail=1; fi
done

for d in "$ROOT"/tests/static/reject/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if check "$d"; then echo "FAIL reject/$n: should be rejected"; fail=1
  elif grep -qF -- "$(cat "$d/expect")" "$TMP/$n.log"; then echo "ok   reject/$n"
  else echo "FAIL reject/$n: rejected, but not with: $(cat "$d/expect")"; grep -E 'error' "$TMP/$n.log" | head -5; fail=1; fi
done
exit $fail
