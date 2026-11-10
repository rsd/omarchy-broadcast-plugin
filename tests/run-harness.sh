#!/bin/sh
# Run tests/harness/shell.qml in a throwaway Quickshell: never the user's
# shell, never ~/.config/omarchy/plugins. Every run builds a new directory of
# its own (mktemp -d), inside --work DIR if given, else in $TMPDIR; nothing
# outside it is ever removed. It holds:
#
#   plugin/    the plugin's files the harness loads, copied from the checkout
#              (SetupDialog.qml without its layer-shell namespace line, which
#              the stub OverlayWindow cannot take); reload/ a second copy
#   qs/        the harness config: shell.qml, Commons -> Omarchy's, Ui copied
#              with tests/harness/KeyboardPanel.qml and OverlayWindow.qml in
#              place of the layer-shell popup and overlay (no compositor
#              offscreen)
#   bin/       omarchy-broadcast = a copy of tests/fake-omarchy-broadcast; its path is
#              the unique marker the harness counts watch processes by
#   fake/      the fake's snapshot, feed, log and exit/stderr/delay files, and
#              frames/0..3.jpg: four real 480x270 JPEGs (gst-launch-1.0
#              videotestsrc ! jpegenc, else ImageMagick) the fake's `preview`
#              mode copies into runtime/
#   runtime/   XDG_RUNTIME_DIR of the harness shell and the fake (0700): the
#              fake's preview.jpg goes here, never the user's runtime dir
#   sysbin/    mock only: symlinks to every executable in /usr/bin and /bin
#              except omarchy-broadcast*. The shell's PATH is bin/ then
#              sysbin/, so the only omarchy-broadcast it can ever find is the
#              fake; the run refuses to start if anything else would answer
#   nl/        a PATH entry whose name holds a newline, with a CLI in it
#              (resolver framing)
#   rbin/      an empty directory: the resolver cases' PATH (OBH_RESOLVER_PATH;
#              the resolver script needs no external tool), so an
#              omarchy-broadcast installed in /usr/bin cannot answer for them
#   realbin/   only with OMARCHY_BROADCAST_CLI (mock): omarchy-broadcast, a
#              symlink to that real CLI, for one resolver case that puts
#              realbin/ on PATH. The resolver only prints the path it finds;
#              nothing runs the real CLI in mock mode
#   live/      live only: the daemon's scratch config, state and log, and
#              bin/omarchy-broadcast, a symlink to OMARCHY_BROADCAST_CLI that
#              the widgets run: its path (argv[0]) is the unique marker the
#              harness counts and stops watch processes by, so a bar of the
#              user's own running the same CLI is never matched
#   screens/   PNG grabs, unless --screens DIR is given
#
# Usage:
#   tests/run-harness.sh [--work DIR] [--screens DIR]          mock CLI
#   tests/run-harness.sh --live [--work DIR] [--screens DIR]   real daemon + CLI
#
# Environment:
#   OMARCHY_SHELL          the Omarchy shell modules (default /usr/share/omarchy/shell)
#   OMARCHY_BROADCAST_CLI  absolute path of a real omarchy-broadcast binary.
#                          Mock: adds a resolver case that finds it on a PATH
#                          (never executed); unset, that case prints SKIP.
#                          Nothing else in a mock run can reach it: the shell's
#                          PATH holds the fake only. Live: the CLI the widgets drive,
#                          run through live/bin/omarchy-broadcast (required)
#   OMARCHY_BROADCASTD     live only: the omarchy-broadcastd binary (default:
#                          omarchy-broadcastd next to OMARCHY_BROADCAST_CLI)
#
# --work DIR must be empty, missing, or a directory an earlier run created
# (it carries a .omarchy-broadcast-harness marker); anything else is refused.
#
# --live starts OMARCHY_BROADCASTD itself (scratch --config and
# --state under the work dir), drives the real CLI, opens /dev/video11 with
# gst-launch for ~12 s, kills the daemon by PID, restarts it, and stops it.
# It refuses to run if br.com.dias.OmarchyBroadcast already has an owner.
#
# The work directory is removed when the run succeeds, and kept (with its path
# printed) when it fails or is signalled; KEEP_WORK=1 keeps it on success too.
#
# Exit status 0 when the harness prints "ALL OK". Whatever it started is gone
# when this returns (checked with pgrep on paths inside the work dir: the
# fake's copy, live/bin/omarchy-broadcast, the daemon's live/config.toml;
# anything left is stopped by PID).
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
plugin=$(dirname -- "$here")
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

# The real binaries, checked before anything is created.
real_cli=${OMARCHY_BROADCAST_CLI:-}
daemon=""
if [ -n "$real_cli" ]; then
  case $real_cli in
    /*) ;;
    *) echo "harness: OMARCHY_BROADCAST_CLI must be an absolute path, not $real_cli" >&2; exit 2 ;;
  esac
  [ -f "$real_cli" ] && [ -x "$real_cli" ] || { echo "harness: OMARCHY_BROADCAST_CLI=$real_cli is not an executable file" >&2; exit 2; }
fi
if [ "$mode" = live ]; then
  [ -n "$real_cli" ] || {
    echo "harness: --live needs OMARCHY_BROADCAST_CLI, the absolute path of a real omarchy-broadcast binary" >&2
    echo "harness: (and OMARCHY_BROADCASTD, default: omarchy-broadcastd next to it)" >&2
    exit 2
  }
  daemon=${OMARCHY_BROADCASTD:-$(dirname -- "$real_cli")/omarchy-broadcastd}
  case $daemon in
    /*) ;;
    *) echo "harness: OMARCHY_BROADCASTD must be an absolute path, not $daemon" >&2; exit 2 ;;
  esac
  [ -f "$daemon" ] && [ -x "$daemon" ] || { echo "harness: no executable omarchy-broadcastd at $daemon (set OMARCHY_BROADCASTD)" >&2; exit 2; }
fi

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
# Only the directory this run's mktemp made is removed, and only when the run
# succeeded: a failed or signalled run keeps it (log, fake log, screenshots) and
# says where it is. KEEP_WORK=1 keeps it on success too. On any exit, first
# stop what this run started: its quickshell and the leftovers the normal path
# below also stops (by PID; paths are regex-escaped, pgrep -f takes a regex).
made_work=$work
qs_pid=""
cli=""
marker_prefix=""
escape() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }
stop_leftovers() {
  left=""
  if [ -n "$cli" ]; then
    left=$(pgrep -f "$marker_prefix$(escape "$cli") " || true)
    if [ "$mode" = live ] && [ -n "$daemon" ]; then
      left="$left $(pgrep -f "^$(escape "$daemon") --config $(escape "$work/live/config.toml")" || true)"
    fi
  fi
  leftovers=0
  for pid in $left; do
    leftovers=$((leftovers + 1))
    echo "harness: stopping leftover process $pid: $(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)" >&2
    kill -TERM "$pid" 2>/dev/null || true
  done
}
# shellcheck disable=SC2329  # run by the EXIT trap
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [ -n "$qs_pid" ]; then
    kill -TERM "$qs_pid" 2>/dev/null || true
    wait "$qs_pid" 2>/dev/null || true
  fi
  stop_leftovers
  if [ -n "$made_work" ] && [ -d "$made_work" ]; then
    if [ "$status" -ne 0 ]; then
      echo "harness: failed (status $status); work directory kept at $made_work (log, fake/log, screens/)" >&2
    elif [ "${KEEP_WORK:-}" != 1 ]; then
      rm -rf -- "$made_work"
    fi
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
echo "harness: work directory $work"
[ -n "$screens" ] || screens=$work/screens
mkdir -p "$screens"

mkdir -p "$work/qs" "$work/bin" "$work/fake"
cp "$here/harness/shell.qml" "$work/qs/shell.qml"
ln -s "$shell_dir/Commons" "$work/qs/Commons"
cp -R "$shell_dir/Ui" "$work/qs/Ui"
cp "$here/harness/KeyboardPanel.qml" "$work/qs/Ui/KeyboardPanel.qml"
cp "$here/harness/OverlayWindow.qml" "$work/qs/Ui/OverlayWindow.qml"
cp "$here/fake-omarchy-broadcast" "$work/bin/omarchy-broadcast"
chmod +x "$work/bin/omarchy-broadcast"
# The plugin as the harness loads it (plugin/), and again at another URL for
# a reload that yields a new singleton (reload/): copies of the checkout's
# files, with one line taken out of SetupDialog.qml, its overlay's
# `WlrLayershell.namespace`. The stub OverlayWindow is an Item, which has no
# layer-shell object to attach, and the engine refuses to create a dialog
# that sets one; tests/check-source.py checks the line in the source.
for copy in "$work/plugin/br.com.dias.omarchy-broadcast" "$work/reload/br.com.dias.omarchy-broadcast"; do
  mkdir -p "$copy"
  cp "$plugin"/*.qml "$plugin"/*.js "$plugin"/qmldir "$plugin"/manifest.json "$copy/"
  ns_lines=$(grep -c '^ *WlrLayershell\.namespace: "omarchy-broadcast"$' "$copy/SetupDialog.qml" || true)
  [ "$ns_lines" = 1 ] || { echo "harness: SetupDialog.qml should set its overlay's namespace once, found $ns_lines" >&2; exit 1; }
  grep -v '^ *WlrLayershell\.namespace: "omarchy-broadcast"$' "$copy/SetupDialog.qml" > "$copy/SetupDialog.qml.new"
  mv "$copy/SetupDialog.qml.new" "$copy/SetupDialog.qml"
done
mkdir -m 700 "$work/runtime"
# Real JPEG frames for the fake's preview stream, made before the shell starts.
mkdir -p "$work/fake/frames"
i=0
for pattern in smpte smpte75 pinwheel ball; do
  frame=$work/fake/frames/$i.jpg
  if command -v gst-launch-1.0 >/dev/null 2>&1; then
    gst-launch-1.0 -q videotestsrc num-buffers=1 pattern="$pattern" \
      ! video/x-raw,width=480,height=270 ! jpegenc quality=70 ! filesink location="$frame" >/dev/null 2>&1 || true
  elif command -v magick >/dev/null 2>&1; then
    magick -seed "$((i + 1))" -size 480x270 "plasma:fractal" -quality 70 "$frame" >/dev/null 2>&1 || true
  fi
  [ "$(head -c 2 -- "$frame" 2>/dev/null | od -An -tx1 | tr -d ' ')" = "ffd8" ] || {
    echo "harness: could not make the JPEG frame $frame (needs gst-launch-1.0 with jpegenc, or ImageMagick)" >&2; exit 1; }
  i=$((i + 1))
done
# A PATH entry whose name holds a newline, with a CLI in it.
nl='
'
mkdir -p "$work/nl/bin${nl}y"
cp "$here/fake-omarchy-broadcast" "$work/nl/bin${nl}y/omarchy-broadcast"
chmod +x "$work/nl/bin${nl}y/omarchy-broadcast"
# The resolver cases' PATH: an empty directory (command, printf, [ and case
# are sh builtins), never an omarchy-broadcast. sh needs no link: Quickshell
# finds a command's argv[0] on its own PATH, not the child's.
mkdir -p "$work/rbin"
# The real CLI, for one resolver case (mock): a symlink in a directory of its
# own, put on that case's PATH. Its answer is the link's path.
realcli=""
if [ "$mode" = mock ] && [ -n "$real_cli" ]; then
  mkdir -p "$work/realbin"
  ln -s "$real_cli" "$work/realbin/omarchy-broadcast"
  realcli=$work/realbin/omarchy-broadcast
fi
# Hermetic PATH of a mock run: the fake, then the system tools without any
# omarchy-broadcast*. Anything but the fake answering is fatal, before the
# shell starts (a real CLI on the user's PATH must never be run by a mock test).
run_path="$work/bin:/usr/bin:/bin"
if [ "$mode" = mock ]; then
  mkdir -p "$work/sysbin"
  for d in /usr/bin /bin; do
    [ -d "$d" ] || continue
    find "$d" -mindepth 1 -maxdepth 1 ! -name 'omarchy-broadcast*' -print0 \
      | xargs -0 -r ln -sf -t "$work/sysbin" --
  done
  run_path="$work/bin:$work/sysbin"
  found=$(PATH="$run_path" command -v omarchy-broadcast || true)
  [ "$found" = "$work/bin/omarchy-broadcast" ] || {
    echo "harness: the mock PATH resolves omarchy-broadcast to '$found', not the fake $work/bin/omarchy-broadcast" >&2
    exit 1
  }
  [ -x "$work/sysbin/sh" ] || { echo "harness: no sh among the system tools" >&2; exit 1; }
  echo "harness: mock PATH resolves omarchy-broadcast to the fake ($found)"
fi

if [ "$mode" = live ]; then
  if busctl --user status br.com.dias.OmarchyBroadcast >/dev/null 2>&1; then
    echo "harness: br.com.dias.OmarchyBroadcast already has an owner; not starting a second daemon" >&2
    exit 1
  fi
  mkdir -p "$work/live/bin"
  : > "$work/live/config.toml"
  # The widgets run the real CLI through this link: argv[0] (and so
  # /proc/PID/cmdline) keeps the link's path, unique to this run, where the
  # real path would match any bar running the same binary.
  ln -s "$real_cli" "$work/live/bin/omarchy-broadcast"
  cli=$work/live/bin/omarchy-broadcast
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
  # fake first (mock: and no other omarchy-broadcast at all), so the "no
  # cliPath" case resolves the fake from PATH.
  unset WAYLAND_DISPLAY DISPLAY QT_QPA_PLATFORMTHEME
  export QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$work/runtime"
  export PATH="$run_path"
  export FAKE_OB_DIR="$work/fake"
  export OBH_MODE="$mode" OBH_PLUGIN="$work/plugin/br.com.dias.omarchy-broadcast" OBH_PLUGIN_COPY="$work/reload/br.com.dias.omarchy-broadcast" OBH_CLI="$cli" OBH_FAKE="$work/fake" \
         OBH_SCREENS="$screens" \
         OBH_DAEMON="$daemon" OBH_LIVE="$work/live" \
         OBH_NLBIN="$work/nl/bin${nl}y" OBH_RESOLVER_PATH="$work/rbin" \
         OBH_REALCLI="$realcli"
  exec quickshell -p "$work/qs"
) > "$log" 2>&1 &
qs_pid=$!

limit=240
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
qs_pid=""

# Anything this run started and the harness did not stop: by PID only.
stop_leftovers

sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E 'qml: ' | sed 's/^.*qml: //'
echo "log: $log"
ok=0
[ "$result" = "done" ] || { echo "harness: no result within ${limit}s" >&2; ok=1; }
if [ "$ok" -eq 0 ] && [ "$leftovers" -ne 0 ]; then echo "harness: $leftovers process(es) left running" >&2; ok=1; fi
if [ "$ok" -eq 0 ]; then sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -q 'qml: ALL OK' || ok=1; fi
case $screens in
  "$work"/*)
    if [ "$ok" -ne 0 ] || [ "${KEEP_WORK:-}" = 1 ]; then echo "screens: $screens"
    else echo "screens: removed with the work directory (KEEP_WORK=1 or --screens DIR keeps them)"; fi ;;
  *) echo "screens: $screens" ;;
esac
exit "$ok"
