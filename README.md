# Omarchy Broadcast bar widget

`br.com.dias.omarchy-broadcast` is a bar widget for the Omarchy shell (Quickshell/QML) that controls omarchy-broadcast, a virtual camera daemon with background effects, noise removal, relighting and enhancement of low-resolution cameras. It shows the state of the virtual camera in the bar, turns it on and off, selects the camera and the video effect, adjusts the effect's settings (blur strength, noise removal, enhancement of a low-resolution camera, relighting), adjusts the camera's own settings (image, white balance, exposure, focus and zoom, whatever the camera offers), shows live figures while it runs, and can show a live preview of what video apps receive.

It is a client of `omarchy-broadcastd`, the daemon of the omarchy-broadcast project, and does not include it: it reads the state from the stream of `omarchy-broadcast watch --json` and sends commands through the `omarchy-broadcast` command-line client. For the preview it also runs `omarchy-broadcast preview --json`. It does not speak D-Bus itself and never opens a camera device. The stream formats are specified in `docs/cli-json.md` in the omarchy-broadcast repository; the widget requires its schema version (`v`) 1.

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

- Left (or middle) click opens and closes the panel, as the shell's panel hotkey does.
- Right click turns the camera on or off. It does nothing while an earlier on/off, camera, effect or noise removal command is still running or waiting; camera setting writes do not hold it, and the on/off command goes ahead of any that are waiting. While the daemon is unavailable it opens the panel instead, so that a persisted `off` is never flipped without being seen and a stopped daemon is never started by a click.
- For screen readers the icon carries the tooltip's state as its name and what each click does as its description.
- The tooltip gives the state, and while running the camera name, the number of consumers, the effect when one is on (background blurred or background replaced) and noise removal when it is on (worded as a setting, "noise removal on", because the daemon may be unable to run it; with an effect, for example "background blurred, noise removal on"). An error text is appended when there is one. When unavailable it names the cause.

The panel is 520 pixels wide and as tall as its content, so at the normal size nothing scrolls; it scrolls only on a screen too short for it (and the camera settings then scroll by themselves inside the Camera tab, see [Camera settings](#camera-settings)). From the top:

- the state, the on/off switch and the daemon's error text, if any;
- the last failed command, if any;
- the preview, a fixed 16:9 area showing exactly what video apps receive from the virtual camera (so black while the camera is idle or while an effect is loading), refreshed live, with one row under it holding the Preview switch and the rate selector (15 fps, the default, or 30 fps, which is smoother and closer to what apps see but uses more CPU). The area is not shown while the daemon is unavailable. Where it shows no image it keeps its place and shows one line inside it ("Starting preview…" while the preview starts):
  - "Camera idle; turn on Preview to start it": the camera is on but idle and the Preview switch is off;
  - "Camera off": the privacy switch is off;
  - "Preview off": the preview is not running in any other state (for example while the camera is starting or in error) and the Preview switch is off;
  - "Preview needs omarchy-broadcast 0.18 or newer": the running daemon predates the preview (interface revision below 5); the switch and the rate selector are not shown;
  - "Preview unavailable: ...": `XDG_RUNTIME_DIR` is unset, relative or holds characters the preview cannot use; the switch and the rate selector are not shown;
  - an error line, in the urgent colour: the preview process ended on its own (for example a CLI without the `preview` command, which says it needs 0.18 or newer), the stream reported an outage, or the daemon writes its frames to a different directory than this shell expects. After a failure, close and reopen the panel to retry.
  A preview setting the shell could not store still applies for the session; the panel then says "Could not save the preview setting";
- three tabs, Effect, Camera and Status, of which one is shown (the tab row is not shown while the daemon is unavailable). The panel remembers the last one chosen (the `panelTab` setting, see [Configuration](#configuration)) and opens on Effect the first time;
- when the daemon is unavailable, the reason and, where it helps, a command to copy. The plugin shows these commands and never runs them.

The Effect tab:

- BACKGROUND, the video effect: None, Blur or Replace, with the current one selected (click a choice to change it). While blurring, the blur strength is shown; while replacing, the background image path. Replace can be chosen only once the daemon has a background image; until then it is faded, the panel shows "Replace needs an image:" with the command `omarchy-broadcast effect replace --image PATH` to run in a terminal, and the Replace tooltip names the other way, `background_image` under `[effect]` in the daemon's configuration. The background image is shown, not edited, here (a path is not something the panel can set). The blur strength is a slider below, from a daemon that publishes it (see the next item). If the `omarchy-broadcast` CLI predates video effects, every choice is faded and the panel says the CLI needs updating; if the CLI knows effects but the running daemon does not (its interface revision is below 2, as when the daemon was not restarted after an upgrade), every choice is faded and the panel says the daemon needs updating;
- under it, the daemon's other effect settings, drawn generically from the same settings tree as the camera's ([Camera settings](#camera-settings)): a daemon with D-Bus interface revision 8 publishes them as settings of scope `global`, the same for every camera and present with no camera, and the plugin draws every one of them that is not the effect choice (which keeps the row above, because it also carries the loading and privacy status the schema cannot express). They are grouped under plain headings that stay open (no accordion, no title, no Reset): "Background effect" (the blur strength, a slider, greyed with "Choose Blur to change this" unless Blur is chosen), "Video" (Noise removal and Enhance low-resolution camera, switches) and "Lighting" (Relighting, a switch; the Light, a choice of Warm, Neutral or Cool; the light's direction and the person's brightness, sliders; the last three greyed with "Turn on relighting to change this" while it is off). The plugin names none of them but the effect choice, so a stage that a later daemon publishes appears with no change to the plugin. A setting whose SDK feature is not installed is greyed with "Not installed", and enhancement is greyed with the daemon's reason ("The camera already captures at full resolution") when the camera in use needs none. They have the widgets, the greyed reasons, the debounce and the keyboard of the camera's settings, and each write is `omarchy-broadcast settings set -- <setting id> <value>` with no camera named, because the daemon ignores the camera for a global setting; such a write is not dropped when the camera in use changes. There is no per-row or per-group reset here: Reset to defaults on the Camera tab resets the camera and never the effects (reset an effect setting with `omarchy-broadcast settings reset --setting=<id>`).
- against a daemon that does not publish global settings (interface revision below 8) the Effect tab is as before, one row at a time: the read-only blur strength under the effect choice while Blur is chosen, and the separate Noise removal switch below. Each of those two rows gives way only to the setting that replaces it, so a daemon that publishes one and not the other shows the other as before. Noise removal is not a fourth effect: it is a stage that applies with any effect (it runs before blur or replace, or alone with None), so it is switched on and off on its own and is not one of the choices. It hides nothing, so if the daemon cannot run it the camera keeps streaming without it and the daemon's error text says why. That separate switch is not shown when the `omarchy-broadcast` CLI or the running daemon does not report noise removal (both predate it; the daemon's interface revision is below 4), rather than showing an off switch that nobody reported.

The Camera tab:

- CAMERAS, the list of cameras (click a row to select it) and a Next camera button when there are two or more. The producer lists at most 12 cameras; a row says when more are connected;
- SETTINGS: the camera's own settings, drawn from the schema the daemon publishes, with "Reset to defaults" on the title line; see [Camera settings](#camera-settings). They are grouped (Image, White balance, Exposure, Focus & zoom, Other) and one group is open at a time, Image at first, so the panel fits without a scroll bar. Each setting is a switch, a slider with its value and unit, a row of choices (up to 4 short options) or a dropdown, or an action button. A setting that does not apply now is greyed with the daemon's reason under it (for example "Set exposure to manual to change this"). Under the title the section says which case holds: "Changes apply live." while the daemon has the camera open (state `starting` or `active`), otherwise "Not in use: changes apply when an app next uses the camera." If the camera reports none, the section says so. If the `omarchy-broadcast` CLI or the running daemon predates the settings (or the daemon's schema is newer than the plugin's), the tab shows the cameras and a hint saying which needs updating, and no settings.

The Status tab:

- the state, the camera in use, the number of consumers and, while the daemon's PipeWire output is on, the same number by kind in a "Used by" row (Apps: applications holding the virtual camera device; PipeWire: links to the PipeWire camera node; Preview: preview leases), the output mode, the state of the PipeWire output (`off`, `ready`, `streaming`, ...) and the daemon's D-Bus interface revision ("D-Bus API") (the daemon reports no version number of its own); a value not reported reads as a dash;
- LIVE, while active: the frame rate, the p50 latency and the CPU and GPU load; a figure the daemon has not reported yet reads as a dash.

Keyboard, once the panel is open: Up/Down or j/k move the cursor over the on/off switch, the Preview switch and the rate row (both only where the preview works), the tab row, then the controls of the tab shown: on Effect the effect row (unless the CLI or the daemon predates effects), the Noise removal switch (when it is shown, which is only when the daemon's own settings below do not hold it), then each effect setting of the daemon's groups (the group headings are not stops, and greyed rows are stops, as in the camera's); on Camera the cameras, Next camera, Reset to defaults, then the settings groups: each group header is a stop and so is each row of the open group, greyed rows included (a greyed row takes no input, but its label, value and reason can be reached); Status has none (the first press only shows the cursor). On the tab row Left/Right or h/l change the tab; on the rate and effect rows they move between the choices (arriving on a row lands on the current choice); on a slider they move it by about a twentieth of its range; on a row of choices they move a cursor over the choices and Enter or Space chooses; on a group header Enter or Space opens or closes the group, Right opens it and Left closes it. Enter opens a dropdown's list, flips a switch and runs an action. 1, 2 and 3 show the Effect, Camera and Status tab from anywhere in the panel. Enter or Space activates, Tab switches to the neighbouring panel, Escape closes.

## Requirements

- `omarchy-broadcastd` and the `omarchy-broadcast` CLI, installed as described in `docs/setup/daemon.md` in the omarchy-broadcast repository. The widget shows "unavailable" until the daemon runs; it works without D-Bus activation, but with it `on`, `off`, camera selection, effect selection and the Noise removal switch start a stopped daemon (see the unavailable behaviour below).
- A CLI whose `watch --json` prints schema version (`v`) 1. A line with a higher version is reported as "Unsupported omarchy-broadcast version"; any other value is refused as malformed.
- For the video effects, a running daemon with interface revision 2 or later; for noise removal, interface revision 4 or later (the CLI then reports a `denoise` field). With an older daemon the widget still shows the state and switches the camera; it fades the effect choices or hides the Noise removal switch.
- For the preview, omarchy-broadcast 0.18.0 or newer: a CLI with the `preview` command and a running daemon with interface revision 5 or later. With an older CLI or daemon the panel says so, and the rest of the plugin works as before.
- For the effect settings (blur strength, noise removal, enhancement, relighting) on the Effect tab, omarchy-broadcast and omarchy-broadcastd 0.23.0 or newer: a running daemon with D-Bus interface revision 8 or later, and a CLI that prints the `scope` of each setting. With an older daemon, or a CLI that does not print `scope`, the Effect tab shows the effect choice, the read-only strength and the Noise removal switch as in earlier versions of this plugin (the effect choice needs revision 2 and noise removal revision 4, as above). The effect settings come from the same lines as the camera's, so they are subject to the settings schema (1) too.
- For the camera settings, omarchy-broadcast and omarchy-broadcastd 0.22.0 or newer: a CLI whose snapshot reports `settings_schema` and that has the `settings` command, a running daemon with D-Bus interface revision 7 or later, and a settings schema (the `schema` of the `settings_group` lines) of 1, the one this plugin reads. With an older CLI or daemon the Camera tab shows the cameras and a hint saying which one needs updating ("The daemon needs updating for camera settings (omarchy-broadcastd 0.22 or newer)."); with a newer schema the hint is "Update the plugin to show these camera settings." There is no fallback to the sliders of earlier versions of this plugin, which the settings replaced. The rest of the plugin works as before.
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

Four settings.

`cliPath` is the absolute path of the `omarchy-broadcast` binary. A leading `~/` means the home directory. A bare name such as `omarchy-broadcast` or a relative path is refused, because a command would then run relative to whatever directory the shell has. It is empty by default.

`previewEnabled` (default off) is the panel's Preview switch. On: the preview runs whenever a panel is open, and starts the camera if it is not already running. Off: the preview runs only while another application already uses the virtual camera. `previewFps` (default 15) is the Preview rate, 15 or 30; any other value reads as 15. `panelTab` (default `effect`) is the tab the panel shows: `effect`, `camera` or `status`; any other value reads as `effect`. All three are stored when you change them in the panel, and only then: the plugin writes its settings on a user action, never to store a default or a read value. A change the shell cannot store (no bar-layout entry to write) holds until the shell restarts; for the preview settings the panel says so.

The binary is resolved in this order:

1. `cliPath`, if set. If it is set but unusable, the widget says so and does not fall back.
2. `omarchy-broadcast` on the shell's `PATH`. This is normally the case for the install locations of omarchy-broadcast: `/usr/bin` for its Arch package, `~/.local/bin` for its `scripts/install-user.sh`, `~/.cargo/bin` for `cargo install`; Omarchy's default shell environment appends `~/.local/bin` to `PATH`. The shell must have the directory on its own `PATH`; if it does not, set `cliPath`.
3. A development build at `<plugin real directory>/../../../target/release/omarchy-broadcast`, where the real directory is the plugin directory with symlinks resolved. This layout dates from when the plugin lived inside the omarchy-broadcast repository (at `clients/omarchy-bar/` there), next to its `target/` directory. In a checkout of this repository the path points two levels above the root of the checkout, outside it, so the fallback normally finds nothing; to use a development build of omarchy-broadcast, set `cliPath` to that build's `target/release/omarchy-broadcast`.

A binary found on `PATH` wins over the development-build fallback; set `cliPath` to choose. Resolution runs when a widget appears, once after each failed start of the CLI, and when the setting changes, never on a timer. If nothing was found and you install the CLI afterwards, reload the shell or change the setting.

## How it talks to the daemon

- One `omarchy-broadcast watch --json` process serves every bar (every monitor). There is no polling: the daemon pushes each change, and the widget is exactly as fresh as the stream.
- The process starts when the first widget appears and stops when the last one goes away.
- When it exits, it is started again after 1 s, doubling up to 30 s. The delay returns to 1 s only after a watch has run for 30 s, so a watch that dies right after its first line does not restart every second.
- Commands (`on`, `off`, `camera -- <id>`, `camera next`, `effect none|blur|replace`, `denoise on|off`, `settings set --camera=<id> -- <setting id> <value>`, `settings set -- <setting id> <value>` for a global (effect) setting, `settings reset --camera=<id>`) run as argument lists, never through a shell, and time out after 30 s. A new click is ignored while one runs; setting writes and Reset to defaults instead wait behind it (see [Camera settings](#camera-settings)), and the queue never drops a command that is not a setting write. The camera id is passed as one argument after `--`. The effect is always one of the three fixed words and noise removal one of `on` and `off`. A setting id is passed back only when it matches the daemon's id grammar (lowercase words joined by dots, at most 48 bytes); a prototype key such as `__proto__` is refused. A value is `on` or `off` for a switch, a decimal integer within the range the daemon reports, on its step, for a slider, one of the option ids the daemon published for a choice, and `true` for an action. Nothing else the daemon reports is passed back on the command line.
- Text from the daemon (camera names, errors, the background image path) is shown as plain text, stripped of markup, control, bidi and invisible formatting characters (the zero-width joiner and non-joiner stay, so emoji sequences and Persian or Arabic words display correctly), and shortened. The background image path is shown inside a left-to-right Unicode isolate, so right-to-left text in a file name cannot reorder the row or reverse the path. An effect name the plugin does not know selects no choice and is reported as such; a blur strength outside 0 to 1 reads as a dash. The producer already limits a line to 4096 bytes and the camera list to 12; the plugin drops a line over 8192 characters and restarts the watch. Of the camera settings it reads at most 16 groups, 16 settings in a group, 16 options in a setting and 64 rows in all, and the panel says "Showing N of M groups", "settings" or "choices" when it shows fewer than the daemon reports. It keeps a setting only when its id passes the check above, its type is known, and every number in it is an integer, its minimum is not above its maximum, its step is at least 1 and its default and value lie within the range. Unlike camera names, settings text keeps `&` ("Focus & zoom"): every place it is drawn is plain text, so nothing there reads it as markup.
- Reads never start the daemon. The commands `on`, `off`, `camera`, `effect`, `denoise`, `settings set` and `settings reset` start it through D-Bus activation if you installed that file (see "Service presence and activation" in `docs/dbus-api.md` in the omarchy-broadcast repository); the widget avoids sending them while the daemon is known to be down.

When the daemon stops or restarts, the stream says so and the icon shows "unavailable" until the daemon is back; no action is needed. If the watch itself ends, the panel names the exit status or signal and the retry delay.

## The live preview

The preview shows the frames the daemon writes for the virtual camera, so it is what apps get, effects included.

- Opening the panel never starts the camera by itself. If the stream is already active for another application, the preview shows at once.
- The Preview switch is what starts the camera: the preview counts as a consumer of the virtual camera. With the switch on, opening the panel starts the camera if needed. When the panel closes, or the switch is turned off, and no other application uses the camera, the camera stops again after the daemon's idle grace period.
- The preview runs only while a panel is open. One `omarchy-broadcast preview --json --fps N` process serves every bar; it is started when a panel opens and stopped when the last one closes. If it ends on its own, the panel says why and it stays stopped until the panel is closed and reopened.
- The plugin never opens the camera device and never speaks D-Bus. The command runs as an argument list, with no shell, and `N` is only ever 15 or 30. Frames are read from one fixed file, `$XDG_RUNTIME_DIR/omarchy-broadcast/preview.jpg`; every frame line the CLI prints is checked to name exactly that path, and any other is dropped, as is a frame that is not newer than the last. Each new frame is loaded under a new URL, so it is never served from a cache.
- The stream format and the daemon side are described in `docs/cli-json.md` and `docs/adr/0019-live-preview.md` in the omarchy-broadcast repository.
- Trade-off: the plugin drops a line over 8192 characters and stops the preview, but a line that never ends is buffered until it does, as for the watch stream. The producer is your own CLI, from your own installation, and it caps its lines.

## Camera settings

Many webcams leave the factory, or another application, with image settings far from neutral: sharpness at its maximum draws halos around edges, a high saturation makes skin look sunburnt. The SETTINGS section of the Camera tab sets the camera's own controls, which change the picture before any effect runs. The plugin names none of them: it draws whatever the daemon publishes for the camera in use, from the `settings_group`, `settings_delta` and `settings_clear` lines of `omarchy-broadcast watch --json` (specified in `docs/cli-json.md` in the omarchy-broadcast repository). A camera therefore shows only the settings it has: typically, in the groups Image, White balance, Exposure, Focus & zoom and Other, brightness, contrast, saturation, sharpness, white balance, exposure mode and time, gain, anti-flicker, "Keep 30 fps in low light", autofocus, focus, zoom, and on a Logitech MX Brio or Brio a Field of view of 90°, 78° or 65°.

- One group is open at a time (Image by default; the choice is kept only while the panel exists), so the tab never grows past its tallest group and fits without a scroll bar. Only on a screen too short for it do the groups scroll, inside the Camera tab and under the title line, with a scroll bar and a fade at the bottom while there is more.
- Each setting has a widget for its type: a switch, a slider with its value and unit, a row of choices (up to 4 short options) or else a dropdown, or an action button (for example to balance the white once).
- A setting that does not apply now stays in its place, greyed, with the reason the daemon gives under it ("Set exposure to manual to change this"); it takes no input. Screen readers hear its label, its value and "Unavailable" with the reason; a group header says whether it is expanded or collapsed.
- A slider writes about 150 ms after the hand stops and once more on release, so a drag runs a few commands, not one per pixel; a switch, a choice and an action write at once. Each write is `omarchy-broadcast settings set --camera=<id> -- <setting id> <value>`. While a command runs, later moves of the same setting replace each other and only the last one is sent after it, and at most one write per setting waits. A write or reset still waiting when the active camera changes is dropped, never applied to the other camera. While you hold a slider, news from the daemon does not move it.
- While the daemon has the camera open (state `starting` or `active`), a change applies at once, and the preview above shows it. In any other state the daemon stores the value and applies it the next time the camera opens. The note under the title says which case holds ("Changes apply live." or "Not in use: changes apply when an app next uses the camera.").
- Reset to defaults, on the SETTINGS title line, runs `omarchy-broadcast settings reset --camera=<id>`: it sets every setting of that camera back to its default and the daemon forgets the stored values. It is a stop of the keyboard order before the groups.
- The camera tab draws only the settings of scope `camera`; the effects' settings, which are global, are on the Effect tab (see above), and this section's Reset to defaults never touches them.
- The daemon, not the plugin, keeps the values: per camera, across restarts, and it applies them each time it opens that camera, whichever client set them. The plugin stores nothing; the same settings are reachable with `omarchy-broadcast settings`.
- Needs omarchy-broadcast and omarchy-broadcastd 0.22.0 or newer; see [Requirements](#requirements). Settings the daemon publishes that the plugin cannot draw safely (unknown type, bad id, out of range numbers, over the caps) are left out; the panel says so where a cap cuts the list.

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
| An effect setting (relighting, enhancement, noise removal) is greyed "Not installed" | the SDK package the daemon uses lacks that feature or its models for your GPU | the daemon's reason is the text shown; see `docs/setup/maxine.md` in the omarchy-broadcast repository |
| The Effect tab has only the effect choice, the read-only strength and Noise removal | the running daemon (or the CLI) predates the effect settings (interface revision below 8) | update omarchy-broadcast and omarchy-broadcastd to 0.23.0 or newer; restart the daemon if it is already updated: `systemctl --user restart omarchy-broadcastd` |
| Noise removal switch missing | the `omarchy-broadcast` CLI or the running omarchy-broadcastd predates noise removal (the CLI prints no `denoise` field) | update both; restart the daemon if it is already updated: `systemctl --user restart omarchy-broadcastd` |
| Noise removal is on, and the panel shows an error from the daemon | the daemon could not run noise removal; the camera streams without it | the error text says why; see `omarchy-broadcast status` |
| Preview needs omarchy-broadcast 0.18 or newer | the running daemon reports an interface revision below 5 | update omarchy-broadcastd and the CLI; restart the daemon if it is already updated: `systemctl --user restart omarchy-broadcastd` |
| This omarchy-broadcast has no preview command | the CLI predates the preview | update the CLI |
| omarchy-broadcast preview exited / stopped / could not be started ... Reopen the panel to retry. | the preview process ended | reopen the panel; if it repeats, run `omarchy-broadcast preview --json` in a terminal |
| omarchy-broadcastd writes its preview elsewhere than this shell expects | the daemon and the shell have different `XDG_RUNTIME_DIR` values | start both from the same session environment |
| Preview unavailable: ... | `XDG_RUNTIME_DIR` is unset, relative or unusable in the shell's environment | fix the shell's environment |
| The omarchy-broadcast CLI needs updating for camera settings | the `omarchy-broadcast` CLI predates them (its snapshot has no `settings_schema`) | update the CLI and the daemon to 0.22.0 or newer |
| The daemon needs updating for camera settings | the CLI knows them, but the running omarchy-broadcastd reports an interface revision below 7 | update omarchy-broadcastd to 0.22.0 or newer, or restart it if it is already updated: `systemctl --user restart omarchy-broadcastd` |
| Update the plugin to show these camera settings | the daemon publishes a newer settings schema than this plugin reads (schema 1) | update the plugin |
| A camera setting is greyed, with a reason under it | the daemon says the setting does not apply now (for example "Set exposure to manual to change this") | follow the reason; not an error |
| A camera setting jumps back after you let go, and an error shows | the daemon refused the value; the row shows what the camera has | the text after the colon is the daemon's reason |
| This camera reports no settings | the camera exposes no control the daemon publishes, or no camera is in use | not an error |
| Showing N of M settings / choices / groups | the settings are capped (see [How it talks to the daemon](#how-it-talks-to-the-daemon)) | not an error |
| Could not save the preview setting | the shell stored neither the Preview switch nor the rate | the choice holds for this session; check the plugin's entry in the bar layout |
| D-Bus failure | the CLI could not reach the session bus | check `DBUS_SESSION_BUS_ADDRESS` in the shell's environment |
| Command failed with status N | any other exit status | run the same `omarchy-broadcast` command in a terminal |
| Showing N of M cameras / More cameras are connected; they are not shown | the camera list is capped | not an error |
| Next camera missing | fewer than two cameras listed | connect a second camera |
| A camera row is not selectable (its id is the word `next`) | the CLI would read the id as Next camera | not selectable unless its USB vendor and product id are unique |

## Testing the plugin

Run from the root of the checkout. None of the tests needs omarchy-broadcast, except the optional cases noted below. All commands are read-only with respect to your shell and your configuration; none starts or touches the running shell.

```sh
# Unit tests of the logic (Model.js): reducer, caps, tooltips, argument lists, effects, noise removal, the camera settings (parsing the settings lines of the watch stream against a fixture of real CLI lines, the reducer for full sets and deltas, caps, the capability rule, validation of ids and values, snapping, argument lists, the command queue), the preview (run rule, argument list, frame lines, placeholder texts, settings), the panel tabs (stored value, keyboard stops) and the Status rows, the click actions, path resolution
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
    -input br.com.dias.omarchy-broadcast/tests/tst_model.qml

# Source invariants (plain text everywhere, no shell strings, no polling timer, manifest id, effect, noise removal and camera setting whitelists, the setting-id check, the command queue and slider debounce, the preview's single process, argument list and fixed frame path, the click mapping, the tab setting and the panel's size)
python3 -I br.com.dias.omarchy-broadcast/tests/check-source.py

# qmllint on every QML file, import errors fatal
br.com.dias.omarchy-broadcast/tests/lint.sh

# The shell's manifest validator
omarchy plugin validate br.com.dias.omarchy-broadcast

# The plugin inside a throwaway Quickshell with a fake CLI, including its fake preview stream and a scratch `XDG_RUNTIME_DIR` (needs quickshell)
br.com.dias.omarchy-broadcast/tests/run-harness.sh

# The same, plus one resolver case against a real omarchy-broadcast binary (found, never run)
OMARCHY_BROADCAST_CLI=/absolute/path/to/omarchy-broadcast br.com.dias.omarchy-broadcast/tests/run-harness.sh

# Against a real daemon and CLI
OMARCHY_BROADCAST_CLI=/absolute/path/to/omarchy-broadcast br.com.dias.omarchy-broadcast/tests/run-harness.sh --live
```

- `qmltestrunner` and `qmllint` come from Qt 6 (`/usr/lib/qt6/bin`, package `qt6-declarative` on Arch). `lint.sh` and `run-harness.sh` also need the Omarchy shell modules, by default in `/usr/share/omarchy/shell`; set `OMARCHY_SHELL` to use another copy, such as the `shell/` directory of a checkout of the Omarchy repository.
- `run-harness.sh` builds its own directory (under `$TMPDIR`, or `--work DIR` if that is empty or an earlier harness directory), runs a separate offscreen Quickshell with the fake CLI `tests/fake-omarchy-broadcast` (which also streams a Logitech MX Brio's camera settings and answers `settings set` and `settings reset`, prints a preview stream and writes real JPEG frames into the harness's own runtime directory, never yours), and removes nothing outside it. It prints `ALL OK` and exits 0 on success. `--screens DIR` keeps the screenshots. Its text-layout checks need a font installed (Omarchy's default is JetBrains Mono Nerd Font).
- The CLI resolver cases run against scratch directory trees the harness builds, so the harness does not depend on where this checkout lives. With `OMARCHY_BROADCAST_CLI` set to the absolute path of a real `omarchy-broadcast` binary, one more case checks that the resolver finds it through a symlinked plugin directory; the resolver only prints the path, and nothing executes the binary in this mode. Without the variable that case prints a `SKIP` line and does not count as a failure.
- `--live` takes the CLI from `OMARCHY_BROADCAST_CLI` and the daemon from `OMARCHY_BROADCASTD` (default: `omarchy-broadcastd` in the same directory as the CLI), and refuses to run without them. It starts its own `omarchy-broadcastd` with a scratch configuration and state, opens the virtual camera for a few seconds with `gst-launch-1.0` and stops everything again. It refuses to run if `br.com.dias.OmarchyBroadcast` already has an owner on the session bus, and it needs the "Omarchy Broadcast" v4l2loopback device (`docs/setup/loopback.md` in the omarchy-broadcast repository).
- Continuous integration (`.github/workflows/ci.yml`) runs all of the above except `--live` and the real-CLI case in an Arch Linux container, against the shell modules of a pinned Omarchy release.

## Remove

```sh
omarchy plugin disable br.com.dias.omarchy-broadcast
omarchy plugin remove br.com.dias.omarchy-broadcast
```

If you linked the plugin, deleting the link has the same effect: `rm ~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast`. If a placement is left in the bar layout, remove it with the shell's bar commands (`omarchy bar --help`) and reload the shell.

The plugin starts no service of its own and writes no files, except that the shell stores a preview setting or the tab you choose in the panel in the plugin's bar-layout entry. The processes it owns are the `watch` child and, while a panel is open, the `preview` child; both end with the shell (they exit when their output pipe closes or on SIGTERM). Removing the plugin does not touch the daemon; to stop and uninstall that, see "Stop, disable, uninstall" in `docs/setup/daemon.md` in the omarchy-broadcast repository.

## Notes for maintainers and marketplace review

- `tests/` is test-only. It contains `pgrep`/`kill` calls (confined to processes the harness started, counted by a marker path inside its own work directory), `sh -c`, and an executable fake CLI. None of it is loaded by the shell.
- The one `sh -c` in the plugin code is the CLI resolver. The plugin directory is passed to it as a positional argument, never interpolated. Every other command is an argument list.
- The development-build fallback executes a binary from outside the plugin directory (`../../../target/release/omarchy-broadcast`, from the plugin's real directory). It is used only when `cliPath` is empty and `omarchy-broadcast` is not on `PATH`. In a checkout of this repository that path lies outside the checkout and normally holds nothing (see [Configuration](#configuration)).
- The plugin id uses the `br.com.dias.` namespace like the daemon's D-Bus name; check it against the marketplace naming rule before publishing. The licence files are at the root of this repository, `LICENSE-MIT` and `LICENSE-APACHE` (`MIT OR Apache-2.0`, as in `manifest.json`); the plugin directory itself holds none.

## Versioning

The plugin's version is the `version` field of `br.com.dias.omarchy-broadcast/manifest.json`. It started at 0.16.0, the omarchy-broadcast release it was split from, and is independent of the omarchy-broadcast version from then on: the two are released separately, and matching numbers carry no meaning.

Compatibility is set by the interface, not by version numbers. The plugin needs an `omarchy-broadcast` CLI whose `watch --json` output is schema version (`v`) 1, specified in `docs/cli-json.md` in the omarchy-broadcast repository; the video effects need a daemon interface revision of 2 or later, noise removal one of 4 or later, the preview one of 5 or later, with a CLI that has `preview --json`, the camera settings one of 7 or later and settings schema 1, and the effect settings on the Effect tab one of 8 or later, with a CLI whose snapshot reports `settings_schema` (see [Requirements](#requirements)). A change of the schema version requires a new release of the plugin.

## Licence

Licensed under either of the [MIT License](LICENSE-MIT) or the [Apache License, Version 2.0](LICENSE-APACHE), at your option.

## Limitations

- English only; there is no translation catalogue.
- The `active` state uses the theme's accent colour, so it is distinguished from `idle` by the icon shape and colour together.
- Camera names are shown as the daemon reports them (after removing markup characters such as `&`, `<` and `>`).
