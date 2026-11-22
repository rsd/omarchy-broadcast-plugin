# The bar icon and the panel

What the plugin shows in the bar and in its panel, the plugin's settings, the live preview and the camera settings. Back to the [README](../README.md). The right click's dialog has a page of its own: [The setup dialog](setup-dialog.md).

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
- **Right click** opens the setup dialog ([The setup dialog](setup-dialog.md)), whatever the daemon's state. When the daemon is unavailable or too old, the dialog says so, and its Diagnostics section still shows what it can.

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
- **When the daemon is unavailable**, the reason and, where it helps, a command to copy. The command is text for you to run in a terminal: the plugin never runs `systemctl`. When the daemon is not running, a **Start** button runs the command below. That starts the daemon through D-Bus activation and changes no setting. It needs the daemon's D-Bus activation file, which the daemon's packages install, and a CLI that has `start`.

  ```sh
  omarchy-broadcast start
  ```

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
- A choice is written as that setting is, with:

  ```sh
  omarchy-broadcast settings set -- effect.background.mode <option>
  ```

- While the daemon greys the setting out (for example while the camera is off, or a module is loading), the choices are faded and the daemon's reason is shown under them.
- With no enabled module providing the background effect, the row is not shown, and the tab says "No effect module provides a background effect. Right click the bar icon to set up modules."
- Against a daemon below D-Bus interface revision 15, the background image the daemon holds, if any, is shown under the choices, read-only.

**The Background row** (interface revision 15 or later, while Replace is the choice shown: the row follows the choice, so it appears with the click). It sits under the choices and has:

- a small 16:9 thumbnail of the background in force. For a video it is the poster, with a small video glyph in the corner. A faint image glyph shows when there is none or it cannot be loaded;
- its name;
- two buttons, **Gallery…** and **Add…**.

The panel finds the poster in the last gallery list it read (Gallery… or the setup dialog). A video it has not seen listed yet, or whose poster the daemon has not made yet, shows the faint glyph with the video glyph, by its file name (`.mp4`, `.m4v`, `.mov`, `.mkv`, `.webm`). A poster is loaded only from the daemon's poster cache (a JPEG directly in a directory ending in `omarchy-broadcast/posters`).

When Replace is chosen and the daemon has no background set (or its file is gone), the daemon picks the first bundled background itself, a still image before a video, so Replace works at once. The row then shows that background, and Gallery… changes it.

*Gallery…* closes the panel and opens the shell's image picker (`omarchy-menu-images`) over the bundled backgrounds and your own, listed with:

```sh
omarchy-broadcast media list background --json
```

- The image you pick is selected with the command below, which also turns the Replace effect on.

  ```sh
  omarchy-broadcast effect replace --image <path>
  ```

- Before it opens the picker, the panel asks the picker tool for the rows it would show, with the command below (the folders are the bundled folder, then your pictures and videos folders). That prints them and exits before the picker opens. The panel opens the picker only when at least one row is a file in one of those folders.

  ```sh
  omarchy-menu-images --print-rows --show-labels <folders>
  ```

- With nothing listed, the panel's failure line says "No backgrounds yet. Add one with Add…". With items listed but no row, it says "The picker cannot show any of the gallery's backgrounds. Add another with Add…". (The picker drops a row whose thumbnail it cannot make, for example a damaged picture.) Either way the picker is not run, because with no rows it falls back to the desktop theme's backgrounds, which must never be shown or chosen from here.
- A gallery of videos alone is shown as long as the picker has a row for them.
- Closing the picker without a choice changes nothing. A file the gallery did not list is refused with "That file is not in the gallery; nothing was changed". (The picker also shows files the daemon skips, such as unsupported formats and links.)

*Add…* closes the panel and opens the desktop file chooser (`omarchy-file-select`). It offers still images (PNG, JPEG, WebP), animated images (GIF, animated WebP, APNG) and videos (MP4, M4V, MOV, MKV, WebM).

- The file you choose is copied into your gallery (a still image into your pictures folder, a video into your videos folder), checked and selected with:

  ```sh
  omarchy-broadcast media import background <path> --select
  ```

- The daemon converts an animated image to a video as it imports it (the video lands in your videos folder). That takes `ffmpeg` and can take a few seconds. The panel opens again at once and says "Adding the background…" until the import ends, with both buttons faded. The import runs beside the panel's other commands, so the on/off switch never waits for it.
- Choosing nothing changes nothing. A chooser that cannot open, or an import the daemon refuses (for example an unsupported format or codec, or an animated image without `ffmpeg` installed), is reported on the panel's failure line with the daemon's reason. If you closed the panel while a long import ran, its failure is on that line the next time you open the panel.

Both buttons:

- When the picker or the chooser is done (a choice, a refusal, a failure or a cancel), the panel opens again on the same bar icon, so a failure line is seen where the button was pressed.
- Each button is faded and does nothing, with a note saying why, while its tool is not on `PATH`. Both are faded while one runs ("Waiting for the gallery…", "Waiting for the file chooser…", "Adding the background…"). One runs at a time.
- A picker, chooser or import still running after 610 seconds (just over `omarchy-file-select`'s own 600-second timeout) is stopped, and the failure line says so. For a picker or chooser nothing is changed. An import the daemon was still doing may still finish.
- Both tools come with Omarchy.

Your own backgrounds are kept in two folders, both named `omarchy-broadcast`: pictures in your Pictures folder, and videos in your Videos folder. The Videos folder also receives the video an animated image becomes when it is added. The daemon reports both folders (`video_dir` and `user_dir` of the `media list background --json` output), and the setup dialog's Backgrounds section shows them. Files you copy into either by hand appear the next time you open Gallery… or the dialog. The gallery never reads or changes the desktop's wallpapers.

Video backgrounds play on the GPU when the effect runs there. Where the effect runs on the CPU (system memory), a video the daemon cannot play there shows as a still (its poster). The setup dialog's Backgrounds section offers the command that converts it ([The setup dialog](setup-dialog.md#backgrounds)).

**More**, a line under the effect settings. It is folded until opened (the panel's choice of the session) and shows only while the daemon offers one of the two rows below. It holds options you set once and leave.

- The **Battery saver** row (D-Bus interface revision 22 or later, while the daemon publishes `video.battery_saver`): its label, a **Mode** dropdown and a switch, in one row.
  - The switch is on while the daemon's mode is anything but Off.
  - Turning it on writes the last mode the switch turned off. The first time that is "On battery or power saver" with revision 23 or later, else On battery. The `batterySaverMode` setting remembers it, see [Configuration](#configuration). Turning it off writes Off. The write is:

    ```sh
    omarchy-broadcast config set -- video.battery_saver <mode>
    ```

  - The Mode dropdown picks the mode the switch turns on: "On battery or power saver" (on battery, or while the power profile is power-saver; offered only with interface revision 23 or later, where it is the daemon's default), "On battery", "Follow the power profile" or "Always". With revision 22 the last three are offered.
  - While the switch is on, choosing a mode writes it to the daemon at once and remembers it. While the switch is off, choosing a mode only remembers it, for the next time the switch is turned on. While the saver is on, the dropdown shows the daemon's mode. While it is off, the dropdown shows the remembered one. A mode the daemon reports that the plugin cannot offer is shown read-only.
  - What is in force now (the part of the daemon's description that says it, "Now: on battery, the camera runs without the NVIDIA GPU") is the switch's tip.
  - The daemon applies the saver when the camera starts. When the mode or the power state changed since, the daemon's notice ("Applies when the camera restarts") shows under the row.
  - The switch and the dropdown are greyed out, with the daemon's reason under the row, while video processing is not set to automatic.
  - The switch is a keyboard stop, then the dropdown: Enter or Space opens its list, Up/Down or j/k move through it, Enter chooses and Escape closes it.
  - The panel reads the configuration while it is open for this row. The setup dialog also offers the mode, together with Off (see [The setup dialog](setup-dialog.md#daemon)).
- The **Away image** row (D-Bus interface revision 17 or later): its label and a **Setup…** button. The button closes the panel and opens the setup dialog at the away image's row in its Daemon section, where the image is chosen (see [The setup dialog](setup-dialog.md#daemon)). The panel does not show the away image. The image and its switch are set there.

**The effect settings.** Under them, the panel draws the daemon's other effect settings, from the same settings tree as the camera's ([Camera settings](#camera-settings)). The daemon publishes them as settings of scope `global`, the same for every camera and present with no camera. The plugin draws every one of them but the effect choice above.

- They are grouped under plain headings that stay open (no accordion, no Reset).
- What follows the effect choice comes first, directly under it: the blur strength, a slider, shows indented under the choice only while Blur is chosen.
- Then come, for example, "Video" (Noise removal and Enhance low-resolution camera, switches) and "Lighting" (Relighting, a switch). Under Relighting, indented and shown only while it is on, are the Light (a choice of Warm, Neutral or Cool) and the light's direction and the person's brightness (sliders).
- A heading that would only repeat its single master is left out, so a switch and its dependents read as one block.
- Which settings are drawn, hidden under a switch that is off, greyed, or listed under "Not available now (n)" at the foot of the tab follows the visibility rule in [Camera settings](#camera-settings). A setting lands in "Not available now" when, for example, its SDK feature is not installed, enhancement is offered for a camera that already captures at full resolution, or another module provides the stage.
- The plugin names none of them, so a stage that a new module publishes appears with no change to the plugin. There is one documented exception: the live zoom line of the Auto-frame group, below.
- They have the widgets, the tips, the debounce and the keyboard of the camera's settings. Each write is the command below, with no camera named, because the daemon ignores the camera for a global setting. Such a write is not dropped when the camera in use changes.

  ```sh
  omarchy-broadcast settings set -- <setting id> <value>
  ```

- There is no per-row or per-group reset here. Reset to defaults on the Camera tab resets the camera and never the effects. Reset an effect setting with:

  ```sh
  omarchy-broadcast settings reset --setting=<id>
  ```

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
  - Effect suggestions, each with the setting, the daemon's reason and a button ("Turn on") that writes it with the command below. A suggestion shows only while its setting is offered, enabled and not already at that value. The first suggestion shows, and a "+N more" line opens the rest.

    ```sh
    omarchy-broadcast settings set -- <setting id> <value>
    ```

  - From revision 26 the health area also begins with the daemon's status lines for the camera in muted text, such as "Show Mode: desk view". "Shutter closed", which explains a black or away picture, is emphasised in bold behind a caution sign. These lines are for reading only.
  - The Camera tab's button shows a caution sign too, visible from the other tabs, while the camera has a warning or, during a session, a closed shutter. Its accessible name says which: "Camera, with a warning", "Camera, shutter closed", or "Camera, shutter closed, with a warning".
- **RECOMMENDED FOR THIS CAMERA** (revision 20, when the daemon has a recommended-settings row that would change something).
  - **Use recommended settings** on the title line runs the command below. Nothing is applied without that click.

    ```sh
    omarchy-broadcast recommended apply
    ```

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
  - On runs the first command below: its service is enabled and started, and starts again at every login.
  - Off runs the second: if the Omarchy Broadcast Mic is the default microphone, the one before it becomes the default again, then the service is stopped and disabled.

    ```sh
    omarchy-broadcast mic on
    omarchy-broadcast mic off
    ```

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

  The plugin names none of these settings. What each one is called, its choices and when it is greyed are the daemon's. Each write is the command below, with no camera named.

  ```sh
  omarchy-broadcast settings set -- <setting id> <value>
  ```

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
| `cliPath` | empty | The absolute path of the `omarchy-broadcast` binary. A leading `~/` means the home directory. A bare name such as `omarchy-broadcast` or a relative path is refused, because a command would then run relative to whatever directory the shell has. Empty: `omarchy-broadcast` on `PATH` (the lookup is under "Finding the CLI" in [How it talks to the daemon](development.md#how-it-talks-to-the-daemon)) |
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

## The live preview

The preview shows the frames the daemon writes for the virtual camera, so it is what apps get, effects included.

- **Shown or hidden.** The preview is hidden until you first show it. The choice is remembered across openings and shell restarts (the `previewEnabled` setting). A hidden preview never runs, whoever else uses the virtual camera, and never starts the camera: the panel draws a one-line strip instead of the frame. What the preview does depends only on your choice. (An earlier version also ran the preview while another application used the camera. It no longer does.)
- **It starts the camera.** The preview counts as a consumer of the virtual camera. With it shown, opening the panel starts the camera if needed. When the panel closes, or the preview is hidden, and no other application uses the camera, the camera stops again after the daemon's idle grace period.
- **One process.** The preview runs only while a panel is open and has a place to draw it. In the one-column layout the Mic tab has none, so the preview stops there and starts again on another tab. One process, the command below, serves every bar. It is started when a panel opens and stopped when the last one closes. If it ends on its own, the panel says why, and it stays stopped until the panel is closed and reopened.

  ```sh
  omarchy-broadcast preview --json --fps N
  ```

- **The layout ignores the preview's state.** The panel's layout follows your choices (the "Narrow panel (one column)" setting, shown or hidden), never the preview's own state, and a failing preview shows its error inside the frame. Following the state would loop: an error would narrow the panel, the narrow Mic tab would then release the preview, which clears the error, the panel would widen and start the preview again, and it would fail again.
- **Safety.** The plugin never opens the camera device and never speaks D-Bus. The command runs as an argument list, with no shell, and `N` is only ever 15 or 30. Frames are read from one fixed file, `$XDG_RUNTIME_DIR/omarchy-broadcast/preview.jpg`. Every frame line the CLI prints is checked to name exactly that path, and any other is dropped, as is a frame that is not newer than the last. Each new frame is loaded under a new URL, so it is never served from a cache.
- **Trade-off.** The plugin drops a line over 8192 characters and stops the preview, but a line that never ends is buffered until it does, as for the watch stream. The producer is your own CLI, from your own installation, and it caps its lines.
- The stream format and the daemon side are described in [`docs/cli-json.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/cli-json.md) and [`docs/architecture.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/architecture.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast).

## Camera settings

Many webcams leave the factory, or another application, with image settings far from neutral: sharpness at its maximum draws halos around edges, and a high saturation makes skin look sunburnt. The SETTINGS section of the Camera tab sets the camera's own controls, which change the picture before any effect runs.

The plugin names none of them. It draws whatever the daemon publishes for the camera in use, from the `settings_group`, `settings_delta` and `settings_clear` lines of the CLI's `watch --json` stream (specified in [`docs/cli-json.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/cli-json.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast)). A camera therefore shows only the settings it has:

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
- **Writes.** A slider writes about 150 ms after the hand stops and once more on release, so a drag runs a few commands, not one per pixel. A switch, a choice and an action write at once. Each write is:

  ```sh
  omarchy-broadcast settings set --camera=<id> -- <setting id> <value>
  ```

  - While a command runs, later moves of the same setting replace each other, and only the last one is sent after it. At most one write per setting waits.
  - A write or reset still waiting when the active camera changes is dropped, never applied to the other camera.
  - While you hold a slider, news from the daemon does not move it.
- **Live or stored.** While the daemon has the camera open (state `starting` or `active`), a change applies at once, and the preview shows it. In any other state the daemon stores the value and applies it the next time the camera opens. The note at the top of the section says which case holds ("Changes apply live." or "Not in use: changes apply when an app next uses the camera.").
- **Reset to defaults**, a quiet link at the foot of the section, runs the command below. It sets every setting of that camera back to its default, and the daemon forgets the stored values. It is the last stop of the Camera tab's keyboard order.

  ```sh
  omarchy-broadcast settings reset --camera=<id>
  ```

- **Scope.** The Camera tab draws only the settings of scope `camera`. The effects' settings, which are global, are on the Effects tab (see above), and this section's Reset to defaults never touches them.
- **Who keeps the values.** The daemon keeps the values, not the plugin: per camera, across restarts. It applies them each time it opens that camera, whichever client set them. The plugin stores nothing. The same settings are reachable from a terminal with:

  ```sh
  omarchy-broadcast settings
  ```

- **Version.** Needs omarchy-broadcast and omarchy-broadcastd 0.22.0 or newer; see [Versioning](development.md#versioning). Settings the daemon publishes that the plugin cannot draw safely (unknown type, bad id, out of range numbers, over the caps) are left out. The panel says so where a cap cuts the list.
