# Development and review

How the plugin talks to the daemon, how to run it from a checkout and test it, notes for maintainers and marketplace reviewers, and how it is versioned. Back to the [README](../README.md).

The plugin is the root of this repository (`manifest.json` and the QML files). Its tests are in [`tests/`](../tests/). Nothing is built or installed by this repository.

## How it talks to the daemon

- **One watch.** One process, the CLI's `watch --json`, serves every bar (every monitor). There is no polling: the daemon pushes each change, and the plugin is exactly as fresh as the stream.
  - The process starts when the first icon appears and stops when the last one goes away.
  - When it exits, it is started again after 1 s, doubling up to 30 s. The delay returns to 1 s only after a watch has run for 30 s, so a watch that dies right after its first line does not restart every second.
- **Commands.** These run as argument lists of the `omarchy-broadcast` CLI, never through a shell:
  - `on`, `off`, `camera -- <id>` and `camera next`;
  - `settings set --camera=<id> -- <setting id> <value>`, `settings set -- <setting id> <value>` for a global (effect) setting, and `settings reset --camera=<id>`;
  - `recommended apply`;
  - from the setup dialog, `modules enable|disable <module id>`, `order set <stage>,<stage>,...`, `order reset` and `config set -- <key> <value>`.

  Each short-lived process has a time bound, and one that outlives it is stopped with `SIGKILL`, not `SIGTERM`, because a binary that hangs may ignore `SIGTERM`:
  - a command above, 30 s (`COMMAND_TIMEOUT_MS`), and `start`, 45 s (`START_TIMEOUT_MS`);
  - a setup dialog read (`modules list`, `order show`, `config show`, `config files` and `media list`, one at a time on one child, only while the dialog is open), and `config show` while a panel is open (the Battery saver row, from revision 22), 30 s. The read then fails with "omarchy-broadcast did not answer within 30 s", and reopening the dialog or the panel reads again;
  - a gallery step (a `media` command, the import included, `omarchy-menu-images` or `omarchy-file-select`, one at a time, only while you use the Background row or the setup dialog's Away image row), 610 s (`MEDIA_WATCHDOG_MS`), just past `omarchy-file-select`'s own 600 s;
  - the two constant `sh -c` lookups, the CLI resolver (`command -v omarchy-broadcast`) and the gallery tool lookup (`omarchy-menu-images`, `omarchy-file-select`), 5 s (`LOOKUP_TIMEOUT_MS`). A lookup that times out counts as not found;
  - the long-lived `watch --json` child has no bound: it is meant to run, and it restarts with the backoff above when it exits (the `preview --json` child runs while a panel is open and is not bounded either).

  Every child ends with the shell: it exits when its output pipe closes or on `SIGTERM`.

  A new click is ignored while one runs. Setting writes and Reset to defaults instead wait behind it (see [Camera settings](panel.md#camera-settings)), and the queue never drops a command that is not a setting write.
- **What is passed back.** Nothing else the daemon reports is passed back on the command line.
  - The camera id is passed as one argument after `--`.
  - A module id, a stage id and a config key are passed back only when they match the daemon's grammars ([`docs/modules.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/modules.md), "Reserved names").
  - A stage order is passed back only as the daemon's own order with two neighbours swapped where the daemon said that swap is valid.
  - A config value is passed back only as a value of its row: `true` or `false`, a number within the row's range and on its step, or one of the row's options (the empty option is a pin's Automatic).
  - A setting id is passed back only when it matches the daemon's id grammar (lowercase words joined by dots, at most 48 bytes). A prototype key such as `__proto__` is refused.
  - A setting value is `on` or `off` for a switch; a decimal integer within the range the daemon reports, on its step, for a slider; one of the option ids the daemon published for a choice; and `true` for an action.
- **Text from the daemon** (camera names, errors, the background image path) is shown as plain text, stripped of markup, control, bidi and invisible formatting characters, and shortened.
  - The zero-width joiner and non-joiner stay, so emoji sequences and Persian or Arabic words display correctly.
  - The background image path is shown inside a left-to-right Unicode isolate, so right-to-left text in a file name cannot reorder the row or reverse the path.
- **Limits.** The producer already limits a line to 4096 bytes and the camera list to 12. The plugin drops a line over 8192 characters and restarts the watch.
  - Of the camera settings it reads at most 16 groups, 16 settings in a group, 16 options in a setting and 64 rows in all. The panel says "Showing N of M groups", "settings" or "choices" when it shows fewer than the daemon reports.
  - It keeps a setting only when its id passes the check above, its type is known, and every number in it is an integer, its minimum is not above its maximum, its step is at least 1 and its default and value lie within the range.
  - Unlike camera names, settings text keeps `&` ("Focus & zoom"): every place it is drawn is plain text, so nothing there reads it as markup.
- **Start.** The panel's **Start** button (shown only while the daemon is not running) runs the command below, which D-Bus-activates the daemon without changing its state. The running watch then picks it up. It needs the D-Bus activation file and a CLI that has `start`.

  ```sh
  omarchy-broadcast start
  ```

- **Finding the CLI.** The plugin looks for `omarchy-broadcast` in two places, in this order: the `cliPath` setting, if set ([Configuration](panel.md#configuration)), and then `PATH`. A `cliPath` that is set but unusable is reported, with no fallback to `PATH`. The plugin resolves the binary when the icon appears, once after each failed start of the CLI, and when the setting changes. It never resolves on a timer, so a CLI installed later is found after a shell reload or a change of the setting.
- **Reads never start the daemon.** The commands `on`, `off`, `camera`, `settings set`, `settings reset`, `modules enable|disable`, `order set|reset` and `config set` start it through D-Bus activation if you installed that file (see "Service presence and activation" in [`docs/dbus-api.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/dbus-api.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast)). The plugin avoids sending them while the daemon is known to be down.

When the daemon stops or restarts, the stream says so and the icon shows "unavailable" until the daemon is back. No action is needed. If the watch itself ends, the panel names the exit status or signal and the retry delay.

## Running from a local checkout

To work from a checkout, link its root into the shell's plugin directory:

```sh
mkdir -p ~/.config/omarchy/plugins
ln -s /path/to/omarchy-broadcast-plugin ~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast
```

To copy instead of linking, use the command below. Later changes in the checkout then no longer apply. The `tests/` and `.git` directories are not needed at run time and may be left out of the copy.

```sh
cp -r /path/to/omarchy-broadcast-plugin ~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast
```

With a symlink, a change made in the checkout may not trigger a reload by itself. To remove a linked plugin, delete the link:

```sh
rm ~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast
```

The manifest is at the root of the repository, which is what the add command expects. It installs the whole clone, `tests/` included. The shell never loads `tests/`: it reads only the files named by `manifest.json`.

## Testing the plugin

Run from the root of the checkout. None of the tests needs omarchy-broadcast, except the optional cases noted below. All commands are read-only with respect to your shell and your configuration. None starts or touches the running shell.

Run every check in one go:

```sh
tests/check-all.sh
```

To check against a given Omarchy release instead of the installed one, add `--omarchy-ref`:

```sh
tests/check-all.sh --omarchy-ref v4.5.0
```

`tests/check-all.sh` runs all the checks below plus shellcheck on the test scripts. It does not run `--live`, nor the real-CLI case unless `OMARCHY_BROADCAST_CLI` is set. It stops at the first failure. With `--omarchy-ref REF` it uses a shallow clone of the Omarchy repository at that tag, in a scratch directory. It needs `shellcheck`, or `uvx` to run it from the `shellcheck-py` package.

The checks, one by one:

- The logic in `Model.js` (see the list below):

  ```sh
  QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_model.qml
  ```

- Source invariants (see the list below):

  ```sh
  python3 -I tests/check-source.py
  ```

- `qmllint` on every QML file, import errors fatal:

  ```sh
  tests/lint.sh
  ```

- The shell's manifest validator:

  ```sh
  omarchy plugin validate .
  ```

- The plugin inside a throwaway Quickshell with a fake CLI (see below). Needs `quickshell`:

  ```sh
  tests/run-harness.sh
  ```

- The same, plus one resolver case against a real omarchy-broadcast binary (found, never run):

  ```sh
  OMARCHY_BROADCAST_CLI=/absolute/path/to/omarchy-broadcast tests/run-harness.sh
  ```

- The plugin against a real daemon and CLI:

  ```sh
  OMARCHY_BROADCAST_CLI=/absolute/path/to/omarchy-broadcast tests/run-harness.sh --live
  ```

**The unit tests** (`tests/tst_model.qml`) cover:

- the reducer, caps, tooltips, argument lists, path resolution and the click actions;
- the camera settings: parsing the settings lines of the watch stream against a fixture of real CLI lines, the reducer for full sets and deltas, caps, the capability rule, validation of ids and values, snapping, argument lists, the command queue, and the background effect drawn from the schema;
- where each disabled setting is drawn (`disabled_kind`, `enabled_when`: shown, hidden under its master, in "Not available now" or greyed);
- the setup dialog: its payload, the watch's change lines, parsing and bounding the modules, order, configuration and files lines, which stage moves and config writes are offered, row widgets, its sections, keyboard stops and argument lists;
- the preview: run rule, argument list, frame lines, placeholder texts, settings;
- the panel: its tabs (stored value, keyboard stops), its two layouts and the preview's frame or strip, the Details rows and their copy, the header's state line and the camera dropdown;
- the microphone: its `mic` lines, the settings groups routed to the Mic tab by their surface, its rows, writes and keyboard stops, the bar's microphone glyph;
- the background gallery: its `media` lines, video items, poster path checks, the video badge, the file chooser's extensions, the Gallery… and Add… steps with the import, the Background row and the Backgrounds section;
- the away image: its revision gate, its config row and picker view, its argument lists and flows, the dialog payload's row to open at;
- the battery saver: its revision gate, the switch's view, the mode it writes and remembers, the Mode dropdown with its revision 23 gate, its remembered mode and its writes, greyed and notice, the keyboard stops.

**The source invariants** (`tests/check-source.py`) cover: plain text everywhere, no shell strings, no polling timer, the manifest id and overlay entry point, no effect named anywhere, the camera setting and config write whitelists, the setting-id check, the command queue and slider debounce, the setup dialog's payload, reads and writes, the preview's single process, argument list and fixed frame path, the click mapping, the tab setting, the panel's size (920 and 520 wide, the 860 cap, one scroller), the `narrowPanel` setting, the visibility rule (`enabled` stays the daemon's word), the Mic tab drawn from the daemon's groups only, its switch and setting writes, and the battery saver's switch, its Mode dropdown and its stored mode.

**The harness** (`tests/run-harness.sh`) covers: the plugin's own fake preview stream; the setup dialog with the fake's modules, order and configuration; the background and away image galleries with fake `omarchy-menu-images` and `omarchy-file-select`; the battery saver's switch (revision gate, writes, remembered mode, greyed, notice) and its Mode dropdown (revision gate, writes, remembered mode, greyed, keyboard); and the panel's size measured on a 1080-high screen. For the size it prints one `MEASURE <state> <width>x<height>` line each for the narrow Effects view, the narrow Mic tab, the Details view and the wide layout with the preview hidden and live, and checks that each is within the 860 cap and the screen without the body scrolling. It uses a scratch `XDG_RUNTIME_DIR`.

Notes on the tools:

- `qmltestrunner` and `qmllint` come from Qt 6 (`/usr/lib/qt6/bin`, package `qt6-declarative` on Arch). `lint.sh` and `run-harness.sh` also need the Omarchy shell modules, by default in `/usr/share/omarchy/shell`. Set `OMARCHY_SHELL` to use another copy, such as the `shell/` directory of a checkout of the Omarchy repository.
- `run-harness.sh` builds its own directory (under `$TMPDIR`, or `--work DIR` if that is empty or an earlier harness directory). It runs a separate offscreen Quickshell on a copy of the plugin's files (the setup dialog's layer-shell namespace line taken out: offscreen its overlay window is a plain item) with the fake CLI `tests/fake-omarchy-broadcast`. The fake CLI:
  - streams a Logitech MX Brio's camera settings and answers `settings set` and `settings reset`;
  - prints each setting's `disabled_kind` (left out when the file `settings-no-kind` exists, as a daemon before interface revision 28 prints them);
  - prints the setup dialog's modules, order, configuration and files and answers its writes;
  - prints a preview stream and writes real JPEG frames into the harness's own runtime directory, never yours.

  The harness removes nothing outside its directory. It prints `ALL OK` and exits 0 on success, and removes its directory. After a failure it keeps the directory (log, fake log, screenshots) and prints where it is. `KEEP_WORK=1` or `--screens DIR` keeps the screenshots on success. Its text-layout checks need a font installed (Omarchy's default is JetBrains Mono Nerd Font).
- The mock run is hermetic: the shell it starts has a `PATH` made of the fake CLI and the system tools only, never another `omarchy-broadcast`, and the run refuses to start if anything else would answer. A real CLI installed on the machine is never executed by it. The CLI resolver cases use scratch directories as their `PATH`. With `OMARCHY_BROADCAST_CLI` set to the absolute path of a real `omarchy-broadcast` binary, one more case checks that the resolver finds it on a `PATH`. The resolver only prints the path, and nothing executes the binary in this mode. Without the variable that case prints a `SKIP` line and does not count as a failure.
- `--live` takes the CLI from `OMARCHY_BROADCAST_CLI` and the daemon from `OMARCHY_BROADCASTD` (default: `omarchy-broadcastd` in the same directory as the CLI), and refuses to run without them. It starts its own `omarchy-broadcastd` with a scratch configuration and state, opens the virtual camera for a few seconds with `gst-launch-1.0` and stops everything again. It refuses to run if `br.com.dias.OmarchyBroadcast` already has an owner on the session bus. It needs the "Omarchy Broadcast" v4l2loopback device ([`docs/setup/loopback.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/loopback.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast)).

## Notes for maintainers and marketplace review

- **Starting the daemon.** The plugin starts the daemon only through the CLI's D-Bus activation (the CLI's `start` command, run by the panel's Start button). It never runs `systemctl`. The line below, shown in the panel's not-running message and quoted here, is text for the user to copy:

  ```sh
  systemctl --user enable --now omarchy-broadcastd
  ```

- **Every `systemctl` and `journalctl` line is display text.** The plugin executes none of them. They are shown in the panel or the setup dialog for the user to run in a terminal:
  - `systemctl --user enable --now omarchy-broadcastd`, in the panel's not-running message (above);
  - `journalctl --user -u omarchy-broadcastd`, in the panel's "not answering" message and in the setup dialog's Diagnostics ([The setup dialog](setup-dialog.md#diagnostics)).

  Beyond this list, the docs quote only the log command as the setup dialog displays it, in [Diagnostics](setup-dialog.md#diagnostics), and no other `systemctl` or `journalctl` line: the daemon's own fixes are linked in its repository.

  `tests/check-source.py` pins this: "systemctl and journalctl appear only as displayed command text".

- **External dependency.** The plugin is a client and needs the external daemon, `omarchy-broadcastd` and its `omarchy-broadcast` CLI, installed with the daemon's own guide (see [Before you start](../INSTALL.md#before-you-start)). Nothing in this repository installs it.
- **External commands the plugin runs**, each as an argument list (the only shell is the two constant `sh -c` scripts described below):
  - `omarchy-broadcast`, the CLI: `watch --json` for the state, `preview --json` for the live preview, `start` for the Start button, and the commands that change the daemon's state, such as `on`, `off`, `settings set`, `modules`, `order`, `config` and `media`;
  - `omarchy-menu-images` and `omarchy-file-select`, Omarchy's image picker and file chooser, for the background and away image galleries;
  - `sh -c`, with a constant script, to find the CLI and those two tools on `PATH`.

  The plugin runs no package manager, no `systemctl` and no `journalctl`, and needs no root.
- **Scan triggers that are not plugin behaviour.** Some marketplace scan triggers are not plugin behaviour.
  - The git clone in `tests/check-all.sh` (a remote build) is test-only: it fetches an Omarchy release for `--omarchy-ref` and is never loaded by the shell.
  - The plugin itself never runs a package manager, `sudo`, `git`, `systemctl` or `journalctl`.
  - The scripts in `tests/` that have the executable bit (the fake CLI and its helpers) are test fixtures, not bundled executables; the shell never loads them.
- **`tests/` is test-only.** It contains `pgrep`/`kill` calls (confined to processes the harness started, counted by a marker path inside its own work directory), `sh -c`, and an executable fake CLI. None of it is loaded by the shell.
- **The two `sh -c`** in the plugin code are the CLI resolver and the lookup of the gallery's two tools (`omarchy-menu-images`, `omarchy-file-select`) on `PATH`. Both scripts are constants. Nothing is interpolated into them (the lookup gets the two tool names as positional arguments). Every other command is an argument list. A path the image picker or the file chooser returns is passed as one argument, and the picker's only when it is exactly a path the daemon's gallery list just named.
- **Identity and licence.** The plugin id is `br.com.dias.omarchy-broadcast`, which the shell's manifest validator accepts (see [Testing the plugin](#testing-the-plugin)). It stays fixed: renaming it would break existing installs. The licence files are at the root of this repository, `LICENSE-MIT` and `LICENSE-APACHE` (`MIT OR Apache-2.0`, as in `manifest.json`). The plugin directory itself holds none.

## Versioning

The plugin's version is the `version` field of `manifest.json`. It started at 0.16.0, the omarchy-broadcast release it was split from, and is independent of the omarchy-broadcast version from then on. The two are released separately, and matching numbers carry no meaning.

Compatibility is set by the interface, not by version numbers. The plugin needs an `omarchy-broadcast` CLI whose `watch --json` output is schema version (`v`) 1, specified in [`docs/cli-json.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/cli-json.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast). A line with a higher version is reported as "Unsupported omarchy-broadcast version", and any other value is refused as malformed. A change of the schema version requires a new release of the plugin.

The daemon's D-Bus interface revision each feature needs is below. The plugin shows the running daemon's revision as "Daemon API" in the Details view. A release in brackets is the omarchy-broadcast and omarchy-broadcastd version, or newer, that the feature needs.

| Revision | Feature | CLI needs |
|---|---|---|
| 5 or later (0.18.0) | The preview | `preview --json` |
| 7 or later (0.22.0) | The camera settings, with settings schema 1 | a snapshot that reports `settings_schema`, and the `settings` command |
| 9 or later (0.24.0) | The effects on the Effects tab, from loadable modules, and the setup dialog's Modules and Order | |
| 10 or later (0.25.0) | The dialog's Backends, Daemon and configuration files | the `config` command |
| 13 or later | The microphone | a snapshot that reports `mic`, and the `mic` command |
| 15 or later | The background gallery, which also needs Omarchy's `omarchy-menu-images` and `omarchy-file-select` on `PATH` | the `media` command and `effect replace --image` |
| 17 or later | The away image (`output.placeholder`, an editable `effect.fallback_image`, the `away` gallery) | `media list away` and `media import away` |
| 19 or later | The convert command under a video the CPU path cannot play | |
| 21 or later | `effect.privacy` and `effect.privacy_mode` in place of `effect.on_failure` | |
| 22 or later | The battery saver (`video.battery_saver`) | |
| 23 or later | The battery saver's "On battery or power saver" mode (`auto`) | |
| 28 or later | The placement of disabled settings (`disabled_kind`) and the default-microphone switch | |
