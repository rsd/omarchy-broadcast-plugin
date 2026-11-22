# Install the Omarchy Broadcast bar plugin

Install the daemon first, then add the plugin to the Omarchy shell and enable it. The plugin needs no root and installs no packages. The daemon's packages do.

Not sure whether the plugin is for you? Read the [README](README.md) first.

## Before you start

You need the Omarchy shell, a Nerd Font and a working omarchy-broadcast daemon and CLI. The plugin is a client of the daemon and does not include it. Nothing in this repository installs it. The full list follows.

### Requirements

The plugin reads the state from the stream of the CLI's `watch --json` and sends commands through the `omarchy-broadcast` CLI. For the preview it also runs the CLI's `preview --json`. The stream formats are specified in [`docs/cli-json.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/cli-json.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast).

Always required:

- `omarchy-broadcastd` and the `omarchy-broadcast` CLI, installed as in [Install the daemon](#install-the-daemon) and described in [`docs/setup/daemon.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/daemon.md). The icon shows "unavailable" until the daemon runs. The plugin works without D-Bus activation. With activation, `on`, `off`, camera selection and setting writes start a stopped daemon (see [How it talks to the daemon](docs/development.md#how-it-talks-to-the-daemon)).
- A CLI whose `watch --json` prints schema version (`v`) 1. A line with a higher version is reported as "Unsupported omarchy-broadcast version". Any other value is refused as malformed.
- The Omarchy shell (Quickshell) with the plugin system, and `omarchy` on `PATH`.
- A theme-aware Nerd Font for the icons, as the rest of the bar uses.

Per feature. D-Bus interface revisions are the daemon's; the plugin shows the daemon's revision as "Daemon API" in the Details view.

| Feature | Needs | With an older daemon or CLI |
|---|---|---|
| Camera settings (Camera tab) | omarchy-broadcast and omarchy-broadcastd 0.22.0 or newer: a CLI whose snapshot reports `settings_schema` and that has the `settings` command, a running daemon with interface revision 7 or later, and a settings schema (the `schema` of the `settings_group` lines) of 1, the one this plugin reads | The Camera tab shows the cameras and a hint saying which one needs updating ("The daemon needs updating for camera settings (omarchy-broadcastd 0.22 or newer)."). With a newer schema the hint is "Update the plugin to show these camera settings." There is no fallback to the sliders of earlier versions of this plugin, which the settings replaced. The rest of the plugin works as before |
| Video effects (Effects tab) | omarchy-broadcastd 0.24.0 or newer: a running daemon with interface revision 9 or later, whose effects come from loadable modules and are published as global settings | The Effects tab says the daemon needs updating. The rest of the plugin still shows the state, switches the camera and adjusts the camera's settings |
| Setup dialog | omarchy-broadcastd 0.24.0 or newer (revision 9) for Modules and Order. 0.25.0 or newer (revision 10) for Backends, Daemon and the configuration files in Diagnostics, with a CLI that has the `config` command | Each section that needs more says so |
| Preview | omarchy-broadcast 0.18.0 or newer: a CLI with the `preview` command and a running daemon with revision 5 or later | The panel says so. The rest of the plugin works as before |
| Microphone (Mic tab, the bar's microphone glyph) | A running daemon with revision 13 or later and a CLI whose snapshot reports `mic` and that has the `mic` command | The Mic tab says which one needs updating. The rest of the plugin works as before |
| Background gallery (Effects tab's Background row, the dialog's Backgrounds section) | Revision 15 or later: a running daemon of that revision, a CLI that has the `media` command and `effect replace --image`, and Omarchy's `omarchy-menu-images` and `omarchy-file-select` on `PATH` | The Effects tab shows the image read-only. The dialog has no Backgrounds section |
| Video and animated backgrounds | A daemon that accepts them (it lists video items in the gallery). `ffmpeg` is needed by the daemon, not the plugin: to import animated images and to make the playback copies the CPU path uses | Without `ffmpeg` those imports are refused with the reason, and such a video is shown as a still |
| Away image (the dialog's Away image row, the Effects tab's Away image row under More) | Revision 17 or later: a daemon that offers `output.placeholder`, takes `effect.fallback_image` as an editable path and has the `away` gallery (`media list away`, `media import away`) | The dialog shows the image path read-only, and the panel has no button |
| Convert command for a video the CPU path cannot play (the dialog's Backgrounds rows) | Revision 19 or later: a daemon whose `media list background --json` items carry `cpu_ready` and `convert_command` | Nothing is shown there |
| Battery saver (Effects tab's Battery saver row under More, with its switch and Mode dropdown, and the mode in the dialog) | Revision 22 or later: a daemon that publishes the `video.battery_saver` configuration row. The "On battery or power saver" mode (`auto`) needs revision 23 or later | None of them is shown. With revision 22 the dropdown and the dialog offer the other three modes |
| Placement of disabled settings (a setting is shown only where it can be acted on, see [Camera settings](docs/panel.md#camera-settings)) and the default-microphone switch | Revision 28 or later: a daemon whose settings carry `disabled_kind` | A setting whose `enabled_when` rule does not hold is hidden under its master, every other disabled setting is greyed in place, and the default-microphone choice is not a switch |

## Install the daemon

The daemon is a set of AUR packages: `omarchy-broadcast-bin` (prebuilt) or `omarchy-broadcast-git` (built from source), plus at least one effect module such as `omarchy-broadcast-onnx-bin`. The packages and the virtual camera device need `sudo`. A typical install:

```sh
yay -S omarchy-broadcast-bin omarchy-broadcast-onnx-bin
```

The [daemon's INSTALL.md](https://github.com/rsd/omarchy-broadcast/blob/main/INSTALL.md) is the full guide. It covers the package choices (NVIDIA and non-NVIDIA), the `v4l2loopback` setup, starting the daemon at every login and checking the result. Follow it up to its "Check that it works" section, then come back here.

## Install the plugin

Install it from the Omarchy plugin marketplace listing, or add it by hand from its git URL:

```sh
omarchy plugin add https://github.com/rsd/omarchy-broadcast-plugin
```

The command shows a warning that plugins run as unsandboxed code in the shell and asks you to confirm. Then it clones the repository into `~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast`, validates it and asks the shell to rescan. The manifest is at the root of the repository, which is what the add command expects.

The whole clone is installed, including `tests/`. The shell never loads it: it reads only the files named by `manifest.json`.

### From a local checkout

To work from a checkout, link its root into the shell's plugin directory:

```sh
mkdir -p ~/.config/omarchy/plugins
ln -s /path/to/omarchy-broadcast-plugin ~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast
```

To copy instead of linking, use the command below. Later changes in the checkout then no longer apply. The `tests/` and `.git` directories are not needed at run time and may be left out of the copy.

```sh
cp -r /path/to/omarchy-broadcast-plugin ~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast
```

With a symlink, a change made in the checkout may not trigger a reload by itself.

## Enable the plugin on the bar

Enable the plugin. This also places the icon in the right section of the bar:

```sh
omarchy plugin enable br.com.dias.omarchy-broadcast
```

To choose the place yourself, pass a placement to `enable`, or move the icon later:

```sh
omarchy bar move br.com.dias.omarchy-broadcast --section centerBegin --index 0
omarchy bar put  br.com.dias.omarchy-broadcast --after omarchy.clock
```

You can also add and enable in one step:

```sh
omarchy plugin add https://github.com/rsd/omarchy-broadcast-plugin --enable
```

## Set the CLI path (optional)

The plugin looks for `omarchy-broadcast` in two places, in this order:

1. The `cliPath` setting, if you set it. If it is set but unusable, the plugin says so and does not fall back.
2. `omarchy-broadcast` on the shell's `PATH`. The AUR packages install it in `/usr/bin`. The daemon's [`scripts/install-user.sh`](https://github.com/rsd/omarchy-broadcast/blob/main/scripts/install-user.sh) installs it in `~/.local/bin`, and a cargo install in `~/.cargo/bin`. Omarchy's default shell environment appends `~/.local/bin` to `PATH`.

Set `cliPath` in the plugin's settings in the shell when the directory is not on the shell's own `PATH`, or to use a build that is not on `PATH`, such as a development build. It takes an absolute path. A leading `~/` means your home directory. A bare name or a relative path is refused, because a command would then run relative to whatever directory the shell has.

The plugin resolves the binary when the icon appears, once after each failed start of the CLI, and when the setting changes. It never resolves on a timer. If nothing was found and you install the CLI afterwards, reload the shell or change the setting.

All six plugin settings are described in [Configuration](docs/panel.md#configuration).

## Check that it works

1. Confirm that the shell found the plugin:

   ```sh
   omarchy plugin list
   ```

   The list shows `br.com.dias.omarchy-broadcast`.

2. Look at the bar icon. A webcam icon means the plugin talks to the daemon (a crossed-out webcam means the camera is off). A warning sign means it does not: see [Troubleshooting](#troubleshooting).

3. Left click the icon. The panel opens with the preview strip, the Effects, Camera and Mic tabs and the camera's state in its header.

## Update

For a plugin added with the add command, or linked from a git checkout:

```sh
omarchy plugin update br.com.dias.omarchy-broadcast
```

The command fetches the repository, shows the changes, asks for confirmation, fast-forwards and validates the result. A copy made without `.git` has nothing to pull from: copy it again. The plugin's version is the `version` field of `manifest.json`.

Update the plugin and the daemon together when a message says one needs updating. The plugin reads a fixed interface, not a version number: see [Versioning](docs/development.md#versioning).

## Uninstall

```sh
omarchy plugin disable br.com.dias.omarchy-broadcast
omarchy plugin remove br.com.dias.omarchy-broadcast
```

If you linked the plugin, deleting the link has the same effect:

```sh
rm ~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast
```

If a placement is left in the bar layout, remove it with the shell's bar commands and reload the shell. They are listed by:

```sh
omarchy bar --help
```

The plugin starts no service of its own and writes no files. The one exception is that the shell stores your choices in the panel (the preview's shown or hidden state and rate, and the tab) in the plugin's bar-layout entry.

The processes the plugin owns are:

- the `watch` child;
- the `preview` child, while a panel is open;
- the gallery's steps, only while you use the Background row or the setup dialog's Away image row: the `media` commands (the import included), `omarchy-menu-images` and `omarchy-file-select`, one at a time.

They end with the shell: they exit when their output pipe closes or on `SIGTERM`.

Removing the plugin does not touch the daemon. To stop and uninstall it, see "Stop, disable, uninstall" in the daemon's [`docs/setup/daemon.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/daemon.md) and the [Uninstall section of its INSTALL.md](https://github.com/rsd/omarchy-broadcast/blob/main/INSTALL.md#uninstall).

## Troubleshooting

The bar icon shows a warning sign and the panel shows one of the messages below when the plugin cannot use the daemon. Messages about how the panel behaves while it works (greyed settings, a failed preview, the caps) are in [docs/troubleshooting.md](docs/troubleshooting.md).

### omarchy-broadcastd is not running

**Cause.** The service is stopped.

**Fix.** Press **Start** in the panel. It runs the command below. **Start** needs the daemon's D-Bus activation file, which the AUR packages install, and a CLI that has `start`.

```sh
omarchy-broadcast start
```

An older CLI answers "This omarchy-broadcast version cannot start the daemon". Then run the command below in a terminal yourself. It also starts the daemon at every login ([`docs/setup/daemon.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/daemon.md)):

```sh
systemctl --user enable --now omarchy-broadcastd
```

### omarchy-broadcastd is not answering

**Cause.** The service runs but does not reply on the bus.

**Fix.** Read its log. The plugin retries every 2 s.

```sh
journalctl --user -u omarchy-broadcastd
```

### omarchy-broadcast CLI not found, or "not on PATH"

**Cause.** No binary at `cliPath` or on `PATH`. The panel's hint reads "Install omarchy-broadcast-bin or -git from the AUR. Or set the cliPath setting."

**Fix.** Install the CLI (the AUR package `omarchy-broadcast-git` or the prebuilt `omarchy-broadcast-bin`, [`scripts/install-user.sh`](https://github.com/rsd/omarchy-broadcast/blob/main/scripts/install-user.sh) or a cargo install). Make sure its directory is on the shell's `PATH`, or set `cliPath` ([Set the CLI path](#set-the-cli-path-optional)). Then reload the shell or change the setting.

### cliPath must be an absolute path

**Cause.** `cliPath` is a bare name or a relative path.

**Fix.** Use an absolute path, or one starting with `~/`.

### omarchy-broadcast watch stopped / exited with status N / stopped by signal N; restarting in N s

**Cause.** The watch process ended.

**Fix.** The plugin restarts it, first after 1 s, doubling up to 30 s. If it repeats, run it in a terminal:

```sh
omarchy-broadcast watch --json
```

### Unsupported omarchy-broadcast version

**Cause.** The CLI prints a schema version the plugin does not know, or a line over the limit.

**Fix.** Update the plugin or the CLI so they match. The plugin reads schema `v` 1 ([Versioning](docs/development.md#versioning)).

### omarchy-broadcastd reports a state this plugin does not know

**Cause.** The daemon is newer than the plugin.

**Fix.** Update the plugin.

### The daemon needs updating for effects (omarchy-broadcastd 0.24 or newer).

**Cause.** The running daemon reports a D-Bus interface revision below 9 (or none): its effects do not come from modules.

**Fix.** Update omarchy-broadcastd. If it is already updated, restart it:

```sh
systemctl --user restart omarchy-broadcastd
```

### The daemon needs updating for camera settings

**Cause.** The CLI knows them, but the running daemon reports an interface revision below 7.

**Fix.** Update omarchy-broadcastd to 0.22.0 or newer, or restart it if it is already updated.

### The omarchy-broadcast CLI needs updating for camera settings

**Cause.** The CLI predates them (its snapshot has no `settings_schema`).

**Fix.** Update the CLI and the daemon to 0.22.0 or newer.

### Update the plugin to show these camera settings

**Cause.** The daemon publishes a newer settings schema than the plugin reads (schema 1).

**Fix.** Update the plugin.

### The setup dialog says the daemon needs updating

**Cause.** The daemon is below interface revision 9 (the dialog), or 10 (its configuration sections).

**Fix.** Update omarchy-broadcast and omarchy-broadcastd. Restart the daemon if it is already updated.

### Preview needs omarchy-broadcast 0.18 or newer

**Cause.** The running daemon reports an interface revision below 5.

**Fix.** Update omarchy-broadcastd and the CLI. Restart the daemon if it is already updated.

### This omarchy-broadcast has no preview command

**Cause.** The CLI predates the preview.

**Fix.** Update the CLI.

### omarchy-broadcastd writes its preview elsewhere than this shell expects

**Cause.** The daemon and the shell have different `XDG_RUNTIME_DIR` values.

**Fix.** Start both from the same session environment.

### Preview unavailable: ...

**Cause.** `XDG_RUNTIME_DIR` is unset, relative or unusable in the shell's environment.

**Fix.** Fix the shell's environment.

### D-Bus failure

**Cause.** The CLI could not reach the session bus.

**Fix.** Check `DBUS_SESSION_BUS_ADDRESS` in the shell's environment.
