#!/bin/sh
# Run every check of the plugin, in order, from the repository root whatever
# the current directory, and stop at the first one that fails:
#
#   1. unit tests          qmltestrunner on tests/tst_model.qml
#   2. source invariants   python3 -I tests/check-source.py
#   3. qmllint             tests/lint.sh
#   4. manifest            omarchy-plugin-validate (the checks of `omarchy plugin validate`)
#   5. harness             tests/run-harness.sh, mock CLI
#   6. shellcheck          tests/*.sh and tests/fake-*
#
# Not covered: tests/run-harness.sh --live (needs a real daemon, CLI and
# camera device), and the harness's real-CLI resolver case unless
# OMARCHY_BROADCAST_CLI is set (it then prints SKIP for that case).
#
# Usage:
#   tests/check-all.sh                      against the installed Omarchy
#   tests/check-all.sh --omarchy-ref REF    against Omarchy at tag/branch REF:
#                                           a shallow clone of
#                                           https://github.com/omacom/omarchy.git
#                                           in a scratch directory, removed on exit
#   tests/check-all.sh --help
#
# Environment:
#   OMARCHY_SHELL          the Omarchy shell modules (default /usr/share/omarchy/shell);
#                          replaced by the clone's shell/ with --omarchy-ref
#   OMARCHY_BIN            the directory with omarchy-plugin-validate (default
#                          /usr/share/omarchy/bin); replaced by the clone's bin/
#   OMARCHY_BROADCAST_CLI  absolute path of a real omarchy-broadcast binary, passed
#                          on to the harness (see tests/run-harness.sh)
#   QMLTESTRUNNER          qmltestrunner binary (default /usr/lib/qt6/bin/qmltestrunner)
#
# Needs: qt6-declarative (qmltestrunner, qmllint), quickshell, python3, jq and
# the Omarchy shell modules (and, for --omarchy-ref, git and network access);
# for the shellcheck step, the shellcheck program on PATH or else uvx (which
# runs it from the shellcheck-py package), and the harness's own needs (a
# font, see tests/run-harness.sh).
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
plugin=$(dirname -- "$here")
omarchy_repo=https://github.com/omacom/omarchy.git
ref=""

usage() {
  sed -n '2,/^set -eu$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case $1 in
    --omarchy-ref)
      [ $# -ge 2 ] || { echo "check-all: --omarchy-ref needs a tag or branch" >&2; exit 2; }
      ref=$2
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "usage: $0 [--omarchy-ref REF] [--help]" >&2; exit 2 ;;
  esac
  shift
done

cd -- "$plugin"

tmp=""
cleanup() {
  [ -z "$tmp" ] || rm -rf -- "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -n "$ref" ]; then
  command -v git >/dev/null || { echo "check-all: git is not installed (needed for --omarchy-ref)" >&2; exit 1; }
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-broadcast-check.XXXXXX")
  echo "== Omarchy $ref: cloning $omarchy_repo"
  git clone --quiet --depth 1 --branch "$ref" "$omarchy_repo" "$tmp/omarchy" \
    || { echo "check-all: cloning Omarchy at $ref failed" >&2; exit 1; }
  [ -d "$tmp/omarchy/shell/Commons" ] && [ -d "$tmp/omarchy/shell/Ui" ] \
    || { echo "check-all: Omarchy $ref has no shell/Commons and shell/Ui" >&2; exit 1; }
  OMARCHY_SHELL=$tmp/omarchy/shell
  OMARCHY_BIN=$tmp/omarchy/bin
fi
OMARCHY_SHELL=${OMARCHY_SHELL:-/usr/share/omarchy/shell}
OMARCHY_BIN=${OMARCHY_BIN:-/usr/share/omarchy/bin}
export OMARCHY_SHELL OMARCHY_BIN
echo "Omarchy shell: $OMARCHY_SHELL"
echo "Omarchy bin:   $OMARCHY_BIN"

# step TITLE COMMAND [ARG...]: heading, run, stop with the command's status on failure.
step() {
  title=$1
  shift
  echo
  echo "== $title"
  status=0
  "$@" || status=$?
  if [ "$status" -ne 0 ]; then
    echo "check-all: FAILED: $title (exit $status)" >&2
    exit "$status"
  fi
}

unit_tests() {
  QT_QPA_PLATFORM=offscreen "${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}" -input tests/tst_model.qml
}

manifest() {
  bash "$OMARCHY_BIN/omarchy-plugin-validate" .
}

shellcheck_all() {
  # A version-manager shim can be on PATH without a version set: probe it.
  if command -v shellcheck >/dev/null 2>&1 && shellcheck --version >/dev/null 2>&1; then
    set -- shellcheck
  elif command -v uvx >/dev/null 2>&1; then
    set -- uvx --from shellcheck-py shellcheck
  else
    echo "check-all: no working shellcheck on PATH, and uvx is not installed" >&2
    return 1
  fi
  "$@" tests/*.sh tests/fake-*
}

step "Unit tests (Model.js)" unit_tests
step "Source invariants" python3 -I tests/check-source.py
step "qmllint" tests/lint.sh
step "Manifest" manifest
step "Harness (mock CLI)" tests/run-harness.sh
step "Shellcheck" shellcheck_all

echo
echo "check-all: ALL OK"
