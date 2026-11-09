# Omarchy Broadcast bar widget

`br.com.dias.omarchy-broadcast` is a bar widget for the Omarchy shell (Quickshell/QML) that controls omarchy-broadcast, a virtual camera daemon with background effects and noise removal. It shows the state of the virtual camera in the bar, turns it on and off, selects the camera and the video effect, switches noise removal, and shows live figures while it runs.

It is a client of `omarchy-broadcastd`, the daemon of the omarchy-broadcast project, and does not include it: it reads the state from the stream of `omarchy-broadcast watch --json` and sends commands through the `omarchy-broadcast` command-line client. It does not speak D-Bus itself. The stream format is specified in `docs/cli-json.md` in the omarchy-broadcast repository; the widget requires its schema version (`v`) 1.

The plugin is the directory [br.com.dias.omarchy-broadcast/](br.com.dias.omarchy-broadcast/); its tests are in `br.com.dias.omarchy-broadcast/tests/`. Nothing is built or installed by this repository.

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
- The tooltip gives the state, and while running the camera name, the number of consumers, the effect when one is on (background blurred or background replaced) and noise removal when it is on (worded as a setting, "noise removal on", because the daemon may be unable to run it; with an effect, for example "background blurred, noise removal on"). An error text is appended when there is one. When unavailable it names the cause.

The panel shows:

- the state, the on/off switch and the daemon's error text, if any;
- the last failed command, if any;
- the camera in use, the number of consumers (the total of applications holding the virtual camera device and applications linked to the optional PipeWire camera node) and the output mode;
- the video effect: None, Blur or Replace, with the current one selected (click a choice to change it). While blurring, the blur strength is shown; while replacing, the background image path. Replace can be chosen only once the daemon has a background image; until then it is faded, the panel shows "Replace needs an image:" with the command `omarchy-broadcast effect replace --image PATH` to run in a terminal, and the Replace tooltip names the other way, `background_image` under `[effect]` in the daemon's configuration. The strength and the image are shown, not edited, here. If the `omarchy-broadcast` CLI predates video effects, every choice is faded and the panel says the CLI needs updating; if the CLI knows effects but the running daemon does not (its interface revision is below 2, as when the daemon was not restarted after an upgrade), every choice is faded and the panel says the daemon needs updating;
- in the same section, under the effect choices, a separate Noise removal switch. Noise removal is not a fourth effect: it is a stage that applies with any effect (it runs before blur or replace, or alone with None), so it is switched on and off on its own and is not one of the choices. It hides nothing, so if the daemon cannot run it the camera keeps streaming without it and the daemon's error text says why. The switch is not shown when the `omarchy-broadcast` CLI or the running daemon does not report noise removal (both predate it; the daemon's interface revision is below 4), rather than showing an off switch that nobody reported;
- while active, the frame rate, the p50 latency and the CPU and GPU load; a figure the daemon has not reported yet reads as a dash;
- the list of cameras (click a row to select it) and a Next camera button when there are two or more. The producer lists at most 12 cameras; a row says when more are connected;
- when the daemon is unavailable, the reason and, where it helps, a command to copy. The plugin shows these commands and never runs them.

Keyboard, once the panel is open: Up/Down or j/k move the cursor over the switch, the effect row (unless the CLI or the daemon predates effects), the Noise removal switch (when it is shown), the cameras and Next camera (the first press only shows the cursor), Left/Right or h/l move between the effect choices (arriving on the row lands on the current effect), Enter or Space activates, Tab switches to the neighbouring panel, Escape closes.

## Requirements

- `omarchy-broadcastd` and the `omarchy-broadcast` CLI, installed as described in `docs/setup/daemon.md` in the omarchy-broadcast repository. The widget shows "unavailable" until the daemon runs; it works without D-Bus activation, but with it `on`, `off`, camera selection, effect selection and the Noise removal switch start a stopped daemon (see the unavailable behaviour below).
- A CLI whose `watch --json` prints schema version (`v`) 1. A line with a higher version is reported as "Unsupported omarchy-broadcast version"; any other value is refused as malformed.
- For the video effects, a running daemon with interface revision 2 or later; for noise removal, interface revision 4 or later (the CLI then reports a `denoise` field). With an older daemon the widget still shows the state and switches the camera; it fades the effect choices or hides the Noise removal switch.
- The Omarchy shell (Quickshell) with the plugin system, and `omarchy` on `PATH`.
- A theme-aware Nerd Font for the icons, as the rest of the bar uses.

## Install

Clone this repository, then, from the root of the checkout, link the plugin directory into the shell's plugin directory:

```sh
mkdir -p ~/.config/omarchy/plugins
ln -s "$PWD/br.com.dias.omarchy-broadcast" ~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast
```

That is, `ln -s <checkout>/br.com.dias.omarchy-broadcast ~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast`, with `<checkout>` the absolute path of the clone.

To copy instead of linking (later changes in the checkout then no longer apply), use `cp -r br.com.dias.omarchy-broadcast ~/.config/omarchy/plugins/`. The `tests/` directory inside the plugin is not needed at run time and may be left out of a copy.

`omarchy plugin add <git-url>` does not apply to this repository: it expects `manifest.json` at the root of the cloned repository, and here the plugin is a subdirectory. Link or copy the directory as above.

Enable the plugin, which also places the widget in the right section of the bar:

```sh
omarchy plugin enable br.com.dias.omarchy-broadcast
```

To choose the place yourself, pass a placement to `enable`, or move the widget later:

```sh
omarchy bar move br.com.dias.omarchy-broadcast --section centerBegin --index 0
omarchy bar put  br.com.dias.omarchy-broadcast --after omarchy.clock
```

`omarchy plugin list` shows whether the plugin was discovered. With a symlink, a change made in the checkout may not trigger a reload by itself.

## Configuration

One setting, `cliPath`, the absolute path of the `omarchy-broadcast` binary. A leading `~/` means the home directory. A bare name such as `omarchy-broadcast` or a relative path is refused, because a command would then run relative to whatever directory the shell has. It is empty by default.

The binary is resolved in this order:

1. `cliPath`, if set. If it is set but unusable, the widget says so and does not fall back.
2. `omarchy-broadcast` on the shell's `PATH`. This is normally the case for the install locations of omarchy-broadcast: `/usr/bin` for its Arch package, `~/.local/bin` for its `scripts/install-user.sh`, `~/.cargo/bin` for `cargo install`; Omarchy's default shell environment appends `~/.local/bin` to `PATH`. The shell must have the directory on its own `PATH`; if it does not, set `cliPath`.
3. A development build at `<plugin real directory>/../../../target/release/omarchy-broadcast`, where the real directory is the plugin directory with symlinks resolved. This layout dates from when the plugin lived inside the omarchy-broadcast repository (at `clients/omarchy-bar/` there), next to its `target/` directory. In a checkout of this repository the path points two levels above the root of the checkout, outside it, so the fallback normally finds nothing; to use a development build of omarchy-broadcast, set `cliPath` to that build's `target/release/omarchy-broadcast`.

A binary found on `PATH` wins over the development-build fallback; set `cliPath` to choose. Resolution runs when a widget appears, once after each failed start of the CLI, and when the setting changes, never on a timer. If nothing was found and you install the CLI afterwards, reload the shell or change the setting.

## How it talks to the daemon

- One `omarchy-broadcast watch --json` process serves every bar (every monitor). There is no polling: the daemon pushes each change, and the widget is exactly as fresh as the stream.
- The process starts when the first widget appears and stops when the last one goes away.
- When it exits, it is started again after 1 s, doubling up to 30 s. The delay returns to 1 s only after a watch has run for 30 s, so a watch that dies right after its first line does not restart every second.
- Commands (`on`, `off`, `camera -- <id>`, `camera next`, `effect none|blur|replace`, `denoise on|off`) run as argument lists, never through a shell, and time out after 30 s. A new click is ignored while one runs. The camera id is passed as one argument after `--`. The effect is always one of the three fixed words, and noise removal one of `on` and `off`; nothing the daemon reports is passed back on the command line.
- Text from the daemon (camera names, errors, the background image path) is shown as plain text, stripped of markup, control, bidi and invisible formatting characters (the zero-width joiner and non-joiner stay, so emoji sequences and Persian or Arabic words display correctly), and shortened. The background image path is shown inside a left-to-right Unicode isolate, so right-to-left text in a file name cannot reorder the row or reverse the path. An effect name the plugin does not know selects no choice and is reported as such; a blur strength outside 0 to 1 reads as a dash. The producer already limits a line to 4096 bytes and the camera list to 12; the plugin drops a line over 8192 characters and restarts the watch.
- Reads never start the daemon. The commands `on`, `off`, `camera`, `effect` and `denoise` start it through D-Bus activation if you installed that file (see "Service presence and activation" in `docs/dbus-api.md` in the omarchy-broadcast repository); the widget avoids sending them while the daemon is known to be down.

When the daemon stops or restarts, the stream says so and the icon shows "unavailable" until the daemon is back; no action is needed. If the watch itself ends, the panel names the exit status or signal and the retry delay.

## Troubleshooting

| Message | Cause | What to do |
|---|---|---|
| omarchy-broadcastd is not running | the service is stopped | `systemctl --user start omarchy-broadcastd`, or enable it (`docs/setup/daemon.md` in the omarchy-broadcast repository) |
| omarchy-broadcastd is not answering | the service runs but does not reply on the bus | `journalctl --user -u omarchy-broadcastd`; the widget retries every 2 s |
| omarchy-broadcast CLI not found, or "not on PATH ... no development build at ..." | no binary at `cliPath`, on `PATH` or at the development-build fallback | install the CLI as described in the omarchy-broadcast repository (Arch package, `scripts/install-user.sh` or `cargo install`) and make sure its directory is on the shell's `PATH`, or set `cliPath`; then reload or change the setting |
| cliPath must be an absolute path | `cliPath` is a bare name or a relative path | use an absolute path or one starting with `~/` |
| omarchy-broadcast watch stopped / exited with status N / stopped by signal N; restarting in N s | the watch process ended | the widget restarts it with backoff; if it repeats, run `omarchy-broadcast watch --json` in a terminal |
| Unsupported omarchy-broadcast version | the CLI prints a schema version the plugin does not know, or a line over the limit | update the plugin or the CLI so they match (the plugin reads schema `v` 1; see [Versioning](#versioning)) |
| omarchy-broadcastd reports a state this plugin does not know | the daemon is newer than the plugin | update the plugin |
| The daemon refused the request | the daemon rejected `on`, `off`, the camera, the effect or noise removal | the text after the colon is the daemon's reason; see `omarchy-broadcast status` |
| The omarchy-broadcast CLI needs updating for effects (the effect choices are faded) | the `omarchy-broadcast` CLI predates video effects | update the CLI and the daemon |
| The daemon needs updating for effects (the effect choices are faded) | the CLI knows effects, but the running omarchy-broadcastd reports an interface revision below 2 (or none) | update omarchy-broadcastd, or restart it if it is already updated: `systemctl --user restart omarchy-broadcastd` |
| Replace is faded; "Replace needs an image:" | the daemon has no background image | run `omarchy-broadcast effect replace --image PATH`, or set `background_image` under `[effect]` in the daemon's configuration |
| omarchy-broadcastd reports an effect this plugin does not know | the daemon is newer than the plugin | update the plugin |
| Noise removal switch missing | the `omarchy-broadcast` CLI or the running omarchy-broadcastd predates noise removal (the CLI prints no `denoise` field) | update both; restart the daemon if it is already updated: `systemctl --user restart omarchy-broadcastd` |
| Noise removal is on, and the panel shows an error from the daemon | the daemon could not run noise removal; the camera streams without it | the error text says why; see `omarchy-broadcast status` |
| D-Bus failure | the CLI could not reach the session bus | check `DBUS_SESSION_BUS_ADDRESS` in the shell's environment |
| Command failed with status N | any other exit status | run the same `omarchy-broadcast` command in a terminal |
| Showing N of M cameras / More cameras are connected; they are not shown | the camera list is capped | not an error |
| Next camera missing | fewer than two cameras listed | connect a second camera |
| A camera row is not selectable (its id is the word `next`) | the CLI would read the id as Next camera | not selectable unless its USB vendor and product id are unique |

## Testing the plugin

Run from the root of the checkout. None of the tests needs omarchy-broadcast, except the optional cases noted below. All commands are read-only with respect to your shell and your configuration; none starts or touches the running shell.

```sh
# Unit tests of the logic (Model.js): reducer, caps, tooltips, argument lists, effects, noise removal, path resolution
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
    -input br.com.dias.omarchy-broadcast/tests/tst_model.qml

# Source invariants (plain text everywhere, no shell strings, no polling timer, manifest id, effect and noise removal whitelists)
python3 -I br.com.dias.omarchy-broadcast/tests/check-source.py

# qmllint on every QML file, import errors fatal
br.com.dias.omarchy-broadcast/tests/lint.sh

# The shell's manifest validator
omarchy plugin validate br.com.dias.omarchy-broadcast

# The plugin inside a throwaway Quickshell with a fake CLI (needs quickshell)
br.com.dias.omarchy-broadcast/tests/run-harness.sh

# The same, plus one resolver case against a real omarchy-broadcast binary (found, never run)
OMARCHY_BROADCAST_CLI=/absolute/path/to/omarchy-broadcast br.com.dias.omarchy-broadcast/tests/run-harness.sh

# Against a real daemon and CLI
OMARCHY_BROADCAST_CLI=/absolute/path/to/omarchy-broadcast br.com.dias.omarchy-broadcast/tests/run-harness.sh --live
```

- `qmltestrunner` and `qmllint` come from Qt 6 (`/usr/lib/qt6/bin`, package `qt6-declarative` on Arch). `lint.sh` and `run-harness.sh` also need the Omarchy shell modules, by default in `/usr/share/omarchy/shell`; set `OMARCHY_SHELL` to use another copy, such as the `shell/` directory of a checkout of the Omarchy repository.
- `run-harness.sh` builds its own directory (under `$TMPDIR`, or `--work DIR` if that is empty or an earlier harness directory), runs a separate offscreen Quickshell with the fake CLI `tests/fake-omarchy-broadcast`, and removes nothing outside it. It prints `ALL OK` and exits 0 on success. `--screens DIR` keeps the screenshots. Its text-layout checks need a font installed (Omarchy's default is JetBrains Mono Nerd Font).
- The CLI resolver cases run against scratch directory trees the harness builds, so the harness does not depend on where this checkout lives. With `OMARCHY_BROADCAST_CLI` set to the absolute path of a real `omarchy-broadcast` binary, one more case checks that the resolver finds it through a symlinked plugin directory; the resolver only prints the path, and nothing executes the binary in this mode. Without the variable that case prints a `SKIP` line and does not count as a failure.
- `--live` takes the CLI from `OMARCHY_BROADCAST_CLI` and the daemon from `OMARCHY_BROADCASTD` (default: `omarchy-broadcastd` in the same directory as the CLI), and refuses to run without them. It starts its own `omarchy-broadcastd` with a scratch configuration and state, opens the virtual camera for a few seconds with `gst-launch-1.0` and stops everything again. It refuses to run if `br.com.dias.OmarchyBroadcast` already has an owner on the session bus, and it needs the "Omarchy Broadcast" v4l2loopback device (`docs/setup/loopback.md` in the omarchy-broadcast repository).
- Continuous integration (`.github/workflows/ci.yml`) runs all of the above except `--live` and the real-CLI case in an Arch Linux container, against the shell modules of a pinned Omarchy release.

## Remove

```sh
omarchy plugin disable br.com.dias.omarchy-broadcast
omarchy plugin remove br.com.dias.omarchy-broadcast
```

If you linked the plugin, deleting the link has the same effect: `rm ~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast`. If a placement is left in the bar layout, remove it with the shell's bar commands (`omarchy bar --help`) and reload the shell.

The plugin starts no service of its own and writes no files. The only process it owns is the `watch` child, which ends with the shell (it exits when its output pipe closes or on SIGTERM). Removing the plugin does not touch the daemon; to stop and uninstall that, see "Stop, disable, uninstall" in `docs/setup/daemon.md` in the omarchy-broadcast repository.

## Notes for maintainers and marketplace review

- `tests/` is test-only. It contains `pgrep`/`kill` calls (confined to processes the harness started, counted by a marker path inside its own work directory), `sh -c`, and an executable fake CLI. None of it is loaded by the shell.
- The one `sh -c` in the plugin code is the CLI resolver. The plugin directory is passed to it as a positional argument, never interpolated. Every other command is an argument list.
- The development-build fallback executes a binary from outside the plugin directory (`../../../target/release/omarchy-broadcast`, from the plugin's real directory). It is used only when `cliPath` is empty and `omarchy-broadcast` is not on `PATH`. In a checkout of this repository that path lies outside the checkout and normally holds nothing (see [Configuration](#configuration)).
- The plugin id uses the `br.com.dias.` namespace like the daemon's D-Bus name; check it against the marketplace naming rule before publishing. The licence files are at the root of this repository, `LICENSE-MIT` and `LICENSE-APACHE` (`MIT OR Apache-2.0`, as in `manifest.json`); the plugin directory itself holds none.

## Versioning

The plugin's version is the `version` field of `br.com.dias.omarchy-broadcast/manifest.json`. It started at 0.16.0, the omarchy-broadcast release it was split from, and is independent of the omarchy-broadcast version from then on: the two are released separately, and matching numbers carry no meaning.

Compatibility is set by the interface, not by version numbers. The plugin needs an `omarchy-broadcast` CLI whose `watch --json` output is schema version (`v`) 1, specified in `docs/cli-json.md` in the omarchy-broadcast repository; the video effects need a daemon interface revision of 2 or later and noise removal one of 4 or later (see [Requirements](#requirements)). A change of the schema version requires a new release of the plugin.

## Licence

Licensed under either of the [MIT License](LICENSE-MIT) or the [Apache License, Version 2.0](LICENSE-APACHE), at your option.

## Limitations

- English only; there is no translation catalogue.
- The `active` state uses the theme's accent colour, so it is distinguished from `idle` by the icon shape and colour together.
- Camera names are shown as the daemon reports them (after removing markup characters such as `&`, `<` and `>`).
