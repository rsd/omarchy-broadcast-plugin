# The setup dialog

A right click on the bar icon opens the setup dialog, a centred card over the screen. Back to the [README](../README.md). The panel the left click opens is described in [The bar icon and the panel](panel.md).

Its sections are listed on the left (five, or six from interface revision 15, with Backgrounds), and one is shown at a time. Everything shown comes from the daemon, through the CLI's JSON (`modules list --json`, `order show --json`, `config show --json`, `config files --json`, `media list background --json`, specified in [`docs/cli-json.md`](https://github.com/rsd/omarchy-broadcast/blob/main/docs/cli-json.md) in the [omarchy-broadcast repository](https://github.com/rsd/omarchy-broadcast)).

- **Reads and writes.** The dialog reads when it opens, and again whenever the daemon reports a change of its configuration or its modules. After each write it reads the daemon's answer back rather than assuming it. While a write runs the title line says "Saving…". A refusal shows the daemon's reason under the title, until a later write goes through. One write runs at a time.
- **Keyboard.**
  - Keys 1 to 5 (or 6) show a section. Tab and Shift+Tab show the next and previous one.
  - The first arrow key shows the cursor. Up/Down (or j/k) walk the section list and then the shown section's controls. Right goes from the list into the section and Left back.
  - Enter or Space activates.
  - PageUp and PageDown scroll the section. In a section with nothing to act on (Diagnostics) that does not fit, Up and Down scroll it too.
  - Escape (or a click outside the card) closes it.
  - The mouse moves the same cursor, so one highlight is ever drawn.

## Modules

Each installed effect module is listed with its name, version, status (Available, Unavailable or Disabled) and the reason when it is not available, its kind (Camera effect or Microphone effect, from a daemon that reports it) and its stages. A switch enables or disables it, with one of the commands below. A change applies at the next camera start.

```sh
omarchy-broadcast modules enable <id>
omarchy-broadcast modules disable <id>
```

- A reason such as "Disabled after crashing the daemon twice in a row" shows for a module the daemon's crash ledger turned off. Enabling such a module forgives it.
- From a daemon of interface revision 14 the row also says what the daemon enforces:
  - A module refused by a declared conflict or a missing required module shows the daemon's reason ("Conflicts with <name> (<id>)", "Needs the module <id>") as its status.
  - An enabled module that can run shows one note, `<stage>: <reason>`, for each of its stages the daemon refuses (for example `matte: Cannot run together with noise removal`).
  - A module whose conflicts are not enforced (the debug override `modules.forced.<id>`) carries a line in the urgent colour, "Forced: conflicts are not enforced (debug override)", also read out with the row.
  - The dialog only shows the mark. Either command below sets the override:

    ```sh
    omarchy-broadcast modules enable <id> --force
    omarchy-broadcast config set modules.forced.<id> true
    ```

    This command clears it:

    ```sh
    omarchy-broadcast modules enable <id>
    ```

- When there is no module, the section says "No effect modules installed", names the AUR packages that provide modules (`omarchy-broadcast-onnx-git`, or the `omarchy-broadcast-maxine-*-git` modules for NVIDIA GPUs) and says where a module's manifest goes: `~/.local/share/omarchy-broadcast/modules.d` for your own, `/usr/lib/omarchy-broadcast/modules.d` for packaged ones.

## Order

The stages are listed in the order they run, each with its slot. Move up and Move down buttons are offered only where the daemon says the swap with the neighbour is valid.

- With the cursor on a stage, Left/Right pick the button and Enter moves it, or Ctrl+Up/Down moves it at once.
- A move is written as the whole new order:

  ```sh
  omarchy-broadcast order set <stage>,<stage>,...
  ```

- Reset order goes back to the default:

  ```sh
  omarchy-broadcast order reset
  ```

## Backends

The section shows the backend profile (Quality or Battery) and, for each stage (the microphone's `mic-*` stages included), the module pinned to provide it, or Automatic.

- A short set of short names is a row of choices on a line of its own under the label. A pin with long module names is a dropdown showing the full name.
- The writes are the commands below. The empty value is Automatic.

  ```sh
  omarchy-broadcast config set -- modules.profile <profile>
  omarchy-broadcast config set -- modules.pin.<stage> <module id>
  ```

## Daemon

The section shows the daemon's configuration as its schema describes it, group by group (camera, output, loopback, lifecycle, effect, PipeWire), each row with its description. Every change is:

```sh
omarchy-broadcast config set -- <key> <value>
```

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
  - **Choose…** hides the dialog and opens the shell's image picker over the away gallery's bundled images and your own, listed with the first command below. Your own away images are kept in the `away` folder inside your pictures folder `omarchy-broadcast`. With nothing listed the dialog says "No away images yet. Add one with Add…". With items listed but no row for the picker to show, it says "The picker cannot show any of the gallery's away images. Add another with Add…". In both cases it does not open the picker (the same rows check as the panel's Gallery…). The image you pick must be one the gallery listed, and is set with the second command. Anything else is refused with "That file is not in the gallery; nothing was changed".

    ```sh
    omarchy-broadcast media list away --json
    omarchy-broadcast config set -- effect.fallback_image <path>
    ```

  - **Add…** hides the dialog and opens the desktop file chooser (still images only: PNG, JPEG or WebP, titled "Add an away image"). The file is copied into your away gallery, checked and set with:

    ```sh
    omarchy-broadcast media import away <path> --select
    ```

  - **Clear** sets no image:

    ```sh
    omarchy-broadcast config set -- effect.fallback_image ""
    ```

- The dialog shows again when the picker or chooser is done. A refusal or failure appears under its title.
- Left/Right walk the buttons on offer (a faded one is skipped), and Enter runs one.
- While no image is chosen and either switch is on the image, a note under the row says black is shown instead. With a daemon at interface revision 21 or later, "either switch" is `output.placeholder` on Away image, or privacy on with its mode Away image.
- "When there is no camera picture" (`output.placeholder`) is an ordinary row of choices, Black or Away image. With Away image, the image stands in for every frame without a camera picture (the camera switched off, starting, an error, a stall).
- "When an effect can't run" (`effect.on_failure`) keeps its own choices, its image choice using the same picture.
- A row a later configuration file sets, or one the daemon greys out, stays read-only with the reason.
- **From interface revision 21** the "When an effect can't run" dropdown is gone, replaced by two ordinary rows drawn in the daemon's order:
  - a switch, "Hide the camera when an effect can't run" (`effect.privacy`);
  - the choices "Show instead of the camera" (`effect.privacy_mode`): Black, Away image (offered once an away image is chosen, or while it is the choice in force) and Last frame.

  While the switch is off the daemon greys the choices out, and the dialog shows the one in force as read-only text with the daemon's reason (`Turn on "Hide the camera when an effect can't run" to change this`). Both rows are live, and a change is written to the new keys, for example:

  ```sh
  omarchy-broadcast config set -- effect.privacy true
  omarchy-broadcast config set -- effect.privacy_mode freeze
  ```

  A daemon below revision 21 keeps the single `effect.on_failure` row, with its choices "Hide the camera: black", "Hide the camera: image" and "Show the camera" (written as `none`).

**The battery saver** (from interface revision 22): the Video processing group has the **Battery saver** mode (`video.battery_saver`), chosen from a dropdown with the daemon's own labels:

- Off;
- On battery or power saver (from interface revision 23, when the daemon offers it: on battery, or while the power profile is power-saver);
- On battery;
- Follow the power profile (the camera saves power while the power profile is power-saver);
- Always.

It applies when the camera next starts, and is greyed out with the daemon's reason while video processing is not automatic. The description ends with what is in force now ("Now: ..."). Any row for which the daemon has something to say about its present state (a `notice` field, such as "Applies when the camera restarts" on this row when the mode or the power state changed during a camera session) shows that text in muted type under the row.

## Backgrounds

This section needs interface revision 15 or later. It shows:

- how many backgrounds come bundled with omarchy-broadcast;
- a note saying that your own are kept in a folder ("Your own backgrounds are kept in these folders; files you copy there appear here:"), then the pictures folder's path and the videos folder's path, each on a line of its own (broken anywhere when long). With a daemon that reports only the pictures folder, the note says "Your own backgrounds are kept in this folder; files you copy there appear here:" over that one path. All of it is hidden while the daemon reports no folder;
- the backgrounds you added (the section reads the folder again each time the dialog is shown), each with a small thumbnail (a video's poster, with the video glyph), its name, its size (for a video also "video" and its length, for example "1920×1080, video, 0:12") and a Remove button. With none of your own, a note says how to add one.

Remove asks for a second press ("Confirm remove") before it runs the command below. Moving the cursor away (by key or by hovering another control) or changing section cancels it. Bundled backgrounds cannot be removed. The plugin reads at most the 500 backgrounds the daemon lists.

```sh
omarchy-broadcast media remove <path>
```

From D-Bus interface revision 19, under a video the daemon lists as not ready for system memory (`cpu_ready` false) and gives a command for (`convert_command`), the row shows:

- "Without an NVIDIA GPU this video shows as a still. To play it without one, convert it in a terminal; the copy lands in your videos folder:";
- the command in a monospace text you can select (selecting copies it, as in Diagnostics);
- a **Copy** button, which is a stop of its own for the keyboard, after the row's Remove. Enter copies it, and "Copied" appears beside it.

The plugin never runs the command. A command over 1536 characters or with a control character is not shown. An older daemon says nothing of this and nothing is shown.

Add backgrounds with Add… in the panel's Effects tab. While it imports a file, the section says "Adding the background…" and is read again when the import ends.

## Diagnostics

Diagnostics is read-only. It shows:

- the daemon's D-Bus interface revision, error text and warning (the warning row only when there is one; a long warning or error is wrapped under its label, in full);
- the configuration files in the order they are loaded, with their status and any error, and which one this dialog writes;
- the modules and stages that cannot run, with the reason;
- two commands to copy into a terminal, shown below. Select one (or part of it) with the mouse and it is copied to the clipboard, and the section says what was copied. The dialog shows them and never runs them.

  ```sh
  omarchy-broadcast modules
  journalctl --user -u omarchy-broadcastd
  ```

## Where the dialog's changes go

The daemon keeps the dialog's changes in a file of its own, `config.d/50-panel.toml` in its configuration directory (`~/.config/omarchy-broadcast/`). `config.toml` and every other file are never written. A setting that a later file (such as `config.d/90-local.toml`) also sets is shown greyed with "Overridden by <file>", and the daemon refuses to change it: edit or remove it in that file instead.

## Against an older daemon

Against a daemon below interface revision 9 (omarchy-broadcastd before 0.24.0), every section but Diagnostics says the daemon needs updating. At revision 9 (omarchy-broadcastd 0.24), Modules works. Order lists the stages with their Move up and Move down buttons greyed out and disabled, because the daemon's order line then carries no move information: no stage can be moved (Ctrl+Up/Down does nothing), and Reset order still works. Backends, Daemon and the configuration files say the daemon needs updating.

## How the shell opens it

The dialog is the plugin's overlay entry point (`kinds` `overlay`, `entryPoints.overlay` in `manifest.json`), so the shell routes the plugin's summon and toggle to it, the panel hotkey's included.

- A summon whose payload is `{"view":"setup"}` (which is what the right click sends) opens the dialog.
- Any other payload, and any toggle without one (the hotkey, the shell's positional panel toggle), opens and closes the bar panel on the focused monitor, as before.
- Because the shell reports the plugin open while the dialog is shown, the panel hotkey pressed then closes the dialog. Press it again to open the panel.
