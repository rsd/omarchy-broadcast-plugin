# Omarchy bar widget

`br.com.dias.oma-broadcast` is a bar widget for the Omarchy shell (Quickshell/QML). It shows the state of the virtual camera in the bar, turns it on and off, selects the camera and the video effect, and shows live figures while it runs. It is a client of `oma-broadcastd` ([setup/daemon.md](../../docs/setup/daemon.md)): it reads the state from the stream of `oma-broadcast watch --json` and sends commands through the `oma-broadcast` command-line client. It does not speak D-Bus itself. The stream format is specified in [cli-json.md](../../docs/cli-json.md).

The plugin lives in [br.com.dias.oma-broadcast/](br.com.dias.oma-broadcast/). Nothing is installed by the build.

## What it shows

The icon follows the daemon state. Colours come from the active theme.

| State | Icon | Look |
|---|---|---|
| `off` | webcam, crossed out | dimmed; the privacy switch is off |
| `idle` | webcam | normal colour; on, no application is using the camera |
| `starting` | video camera, outline | accent colour |
| `active` | video camera, filled | accent colour; the camera and GPU run |
| `error` | alert circle | urgent colour; the daemon reports an error |
| unavailable | video camera, crossed out outline | dimmed; the daemon is not running, does not answer, or the CLI is missing or unsupported |

- Left click turns the camera on or off. It does nothing while an earlier command is still running. While the daemon is unavailable it opens the panel instead, so that a persisted `off` is never flipped without being seen and a stopped daemon is never started by a click.
- Right or middle click opens and closes the panel.
- The tooltip gives the state, and while running the camera name, the number of consumers and the effect when one is on (background blurred or background replaced). An error text is appended when there is one. When unavailable it names the cause.

The panel shows:

- the state, the on/off switch and the daemon's error text, if any;
- the last failed command, if any;
- the camera in use, the number of consumers (the total of applications holding the virtual camera device and applications linked to the optional PipeWire camera node) and the output mode;
- the video effect: None, Blur or Replace, with the current one selected (click a choice to change it). While blurring, the blur strength is shown; while replacing, the background image path. Replace can be chosen only once the daemon has a background image; until then it is faded, the panel shows "Replace needs an image:" with the command `oma-broadcast effect replace --image PATH` to run in a terminal, and the Replace tooltip names the other way, `background_image` under `[effect]` in the daemon's configuration. The strength and the image are shown, not edited, here. If the `oma-broadcast` CLI predates video effects, every choice is faded and the panel says the CLI needs updating; if the CLI knows effects but the running daemon does not (its interface revision is below 2, as when the daemon was not restarted after an upgrade), every choice is faded and the panel says the daemon needs updating;
- while active, the frame rate, the p50 latency and the CPU and GPU load; a figure the daemon has not reported yet reads as a dash;
- the list of cameras (click a row to select it) and a Next camera button when there are two or more. The producer lists at most 12 cameras; a row says when more are connected;
- when the daemon is unavailable, the reason and, where it helps, a command to copy. The plugin shows these commands and never runs them.

Keyboard, once the panel is open: Up/Down or j/k move the cursor over the switch, the effect row (unless the CLI or the daemon predates effects), the cameras and Next camera (the first press only shows the cursor), Left/Right or h/l move between the effect choices (arriving on the row lands on the current effect), Enter or Space activates, Tab switches to the neighbouring panel, Escape closes.

## Requirements

- `oma-broadcastd` and `oma-broadcast` installed as described in [setup/daemon.md](../../docs/setup/daemon.md). The widget shows "unavailable" until the daemon runs; it works without D-Bus activation, but with it `on`, `off`, camera selection and effect selection start a stopped daemon (see the unavailable behaviour below).
- The Omarchy shell (Quickshell) with the plugin system, and `omarchy` on `PATH`.
- A theme-aware Nerd Font for the icons, as the rest of the bar uses.

## Install

From the repository root, link the plugin directory into the shell's plugin directory:

```sh
mkdir -p ~/.config/omarchy/plugins
ln -s "$PWD/clients/omarchy-bar/br.com.dias.oma-broadcast" ~/.config/omarchy/plugins/br.com.dias.oma-broadcast
```

With the Arch package ([setup/daemon.md](../../docs/setup/daemon.md#install)), the plugin is installed under `/usr/share/oma-broadcast/omarchy-bar/`; link that directory instead:

```sh
mkdir -p ~/.config/omarchy/plugins
ln -s /usr/share/oma-broadcast/omarchy-bar/br.com.dias.oma-broadcast ~/.config/omarchy/plugins/br.com.dias.oma-broadcast
```

`scripts/install-user.sh` does not install the plugin; use the link from the repository above.

To copy instead of linking (edits in the repository then no longer apply), use `cp -r clients/omarchy-bar/br.com.dias.oma-broadcast ~/.config/omarchy/plugins/`. The `tests/` directory inside the plugin is not needed at run time and may be left out of a copy.

Enable the plugin, which also places the widget in the right section of the bar:

```sh
omarchy plugin enable br.com.dias.oma-broadcast
```

To choose the place yourself, pass a placement to `enable`, or move the widget later:

```sh
omarchy bar move br.com.dias.oma-broadcast --section centerBegin --index 0
omarchy bar put  br.com.dias.oma-broadcast --after omarchy.clock
```

`omarchy plugin list` shows whether the plugin was discovered. With a symlink, a change made in the repository may not trigger a reload by itself.

## Configuration

One setting, `cliPath`, the absolute path of the `oma-broadcast` binary. A leading `~/` means the home directory. A bare name such as `oma-broadcast` or a relative path is refused, because a command would then run relative to whatever directory the shell has. It is empty by default.

The binary is resolved in this order:

1. `cliPath`, if set. If it is set but unusable, the widget says so and does not fall back.
2. `oma-broadcast` on the shell's `PATH` (normally the case for all three install locations: `/usr/bin` for the Arch package, `~/.local/bin` for `scripts/install-user.sh`, `~/.cargo/bin` for `cargo install`; Omarchy's default shell environment appends `~/.local/bin` to `PATH`). The shell must have the directory on its own `PATH`; if it does not, set `cliPath`.
3. A development build: `target/release/oma-broadcast` of the repository, found from the real directory of the plugin through the symlink (`<plugin directory>/../../../target/release/oma-broadcast`).

A binary found on `PATH` wins over the development build, so a stale installed binary hides a fresh build; set `cliPath` to choose. Resolution runs when a widget appears, once after each failed start of the CLI, and when the setting changes, never on a timer. If nothing was found and you install the CLI afterwards, reload the shell or change the setting.

## How it talks to the daemon

- One `oma-broadcast watch --json` process serves every bar (every monitor). There is no polling: the daemon pushes each change, and the widget is exactly as fresh as the stream.
- The process starts when the first widget appears and stops when the last one goes away.
- When it exits, it is started again after 1 s, doubling up to 30 s. The delay returns to 1 s only after a watch has run for 30 s, so a watch that dies right after its first line does not restart every second.
- Commands (`on`, `off`, `camera -- <id>`, `camera next`, `effect none|blur|replace`) run as argument lists, never through a shell, and time out after 30 s. A new click is ignored while one runs. The camera id is passed as one argument after `--`. The effect is always one of the three fixed words; nothing the daemon reports is passed back on the command line.
- Text from the daemon (camera names, errors, the background image path) is shown as plain text, stripped of markup, control, bidi and invisible formatting characters (the zero-width joiner and non-joiner stay, so emoji sequences and Persian or Arabic words display correctly), and shortened. The background image path is shown inside a left-to-right Unicode isolate, so right-to-left text in a file name cannot reorder the row or reverse the path. An effect name the plugin does not know selects no choice and is reported as such; a blur strength outside 0 to 1 reads as a dash. The producer already limits a line to 4096 bytes and the camera list to 12; the plugin drops a line over 8192 characters and restarts the watch.
- Reads never start the daemon. The commands `on`, `off`, `camera` and `effect` start it through D-Bus activation if you installed that file ([dbus-api.md](../../docs/dbus-api.md#service-presence-and-activation)); the widget avoids sending them while the daemon is known to be down.

When the daemon stops or restarts, the stream says so and the icon shows "unavailable" until the daemon is back; no action is needed. If the watch itself ends, the panel names the exit status or signal and the retry delay.

## Troubleshooting

| Message | Cause | What to do |
|---|---|---|
| oma-broadcastd is not running | the service is stopped | `systemctl --user start oma-broadcastd`, or enable it ([setup/daemon.md](../../docs/setup/daemon.md)) |
| oma-broadcastd is not answering | the service runs but does not reply on the bus | `journalctl --user -u oma-broadcastd`; the widget retries every 2 s |
| oma-broadcast CLI not found, or "not on PATH ... no development build at ..." | no binary at `cliPath`, on `PATH` or in `target/release` | install the CLI (Arch package, `scripts/install-user.sh` or `cargo install --path crates/oma-broadcast`) and make sure its directory is on the shell's `PATH`, or set `cliPath`; then reload or change the setting |
| cliPath must be an absolute path | `cliPath` is a bare name or a relative path | use an absolute path or one starting with `~/` |
| oma-broadcast watch stopped / exited with status N / stopped by signal N; restarting in N s | the watch process ended | the widget restarts it with backoff; if it repeats, run `oma-broadcast watch --json` in a terminal |
| Unsupported oma-broadcast version | the CLI prints a schema version the plugin does not know, or a line over the limit | update the plugin or the CLI so they match ([cli-json.md](../../docs/cli-json.md)) |
| oma-broadcastd reports a state this plugin does not know | the daemon is newer than the plugin | update the plugin |
| The daemon refused the request | the daemon rejected `on`, `off`, the camera or the effect | the text after the colon is the daemon's reason; see `oma-broadcast status` |
| The oma-broadcast CLI needs updating for effects (the effect choices are faded) | the `oma-broadcast` CLI predates video effects | update the CLI and the daemon |
| The daemon needs updating for effects (the effect choices are faded) | the CLI knows effects, but the running oma-broadcastd reports an interface revision below 2 (or none) | update oma-broadcastd, or restart it if it is already updated: `systemctl --user restart oma-broadcastd` |
| Replace is faded; "Replace needs an image:" | the daemon has no background image | run `oma-broadcast effect replace --image PATH`, or set `background_image` under `[effect]` in the daemon's configuration |
| oma-broadcastd reports an effect this plugin does not know | the daemon is newer than the plugin | update the plugin |
| D-Bus failure | the CLI could not reach the session bus | check `DBUS_SESSION_BUS_ADDRESS` in the shell's environment |
| Command failed with status N | any other exit status | run the same `oma-broadcast` command in a terminal |
| Showing N of M cameras / More cameras are connected; they are not shown | the camera list is capped | not an error |
| Next camera missing | fewer than two cameras listed | connect a second camera |
| A camera row is not selectable (its id is the word `next`) | the CLI would read the id as Next camera | not selectable unless its USB vendor and product id are unique |

## Testing the plugin

Run from the repository root. All commands are read-only with respect to your shell and your configuration; none starts or touches the running shell.

```sh
# Unit tests of the logic (Model.js): reducer, caps, tooltips, argument lists, effects, path resolution
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
    -input clients/omarchy-bar/br.com.dias.oma-broadcast/tests/tst_model.qml

# Source invariants (plain text everywhere, no shell strings, no polling timer, manifest id, effect whitelist)
python3 -I clients/omarchy-bar/br.com.dias.oma-broadcast/tests/check-source.py

# qmllint on every QML file, import errors fatal
clients/omarchy-bar/br.com.dias.oma-broadcast/tests/lint.sh

# The shell's manifest validator
omarchy plugin validate clients/omarchy-bar/br.com.dias.oma-broadcast

# The plugin inside a throwaway Quickshell with a fake CLI (needs quickshell)
clients/omarchy-bar/br.com.dias.oma-broadcast/tests/run-harness.sh

# The same against the real daemon and CLI
clients/omarchy-bar/br.com.dias.oma-broadcast/tests/run-harness.sh --live
```

- `qmltestrunner` and `qmllint` come from Qt 6 (`/usr/lib/qt6/bin`); `lint.sh` also needs the Omarchy shell modules in `/usr/share/omarchy/shell` (override with `OMARCHY_SHELL`).
- `run-harness.sh` builds its own directory (under `$TMPDIR`, or `--work DIR` if that is empty or an earlier harness directory), runs a separate Quickshell with the fake CLI `tests/fake-oma-broadcast`, and removes nothing outside it. It prints `ALL OK` and exits 0 on success. `--screens DIR` keeps the screenshots.
- `--live` needs the release builds (`cargo build --release`), starts its own `oma-broadcastd` with a scratch configuration and state, opens the virtual camera for a few seconds and stops everything again. It refuses to run if `br.com.dias.OmaBroadcast` already has an owner on the session bus, and it needs the "Omarchy Broadcast" device ([setup/loopback.md](../../docs/setup/loopback.md)).

## Remove

```sh
omarchy plugin disable br.com.dias.oma-broadcast
omarchy plugin remove br.com.dias.oma-broadcast
```

If you linked the plugin, deleting the link has the same effect: `rm ~/.config/omarchy/plugins/br.com.dias.oma-broadcast`. If a placement is left in the bar layout, remove it with the shell's bar commands (`omarchy bar --help`) and reload the shell.

The plugin starts no service of its own and writes no files. The only process it owns is the `watch` child, which ends with the shell (it exits when its output pipe closes or on SIGTERM). Removing the plugin does not touch the daemon; to stop and uninstall that, see "Stop, disable, uninstall" in [setup/daemon.md](../../docs/setup/daemon.md).

## Notes for maintainers and marketplace review

- `tests/` is test-only. It contains `pgrep`/`kill` calls (confined to processes the harness started, counted by a marker path inside its own work directory), `sh -c`, and an executable fake CLI. None of it is loaded by the shell.
- The one `sh -c` in the plugin code is the CLI resolver. The plugin directory is passed to it as a positional argument, never interpolated. Every other command is an argument list.
- The development-build fallback executes a binary from outside the plugin directory (`../../../target/release/oma-broadcast`). It is used only when `cliPath` is empty and `oma-broadcast` is not on `PATH`.
- The plugin id uses the `br.com.dias.` namespace like the daemon's D-Bus name; check it against the marketplace naming rule before publishing. The plugin directory has no licence files of its own; the licences are those of the repository root (`MIT OR Apache-2.0`).

## Limitations

- English only; there is no translation catalogue.
- The `active` state uses the theme's accent colour, so it is distinguished from `idle` by the icon shape and colour together.
- Camera names are shown as the daemon reports them (after removing markup characters such as `&`, `<` and `>`).
