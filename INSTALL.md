# Install the Omarchy Broadcast bar plugin

Install the daemon first, then add the plugin to the Omarchy shell and enable it. The plugin needs no root and installs no packages. The daemon's packages do.

Not sure whether the plugin is for you? Read the [README](README.md) first.

## Before you start

- The Omarchy shell (Quickshell) with the plugin system, and `omarchy` on `PATH`.
- A theme-aware Nerd Font for the icons, as the rest of the bar uses.
- The `omarchy-broadcastd` daemon and the `omarchy-broadcast` CLI, working. The plugin is a client of the daemon and does not include it. Nothing in this repository installs it.
- A CLI whose `watch --json` output has schema version (`v`) 1. See [Requirements](README.md#requirements) for the daemon and CLI versions each feature needs.

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

The command shows a warning that plugins run as unsandboxed code in the shell and asks you to confirm. Then it clones the repository into `~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast`, validates it and asks the shell to rescan. The manifest is at the root of the repository, which is what `omarchy plugin add` expects.

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

You can also add and enable in one step with `omarchy plugin add <url> --enable`.

## Set the CLI path (optional)

The plugin looks for `omarchy-broadcast` in two places, in this order:

1. The `cliPath` setting, if you set it. If it is set but unusable, the plugin says so and does not fall back.
2. `omarchy-broadcast` on the shell's `PATH`. The AUR packages install it in `/usr/bin`. The daemon's [`scripts/install-user.sh`](https://github.com/rsd/omarchy-broadcast/blob/main/scripts/install-user.sh) installs it in `~/.local/bin`, and `cargo install` in `~/.cargo/bin`. Omarchy's default shell environment appends `~/.local/bin` to `PATH`.

Set `cliPath` in the plugin's settings in the shell when the directory is not on the shell's own `PATH`, or to use a build that is not on `PATH`, such as a development build. It takes an absolute path. A leading `~/` means your home directory. A bare name or a relative path is refused, because a command would then run relative to whatever directory the shell has.

The plugin resolves the binary when the icon appears, once after each failed start of the CLI, and when the setting changes. It never resolves on a timer. If nothing was found and you install the CLI afterwards, reload the shell or change the setting.

## Check that it works

1. Confirm that the shell found the plugin:

   ```sh
   omarchy plugin list
   ```

   The list shows `br.com.dias.omarchy-broadcast`.

2. Look at the bar icon. A webcam icon means the plugin talks to the daemon (a crossed-out webcam means the camera is off). A warning sign means it does not: see [Troubleshooting](#troubleshooting).

3. Left click the icon. The panel opens with the preview strip, the Effects, Camera and Mic tabs and the camera's state in its header.

## Update

For a plugin added with `omarchy plugin add`, or linked from a git checkout:

```sh
omarchy plugin update br.com.dias.omarchy-broadcast
```

The command fetches the repository, shows the changes, asks for confirmation, fast-forwards and validates the result. A copy made without `.git` has nothing to pull from: copy it again. The plugin's version is the `version` field of `manifest.json`.

Update the plugin and the daemon together when a message says one needs updating. The plugin reads a fixed interface, not a version number: see [Versioning](README.md#versioning).

## Uninstall

```sh
omarchy plugin disable br.com.dias.omarchy-broadcast
omarchy plugin remove br.com.dias.omarchy-broadcast
```

If you linked the plugin, deleting the link has the same effect:

```sh
rm ~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast
```

If a placement is left in the bar layout, remove it with the shell's bar commands (`omarchy bar --help`) and reload the shell.

The plugin starts no service of its own and writes no files. The one exception is that the shell stores your choices in the panel (the preview's shown or hidden state and rate, and the tab) in the plugin's bar-layout entry.

The processes the plugin owns are:

- the `watch` child;
- the `preview` child, while a panel is open;
- the gallery's steps, only while you use the Background row or the setup dialog's Away image row: the `media` commands (the import included), `omarchy-menu-images` and `omarchy-file-select`, one at a time.

They end with the shell: they exit when their output pipe closes or on `SIGTERM`.

Removing the plugin does not touch the daemon. To stop and uninstall it, see "Stop, disable, uninstall" in the daemon's [`docs/setup/daemon.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/daemon.md) and the [Uninstall section of its INSTALL.md](https://github.com/rsd/omarchy-broadcast/blob/main/INSTALL.md#uninstall).

## Troubleshooting

The bar icon shows a warning sign and the panel shows the message below when the plugin cannot use the daemon. Messages about how the panel behaves while it works (greyed settings, a failed preview, the caps) are in the [README](README.md#troubleshooting).

| Message | Cause | Fix |
|---|---|---|
| omarchy-broadcastd is not running | The service is stopped | Press **Start** in the panel. It runs `omarchy-broadcast start`. An older CLI answers "This omarchy-broadcast version cannot start the daemon": then run the command below. To start the daemon at every login, run `systemctl --user enable --now omarchy-broadcastd` in a terminal ([`docs/setup/daemon.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/daemon.md)). **Start** needs the daemon's D-Bus activation file, which the AUR packages install, and a CLI that has `start` |
| omarchy-broadcastd is not answering | The service runs but does not reply on the bus | Run `journalctl --user -u omarchy-broadcastd`. The plugin retries every 2 s |
| omarchy-broadcast CLI not found, or "not on PATH" | No binary at `cliPath` or on `PATH`. The panel's hint reads "Install omarchy-broadcast-bin or -git from the AUR. Or set the cliPath setting." | Install the CLI (the AUR package `omarchy-broadcast-git` or the prebuilt `omarchy-broadcast-bin`, [`scripts/install-user.sh`](https://github.com/rsd/omarchy-broadcast/blob/main/scripts/install-user.sh) or `cargo install`). Make sure its directory is on the shell's `PATH`, or set `cliPath`. Then reload the shell or change the setting |
| cliPath must be an absolute path | `cliPath` is a bare name or a relative path | Use an absolute path, or one starting with `~/` |
| omarchy-broadcast watch stopped / exited with status N / stopped by signal N; restarting in N s | The watch process ended | The plugin restarts it, first after 1 s, doubling up to 30 s. If it repeats, run `omarchy-broadcast watch --json` in a terminal |
| Unsupported omarchy-broadcast version | The CLI prints a schema version the plugin does not know, or a line over the limit | Update the plugin or the CLI so they match. The plugin reads schema `v` 1 ([Versioning](README.md#versioning)) |
| omarchy-broadcastd reports a state this plugin does not know | The daemon is newer than the plugin | Update the plugin |
| The daemon needs updating for effects (omarchy-broadcastd 0.24 or newer). | The running daemon reports a D-Bus interface revision below 9 (or none): its effects do not come from modules | Update omarchy-broadcastd. If it is already updated, restart it: `systemctl --user restart omarchy-broadcastd` |
| The daemon needs updating for camera settings | The CLI knows them, but the running daemon reports an interface revision below 7 | Update omarchy-broadcastd to 0.22.0 or newer, or restart it if it is already updated |
| The omarchy-broadcast CLI needs updating for camera settings | The CLI predates them (its snapshot has no `settings_schema`) | Update the CLI and the daemon to 0.22.0 or newer |
| Update the plugin to show these camera settings | The daemon publishes a newer settings schema than the plugin reads (schema 1) | Update the plugin |
| The setup dialog says the daemon needs updating | The daemon is below interface revision 9 (the dialog), or 10 (its configuration sections) | Update omarchy-broadcast and omarchy-broadcastd. Restart the daemon if it is already updated |
| Preview needs omarchy-broadcast 0.18 or newer | The running daemon reports an interface revision below 5 | Update omarchy-broadcastd and the CLI. Restart the daemon if it is already updated |
| This omarchy-broadcast has no preview command | The CLI predates the preview | Update the CLI |
| omarchy-broadcastd writes its preview elsewhere than this shell expects | The daemon and the shell have different `XDG_RUNTIME_DIR` values | Start both from the same session environment |
| Preview unavailable: ... | `XDG_RUNTIME_DIR` is unset, relative or unusable in the shell's environment | Fix the shell's environment |
| D-Bus failure | The CLI could not reach the session bus | Check `DBUS_SESSION_BUS_ADDRESS` in the shell's environment |
