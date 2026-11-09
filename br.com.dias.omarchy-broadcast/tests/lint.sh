#!/bin/sh
# Lint every QML file of the plugin (and of its tests) with qmllint, with
# [import] and [missing-type] warnings made fatal.
#
# Why fatal: qmllint exits 0 on a failed import, while the engine refuses to
# load a file whose import fails — in the shell that is a widget silently not
# there. qs.Commons and qs.Ui are resolvable only from an import path, so a
# scratch tree <tmp>/qs/{Commons,Ui} linking to Omarchy's shell is built here
# and passed with -I (the plugin folder itself must hold no symlinks).
#
# Usage: tests/lint.sh            (OMARCHY_SHELL overrides /usr/share/omarchy/shell)
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
plugin=$(dirname -- "$here")
shell_dir=${OMARCHY_SHELL:-/usr/share/omarchy/shell}
qmllint=${QMLLINT:-/usr/lib/qt6/bin/qmllint}

[ -x "$qmllint" ] || { echo "lint: qmllint not found at $qmllint" >&2; exit 1; }
[ -d "$shell_dir/Commons" ] && [ -d "$shell_dir/Ui" ] || { echo "lint: Omarchy shell modules not found at $shell_dir" >&2; exit 1; }

scratch=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-broadcast-lint.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT INT TERM
mkdir -p "$scratch/qs"
ln -s "$shell_dir/Commons" "$scratch/qs/Commons"
ln -s "$shell_dir/Ui" "$scratch/qs/Ui"

status=0
for file in "$plugin"/*.qml "$here"/*.qml "$here"/harness/*.qml; do
  [ -f "$file" ] || continue
  # Run from outside the plugin, by absolute path: the file's directory (and
  # its qmldir, which declares the Daemon singleton) is then its implicit
  # import, as in the shell. Run from inside it, qmllint reads that qmldir as
  # a type file of its own and wrongly reports the singleton undeclared.
  if ! out=$(cd -- "$scratch" && "$qmllint" -I "$scratch" \
      --import error --missing-type error --syntax error \
      "$file" 2>&1); then
    status=1
    echo "FAIL $file"
  else
    echo "ok   $file"
  fi
  [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/     /'
done

exit "$status"
