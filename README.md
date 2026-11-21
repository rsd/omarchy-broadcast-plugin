# Omarchy Broadcast bar plugin

Control the [omarchy-broadcast](https://github.com/rsd/omarchy-broadcast) virtual camera and virtual microphone from the Omarchy bar. It is for Omarchy users who run the omarchy-broadcast daemon and want its on/off switch, effects and camera settings one click away.

The plugin (`br.com.dias.omarchy-broadcast`) is a bar plugin for the Omarchy shell (Quickshell/QML). It is a client of the daemon, `omarchy-broadcastd`, and does not include it: install the daemon first ([INSTALL.md](INSTALL.md)).

## What you get

**In the bar**, an icon that shows the state of the virtual camera: off, idle, starting, active, error or unavailable. While an application records from the Omarchy Broadcast Mic, a microphone glyph shows beside it. A left click opens the panel, a middle click turns the camera on or off, and a right click opens the setup dialog.

**In the panel:**

- **Preview.** A live view of exactly what video apps receive from the virtual camera.
- **Effects.** Choose the background effect (typically Off, Blur or Replace) and adjust the other effect settings: blur strength, noise removal, enhancement of a low-resolution camera, relighting and whatever else the installed modules offer. Pick the background image from a gallery of bundled and your own pictures and videos.
- **Camera.** Select the camera and adjust its own settings: image, white balance, exposure, focus and zoom, whatever the camera offers. See the health of the camera, and apply the daemon's recommended settings with one click.
- **Mic.** Turn the Omarchy Broadcast Mic on and off, choose its input device and adjust its noise and echo removal and studio voice.
- **Details.** Live figures while the camera runs (frame rate, latency, CPU and GPU load), and a **Copy** button for bug reports.
- **More**, under the effect settings: a battery saver and a shortcut to the away image.

**In the setup dialog** (right click on the icon): the effect modules, the order their stages run in, the backend profile and pins, the daemon's configuration, the background and away image galleries, and a diagnosis.

The plugin names no effect and no setting. It draws what the daemon publishes, so what you can do depends on the modules you installed. Open-model (ONNX) modules run on any GPU or on the CPU. The NVIDIA Maxine modules need an NVIDIA RTX GPU.

## Why use it

- **One place for the whole camera.** The state, the effects, the camera's own controls and the microphone are in one panel on the bar, not in a terminal.
- **It stays idle until you ask.** The preview is hidden by default, and a hidden preview never starts the camera. The plugin does not poll: the daemon pushes each change.
- **It follows the daemon.** A module you install, or a setting the camera offers, appears without a plugin update.
- **It stays out of the way.** The plugin needs no root and runs no package manager and no `systemctl`. It never opens a camera device and never speaks D-Bus: it runs the `omarchy-broadcast` CLI, always as an argument list and never through a shell.
- **It works from the keyboard.** The panel and the setup dialog have keyboard stops and shortcuts. The icon and the settings carry names and states for screen readers. Colours come from the active theme.

## Install

Install the daemon first ([INSTALL.md](INSTALL.md#install-the-daemon)), then add and enable the plugin:

```sh
omarchy plugin add https://github.com/rsd/omarchy-broadcast-plugin
omarchy plugin enable br.com.dias.omarchy-broadcast
```

The marketplace route, a local checkout, the `cliPath` setting, updating, removing and troubleshooting are in [INSTALL.md](INSTALL.md).

The plugin is the root of this repository (`manifest.json` and the QML files). Its tests are in [`tests/`](tests/). Nothing is built or installed by this repository.

## Requirements

The plugin reads the state from the stream of `omarchy-broadcast watch --json` and sends commands through the `omarchy-broadcast` CLI. For the preview it also runs `omarchy-broadcast preview --json`. The stream formats are specified in [`docs/cli-json.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/cli-json.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast).

Always required:

- `omarchy-broadcastd` and the `omarchy-broadcast` CLI, installed as in [INSTALL.md](INSTALL.md#install-the-daemon) and described in [`docs/setup/daemon.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/daemon.md). The icon shows "unavailable" until the daemon runs. The plugin works without D-Bus activation. With activation, `on`, `off`, camera selection and setting writes start a stopped daemon (see [How it talks to the daemon](#how-it-talks-to-the-daemon)).
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
| Placement of disabled settings (a setting is shown only where it can be acted on, see [Camera settings](#camera-settings)) and the default-microphone switch | Revision 28 or later: a daemon whose settings carry `disabled_kind` | A setting whose `enabled_when` rule does not hold is hidden under its master, every other disabled setting is greyed in place, and the default-microphone choice is not a switch |

## What it shows

### The bar icon

The icon follows the daemon state. Colours come from the active theme.

| State | Icon | Look |
|---|---|---|
| `off` | webcam, crossed out | dimmed; the privacy switch is off |
| `idle` | webcam | normal colour; on, no application is using the camera |
| `starting` | webcam | accent colour at half strength |
| `active` | webcam | accent colour; the camera and GPU run |
| `error` | alert circle | urgent colour; the daemon reports an error |
| unavailable | warning sign | dimmed; the daemon is not running, does not answer, or the CLI is missing or unsupported |

While a session runs and the camera's privacy shutter is closed (daemon interface revision 26 or later), the icon is the crossed-out webcam, in the state's colour, and the tooltip says "camera shutter closed".

The tooltip gives the state. While the camera runs it also gives the camera name, the number of consumers and the background effect when one is on, by the name the daemon gives its choice (for example "background: Blur"). An error text is appended when there is one, and so is a warning: a non-fatal message from the daemon, which keeps running. A warning does not change the icon or the state. When the plugin is unavailable, the tooltip names the cause. For screen readers the icon carries the tooltip's state as its name and what each click does as its description.

Clicks:

- **Left click** opens and closes the panel, as the shell's panel hotkey does.
- **Middle click** turns the camera on or off.
  - It does nothing while an earlier on/off or camera command is still running or waiting. Camera and effect setting writes and the setup dialog's changes do not hold it, and the on/off command goes ahead of any that are waiting.
  - While the daemon is unavailable it opens the panel instead. This way a persisted `off` is never flipped without being seen, and a click on the icon never starts a stopped daemon.
  - The panel's own on/off switch, at its top, follows the same rule. To start a stopped daemon, use the panel's **Start** button.
- **Right click** opens the setup dialog ([The setup dialog](#the-setup-dialog)), whatever the daemon's state. When the daemon is unavailable or too old, the dialog says so, and its Diagnostics section still shows what it can.

### The microphone glyph

While applications record from the Omarchy Broadcast Mic, a microphone glyph in the accent colour shows beside the camera's icon, whatever the camera's state. It is after the icon on a horizontal bar and under it on a vertical one. It turns the urgent colour while the microphone reports an error.

- Its tooltip gives the microphone's state, how many applications record from it, and the error when there is one.
- It follows the daemon's reports in the `watch` stream. The plugin does not poll for it.
- A left click opens the panel on the Mic tab, for that opening only: the tab the panel remembers does not change. When the panel is open, a left click closes it.
- A right click opens the setup dialog, as on the camera's icon.
- A middle click does nothing. Turning the camera on or off is the camera icon's job.

### The panel layouts

The panel has two layouts. Which one is drawn follows from your choices: the plugin's "Narrow panel (one column)" setting, and whether the preview is shown or hidden. It never follows what the preview is doing, so a preview that fails does not move it.

- **Wide**, the default while the preview is shown: 920 pixels wide, in two columns. The live preview is on the left, over a short summary (the camera, the output format, how many applications use it and the microphone's state). The settings tabs are on the right.
- **One column**, 520 pixels wide: the settings column alone while the preview is hidden, with the preview reduced to a one-line strip under the tab row. It is also the layout whenever "Narrow panel (one column)" is on, where a shown preview sits under the tab row. On the Mic tab the one-column layout has no preview, and the preview does not run there.

The panel is as tall as its content, at most 860 pixels and at most the screen's room. Past that, one scroller moves, the body (the tab's content). The header, the tab row and the preview stay in place. A camera settings group taller than the room (for example Focus & zoom on an MX Brio) scrolls with the body, see [Camera settings](#camera-settings).

### The panel from the top

- **The header.**
  - The state as a sentence: "Off", "Ready: starts when an app uses the camera", "Starting…", "In use by 2 apps, 30 fps", "Preview only, 30 fps" or "Error". The rate is the live figure, while one is reported.
  - A labelled "Virtual camera" on/off switch.
  - An (i) button that opens the [Details view](#the-details-view).
  - Under them, the daemon's error text, if any, and its warning, if any. The warning is a line of its own with a caution sign (a non-fatal message; the icon and the state do not change for it). A long one, up to the daemon's 512 bytes, wraps onto as many lines as it needs, in full, with its line breaks read as spaces. The tooltip gives its first 60 characters.
- **The last failed command**, if any.
- **The preview**, see the next section.
- **Three tabs**, Effects, Camera and Mic, of which one is shown.
  - The tab row is not shown while the daemon is unavailable, and the Details view takes the tabs' place while it is open.
  - The panel remembers the last tab chosen (the `panelTab` setting, see [Configuration](#configuration)) and opens on Effects the first time. A stored `status` from an earlier version reads as Effects.
- **When the daemon is unavailable**, the reason and, where it helps, a command to copy. The command is text for you to run in a terminal: the plugin never runs `systemctl`. When the daemon is not running, a **Start** button runs `omarchy-broadcast start`. That starts the daemon through D-Bus activation and changes no setting. It needs the daemon's D-Bus activation file, which the AUR packages install, and a CLI that has `start`.

### The preview in the panel

The preview is a 16:9 frame that shows exactly what video apps receive from the virtual camera, refreshed live. It is black while the camera is idle or while an effect is loading.

In a row under the frame, never over the picture:

- **Grid**: a rule-of-thirds grid for framing. It is a choice of the open panel and is not stored.
- A "Preview:" label and a joined 15 | 30 fps choice for how often the preview refreshes: 15 (the default), or 30, which is smoother but uses more CPU. Its tooltip says the camera feed apps receive is not affected.
- **Hide preview**.

The preview is off by default and shown or hidden as you choose. The panel remembers the choice ([The live preview](#the-live-preview)). Showing it starts the camera. Nothing is drawn while the daemon is unavailable.

While the preview is hidden, or where it cannot run, the frame is a one-line strip, with a **Show preview** button where the preview can run. Where the frame shows no image it keeps its place and shows one line inside it: "Starting preview…" while the preview starts, or the reason it failed. The line in the strip is one of these:

- "Preview off": the preview is hidden, or is not running in another state (for example while the camera is starting or in error).
- "Camera off": the privacy switch is off.
- "Preview needs omarchy-broadcast 0.18 or newer": the running daemon predates the preview (interface revision below 5). The button, the grid and the rate selector are not shown.
- "Preview unavailable: ...": `XDG_RUNTIME_DIR` is unset, relative or holds characters the preview cannot use. The button, the grid and the rate selector are not shown.
- An error line, in the urgent colour: the preview process ended on its own (for example a CLI without the `preview` command, which says it needs 0.18 or newer), the stream reported an outage, or the daemon writes its frames to a different directory than this shell expects. In the wide layout the line is inside the frame, with Hide preview to put the preview away. After a failure, close and reopen the panel to retry.

A preview setting the shell could not store still applies for the session. The panel then says "Could not save the preview setting".

### The Effects tab

**The effect choices.** The background effect's choices are shown with the current one selected. Click a choice to change it.

- The plugin names no effect. The choices and their labels are the options of the daemon's `effect.background.mode` setting, a global setting of its settings schema (see the settings item below). They are whatever the installed modules offer, typically Off, Blur and Replace.
- A choice the daemon says cannot run here (no GPU for it, its models missing) is not drawn. The tab's "Not available now" line names it.
- A choice is written as that setting is, with `omarchy-broadcast settings set -- effect.background.mode <option>`.
- While the daemon greys the setting out (for example while the camera is off, or a module is loading), the choices are faded and the daemon's reason is shown under them.
- With no enabled module providing the background effect, the row is not shown, and the tab says "No effect module provides a background effect. Right click the bar icon to set up modules."
- Against a daemon below D-Bus interface revision 15, the background image the daemon holds, if any, is shown under the choices, read-only.

**The Background row** (interface revision 15 or later, while Replace is the choice shown: the row follows the choice, so it appears with the click). It sits under the choices and has:

- a small 16:9 thumbnail of the background in force. For a video it is the poster, with a small video glyph in the corner. A faint image glyph shows when there is none or it cannot be loaded;
- its name;
- two buttons, **Gallery…** and **Add…**.

The panel finds the poster in the last gallery list it read (Gallery… or the setup dialog). A video it has not seen listed yet, or whose poster the daemon has not made yet, shows the faint glyph with the video glyph, by its file name (`.mp4`, `.m4v`, `.mov`, `.mkv`, `.webm`). A poster is loaded only from the daemon's poster cache (a JPEG directly in a directory ending in `omarchy-broadcast/posters`).

When Replace is chosen and the daemon has no background set (or its file is gone), the daemon picks the first bundled background itself, a still image before a video, so Replace works at once. The row then shows that background, and Gallery… changes it.

*Gallery…* closes the panel and opens the shell's image picker (`omarchy-menu-images`) over the bundled backgrounds and your own, listed with `omarchy-broadcast media list background --json`.

- The image you pick is selected with `omarchy-broadcast effect replace --image <path>`, which also turns the Replace effect on.
- Before it opens the picker, the panel asks the picker tool for the rows it would show: `omarchy-menu-images --print-rows --show-labels <the bundled folder, then your pictures and videos folders>`. That prints them and exits before the picker opens. The panel opens the picker only when at least one row is a file in one of those folders.
- With nothing listed, the panel's failure line says "No backgrounds yet. Add one with Add…". With items listed but no row, it says "The picker cannot show any of the gallery's backgrounds. Add another with Add…". (The picker drops a row whose thumbnail it cannot make, for example a damaged picture.) Either way the picker is not run, because with no rows it falls back to the desktop theme's backgrounds, which must never be shown or chosen from here.
- A gallery of videos alone is shown as long as the picker has a row for them.
- Closing the picker without a choice changes nothing. A file the gallery did not list is refused with "That file is not in the gallery; nothing was changed". (The picker also shows files the daemon skips, such as unsupported formats and links.)

*Add…* closes the panel and opens the desktop file chooser (`omarchy-file-select`). It offers still images (PNG, JPEG, WebP), animated images (GIF, animated WebP, APNG) and videos (MP4, M4V, MOV, MKV, WebM).

- The file you choose is copied into your gallery (a still image into your pictures folder, a video into your videos folder), checked and selected with `omarchy-broadcast media import background <path> --select`.
- The daemon converts an animated image to a video as it imports it (the video lands in your videos folder). That takes `ffmpeg` and can take a few seconds. The panel opens again at once and says "Adding the background…" until the import ends, with both buttons faded. The import runs beside the panel's other commands, so the on/off switch never waits for it.
- Choosing nothing changes nothing. A chooser that cannot open, or an import the daemon refuses (for example an unsupported format or codec, or an animated image without `ffmpeg` installed), is reported on the panel's failure line with the daemon's reason. If you closed the panel while a long import ran, its failure is on that line the next time you open the panel.

Both buttons:

- When the picker or the chooser is done (a choice, a refusal, a failure or a cancel), the panel opens again on the same bar icon, so a failure line is seen where the button was pressed.
- Each button is faded and does nothing, with a note saying why, while its tool is not on `PATH`. Both are faded while one runs ("Waiting for the gallery…", "Waiting for the file chooser…", "Adding the background…"). One runs at a time.
- A picker, chooser or import still running after 610 seconds (just over `omarchy-file-select`'s own 600-second timeout) is stopped, and the failure line says so. For a picker or chooser nothing is changed. An import the daemon was still doing may still finish.
- Both tools come with Omarchy.

Your own backgrounds are kept in two folders, both named `omarchy-broadcast`: pictures in your Pictures folder, and videos in your Videos folder. The Videos folder also receives the video an animated image becomes when it is added. The daemon reports both folders (`video_dir` and `user_dir` of `media list background --json`), and the setup dialog's Backgrounds section shows them. Files you copy into either by hand appear the next time you open Gallery… or the dialog. The gallery never reads or changes the desktop's wallpapers.

Video backgrounds play on the GPU when the effect runs there. Where the effect runs on the CPU (system memory), a video the daemon cannot play there shows as a still (its poster). The setup dialog's Backgrounds section offers the command that converts it ([The setup dialog](#the-setup-dialog)).

**More**, a line under the effect settings. It is folded until opened (the panel's choice of the session) and shows only while the daemon offers one of the two rows below. It holds options you set once and leave.

- The **Battery saver** row (D-Bus interface revision 22 or later, while the daemon publishes `video.battery_saver`): its label, a **Mode** dropdown and a switch, in one row.
  - The switch is on while the daemon's mode is anything but Off.
  - Turning it on writes the last mode the switch turned off. The first time that is "On battery or power saver" with revision 23 or later, else On battery. The `batterySaverMode` setting remembers it, see [Configuration](#configuration). Turning it off writes Off (`omarchy-broadcast config set -- video.battery_saver <mode>`).
  - The Mode dropdown picks the mode the switch turns on: "On battery or power saver" (on battery, or while the power profile is power-saver; offered only with interface revision 23 or later, where it is the daemon's default), "On battery", "Follow the power profile" or "Always". With revision 22 the last three are offered.
  - While the switch is on, choosing a mode writes it to the daemon at once and remembers it. While the switch is off, choosing a mode only remembers it, for the next time the switch is turned on. While the saver is on, the dropdown shows the daemon's mode. While it is off, the dropdown shows the remembered one. A mode the daemon reports that the plugin cannot offer is shown read-only.
  - What is in force now (the part of the daemon's description that says it, "Now: on battery, the camera runs without the NVIDIA GPU") is the switch's tip.
  - The daemon applies the saver when the camera starts. When the mode or the power state changed since, the daemon's notice ("Applies when the camera restarts") shows under the row.
  - The switch and the dropdown are greyed out, with the daemon's reason under the row, while video processing is not set to automatic.
  - The switch is a keyboard stop, then the dropdown: Enter or Space opens its list, Up/Down or j/k move through it, Enter chooses and Escape closes it.
  - The panel reads the configuration while it is open for this row. The setup dialog also offers the mode, together with Off (see [The setup dialog](#the-setup-dialog)).
- The **Away image** row (D-Bus interface revision 17 or later): its label and a **Setup…** button. The button closes the panel and opens the setup dialog at the away image's row in its Daemon section, where the image is chosen (see [The setup dialog](#the-setup-dialog)). The panel does not show the away image. The image and its switch are set there.

**The effect settings.** Under them, the panel draws the daemon's other effect settings, from the same settings tree as the camera's ([Camera settings](#camera-settings)). The daemon publishes them as settings of scope `global`, the same for every camera and present with no camera. The plugin draws every one of them but the effect choice above.

- They are grouped under plain headings that stay open (no accordion, no Reset).
- What follows the effect choice comes first, directly under it: the blur strength, a slider, shows indented under the choice only while Blur is chosen.
- Then come, for example, "Video" (Noise removal and Enhance low-resolution camera, switches) and "Lighting" (Relighting, a switch). Under Relighting, indented and shown only while it is on, are the Light (a choice of Warm, Neutral or Cool) and the light's direction and the person's brightness (sliders).
- A heading that would only repeat its single master is left out, so a switch and its dependents read as one block.
- Which settings are drawn, hidden under a switch that is off, greyed, or listed under "Not available now (n)" at the foot of the tab follows the visibility rule in [Camera settings](#camera-settings). A setting lands in "Not available now" when, for example, its SDK feature is not installed, enhancement is offered for a camera that already captures at full resolution, or another module provides the stage.
- The plugin names none of them, so a stage that a new module publishes appears with no change to the plugin. There is one documented exception: the live zoom line of the Auto-frame group, below.
- They have the widgets, the tips, the debounce and the keyboard of the camera's settings. Each write is `omarchy-broadcast settings set -- <setting id> <value>` with no camera named, because the daemon ignores the camera for a global setting. Such a write is not dropped when the camera in use changes.
- There is no per-row or per-group reset here. Reset to defaults on the Camera tab resets the camera and never the effects. Reset an effect setting with `omarchy-broadcast settings reset --setting=<id>`.

**The Auto-frame group.** A read-only "Zoom 1.24×" line (1.00× is the full frame) sits under the group's rows, from the `stage_values` of the daemon's snapshot and state lines.

- It shows only while the camera is on and auto-frame is enabled, and only when the daemon reports a zoom. An older daemon reports none, so the line is absent.
- It is one line, never wrapped, so its height does not change while shown. Screen readers do not read it out as it changes.
- This is the one live value the plugin names (the group `auto_frame`, the stage `auto-frame` and the value `zoom`). It is the single exception to "the plugin names no settings". A later daemon that publishes the label and unit with each value would make it generic.

**Against an older daemon.** A daemon whose effects do not come from modules (D-Bus interface revision below 9, omarchy-broadcastd before 0.24.0) gets only "The daemon needs updating for effects (omarchy-broadcastd 0.24 or newer)." on the Effects tab. The rest of the panel works as before.

### The Camera tab

- **The camera dropdown** lists the cameras with the one in use selected. Choosing another selects it.
  - A camera that cannot be chosen is marked "(cannot be chosen)", with a note saying why.
  - The producer lists at most 12 cameras. A line says when more are connected.
  - The cameras' USB ids are in the Details view.
- **Camera health** (daemon interface revision 20 or later; nothing for another camera, or with an older daemon).
  - "Delivers 19.5 of 30 fps" in muted text when the camera delivers less than 95 % of its capture mode's rate.
  - The daemon's warnings about the camera, behind a caution sign.
  - Effect suggestions, each with the setting, the daemon's reason and a button ("Turn on") that writes it as `omarchy-broadcast settings set -- <setting id> <value>`. A suggestion shows only while its setting is offered, enabled and not already at that value. The first suggestion shows, and a "+N more" line opens the rest.
  - From revision 26 the health area also begins with the daemon's status lines for the camera in muted text, such as "Show Mode: desk view". "Shutter closed", which explains a black or away picture, is emphasised in bold behind a caution sign. These lines are for reading only.
  - The Camera tab's button shows a caution sign too, visible from the other tabs, while the camera has a warning or, during a session, a closed shutter. Its accessible name says which: "Camera, with a warning", "Camera, shutter closed", or "Camera, shutter closed, with a warning".
- **RECOMMENDED FOR THIS CAMERA** (revision 20, when the daemon has a recommended-settings row that would change something).
  - **Use recommended settings** on the title line runs `omarchy-broadcast recommended apply`. Nothing is applied without that click.
  - Under the title, the changes in one line ("2 changes: Sharpness, Anti-flicker") open the list as "Label: now → recommended".
  - The list goes when the daemon reports the camera again.
- **SETTINGS**: the camera's own settings, drawn from the schema the daemon publishes. See [Camera settings](#camera-settings).
  - They are grouped (Capture, Image, White balance, Exposure, Focus & zoom, Other). One group is open at a time, Image at first, which fits without a scroll bar. A group taller than the room scrolls with the panel's body.
  - Each setting is a switch (an integer of exactly two values too), a slider with its value and unit, a row of choices (up to 4 short options), a dropdown, or an action button.
  - A setting the daemon describes (interface revision 26) shows the description as a tip while the pointer or the keyboard cursor is on its row, not as text in the layout.
  - An integer setting for which the daemon gives a display offset or scale (revision 27) shows a signed value, such as "+0" or "+280 K", instead of the device's number. The slider keeps the device's range, and a change writes the device's number.
  - A setting that does not apply now is hidden, greyed or listed under "Not available now (n)" at the foot of the tab, as the daemon's reason says.
  - The section says which case holds: "Changes apply live." while the daemon has the camera open (state `starting` or `active`), otherwise "Not in use: changes apply when an app next uses the camera."
  - "Reset to defaults" is a quiet link at its foot. If the camera reports no settings, the section says so.
  - If the `omarchy-broadcast` CLI or the running daemon predates the settings (or the daemon's schema is newer than the plugin's), the tab shows the cameras and a hint saying which needs updating, and no settings.

### The Mic tab

The Mic tab is for the Omarchy Broadcast Mic: the microphone the daemon processes (D-Bus interface revision 13 or later).

- **The microphone's own switch.**
  - On runs `omarchy-broadcast mic on`: its service is enabled and started, and starts again at every login.
  - Off runs `omarchy-broadcast mic off`: if the Omarchy Broadcast Mic is the default microphone, the one before it becomes the default again, then the service is stopped and disabled.
  - The switch waits while its last command is still running and until the daemon's `mic` line shows the change (at most 3 seconds). It neither waits for nor holds the camera's on/off switch.
- **While the microphone is off**, one sentence says what it is ("A microphone with noise and echo removed. Turn it on, then choose “Omarchy Broadcast Mic” in your apps.") and nothing else.
- **While it is on**, one line gives its state, for example "Processing, 1 app recording, adds 12 ms", and the daemon's error text follows if there is one.
  - The state is Off, "On, not processed" while the sound passes through, Starting, Processing or Error.
  - Then the applications recording from it.
  - Then the delay its processing adds in milliseconds, which the daemon measures and studio voice makes noticeable. It shows only while the state is Processing or Starting.
  - The state and the module that runs each stage as the daemon words it (for example NVIDIA Maxine on the GPU, or DeepFilterNet on the CPU) are also in the Details view.
- **The microphone's settings** are drawn by the same renderer as the effect and camera settings, from the settings groups the daemon marks for the microphone (`surface` `mic`). They start with the microphone's own group:
  - the processing switch, "Noise and echo processing";
  - the input device, a dropdown of "System default" and the microphones the daemon lists;
  - "Hardware gain" (daemon interface revision 25), a slider in dB over the device's own range (which can start below zero). It shows only while the captured microphone is a USB device with one capture-volume control. It is the same control as that microphone's PipeWire source volume, so a change in one moves the other and the last writer wins;
  - "Use as default microphone", a switch that makes the Omarchy Broadcast Mic the system's default microphone and, turned off, puts back the one the daemon remembered (daemon interface revision 28 or later; a daemon before it offers two actions instead, "Use as default microphone" and "Use the previous default microphone").

  Then comes one group per stage the installed audio modules offer, such as Noise removal and Room echo removal (each a switch and a strength) and Studio voice (a switch labelled with the delay it adds, and a mic profile). Studio voice already removes noise and echo, so while it is on the daemon disables those two with its reason. The panel places them by the rule in [Camera settings](#camera-settings): a row that cannot be changed for now is greyed, with the reason as its tip.

  The plugin names none of these settings. What each one is called, its choices and when it is greyed are the daemon's. Each write is `omarchy-broadcast settings set -- <setting id> <value>`, with no camera named.
- **With no audio module installed**, the tab says "No microphone modules installed: the microphone passes the sound through unprocessed." under the daemon's own group. While the microphone is off, it says only "No microphone modules installed".
- **Against an older daemon or CLI.** A daemon that predates the microphone (D-Bus interface revision below 13) leaves the tab in the tab row, with only "The daemon needs updating for the microphone (omarchy-broadcastd 0.29 or newer)." A CLI that predates it gets "The omarchy-broadcast CLI needs updating for the microphone." The rest of the panel works as before. A daemon that publishes the microphone's settings without marking them for the microphone has them drawn on the Effects tab instead.

### The Details view

The (i) button in the header opens the Details view. It takes the place of the tabs (and of the preview's strip) until you press Back, and replaces the Status tab of earlier versions.

- It shows:
  - the state;
  - the camera in use and, when the daemon lists one, its USB id (`VID:PID`);
  - the output mode and the state of the PipeWire output (`off`, `ready`, `streaming`, ...);
  - the consumers, while the PipeWire output is on, by kind in a "Used by" row: Apps (applications holding the virtual camera device), PipeWire (links to the PipeWire camera node) and Preview (preview leases);
  - while the camera is active, the live figures: the frame rate, the p50 latency and the CPU and GPU load;
  - the microphone's state and, while it processes, the module that runs it;
  - the daemon's D-Bus interface revision ("Daemon API"; the daemon reports no version number of its own) and the plugin's version.
- A value not reported reads as a dash.
- **Copy** puts the same rows on the clipboard as text, one "label: value" a line under the product's name, for a bug report.

### Keyboard

Once the panel is open:

- Up/Down or j/k move the cursor over these stops, in order: the on/off switch, the (i) button, the preview's controls, the tab row, then the controls of the tab shown.
  - The preview's controls are the row under the frame (Hide preview, the grid and the rate row), or the strip's Show preview or Hide preview button where the preview is a strip. In the one-column layout they come after the tab row, where the preview is drawn.
  - **Effects:** the effect row (when it is shown); the Background row (Left/Right pick Gallery… or Add…, Enter runs it); each effect setting of the daemon's groups (the group headings are not stops, and greyed rows are stops, as in the camera's); the "Not available now" line (Enter or Space opens or folds it) and, while it is open, each entry's Setup…; then the More line (Enter or Space opens or folds it) and, while it is open, the Battery saver switch, its Mode dropdown (Enter opens its list) and the Away image row's Setup… button.
  - **Camera:** the camera dropdown; each suggestion's button shown and the line that opens or folds the rest; Use recommended settings and the line that opens or folds its changes (Enter or Space); then the settings groups (each group header is a stop and so is each row of the open group, greyed rows included: a greyed row takes no input, but its label, value and reason can be reached); the "Not available now" line with its Setup… buttons; and Reset to defaults.
  - **Mic:** the microphone's switch, then each of its settings and its "Not available now" line.
  - **Details view:** only Back and Copy are stops.
- On the tab row, Left/Right or h/l change the tab.
- On the rate and effect rows, Left/Right move between the choices. Arriving on a row lands on the current choice.
- On a slider, Left/Right move it by about a twentieth of its range.
- On a row of choices, Left/Right move a cursor over the choices, and Enter or Space chooses.
- On a group header, Enter or Space opens or closes the group, Right opens it and Left closes it.
- Enter opens a dropdown's list, flips a switch and runs an action.
- 1 to 3 show the Effects, Camera and Mic tab from anywhere in the panel (not while the Details view is open).
- Enter or Space activates, Tab switches to the neighbouring panel, Escape closes.

## Configuration

The plugin has six settings, set in the plugin's settings in the shell.

| Setting | Default | Meaning |
|---|---|---|
| `cliPath` | empty | The absolute path of the `omarchy-broadcast` binary. A leading `~/` means the home directory. A bare name such as `omarchy-broadcast` or a relative path is refused, because a command would then run relative to whatever directory the shell has. Empty: `omarchy-broadcast` on `PATH` (the lookup is in [INSTALL.md](INSTALL.md#set-the-cli-path-optional)) |
| `previewEnabled` | off | Whether the panel shows the live preview. The panel's Show preview and Hide preview buttons set it, and the next opening, and the next shell start, restores it. On: the preview runs whenever a panel is open and has a place for it, and starts the camera if it is not already running. Off (hidden): the preview never runs and the panel shows a one-line strip |
| `previewFps` | 15 | The preview's refresh rate, not the camera's. Also chosen in the row under the frame: 15 or 30. Any other value reads as 15 |
| `panelTab` | `effect` | The tab the panel shows: `effect` (labelled Effects), `camera` or `mic`. Any other value reads as `effect`, `status` of earlier versions included (the Status tab is now the header's Details view) |
| `narrowPanel` | off | "Narrow panel (one column)". On: the panel is one column 520 pixels wide, with the preview, when shown, under the tab row and none on the Mic tab. Off: the panel is 920 pixels wide with the preview beside the settings while it is shown, and the 520-pixel settings column alone while it is hidden. The panel never writes it |
| `batterySaverMode` | `auto` | The mode the panel's Battery saver switch turns on: `auto` (on battery, or while the power profile is power-saver), `on_battery`, `power_profile` or `always`. See below |

About `cliPath`: when the setup dialog opens without a bar icon attached (for example after a shell reload), it ignores `cliPath` and finds `omarchy-broadcast` on `PATH`. A CLI that is reachable only through `cliPath` therefore shows as not found there.

About `batterySaverMode`:

- `auto` reads as `on_battery` with a revision-22 daemon, which has no such mode.
- When the setting is unset, it reads as `auto` with revision 23 or later and as `on_battery` otherwise. Any other value reads as `on_battery`.
- The panel stores it when you choose a mode in the Battery saver Mode dropdown. It also stores it when the switch turns the saver off, as the mode that was in force, so the next time the switch is turned on it writes that mode again.

Which settings the panel stores:

- The panel stores `previewEnabled`, `previewFps`, `panelTab` and `batterySaverMode` when you change them in the panel, and only then. The plugin writes its settings on a user action, never to store a default or a read value.
- A change the shell cannot store (no bar-layout entry to write) holds until the shell restarts. For the preview settings the panel says so.
- The shell hands a plugin its settings again when they change. A hand-over that arrives before the plugin is complete is ignored, so a plugin instance made later (a monitor plugged in) cannot undo a choice the shell has not stored.

## How it talks to the daemon

- **One watch.** One `omarchy-broadcast watch --json` process serves every bar (every monitor). There is no polling: the daemon pushes each change, and the plugin is exactly as fresh as the stream.
  - The process starts when the first icon appears and stops when the last one goes away.
  - When it exits, it is started again after 1 s, doubling up to 30 s. The delay returns to 1 s only after a watch has run for 30 s, so a watch that dies right after its first line does not restart every second.
- **Commands.** These run as argument lists, never through a shell, and time out after 30 s:
  - `on`, `off`, `camera -- <id>` and `camera next`;
  - `settings set --camera=<id> -- <setting id> <value>`, `settings set -- <setting id> <value>` for a global (effect) setting, and `settings reset --camera=<id>`;
  - `recommended apply`;
  - from the setup dialog, `modules enable|disable <module id>`, `order set <stage>,<stage>,...`, `order reset` and `config set -- <key> <value>`.

  A new click is ignored while one runs. Setting writes and Reset to defaults instead wait behind it (see [Camera settings](#camera-settings)), and the queue never drops a command that is not a setting write.
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
- **Start.** The panel's **Start** button (shown only while the daemon is not running) runs `omarchy-broadcast start`, which D-Bus-activates the daemon without changing its state. The running watch then picks it up. It needs the D-Bus activation file and a CLI that has `start`.
- **Reads never start the daemon.** The commands `on`, `off`, `camera`, `settings set`, `settings reset`, `modules enable|disable`, `order set|reset` and `config set` start it through D-Bus activation if you installed that file (see "Service presence and activation" in [`docs/dbus-api.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/dbus-api.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast)). The plugin avoids sending them while the daemon is known to be down.

When the daemon stops or restarts, the stream says so and the icon shows "unavailable" until the daemon is back. No action is needed. If the watch itself ends, the panel names the exit status or signal and the retry delay.

## The live preview

The preview shows the frames the daemon writes for the virtual camera, so it is what apps get, effects included.

- **Shown or hidden.** The preview is hidden until you first show it. The choice is remembered across openings and shell restarts (the `previewEnabled` setting). A hidden preview never runs, whoever else uses the virtual camera, and never starts the camera: the panel draws a one-line strip instead of the frame. What the preview does depends only on your choice. (An earlier version also ran the preview while another application used the camera. It no longer does.)
- **It starts the camera.** The preview counts as a consumer of the virtual camera. With it shown, opening the panel starts the camera if needed. When the panel closes, or the preview is hidden, and no other application uses the camera, the camera stops again after the daemon's idle grace period.
- **One process.** The preview runs only while a panel is open and has a place to draw it. In the one-column layout the Mic tab has none, so the preview stops there and starts again on another tab. One `omarchy-broadcast preview --json --fps N` process serves every bar. It is started when a panel opens and stopped when the last one closes. If it ends on its own, the panel says why, and it stays stopped until the panel is closed and reopened.
- **The layout ignores the preview's state.** The panel's layout follows your choices (the "Narrow panel (one column)" setting, shown or hidden), never the preview's own state, and a failing preview shows its error inside the frame. Following the state would loop: an error would narrow the panel, the narrow Mic tab would then release the preview, which clears the error, the panel would widen and start the preview again, and it would fail again.
- **Safety.** The plugin never opens the camera device and never speaks D-Bus. The command runs as an argument list, with no shell, and `N` is only ever 15 or 30. Frames are read from one fixed file, `$XDG_RUNTIME_DIR/omarchy-broadcast/preview.jpg`. Every frame line the CLI prints is checked to name exactly that path, and any other is dropped, as is a frame that is not newer than the last. Each new frame is loaded under a new URL, so it is never served from a cache.
- **Trade-off.** The plugin drops a line over 8192 characters and stops the preview, but a line that never ends is buffered until it does, as for the watch stream. The producer is your own CLI, from your own installation, and it caps its lines.
- The stream format and the daemon side are described in [`docs/cli-json.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/cli-json.md) and [`docs/architecture.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/architecture.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast).

## Camera settings

Many webcams leave the factory, or another application, with image settings far from neutral: sharpness at its maximum draws halos around edges, and a high saturation makes skin look sunburnt. The SETTINGS section of the Camera tab sets the camera's own controls, which change the picture before any effect runs.

The plugin names none of them. It draws whatever the daemon publishes for the camera in use, from the `settings_group`, `settings_delta` and `settings_clear` lines of `omarchy-broadcast watch --json` (specified in [`docs/cli-json.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/cli-json.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast)). A camera therefore shows only the settings it has:

- Typically, in the groups Image, White balance, Exposure, Focus & zoom and Other: brightness, contrast, saturation, sharpness, white balance, exposure mode and time, gain, anti-flicker, "Keep 30 fps in low light", autofocus, focus and zoom.
- On a Logitech MX Brio or Brio, a Field of view of 90°, 78° or 65°.
- The MX Brio adds Show Mode, Exposure compensation, Vibrance and Temperature compensation.

A setting is greyed, with the daemon's reason, when the camera reports a value the daemon does not know.

- **One group at a time.** One group is open at a time (Image by default; the choice is kept only while the panel exists), which fits without a scroll bar. A group taller than the screen's room (for example Focus & zoom on an MX Brio on a small screen) scrolls with the panel's body, the one scroller, while the header, the tab row and the preview stay in place.
- **Widgets.** Each setting has a widget for its type: a switch, a slider with its value and unit, a row of choices (up to 4 short options) or else a dropdown, or an action button (for example to balance the white once). An integer that takes exactly two values (its minimum and its maximum) is drawn as a switch, on at the maximum, and written as the one of the two values.
- **The Capture group** (daemon interface revision 12 or later) holds the "Resolution and frame rate" row. This is the camera's capture mode, not the setup dialog's Output row "Output size and rate". The row is a dropdown whose list scrolls past eight rows. It offers "Automatic" or one of the modes the camera offers, labelled like "3840x2160 · 30 fps" (up to 15). A mode kept from before that the camera no longer offers is labelled "(gone)". The group is closed until opened (Image stays the open one). A daemon below revision 12 has no Capture group.
- **Where a setting is drawn.** A setting is shown only when it can be acted on. The daemon says why a setting is disabled in its `disabled_kind` (D-Bus interface revision 28; the `settings_group` and `settings_delta` lines of `watch --json`, and the CLI's JSON), and the panel places the setting by that:
  - `parent_off` (it depends on another setting that is off): not shown. It is revealed, indented under that setting, once the setting allows it, so a switch that turns a stage on shows its strength, direction and the like only while it is on.
  - `not_applicable`, `not_installed`, `needs_hardware`, `other_provider`, `unavailable` (nothing to set here, or something has to be installed, enabled or chosen first): not drawn in place. Each tab has one line at its foot, "Not available now (n)", which opens to the entries with the reason for each. A group another module provides (`other_provider`) is one entry, not one per setting. An entry has a Setup… button, which closes the panel and opens the setup dialog, except `not_applicable` (for example enhancement for a camera that already captures at full resolution), where there is nothing to set up.
  - `busy`, `device` (the camera is busy, or the device does not allow it for now): greyed in place, its label and value legible and its control faded. It takes no input.
  - A daemon before revision 28 sends no kind. A setting whose `enabled_when` rule does not hold is treated as `parent_off`, and every other disabled setting is greyed in place, as before.

  The plugin reads `enabled_when` and `disabled_kind` for this layout only. Whether a setting takes input stays the daemon's `enabled`, which the plugin never works out from a rule. Neither is used to decide a write.
- **Tips.** What a setting says beyond its label (the daemon's description and, while it is greyed, its reason) is a tip. A faint "?" after the label marks a row that has one, and the tip is drawn over the panel while the pointer or the keyboard cursor is on the row. It never changes the layout, so neither the row nor the card changes size. Screen readers hear a greyed row's label, its value and "Unavailable" with the reason. A group header says whether it is expanded or collapsed.
- **Writes.** A slider writes about 150 ms after the hand stops and once more on release, so a drag runs a few commands, not one per pixel. A switch, a choice and an action write at once. Each write is `omarchy-broadcast settings set --camera=<id> -- <setting id> <value>`.
  - While a command runs, later moves of the same setting replace each other, and only the last one is sent after it. At most one write per setting waits.
  - A write or reset still waiting when the active camera changes is dropped, never applied to the other camera.
  - While you hold a slider, news from the daemon does not move it.
- **Live or stored.** While the daemon has the camera open (state `starting` or `active`), a change applies at once, and the preview shows it. In any other state the daemon stores the value and applies it the next time the camera opens. The note at the top of the section says which case holds ("Changes apply live." or "Not in use: changes apply when an app next uses the camera.").
- **Reset to defaults**, a quiet link at the foot of the section, runs `omarchy-broadcast settings reset --camera=<id>`. It sets every setting of that camera back to its default, and the daemon forgets the stored values. It is the last stop of the Camera tab's keyboard order.
- **Scope.** The Camera tab draws only the settings of scope `camera`. The effects' settings, which are global, are on the Effects tab (see above), and this section's Reset to defaults never touches them.
- **Who keeps the values.** The daemon keeps the values, not the plugin: per camera, across restarts. It applies them each time it opens that camera, whichever client set them. The plugin stores nothing. The same settings are reachable with `omarchy-broadcast settings`.
- **Version.** Needs omarchy-broadcast and omarchy-broadcastd 0.22.0 or newer; see [Requirements](#requirements). Settings the daemon publishes that the plugin cannot draw safely (unknown type, bad id, out of range numbers, over the caps) are left out. The panel says so where a cap cuts the list.

## The setup dialog

A right click on the bar icon opens the setup dialog, a centred card over the screen. Its sections are listed on the left (five, or six from interface revision 15, with Backgrounds), and one is shown at a time. Everything shown comes from the daemon, through the CLI's JSON (`modules list --json`, `order show --json`, `config show --json`, `config files --json`, `media list background --json`, specified in [`docs/cli-json.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/cli-json.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast)).

- **Reads and writes.** The dialog reads when it opens, and again whenever the daemon reports a change of its configuration or its modules. After each write it reads the daemon's answer back rather than assuming it. While a write runs the title line says "Saving…". A refusal shows the daemon's reason under the title, until a later write goes through. One write runs at a time.
- **Keyboard.**
  - Keys 1 to 5 (or 6) show a section. Tab and Shift+Tab show the next and previous one.
  - The first arrow key shows the cursor. Up/Down (or j/k) walk the section list and then the shown section's controls. Right goes from the list into the section and Left back.
  - Enter or Space activates.
  - PageUp and PageDown scroll the section. In a section with nothing to act on (Diagnostics) that does not fit, Up and Down scroll it too.
  - Escape (or a click outside the card) closes it.
  - The mouse moves the same cursor, so one highlight is ever drawn.

### Modules

Each installed effect module is listed with its name, version, status (Available, Unavailable or Disabled) and the reason when it is not available, its kind (Camera effect or Microphone effect, from a daemon that reports it) and its stages. A switch enables or disables it (`omarchy-broadcast modules enable|disable <id>`). A change applies at the next camera start.

- A reason such as "Disabled after crashing the daemon twice in a row" shows for a module the daemon's crash ledger turned off. Enabling such a module forgives it.
- From a daemon of interface revision 14 the row also says what the daemon enforces:
  - A module refused by a declared conflict or a missing required module shows the daemon's reason ("Conflicts with <name> (<id>)", "Needs the module <id>") as its status.
  - An enabled module that can run shows one note, `<stage>: <reason>`, for each of its stages the daemon refuses (for example `matte: Cannot run together with noise removal`).
  - A module whose conflicts are not enforced (the debug override `modules.forced.<id>`) carries a line in the urgent colour, "Forced: conflicts are not enforced (debug override)", also read out with the row.
  - The dialog only shows the mark. The override is set with `omarchy-broadcast modules enable <id> --force` or `omarchy-broadcast config set modules.forced.<id> true`, and a plain `modules enable <id>` clears it.
- When there is no module, the section says "No effect modules installed", names the AUR packages that provide modules (`omarchy-broadcast-onnx-git`, or the `omarchy-broadcast-maxine-*-git` modules for NVIDIA GPUs) and says where a module's manifest goes: `~/.local/share/omarchy-broadcast/modules.d` for your own, `/usr/lib/omarchy-broadcast/modules.d` for packaged ones.

### Order

The stages are listed in the order they run, each with its slot. Move up and Move down buttons are offered only where the daemon says the swap with the neighbour is valid.

- With the cursor on a stage, Left/Right pick the button and Enter moves it, or Ctrl+Up/Down moves it at once.
- A move is written as the whole new order (`omarchy-broadcast order set ...`).
- Reset order goes back to the default (`order reset`).

### Backends

The section shows the backend profile (Quality or Battery) and, for each stage (the microphone's `mic-*` stages included), the module pinned to provide it, or Automatic.

- A short set of short names is a row of choices on a line of its own under the label. A pin with long module names is a dropdown showing the full name.
- The writes are `omarchy-broadcast config set -- modules.profile <profile>` and `config set -- modules.pin.<stage> <module id>`. The empty value is Automatic.

### Daemon

The section shows the daemon's configuration as its schema describes it, group by group (camera, output, loopback, lifecycle, effect, PipeWire), each row with its description. Every change is `omarchy-broadcast config set -- <key> <value>`.

- A row the daemon takes a change for is one of:
  - a switch (on or off);
  - a row of choices (up to 4 short options, as in the panel's settings);
  - a dropdown (Enter or Space opens its list, Up/Down or j/k walk it, Enter chooses);
  - a number with − and + buttons (Left/Right step it by about a twentieth of its range).
- A row that does not apply at once says so: "Applies at next camera start" or "Needs a daemon restart".
- The output size and rate ("Output size and rate", from interface revision 12) is a dropdown of the modes the daemon offers for the camera, with "(generated)" on a rate that frame generation makes. It applies at the next camera start.
- Other rows show their value and description, read-only: paths, lists, the default effects (which the panel's runtime choices override), and the output mode of a daemon below revision 12.

**The away image** (interface revision 17 or later) is one image, and the switches that can show it. They are all in the Daemon section in the daemon's own order, except that "Away image" (`effect.fallback_image`) is drawn directly under "When there is no camera picture" (`output.placeholder`), in its Output group. With a daemon that has no such row it stays in its own group.

- It is drawn as a picker: a 16:9 thumbnail of the image (a faint image glyph when none is set or it cannot be loaded), its name, and three buttons.
  - **Choose…** hides the dialog and opens the shell's image picker over the away gallery's bundled images and your own (`omarchy-broadcast media list away --json`). Your own away images are kept in the `away` folder inside your pictures folder `omarchy-broadcast`. With nothing listed the dialog says "No away images yet. Add one with Add…". With items listed but no row for the picker to show, it says "The picker cannot show any of the gallery's away images. Add another with Add…". In both cases it does not open the picker (the same rows check as the panel's Gallery…). The image you pick must be one the gallery listed, and is set with `omarchy-broadcast config set -- effect.fallback_image <path>`. Anything else is refused with "That file is not in the gallery; nothing was changed".
  - **Add…** hides the dialog and opens the desktop file chooser (still images only: PNG, JPEG or WebP, titled "Add an away image"). The file is copied into your away gallery, checked and set with `omarchy-broadcast media import away <path> --select`.
  - **Clear** sets no image (`config set -- effect.fallback_image ""`).
- The dialog shows again when the picker or chooser is done. A refusal or failure appears under its title.
- Left/Right walk the buttons on offer (a faded one is skipped), and Enter runs one.
- While no image is chosen and either switch is on the image, a note under the row says black is shown instead. With a daemon at interface revision 21 or later, "either switch" is `output.placeholder` on Away image, or privacy on with its mode Away image.
- "When there is no camera picture" (`output.placeholder`) is an ordinary row of choices, Black or Away image. With Away image, the image stands in for every frame without a camera picture (the camera switched off, starting, an error, a stall).
- "When an effect can't run" (`effect.on_failure`) keeps its own choices, its image choice using the same picture.
- A row a later configuration file sets, or one the daemon greys out, stays read-only with the reason.
- **From interface revision 21** the "When an effect can't run" dropdown is gone, replaced by two ordinary rows drawn in the daemon's order:
  - a switch, "Hide the camera when an effect can't run" (`effect.privacy`);
  - the choices "Show instead of the camera" (`effect.privacy_mode`): Black, Away image (offered once an away image is chosen, or while it is the choice in force) and Last frame.
  
  While the switch is off the daemon greys the choices out, and the dialog shows the one in force as read-only text with the daemon's reason (`Turn on "Hide the camera when an effect can't run" to change this`). Both rows are live, and a change is written to the new keys (`config set -- effect.privacy true`, `config set -- effect.privacy_mode freeze`). A daemon below revision 21 keeps the single `effect.on_failure` row, with its choices "Hide the camera: black", "Hide the camera: image" and "Show the camera" (written as `none`).

**The battery saver** (from interface revision 22): the Video processing group has the **Battery saver** mode (`video.battery_saver`), chosen from a dropdown with the daemon's own labels:

- Off;
- On battery or power saver (from interface revision 23, when the daemon offers it: on battery, or while the power profile is power-saver);
- On battery;
- Follow the power profile (the camera saves power while the power profile is power-saver);
- Always.

It applies when the camera next starts, and is greyed out with the daemon's reason while video processing is not automatic. The description ends with what is in force now ("Now: ..."). Any row for which the daemon has something to say about its present state (a `notice` field, such as "Applies when the camera restarts" on this row when the mode or the power state changed during a camera session) shows that text in muted type under the row.

### Backgrounds

This section needs interface revision 15 or later. It shows:

- how many backgrounds come bundled with omarchy-broadcast;
- a note saying that your own are kept in a folder ("Your own backgrounds are kept in these folders; files you copy there appear here:"), then the pictures folder's path and the videos folder's path, each on a line of its own (broken anywhere when long). With a daemon that reports only the pictures folder, the note says "Your own backgrounds are kept in this folder; files you copy there appear here:" over that one path. All of it is hidden while the daemon reports no folder;
- the backgrounds you added (the section reads the folder again each time the dialog is shown), each with a small thumbnail (a video's poster, with the video glyph), its name, its size (for a video also "video" and its length, for example "1920×1080, video, 0:12") and a Remove button. With none of your own, a note says how to add one.

Remove asks for a second press ("Confirm remove") before it runs `omarchy-broadcast media remove <path>`. Moving the cursor away (by key or by hovering another control) or changing section cancels it. Bundled backgrounds cannot be removed. The plugin reads at most the 500 backgrounds the daemon lists.

From D-Bus interface revision 19, under a video the daemon lists as not ready for system memory (`cpu_ready` false) and gives a command for (`convert_command`), the row shows:

- "Without an NVIDIA GPU this video shows as a still. To play it without one, convert it in a terminal; the copy lands in your videos folder:";
- the command in a monospace text you can select (selecting copies it, as in Diagnostics);
- a **Copy** button, which is a stop of its own for the keyboard, after the row's Remove. Enter copies it, and "Copied" appears beside it.

The plugin never runs the command. A command over 1536 characters or with a control character is not shown. An older daemon says nothing of this and nothing is shown.

Add backgrounds with Add… in the panel's Effects tab. While it imports a file, the section says "Adding the background…" and is read again when the import ends.

### Diagnostics

Diagnostics is read-only. It shows:

- the daemon's D-Bus interface revision, error text and warning (the warning row only when there is one; a long warning or error is wrapped under its label, in full);
- the configuration files in the order they are loaded, with their status and any error, and which one this dialog writes;
- the modules and stages that cannot run, with the reason;
- two commands to copy into a terminal, `omarchy-broadcast modules` and `journalctl --user -u omarchy-broadcastd`. Select one (or part of it) with the mouse and it is copied to the clipboard, and the section says what was copied. The dialog shows them and never runs them.

### Where the dialog's changes go

The daemon keeps the dialog's changes in a file of its own, `config.d/50-panel.toml` in its configuration directory (`~/.config/omarchy-broadcast/`). `config.toml` and every other file are never written. A setting that a later file (such as `config.d/90-local.toml`) also sets is shown greyed with "Overridden by <file>", and the daemon refuses to change it: edit or remove it in that file instead.

### Against an older daemon

Against a daemon below interface revision 9 (omarchy-broadcastd before 0.24.0), every section but Diagnostics says the daemon needs updating. At revision 9 (omarchy-broadcastd 0.24), Modules works. Order lists the stages with their Move up and Move down buttons greyed out and disabled, because the daemon's order line then carries no move information: no stage can be moved (Ctrl+Up/Down does nothing), and Reset order still works. Backends, Daemon and the configuration files say the daemon needs updating.

### How the shell opens it

The dialog is the plugin's overlay entry point (`kinds` `overlay`, `entryPoints.overlay` in `manifest.json`), so the shell routes the plugin's summon and toggle to it, the panel hotkey's included.

- A summon whose payload is `{"view":"setup"}` (which is what the right click sends) opens the dialog.
- Any other payload, and any toggle without one (the hotkey, the shell's positional panel toggle), opens and closes the bar panel on the focused monitor, as before.
- Because the shell reports the plugin open while the dialog is shown, the panel hotkey pressed then closes the dialog. Press it again to open the panel.

## Troubleshooting

Messages about the connection to the daemon, the CLI and version mismatches are in [INSTALL.md](INSTALL.md#troubleshooting). The messages below appear while the panel works.

| Message | Cause | What to do |
|---|---|---|
| Another app says the camera is busy, or shows no picture, while one app already uses "Omarchy Broadcast" | The virtual camera is a v4l2loopback device, which from version 0.14 lets one process stream at a time (one application can share it internally, as Chrome and Chromium do between tabs) | Close the first application. Or enable the daemon's PipeWire camera node (`[pipewire] enabled = true` in the daemon's configuration) for the applications that support PipeWire cameras: Chrome and Chromium need the `WebRtcPipeWireCamera` flag (`chrome://flags`), and OBS Studio has a "Video Capture Device (PipeWire)" source. Zoom and Discord keep using the virtual camera. Consumers of the PipeWire node that ask for different formats can stall it until all disconnect, so it is optional. See [`docs/setup/loopback.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/loopback.md#one-application-at-a-time) |
| The daemon refused the request | The daemon rejected `on`, `off`, the camera, a setting, or a write of the setup dialog (shown on the dialog's title line) | The text after the colon is the daemon's reason. See `omarchy-broadcast status` |
| No effect module provides a background effect | No enabled, available module provides the `background` stage | Open the setup dialog (right click), Modules: enable one, or see Diagnostics for why it cannot run |
| A setting in the setup dialog is greyed "Overridden by config.d/90-....toml" | A configuration file loaded after the dialog's own file sets it | Change or remove it in that file, then reload the daemon's configuration: `systemctl --user kill -s HUP omarchy-broadcastd` (the daemon's ReloadConfig does the same; no restart is needed) |
| An effect setting (relighting, enhancement, noise removal) is listed under "Not available now" as not installed | The SDK package the daemon uses lacks that feature or its models for your GPU | The daemon's reason is the text shown. See [`docs/setup/maxine.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/maxine.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast) |
| An effect on an Intel GPU or NPU says "not available" | The Intel GPU is not present in the running system (a laptop in its discrete-GPU-only mode), or the NPU's device `/dev/accel/accel0` is not accessible to your user (it needs the `render` group) | See "Troubleshooting" in [`docs/setup/onnx.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/onnx.md#8-troubleshooting) in the omarchy-broadcast repository |
| Noise removal is on, and the panel shows an error from the daemon | The daemon could not run noise removal. The camera streams without it | The error text says why. See `omarchy-broadcast status` |
| omarchy-broadcast preview exited / stopped / could not be started ... Reopen the panel to retry. | The preview process ended | Reopen the panel. If it repeats, run `omarchy-broadcast preview --json` in a terminal |
| A camera or effect setting is greyed | The daemon says it cannot be changed for now (the camera is busy, or a device does not allow it). The reason is in the row's tip, which shows while the pointer or the keyboard cursor is on the row | Follow the reason. This is not an error |
| A setting you expect is not there | It depends on another setting that is off (it appears under that setting once it is on), or the daemon says it cannot run here: it is listed under "Not available now (n)" at the foot of the tab, with the reason, and a Setup… button where something can be installed, enabled or chosen | Not an error. See [Camera settings](#camera-settings) |
| A camera setting jumps back after you let go, and an error shows | The daemon refused the value. The row shows what the camera has | The text after the colon is the daemon's reason |
| This camera reports no settings | The camera exposes no control the daemon publishes, or no camera is in use | Not an error |
| Showing N of M settings / choices / groups | The settings are capped (see [How it talks to the daemon](#how-it-talks-to-the-daemon)) | Not an error |
| Could not save the preview setting | The shell stored neither the preview's shown or hidden choice nor the rate | The choice holds for this session. Check the plugin's entry in the bar layout |
| Command failed with status N | Any other exit status | Run the same `omarchy-broadcast` command in a terminal |
| Showing N of M cameras / More cameras are connected; they are not shown | The camera list is capped | Not an error |
| A camera is marked "(cannot be chosen)" in the camera dropdown | Its id is the word `next`, which the CLI would read as "next camera" | It is not selectable unless its USB vendor and product id are unique |

## Testing the plugin

Run from the root of the checkout. None of the tests needs omarchy-broadcast, except the optional cases noted below. All commands are read-only with respect to your shell and your configuration. None starts or touches the running shell.

Run every check in one go:

```sh
tests/check-all.sh
```

Add `--omarchy-ref v4.5.0` to check against a given Omarchy release instead of the installed one. `tests/check-all.sh` runs all the checks below plus shellcheck on the test scripts. It does not run `--live`, nor the real-CLI case unless `OMARCHY_BROADCAST_CLI` is set. It stops at the first failure. With `--omarchy-ref REF` it uses a shallow clone of the Omarchy repository at that tag, in a scratch directory. It needs `shellcheck`, or `uvx` to run it from the `shellcheck-py` package.

The checks, one by one:

| Command | What it checks |
|---|---|
| `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_model.qml` | The logic in `Model.js` (see the list below) |
| `python3 -I tests/check-source.py` | Source invariants (see the list below) |
| `tests/lint.sh` | `qmllint` on every QML file, import errors fatal |
| `omarchy plugin validate .` | The shell's manifest validator |
| `tests/run-harness.sh` | The plugin inside a throwaway Quickshell with a fake CLI (see below). Needs `quickshell` |
| `OMARCHY_BROADCAST_CLI=/absolute/path/to/omarchy-broadcast tests/run-harness.sh` | The same, plus one resolver case against a real omarchy-broadcast binary (found, never run) |
| `OMARCHY_BROADCAST_CLI=/absolute/path/to/omarchy-broadcast tests/run-harness.sh --live` | The plugin against a real daemon and CLI |

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

- **Starting the daemon.** The plugin starts the daemon only through the CLI's D-Bus activation (`omarchy-broadcast start`, the panel's Start button). It never runs `systemctl`: the `systemctl --user enable --now omarchy-broadcastd` line in the panel and in the docs is text for the user to copy.
- **External dependency.** The plugin is a client and needs the external daemon, `omarchy-broadcastd` and its `omarchy-broadcast` CLI, which come from the AUR (`omarchy-broadcast-bin`, prebuilt, or `omarchy-broadcast-git`, built from source; see [INSTALL.md](INSTALL.md#install-the-daemon)). Nothing in this repository installs it.
- **External commands the plugin runs**, each as an argument list (the only shell is the two constant `sh -c` scripts described below):
  - `omarchy-broadcast`, the CLI: `watch --json` for the state, `preview --json` for the live preview, `start` for the Start button, and the commands that change the daemon's state, such as `on`, `off`, `settings set`, `modules`, `order`, `config` and `media`;
  - `omarchy-menu-images` and `omarchy-file-select`, Omarchy's image picker and file chooser, for the background and away image galleries;
  - `sh -c`, with a constant script, to find the CLI and those two tools on `PATH`.

  The plugin runs no package manager and no `systemctl`, and needs no root.
- **Scan triggers that are not plugin behaviour.** Some marketplace scan triggers are not plugin behaviour.
  - The `yay -S` line (package manager) and the `sudo`/pacman mentions (privilege) in [INSTALL.md](INSTALL.md) are the daemon's install instructions, for you to run in a terminal. The plugin does not run them.
  - The `git clone` in `tests/check-all.sh` (a remote build) is test-only: it fetches an Omarchy release for `--omarchy-ref` and is never loaded by the shell.
  - The plugin itself never runs a package manager, `sudo`, `git` or `systemctl`.
- **`tests/` is test-only.** It contains `pgrep`/`kill` calls (confined to processes the harness started, counted by a marker path inside its own work directory), `sh -c`, and an executable fake CLI. None of it is loaded by the shell.
- **The two `sh -c`** in the plugin code are the CLI resolver and the lookup of the gallery's two tools (`omarchy-menu-images`, `omarchy-file-select`) on `PATH`. Both scripts are constants. Nothing is interpolated into them (the lookup gets the two tool names as positional arguments). Every other command is an argument list. A path the image picker or the file chooser returns is passed as one argument, and the picker's only when it is exactly a path the daemon's gallery list just named.
- **Identity and licence.** The plugin id is `br.com.dias.omarchy-broadcast`, which `omarchy plugin validate` accepts. It stays fixed: renaming it would break existing installs. The licence files are at the root of this repository, `LICENSE-MIT` and `LICENSE-APACHE` (`MIT OR Apache-2.0`, as in `manifest.json`). The plugin directory itself holds none.

## Versioning

The plugin's version is the `version` field of `manifest.json`. It started at 0.16.0, the omarchy-broadcast release it was split from, and is independent of the omarchy-broadcast version from then on. The two are released separately, and matching numbers carry no meaning.

Compatibility is set by the interface, not by version numbers. The plugin needs an `omarchy-broadcast` CLI whose `watch --json` output is schema version (`v`) 1, specified in [`docs/cli-json.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/cli-json.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast). A change of the schema version requires a new release of the plugin. The daemon's D-Bus interface revision each feature needs:

| Revision | Feature | CLI needs |
|---|---|---|
| 5 or later | The preview | `preview --json` |
| 7 or later | The camera settings, with settings schema 1 | |
| 9 or later | The effects on the Effects tab, and the setup dialog's Modules and Order | |
| 10 or later | The dialog's Backends, Daemon and configuration files | the `config` command |
| 13 or later | The microphone | the `mic` command |
| 15 or later | The background gallery | the `media` command |
| 28 or later | The placement of disabled settings and the default-microphone switch | |

See [Requirements](#requirements) for the rest.

## Licence

Licensed under either of the [MIT License](LICENSE-MIT) or the [Apache License, Version 2.0](LICENSE-APACHE), at your option.

## Limitations

- English only. There is no translation catalogue.
- The virtual camera serves one application at a time (see the first row of [Troubleshooting](#troubleshooting)).
- The `active` state uses the theme's accent colour, so it is distinguished from `idle` by the icon shape and colour together.
- Camera names are shown as the daemon reports them, after removing markup characters such as `&`, `<` and `>`.
- The input device dropdown offers a microphone only by a PipeWire node name of at most 128 characters, the longest option value the CLI's JSON carries. A longer name arrives shortened and is not offered (choose it with `omarchy-broadcast mic device <node name>`), and while it is the one in use the dropdown shows no choice selected.
