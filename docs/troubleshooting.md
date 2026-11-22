# Troubleshooting

The messages the bar icon, the panel and the setup dialog show, with their causes and what to do. Back to the [README](../README.md).

Each entry gives the message or symptom, its cause and what to do. Where the fix is on the daemon's side, the entry links the daemon's own docs in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast).

## The connection to the daemon

The bar icon shows a warning sign and the panel shows one of these messages when the plugin cannot use the daemon.

### omarchy-broadcastd is not running

**Cause.** The service is stopped.

**What to do.** Press **Start** in the panel. It runs the command below. **Start** needs the daemon's D-Bus activation file, which the daemon's packages install, and a CLI that has `start`.

```sh
omarchy-broadcast start
```

An older CLI answers "This omarchy-broadcast version cannot start the daemon". Then start the daemon from a terminal, as in "Start the daemon" in the daemon's [`docs/setup/daemon.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/daemon.md#start-the-daemon). The panel also shows the command that starts it at every login, for you to copy.

### omarchy-broadcastd is not answering

**Cause.** The service runs but does not reply on the bus.

**What to do.** The plugin retries every 2 s. Read the daemon's log: the panel shows the command, [Logs](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/daemon.md#logs) and [Troubleshooting](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/daemon.md#troubleshooting) in the daemon's `docs/setup/daemon.md` say what to look for.

### omarchy-broadcast CLI not found, or "not on PATH"

**Cause.** No binary at `cliPath` or on `PATH`. The panel's hint reads "Install omarchy-broadcast-bin or -git from the AUR (see INSTALL.md). Or set the cliPath setting."

**What to do.** Install the CLI with the daemon ([Before you start](../INSTALL.md#before-you-start)). Make sure its directory is on the shell's `PATH`, or set `cliPath` ([Configuration](panel.md#configuration)). Then reload the shell or change the setting.

### cliPath must be an absolute path

**Cause.** `cliPath` is a bare name or a relative path.

**What to do.** Use an absolute path, or one starting with `~/`.

### omarchy-broadcast watch stopped / exited with status N / stopped by signal N; restarting in N s

**Cause.** The watch process ended.

**What to do.** The plugin restarts it, first after 1 s, doubling up to 30 s. If it repeats, run it in a terminal:

```sh
omarchy-broadcast watch --json
```

### A message says the daemon, the CLI or the plugin needs updating

**Cause.** The daemon, the CLI and the plugin read one interface, and one of them is older than a feature needs. The message names the one to update:

| Message | Update |
|---|---|
| Unsupported omarchy-broadcast version | The plugin or the CLI, so they match: the CLI prints a schema version the plugin does not know, or a line over the limit |
| omarchy-broadcastd reports a state this plugin does not know | The plugin |
| The daemon needs updating for effects (omarchy-broadcastd 0.24 or newer). | The daemon |
| The daemon needs updating for camera settings | The daemon |
| The omarchy-broadcast CLI needs updating for camera settings | The CLI and the daemon |
| Update the plugin to show these camera settings | The plugin |
| The setup dialog says the daemon needs updating | The daemon and the CLI |
| Preview needs omarchy-broadcast 0.18 or newer | The daemon and the CLI |
| This omarchy-broadcast has no preview command | The CLI |

**What to do.** Update the one the message names. An updated daemon takes over only once it restarts: if the message stays after an update, restart the daemon (see "Restarts and crashes" in the daemon's [`docs/setup/daemon.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/daemon.md#restarts-and-crashes)). The interface revision each feature needs is in [Versioning](development.md#versioning).

### omarchy-broadcastd writes its preview elsewhere than this shell expects

**Cause.** The daemon and the shell have different `XDG_RUNTIME_DIR` values.

**What to do.** Start both from the same session environment.

### Preview unavailable: ...

**Cause.** `XDG_RUNTIME_DIR` is unset, relative or unusable in the shell's environment.

**What to do.** Fix the shell's environment.

### D-Bus failure

**Cause.** The CLI could not reach the session bus.

**What to do.** Check `DBUS_SESSION_BUS_ADDRESS` in the shell's environment.

## While the panel works

### Another app says the camera is busy

**Symptom.** Another app says the camera is busy, or shows no picture, while one app already uses "Omarchy Broadcast".

**Cause.** The virtual camera lets one application stream at a time (one application can share it internally, as Chrome and Chromium do between tabs).

**What to do.** Close the first application. For several applications at once, see "One application at a time" in the daemon's [`docs/setup/loopback.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/loopback.md#one-application-at-a-time).

### The daemon refused the request

**Cause.** The daemon rejected `on`, `off`, the camera, a setting, or a write of the setup dialog (shown under the dialog's title).

**What to do.** The text after the colon is the daemon's reason. See the daemon's status:

```sh
omarchy-broadcast status
```

### No effect module provides a background effect

**Cause.** No enabled, available module provides the `background` stage.

**What to do.** Open the setup dialog (right click), Modules: enable one, or see Diagnostics for why it cannot run.

### A setting in the setup dialog is greyed "Overridden by config.d/90-....toml"

**Cause.** A configuration file loaded after the dialog's own file sets it, and the daemon refuses to change it from the dialog.

**What to do.** The file is named in the message. How the daemon's configuration files override each other, and how to reload them, is in "Configuration" in the daemon's [`docs/setup/daemon.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/daemon.md#configuration).

### An effect setting is listed under "Not available now" as not installed

**Symptom.** An effect setting (relighting, enhancement, noise removal) is listed under "Not available now" as not installed.

**Cause.** The SDK package the daemon uses lacks that feature or its models for your GPU.

**What to do.** The daemon's reason is the text shown. See "Troubleshooting" in the daemon's [`docs/setup/maxine.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/maxine.md#7-troubleshooting).

### An effect on an Intel GPU or NPU says "not available"

**Cause.** The Intel GPU is not present in the running system (a laptop in its discrete-GPU-only mode), or the NPU's device is not accessible to your user.

**What to do.** See "Troubleshooting" in the daemon's [`docs/setup/onnx.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/onnx.md#8-troubleshooting).

### Noise removal is on, and the panel shows an error from the daemon

**Cause.** The daemon could not run noise removal. The camera streams without it.

**What to do.** The error text says why. See the daemon's status:

```sh
omarchy-broadcast status
```

The daemon's causes and fixes are in the troubleshooting sections of its guides, listed under "Troubleshooting" in its [INSTALL.md](https://github.com/rsd/omarchy-broadcast/blob/main/INSTALL.md#troubleshooting).

### omarchy-broadcast preview exited / stopped / could not be started

**Symptom.** "omarchy-broadcast preview exited / stopped / could not be started ... Reopen the panel to retry."

**Cause.** The preview process ended.

**What to do.** Reopen the panel. If it repeats, run the preview in a terminal:

```sh
omarchy-broadcast preview --json
```

### A camera or effect setting is greyed

**Cause.** The daemon says it cannot be changed for now (the camera is busy, or a device does not allow it). The reason is in the row's tip, which shows while the pointer or the keyboard cursor is on the row.

**What to do.** Follow the reason. This is not an error.

### A setting you expect is not there

**Cause.** It depends on another setting that is off (it appears under that setting once it is on), or the daemon says it cannot run here: it is listed under "Not available now (n)" at the foot of the tab, with the reason, and a Setup… button where something can be installed, enabled or chosen.

**What to do.** Not an error. See [Camera settings](panel.md#camera-settings).

### A camera setting jumps back after you let go, and an error shows

**Cause.** The daemon refused the value. The row shows what the camera has.

**What to do.** The text after the colon is the daemon's reason.

### This camera reports no settings

**Cause.** The camera exposes no control the daemon publishes, or no camera is in use.

**What to do.** Not an error.

### Showing N of M settings / choices / groups

**Cause.** The settings are capped (see [How it talks to the daemon](development.md#how-it-talks-to-the-daemon)).

**What to do.** Not an error.

### Could not save the preview setting

**Cause.** The shell stored neither the preview's shown or hidden choice nor the rate.

**What to do.** The choice holds for this session. Check the plugin's entry in the bar layout.

### Command failed with status N

**Cause.** Any other exit status.

**What to do.** Run the same `omarchy-broadcast` command in a terminal.

### Showing N of M cameras / More cameras are connected; they are not shown

**Cause.** The camera list is capped.

**What to do.** Not an error.

### A camera is marked "(cannot be chosen)" in the camera dropdown

**Cause.** Its id is the word `next`, which the CLI would read as "next camera".

**What to do.** It is not selectable unless its USB vendor and product id are unique.
