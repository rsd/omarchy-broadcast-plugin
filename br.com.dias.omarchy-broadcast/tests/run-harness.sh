#!/bin/sh
# Run tests/harness/shell.qml in a throwaway Quickshell: never the user's
# shell, never ~/.config/omarchy/plugins. Every run builds a new directory of
# its own (mktemp -d), inside --work DIR if given, else in $TMPDIR; nothing
# outside it is ever removed. It holds:
#
#   qs/        the harness config: shell.qml, Commons -> Omarchy's, Ui copied
#              with tests/harness/KeyboardPanel.qml in place of the layer-shell
#              popup (no compositor offscreen)
#   bin/       omarchy-broadcast = a copy of tests/fake-omarchy-broadcast; its path is
#              the unique marker the harness counts watch processes by
#   fake/      the fake's snapshot, feed, log and exit/stderr/delay files
#   plugins/   a symlink to the plugin dir, as an install would make one
#   devrepo/   a scratch "repository": a copy of the plugin under
#              clients/omarchy-bar/ and the fake as target/release/omarchy-broadcast;
#              devlink/ links to that copy (the development-build resolution)
#   nl/        directories whose names hold a newline (resolver framing)
#   screens/   PNG grabs, unless --screens DIR is given
#
# Usage:
#   tests/run-harness.sh [--work DIR] [--screens DIR]          mock CLI
#   tests/run-harness.sh --live [--work DIR] [--screens DIR]   real daemon + CLI
#
# --work DIR must be empty, missing, or a directory an earlier run created
# (it carries a .omarchy-broadcast-harness marker); anything else is refused.
#
# --live starts target/release/omarchy-broadcastd itself (scratch --config and
# --state under the work dir), drives the real CLI, opens /dev/video11 with
# gst-launch for ~12 s, kills the daemon by PID, restarts it, and stops it.
# It refuses to run if br.com.dias.OmarchyBroadcast already has an owner.
#
# Exit status 0 when the harness prints "ALL OK". Whatever it started is gone
# when this returns (checked with pgrep on the work-dir marker; anything left
# is stopped by PID).
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
plugin=$(dirname -- "$here")
repo=$(cd -- "$plugin/../../.." && pwd)
shell_dir=${OMARCHY_SHELL:-/usr/share/omarchy/shell}
mode=mock
work=""
screens=""
while [ $# -gt 0 ]; do
  case $1 in
    --live) mode=live ;;
    --work) work=$2; shift ;;
    --screens) screens=$2; shift ;;
    *) echo "usage: $0 [--live] [--work DIR] [--screens DIR]" >&2; exit 2 ;;
  esac
  shift
done

command -v quickshell >/dev/null || { echo "harness: quickshell is not installed" >&2; exit 1; }
[ -d "$shell_dir/Ui" ] || { echo "harness: Omarchy shell not found at $shell_dir" >&2; exit 1; }

marker=.omarchy-broadcast-harness
if [ -z "$work" ]; then
  work=$(mktemp -d "${TMPDIR:-/tmp}/obh.XXXXXX")
else
  if [ -e "$work" ] && [ ! -d "$work" ]; then
    echo "harness: --work $work is not a directory" >&2; exit 2
  fi
  if [ -d "$work" ] && [ ! -e "$work/$marker" ] && [ -n "$(ls -A -- "$work" 2>/dev/null)" ]; then
    echo "harness: --work $work is not empty and was not made by this harness; give a new or empty directory" >&2
    exit 2
  fi
  mkdir -p -- "$work"
  : > "$work/$marker"
  # A fresh directory per run: nothing of an earlier run, or of anyone
  # else, is deleted to make room.
  work=$(mktemp -d "$(cd -- "$work" && pwd)/obh.XXXXXX")
fi
echo "harness: work directory $work"
[ -n "$screens" ] || screens=$work/screens
mkdir -p "$screens"

mkdir -p "$work/qs" "$work/bin" "$work/fake" "$work/plugins" "$work/norepo/a/b/br.com.dias.omarchy-broadcast"
cp "$here/harness/shell.qml" "$work/qs/shell.qml"
ln -s "$shell_dir/Commons" "$work/qs/Commons"
cp -R "$shell_dir/Ui" "$work/qs/Ui"
cp "$here/harness/KeyboardPanel.qml" "$work/qs/Ui/KeyboardPanel.qml"
cp "$here/fake-omarchy-broadcast" "$work/bin/omarchy-broadcast"
chmod +x "$work/bin/omarchy-broadcast"
ln -s "$plugin" "$work/plugins/br.com.dias.omarchy-broadcast"
# The plugin again at another URL, for a reload that yields a new singleton.
mkdir -p "$work/reload/br.com.dias.omarchy-broadcast"
cp "$plugin"/*.qml "$plugin"/*.js "$plugin"/qmldir "$plugin"/manifest.json "$work/reload/br.com.dias.omarchy-broadcast/"
mkdir -m 700 "$work/runtime"
# A scratch repository for the development-build resolution, reached through a
# symlinked plugin dir as an install makes one.
devplugin=$work/devrepo/clients/omarchy-bar/br.com.dias.omarchy-broadcast
mkdir -p "$devplugin" "$work/devrepo/target/release" "$work/devlink"
cp "$plugin"/*.qml "$plugin"/*.js "$plugin"/qmldir "$plugin"/manifest.json "$devplugin/"
cp "$here/fake-omarchy-broadcast" "$work/devrepo/target/release/omarchy-broadcast"
chmod +x "$work/devrepo/target/release/omarchy-broadcast"
ln -s "$devplugin" "$work/devlink/br.com.dias.omarchy-broadcast"
# Names with a newline: a repository dir, and a PATH entry holding a CLI.
nl='
'
nlrepo="$work/nl/repo${nl}x"
mkdir -p "$nlrepo/clients/omarchy-bar/br.com.dias.omarchy-broadcast" "$nlrepo/target/release" "$work/nl/bin${nl}y"
cp "$here/fake-omarchy-broadcast" "$nlrepo/target/release/omarchy-broadcast"
cp "$here/fake-omarchy-broadcast" "$work/nl/bin${nl}y/omarchy-broadcast"
chmod +x "$nlrepo/target/release/omarchy-broadcast" "$work/nl/bin${nl}y/omarchy-broadcast"

if [ "$mode" = live ]; then
  cli=$repo/target/release/omarchy-broadcast
  daemon=$repo/target/release/omarchy-broadcastd
  [ -x "$cli" ] && [ -x "$daemon" ] || { echo "harness: build the release binaries first" >&2; exit 1; }
  if busctl --user status br.com.dias.OmarchyBroadcast >/dev/null 2>&1; then
    echo "harness: br.com.dias.OmarchyBroadcast already has an owner; not starting a second daemon" >&2
    exit 1
  fi
  mkdir -p "$work/live"
  : > "$work/live/config.toml"
  rm -f -- "$work/live/state.toml"
  marker_prefix="^"
else
  cli=$work/bin/omarchy-broadcast
  marker_prefix="^/bin/sh "
fi

log=$work/harness-$mode.log
(
  # Offscreen: no session needed. Omarchy's gtk3 platform theme opens a GTK
  # display of its own even offscreen, so it is dropped too. PATH holds the
  # fake first, so the "no cliPath" case resolves it from PATH.
  unset WAYLAND_DISPLAY DISPLAY QT_QPA_PLATFORMTHEME
  export QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$work/runtime"
  export PATH="$work/bin:/usr/bin:/bin"
  export FAKE_OB_DIR="$work/fake"
  export OBH_MODE="$mode" OBH_PLUGIN="$plugin" OBH_PLUGIN_COPY="$work/reload/br.com.dias.omarchy-broadcast" OBH_CLI="$cli" OBH_FAKE="$work/fake" \
         OBH_SCREENS="$screens" OBH_LINKED="$work/plugins/br.com.dias.omarchy-broadcast" \
         OBH_NOREPO="$work/norepo/a/b/br.com.dias.omarchy-broadcast" \
         OBH_REPO_CLI="$repo/target/release/omarchy-broadcast" \
         OBH_DAEMON="$repo/target/release/omarchy-broadcastd" OBH_LIVE="$work/live" \
         OBH_DEVLINK="$work/devlink/br.com.dias.omarchy-broadcast" \
         OBH_DEVCLI="$work/devrepo/target/release/omarchy-broadcast" \
         OBH_NLPLUGIN="$nlrepo/clients/omarchy-bar/br.com.dias.omarchy-broadcast" \
         OBH_NLBIN="$work/nl/bin${nl}y"
  exec quickshell -p "$work/qs"
) > "$log" 2>&1 &
qs_pid=$!

limit=180
[ "$mode" = live ] && limit=300
elapsed=0
result=""
while [ "$elapsed" -lt "$limit" ]; do
  # Quickshell colours its log lines; strip the escapes before matching.
  if sed 's/\x1b\[[0-9;]*m//g' "$log" 2>/dev/null | grep -Eq 'qml: (ALL OK|[0-9]+ FAILED)'; then
    result="done"
    break
  fi
  kill -0 "$qs_pid" 2>/dev/null || break
  sleep 1
  elapsed=$((elapsed + 1))
done
kill -TERM "$qs_pid" 2>/dev/null || true
wait "$qs_pid" 2>/dev/null || true

# Anything this run started and the harness did not stop: by PID only.
# Paths are regex-escaped: pgrep -f takes a regular expression.
escape() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }
left=$(pgrep -f "$marker_prefix$(escape "$cli") " || true)
left="$left $(pgrep -f "^/bin/sh $(escape "$work/devrepo/target/release/omarchy-broadcast") " || true)"
if [ "$mode" = live ]; then
  left="$left $(pgrep -f "^$(escape "$daemon") --config $(escape "$work/live/config.toml")" || true)"
fi
leftovers=0
for pid in $left; do
  leftovers=$((leftovers + 1))
  echo "harness: stopping leftover process $pid: $(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)" >&2
  kill -TERM "$pid" 2>/dev/null || true
done

sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E 'qml: ' | sed 's/^.*qml: //'
echo "log: $log"
echo "screens: $screens"
[ "$result" = "done" ] || { echo "harness: no result within ${limit}s" >&2; exit 1; }
[ "$leftovers" -eq 0 ] || { echo "harness: $leftovers process(es) left running" >&2; exit 1; }
sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -q 'qml: ALL OK'
