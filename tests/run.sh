#!/usr/bin/env bash
# Runs the node unit tests, then each tests/integration/*.qml inside real
# Quickshell against the installed Omarchy UI modules, so a host API change
# fails here instead of in the bar. hyprctl, hyprsunset, pgrep, uwsm-app and
# curl are faked (tests/bin) and HOME is a scratch directory: nothing touches
# the live display, the running shell, or your settings.
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_shell=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}

echo "# unit"
node --test "$source_root/tests/"

[[ -n ${WAYLAND_DISPLAY:-} ]] || { echo "run.sh: integration tests need a Wayland session" >&2; exit 1; }

test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

failed=0
for test in "$source_root"/tests/integration/*.qml; do
  name=$(basename -- "$test" .qml)
  work="$test_root/$name"
  mkdir -p "$work/app/plugin" "$work/app/host" "$work/fake" "$work/home/.local/state/omarchy/settings"
  cp -- "$source_root"/*.qml "$source_root"/*.js "$source_root"/manifest.json "$work/app/plugin/"
  cp -r -- "$omarchy_shell/Commons" "$omarchy_shell/Ui" "$work/app/"
  cp -- "$omarchy_shell/services/PluginShellApi.qml" "$work/app/host/"
  cp -- "$test" "$work/app/shell.qml"

  HOME="$work/home" PATH="$source_root/tests/bin:$PATH" FAKE_HYPRSUNSET="$work/fake" \
    timeout 60s qs --no-color -p "$work/app" >"$work/output" 2>&1 || true

  if grep -q NIGHTLIGHT_PASS "$work/output" \
    && ! grep -E '(plugin|shell)\.qml.*(ReferenceError|TypeError)|@plugin/.*(ReferenceError|TypeError)' "$work/output"; then
    grep -E 'ok  - ' "$work/output" | sed 's/.*ok  - /  ok  - /'
    echo "PASS $name"
  else
    cat -- "$work/output"
    echo "FAIL $name"
    failed=1
  fi
done
exit "$failed"
