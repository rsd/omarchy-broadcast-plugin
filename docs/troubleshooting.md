# Troubleshooting

The messages below appear while the panel works. Back to the [README](../README.md).

Messages about the connection to the daemon, the CLI and version mismatches (the bar icon shows a warning sign) are in [INSTALL.md](../INSTALL.md#troubleshooting).

Each entry gives the message or symptom, its cause and what to do.

## Another app says the camera is busy

**Symptom.** Another app says the camera is busy, or shows no picture, while one app already uses "Omarchy Broadcast".

**Cause.** The virtual camera is a v4l2loopback device, which from version 0.14 lets one process stream at a time (one application can share it internally, as Chrome and Chromium do between tabs).

**What to do.** Close the first application. Or enable the daemon's PipeWire camera node (`[pipewire] enabled = true` in the daemon's configuration) for the applications that support PipeWire cameras: Chrome and Chromium need the `WebRtcPipeWireCamera` flag (`chrome://flags`), and OBS Studio has a "Video Capture Device (PipeWire)" source. Zoom and Discord keep using the virtual camera. Consumers of the PipeWire node that ask for different formats can stall it until all disconnect, so it is optional. See [`docs/setup/loopback.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/loopback.md#one-application-at-a-time).

## The daemon refused the request

**Cause.** The daemon rejected `on`, `off`, the camera, a setting, or a write of the setup dialog (shown on the dialog's title line).

**What to do.** The text after the colon is the daemon's reason. See the daemon's status:

```sh
omarchy-broadcast status
```

## No effect module provides a background effect

**Cause.** No enabled, available module provides the `background` stage.

**What to do.** Open the setup dialog (right click), Modules: enable one, or see Diagnostics for why it cannot run.

## A setting in the setup dialog is greyed "Overridden by config.d/90-....toml"

**Cause.** A configuration file loaded after the dialog's own file sets it.

**What to do.** Change or remove it in that file, then reload the daemon's configuration (the daemon's ReloadConfig does the same; no restart is needed):

```sh
systemctl --user kill -s HUP omarchy-broadcastd
```

## An effect setting is listed under "Not available now" as not installed

**Symptom.** An effect setting (relighting, enhancement, noise removal) is listed under "Not available now" as not installed.

**Cause.** The SDK package the daemon uses lacks that feature or its models for your GPU.

**What to do.** The daemon's reason is the text shown. See [`docs/setup/maxine.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/maxine.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast).

## An effect on an Intel GPU or NPU says "not available"

**Cause.** The Intel GPU is not present in the running system (a laptop in its discrete-GPU-only mode), or the NPU's device `/dev/accel/accel0` is not accessible to your user (it needs the `render` group).

**What to do.** See "Troubleshooting" in [`docs/setup/onnx.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/onnx.md#8-troubleshooting) in the omarchy-broadcast repository.

## Noise removal is on, and the panel shows an error from the daemon

**Cause.** The daemon could not run noise removal. The camera streams without it.

**What to do.** The error text says why. See the daemon's status:

```sh
omarchy-broadcast status
```

## omarchy-broadcast preview exited / stopped / could not be started

**Symptom.** "omarchy-broadcast preview exited / stopped / could not be started ... Reopen the panel to retry."

**Cause.** The preview process ended.

**What to do.** Reopen the panel. If it repeats, run the preview in a terminal:

```sh
omarchy-broadcast preview --json
```

## A camera or effect setting is greyed

**Cause.** The daemon says it cannot be changed for now (the camera is busy, or a device does not allow it). The reason is in the row's tip, which shows while the pointer or the keyboard cursor is on the row.

**What to do.** Follow the reason. This is not an error.

## A setting you expect is not there

**Cause.** It depends on another setting that is off (it appears under that setting once it is on), or the daemon says it cannot run here: it is listed under "Not available now (n)" at the foot of the tab, with the reason, and a Setup… button where something can be installed, enabled or chosen.

**What to do.** Not an error. See [Camera settings](panel.md#camera-settings).

## A camera setting jumps back after you let go, and an error shows

**Cause.** The daemon refused the value. The row shows what the camera has.

**What to do.** The text after the colon is the daemon's reason.

## This camera reports no settings

**Cause.** The camera exposes no control the daemon publishes, or no camera is in use.

**What to do.** Not an error.

## Showing N of M settings / choices / groups

**Cause.** The settings are capped (see [How it talks to the daemon](development.md#how-it-talks-to-the-daemon)).

**What to do.** Not an error.

## Could not save the preview setting

**Cause.** The shell stored neither the preview's shown or hidden choice nor the rate.

**What to do.** The choice holds for this session. Check the plugin's entry in the bar layout.

## Command failed with status N

**Cause.** Any other exit status.

**What to do.** Run the same `omarchy-broadcast` command in a terminal.

## Showing N of M cameras / More cameras are connected; they are not shown

**Cause.** The camera list is capped.

**What to do.** Not an error.

## A camera is marked "(cannot be chosen)" in the camera dropdown

**Cause.** Its id is the word `next`, which the CLI would read as "next camera".

**What to do.** It is not selectable unless its USB vendor and product id are unique.
