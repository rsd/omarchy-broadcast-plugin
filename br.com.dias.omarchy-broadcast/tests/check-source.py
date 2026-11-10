#!/usr/bin/env python3
"""Source-level invariants of the plugin, each one a bug class that a running
widget would hide.

  - every `Text {` sets `textFormat: Text.PlainText` (AutoText renders markup,
    and `<img src=...>` in a camera name would fetch a URL);
  - the qmldir declares the Daemon and Preview singletons (without the line,
    the name is the component type and every read off it is undefined);
  - the manifest id equals the directory name (or the shell does not load it);
  - Component.onDestruction only hands back registrations (Daemon.detach,
    Preview.release): no stop, no `running = false`, no `off`, no `bar.run`,
    no pkill (it runs on every hot reload);
  - no shell-string commands (`bash -c`, `bar.run(`, execDetached), no
    pkill/killall, no repeating Timer, no whole-stream StdioCollector;
  - the watch's stdout is read in line mode (a chunked read garbles a
    multi-byte character cut by a read boundary), a command's stderr in
    chunks (it is unbounded; only its capped first line is kept);
  - panel visuals never read `containsMouse` for colour (the shell's
    CursorSurface contract: one highlight, from the panel cursor);
  - an effect reaches the command line only as a word of Model.EFFECTS,
    through an intent (Daemon.setEffect -> Model.effectArgv);
  - noise removal reaches it only as `on` or `off` from a strict boolean,
    through an intent (Daemon.setDenoise -> Model.denoiseArgv), and only
    while the daemon reports it;
  - the effect chips carry the shell ButtonGroup's fill and fade from
    Model's `faded`; the hint and its command share one Column at the
    unavailable block's spacing; the Replace gate reads the raw image field,
    and the shown path sits in a left-to-right Unicode isolate;
  - the preview: one Process, in the Preview singleton, armed with an argv
    from Model.previewArgv (15 or 30 only), read in line mode with the line
    cap that stops it, no Timer anywhere in its path, re-armed through
    Qt.callLater; the Image is never cached and its source comes from
    Model.previewSource (the validated path); no video device and no D-Bus
    tool named anywhere; preview preferences written only from the panel's
    two user actions, through Model.settingsEntry;
  - the camera image controls: a name reaches the command line only as a
    word of Model.CONTROL_NAMES and a value only as a checked integer,
    through an intent (Daemon.flushControls -> Model.controlArgv), and a
    reset as the constant `controls reset`; each bound to the camera whose
    controls the panel showed (Model.controlIntentBound) and dropped from
    the queue when the controls change camera; queued writes coalesce through
    Model.enqueueIntent; the write debounce is the Daemon's one one-shot
    Timer, restarted only by a user's move, and the panel has no Timer; the
    slider rows have the constant model Model.CONTROL_NAMES (a controls line
    never rebuilds the row being dragged), use the shell's PanelSlider, and
    the Flickable lets go of a held slider;
  - the bar clicks: right click turns the camera on or off through
    Model.rightClickAction (its guards, with Daemon.toggleBusy: slider writes
    never hold it), every other click opens and closes the panel;
  - the panel tab: a stored `panelTab` is read only through
    Model.panelTabValue (anything but a word of Model.PANEL_TABS reads as the
    default), written only by the panel's chooseTab as a word of
    Model.PANEL_TABS through Model.settingsEntry, and the manifest's enum
    options are exactly Model.PANEL_TABS; each tab page is drawn only for its
    own word; the card is 520 wide and as tall as its content (the screen's
    available height is the only cap; past it the Flickable scrolls).

Run: python3 -I tests/check-source.py   (exit status 0 = all hold)
"""
import json
import re
import sys
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[1]
failures = []


def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else ": " + detail))
    if not ok:
        failures.append(name)


def strip_comments(text):
    # Line comments only (the plugin uses no block comments); keep strings.
    out = []
    for line in text.splitlines():
        stripped = line.lstrip()
        out.append("" if stripped.startswith("//") else line)
    return "\n".join(out)


qml_files = sorted(PLUGIN.glob("*.qml")) + sorted((PLUGIN / "tests").glob("**/*.qml"))
plugin_qml = sorted(PLUGIN.glob("*.qml"))
sources = {p: strip_comments(p.read_text(encoding="utf-8")) for p in qml_files}
js_sources = {p: strip_comments(p.read_text(encoding="utf-8")) for p in sorted(PLUGIN.glob("*.js"))}

# ---- PlainText on every Text ------------------------------------------------
text_blocks = 0
plain = 0
for path, src in sources.items():
    blocks = len(re.findall(r"(?<![\w.])Text\s*\{", src))
    formats = len(re.findall(r"textFormat:\s*Text\.PlainText\b", src))
    text_blocks += blocks
    plain += formats
    check(f"{path.relative_to(PLUGIN)}: every Text is PlainText ({formats}/{blocks})",
          blocks == formats, f"{blocks} Text blocks, {formats} PlainText")
check("at least one Text checked", text_blocks > 0, "no Text found: the pattern is broken")
check("no other textFormat", all("Text.RichText" not in s and "Text.StyledText" not in s
                                 and "Text.AutoText" not in s and "Text.MarkdownText" not in s
                                 for s in sources.values()), "a non-plain textFormat is used")

# ---- qmldir -----------------------------------------------------------------
qmldir = (PLUGIN / "qmldir").read_text(encoding="utf-8").splitlines()
check("qmldir declares the Daemon singleton",
      any(re.fullmatch(r"\s*singleton\s+Daemon\s+1\.0\s+Daemon\.qml\s*", l) for l in qmldir),
      "missing `singleton Daemon 1.0 Daemon.qml`")
check("qmldir declares the Preview singleton",
      any(re.fullmatch(r"\s*singleton\s+Preview\s+1\.0\s+Preview\.qml\s*", l) for l in qmldir),
      "missing `singleton Preview 1.0 Preview.qml`")
daemon_src = (PLUGIN / "Daemon.qml").read_text(encoding="utf-8")
check("Daemon.qml has pragma Singleton", "pragma Singleton" in daemon_src)
preview_src = (PLUGIN / "Preview.qml").read_text(encoding="utf-8")
check("Preview.qml has pragma Singleton", "pragma Singleton" in preview_src)
# With a qmldir present, only listed types resolve from the directory.
used_types = set(re.findall(r"^\s*([A-Z]\w*)\s*\{", "\n".join(sources[p] for p in plugin_qml), re.M))
local_types = {p.stem for p in plugin_qml}
# BarWidget.qml extends qs.Ui's BarWidget: listing it would make the name
# resolve to the file itself (a recursive type), so it must stay unlisted.
for t in sorted((used_types & local_types) - {"BarWidget"}):
    check(f"qmldir lists local type {t}", any(re.match(rf"\s*(singleton\s+)?{t}\s+1\.0\s+{t}\.qml", l) for l in qmldir))
check("qmldir does not list BarWidget (it would shadow qs.Ui's)",
      not any(re.match(r"\s*BarWidget\s", l) for l in qmldir))

# ---- manifest ---------------------------------------------------------------
manifest = json.loads((PLUGIN / "manifest.json").read_text(encoding="utf-8"))
check("manifest id equals directory name", manifest.get("id") == PLUGIN.name,
      f"id {manifest.get('id')!r} vs dir {PLUGIN.name!r}")
check("entry point is BarWidget.qml", manifest.get("entryPoints", {}).get("barWidget") == "BarWidget.qml")
check("allowMultiple is false", manifest.get("barWidget", {}).get("allowMultiple") is False)
schema = manifest.get("barWidget", {}).get("schema", [])
schema_keys = [s.get("key") for s in schema]
check("settings: cliPath, previewEnabled, previewFps, panelTab",
      schema_keys == ["cliPath", "previewEnabled", "previewFps", "panelTab"], str(schema_keys))
by_key = {s.get("key"): s for s in schema}
defaults = manifest.get("barWidget", {}).get("defaults", {})
check("previewEnabled is a boolean, default false",
      by_key.get("previewEnabled", {}).get("type") == "boolean" and by_key["previewEnabled"].get("defaultValue") is False
      and defaults.get("previewEnabled") is False, str(by_key.get("previewEnabled")))
fps_schema = by_key.get("previewFps", {})
check("previewFps is an integer 15..30 in steps of 15, default 15",
      fps_schema.get("type") == "integer" and fps_schema.get("min") == 15 and fps_schema.get("max") == 30
      and fps_schema.get("step") == 15 and fps_schema.get("defaultValue") == 15 and defaults.get("previewFps") == 15,
      str(fps_schema))
check("defaults hold exactly the schema keys", sorted(defaults) == sorted(schema_keys), str(sorted(defaults)))
tab_schema = by_key.get("panelTab", {})
model_src = (PLUGIN / "Model.js").read_text(encoding="utf-8")
tabs_match = re.search(r'^var PANEL_TABS = (\[[^\]]*\])$', model_src, re.M)
model_tabs = json.loads(tabs_match.group(1)) if tabs_match else None
default_match = re.search(r'^var PANEL_TAB_DEFAULT = "(\w+)"$', model_src, re.M)
check("panelTab is an enum of exactly Model.PANEL_TABS, default Model.PANEL_TAB_DEFAULT (the first)",
      tab_schema.get("type") == "enum" and model_tabs is not None and tab_schema.get("options") == model_tabs
      and default_match is not None and default_match.group(1) == model_tabs[0]
      and tab_schema.get("defaultValue") == model_tabs[0] and defaults.get("panelTab") == model_tabs[0],
      f"{tab_schema} vs {model_tabs}")

# ---- Component.onDestruction bodies -----------------------------------------
def destruction_bodies(src):
    bodies = []
    for m in re.finditer(r"Component\.onDestruction\s*:\s*", src):
        rest = src[m.end():]
        if rest.startswith("{"):
            depth = 0
            for i, ch in enumerate(rest):
                depth += ch == "{"
                depth -= ch == "}"
                if depth == 0:
                    bodies.append(rest[1:i])
                    break
        else:
            bodies.append(rest.split("\n", 1)[0])
    return bodies

all_bodies = []
for path, src in sources.items():
    if path.parent != PLUGIN:
        continue
    for body in destruction_bodies(src):
        all_bodies.append(body)
        statements = [s.strip() for s in re.split(r"[;\n]", body) if s.strip()]
        only_detach = all(re.fullmatch(r"Daemon\.detach\(\s*root\s*\)|Preview\.release\(\s*root\s*\)", s)
                          for s in statements)
        check(f"{path.name}: onDestruction only unregisters", only_detach and statements != [], body.strip())
        for bad in ("running", "stop", "\"off\"", "bar.run", "pkill", "kill", "signal("):
            check(f"{path.name}: onDestruction has no {bad}", bad not in body, body.strip())
check("the widget unregisters on destruction", len(all_bodies) >= 1, "no Component.onDestruction")
check("the widget releases the preview on destruction",
      any("Preview.release(root)" in b for b in destruction_bodies(sources[PLUGIN / "BarWidget.qml"])))

# ---- forbidden constructs ---------------------------------------------------
everything = {**{p: s for p, s in sources.items() if p.parent == PLUGIN}, **js_sources}
for path, src in everything.items():
    name = path.name
    check(f"{name}: no bash -c", "bash -c" not in src and '"bash", "-c"' not in src)
    check(f"{name}: no bar.run(", "bar.run(" not in src)
    check(f"{name}: no execDetached", "execDetached" not in src)
    check(f"{name}: no pkill/killall", re.search(r"\b(pkill|killall)\b", src) is None)
    check(f"{name}: no repeating Timer", re.search(r"repeat\s*:\s*true", src) is None)
    check(f"{name}: no StdioCollector", "StdioCollector" not in src)
    check(f"{name}: no string command", re.search(r"command\s*:\s*[\"']", src) is None)

# The only `sh -c` is the resolver, with its directory passed positionally.
sh_uses = [p.name for p, s in everything.items() if '"sh", "-c"' in s]
check("sh -c only in Model.resolverArgv", sh_uses == ["Model.js"], str(sh_uses))
model = js_sources[PLUGIN / "Model.js"]
check("resolver passes the dir as $1", 'return ["sh", "-c", RESOLVER_SCRIPT, "omarchy-broadcast-resolve", dir]' in model)


def block(src, header):
    """The text of the `{ ... }` block that follows `header`."""
    at = src.find(header)
    if at < 0:
        return ""
    start = src.index("{", at)
    depth = 0
    for i in range(start, len(src)):
        depth += src[i] == "{"
        depth -= src[i] == "}"
        if depth == 0:
            return src[start:i + 1]
    return ""


daemon = sources[PLUGIN / "Daemon.qml"]
watch_block = block(daemon, "property Process watchProc")
command_block = block(daemon, "property Process commandProc")
check("watch stdout is line mode (no splitMarker)", watch_block != "" and "splitMarker" not in watch_block, watch_block[:200])
check("command stderr is chunked (splitMarker: \"\")", re.search(r'stderr:\s*SplitParser\s*\{\s*splitMarker:\s*""', command_block) is not None,
      command_block[:200])
check("command stderr goes through Model.firstLineFeed", "Model.firstLineFeed(" in command_block)
check("an over-cap watch line stops the watch", re.search(r"line\.length > Model\.LINE_CAP\)\s*\{[^}]*stopWatch\(\)", daemon) is not None)
check("an effect is requested as an intent, never a raw argv",
      re.search(r'function setEffect\(effect\)\s*\{\s*return request\(\{ verb: "effect", effect: effect \}\)\s*\}', daemon) is not None)
check("effectArgv only passes a word of Model.EFFECTS",
      re.search(r'function effectArgv\(cli, effect\)\s*\{\s*if \(!cliUsable\(cli\) \|\| effectKey\(effect\) === ""\) return null', model) is not None)
check("noise removal is requested as an intent, never a raw argv",
      re.search(r'function setDenoise\(on\)\s*\{\s*return request\(\{ verb: "denoise", on: on === true \}\)\s*\}', daemon) is not None)
check("denoiseArgv only passes on/off from a strict boolean",
      re.search(r'function denoiseArgv\(cli, on\)\s*\{\s*if \(!cliUsable\(cli\) \|\| typeof on !== "boolean"\) return null\s*'
                r'return \[cli, "denoise", on \? DENOISE_WORDS\.on : DENOISE_WORDS\.off\]', model) is not None
      and 'var DENOISE_WORDS = { on: "on", off: "off" }' in model)
check("a denoise intent runs only while the daemon reports it",
      'case "denoise": return denoiseSupported(record) ? denoiseArgv(cli, intent.on) : null' in model)
check("queued commands are intents re-checked when armed",
      "pendingIntents" in daemon and "pendingArgv" not in daemon and "Model.intentArgv(intent, cliPath, record)" in block(daemon, "function armCommand"))
check("the queue changes only through Model.enqueueIntent (coalescing) and flushPending",
      re.findall(r"pendingIntents\s*=\s*([^\n]*)", daemon)
      == ["Model.dropControlIntents(pendingIntents)", "Model.enqueueIntent(pendingIntents, intent)", "pendingIntents.slice(1)"]
      and ".push(" not in block(daemon, "function request"), str(re.findall(r"pendingIntents\s*=\s*([^\n]*)", daemon)))

panel = sources[PLUGIN / "BroadcastPanel.qml"]
bar_src = sources[PLUGIN / "BarWidget.qml"]
for name, src in ((p.name, sources[p]) for p in plugin_qml):
    check(f"{name}: no containsMouse-driven colour",
          re.search(r"(color|border\.color|fill)\s*:[^\n]*containsMouse", src) is None)
check("the panel sets an effect only from its whitelisted choices",
      re.findall(r"Daemon\.setEffect\(([^)]*)\)", panel) == ["option.value"],
      str(re.findall(r"Daemon\.setEffect\(([^)]*)\)", panel)))
effect_chips = block(panel, "id: effectRepeater")
check("the panel flips noise removal only from the reported state",
      re.findall(r"Daemon\.setDenoise\(([^)]*)\)", panel) == ["root.record.denoise !== true"],
      str(re.findall(r"Daemon\.setDenoise\(([^)]*)\)", panel)))
check("the noise removal switch is drawn only from Model.denoiseRow",
      re.search(r'objectName: "denoiseRow"[^}]*visible: root\.denoiseRow\.visible', panel) is not None)
check("the noise removal switch swallows clicks while a command runs",
      re.search(r'objectName: "denoiseToggle"[^}]*busy: Daemon\.commandBusy', panel) is not None)
check("effect chips have the ButtonGroup fill (Commons.Color.background)",
      re.search(r"^\s*background:\s*Commons\.Color\.background\s*$", effect_chips, re.M) is not None, effect_chips[:200])
check("effect chips fade from Model's `faded`, not a local rule",
      re.search(r"opacity:\s*modelData\.faded \? 0\.45 : 1\.0", effect_chips) is not None)
hint_at = panel.find('objectName: "effectHintBlock"')
hint_column = panel.rfind("Column {", 0, hint_at) if hint_at >= 0 else -1
hint_block = block(panel[hint_column:], "Column {") if hint_column >= 0 else ""
# The Column's own spacing: the indentation of its objectName line.
hint_indent = re.search(r'^( *)objectName:\s*"effectHintBlock"', hint_block, re.M)
check("effect hint and its command share one Column at Style.space(6)",
      re.match(r'\{\s*objectName:\s*"effectHintBlock"', hint_block) is not None and hint_indent is not None
      and re.search(r"^" + hint_indent.group(1) + r"spacing: Style\.space\(6\)$", hint_block, re.M) is not None
      and 'objectName: "effectHint"' in hint_block and 'objectName: "effectHintCommand"' in hint_block,
      hint_block[:200])
check("the image path is isolated (LRI U+2066 ... PDI U+2069) after sanitising",
      'return "\\u2066" + record.backgroundImage + "\\u2069"' in model)
check("the Replace gate reads the raw field, not the display copy",
      re.search(r"function hasBackgroundImage\(record\)\s*\{\s*return !!record && record\.backgroundImageSet === true\s*\}", model) is not None)
check("camera rows are CursorSurfaces", re.search(r"delegate:\s*CursorSurface\s*\{", panel) is not None)
check("the panel scrolls (Flickable)", "Flickable {" in panel)
check("the card is 520 wide and as tall as its content (the screen is the only cap)",
      "contentWidth: panel.fittedContentWidth(Style.space(520))" in sources[PLUGIN / "BarWidget.qml"]
      and "contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)" in sources[PLUGIN / "BarWidget.qml"])
check("no stale reference to check-source.sh (comments included)",
      all("check-source.sh" not in p.read_text(encoding="utf-8") for p in list(everything) + [PLUGIN / "manifest.json"]))

# ---- camera image controls ---------------------------------------------------
check("controlArgv only passes a word of Model.CONTROL_NAMES and a checked integer",
      re.search(r'function controlArgv\(cli, name, value\)\s*\{\s*if \(!cliUsable\(cli\) \|\| CONTROL_NAMES\.indexOf\(name\) < 0 \|\| controlInt\(value\) === null\) return null\s*'
                r'return \[cli, "controls", "set", name, String\(value\)\]', model) is not None
      and 'var CONTROL_NAMES = ["brightness", "contrast", "saturation", "sharpness"]' in model)
check("a reset is the constant `controls reset`",
      re.search(r'function resetControlsArgv\(cli\)\s*\{\s*return cliUsable\(cli\) \? \[cli, "controls", "reset"\] : null\s*\}', model) is not None)
check("control intents run only while the daemon offers the control, on its grid",
      'case "control": return controlIntentBound(intent, record) ? controlIntentArgv(cli, record, intent.name, intent.value) : null' in model
      and 'case "reset-controls": return controlsSupported(record) && controlIntentBound(intent, record) ? resetControlsArgv(cli) : null' in model
      and "intent.camera === record.controlsCameraId" in block(model, "function controlIntentBound")
      and "var v = snapControl(findControl(record, name), value)" in block(model, "function controlIntentArgv"))
check("a camera change drops the queued control writes; the change is seen on the raw id",
      "var otherCamera = record.controlsCameraId !== camera" in block(daemon, "function ingest")
      and "if (otherCamera) dropQueuedControls()" in block(daemon, "function ingest")
      and "var camera = record.controlsCameraId" in block(daemon, "function ingest"))
check("Daemon requests controls only as intents from flushControls and resetControls",
      re.findall(r'request\(\{ verb: "(control|reset-controls)"[^)]*\)', daemon) == ["control", "reset-controls"]
      and 'request({ verb: "control", name: name, value: v, camera: record.controlsCameraId })' in block(daemon, "function flushControls")
      and 'request({ verb: "reset-controls", camera: record.controlsCameraId })' in block(daemon, "function resetControls"))
check("flushControls walks only Model.CONTROL_NAMES",
      "for (var i = 0; i < Model.CONTROL_NAMES.length; i++)" in block(daemon, "function flushControls"))
timers = re.findall(r"property Timer (\w+): Timer \{", daemon)
check("the Daemon's timers are the backoff and the controls debounce", sorted(timers) == ["backoffTimer", "controlTimer"], str(timers))
control_timer = block(daemon, "property Timer controlTimer")
check("the controls debounce is a one-shot of Model.CONTROLS_DEBOUNCE_MS",
      re.search(r"^\s*repeat:\s*false\s*$", control_timer, re.M) is not None
      and "interval: Model.CONTROLS_DEBOUNCE_MS" in control_timer and "running:" not in control_timer
      and "triggeredOnStart" not in control_timer, control_timer[:200])
check("the controls debounce is (re)started only by moveControl, a user's move",
      re.findall(r"controlTimer\.(start|restart)\(\)", daemon) == ["restart"]
      and "controlTimer.restart()" in block(daemon, "function moveControl"))
check("the panel moves a control only through the Daemon, by a name of Model.CONTROL_NAMES",
      re.findall(r"Daemon\.(?:moveControl|commitControl)\(([^,]*),", panel)
      == ["name", "controlRow.modelData", "controlRow.modelData"]
      and "var name = Model.CONTROL_NAMES[index]" in block(panel, "function nudgeControl"),
      str(re.findall(r"Daemon\.(?:moveControl|commitControl)\(([^,]*),", panel)))
check("the panel resets the controls only from resetControls",
      panel.count("Daemon.resetControls()") == 1 and "Daemon.resetControls()" in block(panel, "function resetControls"))
# The delegate's block, and the Repeater's own lines before it.
control_rows = block(panel, "id: controlRepeater")
rows_at = panel.find("id: controlRepeater")
rows_head = panel[rows_at:panel.find("delegate:", rows_at)] if rows_at >= 0 else ""
check("the slider rows have the constant model Model.CONTROL_NAMES",
      re.search(r"^\s*model:\s*Model\.CONTROL_NAMES\s*$", rows_head, re.M) is not None, rows_head[:200])
check("the sliders are the shell's PanelSlider, integer, only in those rows",
      len(re.findall(r"\bPanelSlider\s*\{", panel)) == 1 and "PanelSlider {" in control_rows
      and re.search(r"^\s*integer:\s*true\s*$", control_rows, re.M) is not None)
check("a held slider keeps the Flickable from taking the drag",
      "interactive: contentHeight > height && root.slidersHeld === 0" in panel)
check("the Camera image section is drawn only from Model.controlsSection",
      "readonly property var controlsView: Model.controlsSection(record)" in panel
      and re.search(r'objectName: "controlsBlock"[^}]*visible: root\.controlsView\.visible', panel) is not None)
check("the controls list is capped before it is walked",
      "var n = Math.min(src.length, CONTROLS_CAP)" in block(model, "function controlList"))

# ---- every Process is in a singleton -----------------------------------------
for path, src in sources.items():
    if path.parent == PLUGIN and path.name not in ("Daemon.qml", "Preview.qml"):
        check(f"{path.name}: spawns no Process", re.search(r"\bProcess\s*\{", src) is None)

# ---- the preview ------------------------------------------------------------
preview = sources[PLUGIN / "Preview.qml"]
check("Preview.qml has exactly one Process", len(re.findall(r"\bProcess\s*\{", preview)) == 1)
preview_block = block(preview, "property Process previewProc")
check("preview stdout is line mode (no splitMarker)", preview_block != "" and "splitMarker" not in preview_block)
check("no Timer in the preview path", all(re.search(r"\bTimer\b", sources[PLUGIN / n]) is None
                                          for n in ("Preview.qml", "BroadcastPanel.qml")))
check("the preview command is only an argv from Model.previewArgv",
      re.findall(r"previewProc\.command\s*=\s*([^\n]*)", preview) == ["argv"]
      and "var argv = Model.previewArgv(cliPath, fps)" in block(preview, "function armPreview"))
check("previewArgv passes only 15 or 30, as argv elements",
      re.search(r'function previewArgv\(cli, fps\)\s*\{\s*if \(!cliUsable\(cli\) \|\| PREVIEW_FPS_CHOICES\.indexOf\(fps\) < 0\) return null\s*'
                r'return \[cli, "preview", "--json", "--fps", fps === 30 \? "30" : "15"\]', model) is not None
      and "var PREVIEW_FPS_CHOICES = [15, 30]" in model)
check("an over-cap preview line stops the preview",
      re.search(r"line\.length > Model\.LINE_CAP\)\s*\{[^}]*stopPreview\(\)", preview) is not None)
check("preview lines go through Model.parsePreviewLine with the expected path",
      "Model.parsePreviewLine(line, expectedPath, seq)" in preview)
check("preview re-arm deferred with Qt.callLater", "Qt.callLater(root.syncPreview)" in preview)
check("the expected path comes from XDG_RUNTIME_DIR through Model.previewPath",
      'Model.previewPath(Quickshell.env("XDG_RUNTIME_DIR"))' in preview)
check("the frame source is built only by Model.previewSource",
      "readonly property string frameSource: Model.previewSource(expectedPath, seq)" in preview
      and re.search(r'return "file://" \+ expectedPath \+ "\?" \+ n', model) is not None
      and [p.name for p, s in everything.items() if '"file://"' in s] == ["Model.js"])
image_at = panel.find("id: previewImage")
image_block = block(panel[panel.rfind("Image {", 0, image_at):], "Image {") if image_at >= 0 else ""
check("the preview Image is never cached and reads Preview.frameSource",
      re.search(r"^\s*cache:\s*false\s*$", image_block, re.M) is not None
      and "Preview.frameSource" in image_block and "retainWhileLoading: true" in image_block, image_block[:200])
check("only one Image in the plugin", sum(len(re.findall(r"(?<![\w.])Image\s*\{", s)) for p, s in sources.items()
                                          if p.parent == PLUGIN) == 1)
for path, src in everything.items():
    raw = path.read_text(encoding="utf-8")
    check(f"{path.name}: no video device", "/dev/video" not in raw)
    check(f"{path.name}: no D-Bus tool", re.search(r"\b(busctl|gdbus|dbus-send|qdbus)\b", raw) is None)
check("preview holders are registered only by the widget, on open/close",
      re.findall(r"Preview\.(hold|release)\(([^)]*)\)", "\n".join(s for p, s in sources.items() if p.parent == PLUGIN))
      == [("hold", "root"), ("release", "root"), ("release", "root")])
check("panel preferences are requested only by togglePreview, chooseFps and chooseTab",
      re.findall(r"root\.settingsRequested\(([^)]*\))", panel)
      == ["{ previewEnabled: !Preview.switchOn })", "{ previewFps: option.value })", "{ panelTab: value })"]
      and "root.settingsRequested(" not in panel.replace(block(panel, "function togglePreview"), "")
      .replace(block(panel, "function chooseFps"), "").replace(block(panel, "function chooseTab"), ""),
      str(re.findall(r"root\.settingsRequested\(([^)]*\))", panel)))
check("chooseTab writes only a word of Model.PANEL_TABS",
      "var value = Model.PANEL_TABS[index]" in block(panel, "function chooseTab")
      and "if (value === undefined || !root.available) return false" in block(panel, "function chooseTab"))
check("settingsEntry writes panelTab only as a word of PANEL_TABS",
      "if (PANEL_TABS.indexOf(values.panelTab) < 0) return null" in block(model, "function settingsEntry"))
check("a stored tab is read only through Model.panelTabValue",
      re.search(r'function panelTabValue\(value\)\s*\{\s*return typeof value === "string" && PANEL_TABS\.indexOf\(value\) >= 0 \? value : PANEL_TAB_DEFAULT\s*\}', model) is not None
      and 'readonly property string storedTab: Model.panelTabValue(Model.settingValue(settings, "panelTab"))' in bar_src
      and "var next = Model.panelTabValue(value)" in block(panel, "function showTab")
      and re.findall(r"root\.tab = ([^\n]*)", panel) == ["next"])
for word, name in (("effect", "effectTab"), ("camera", "cameraTab"), ("status", "statusTab")):
    check(f"the {word} tab is drawn only while it is the tab shown",
          re.search(r'objectName: "' + name + r'"[^}]*visible: root\.tab === "' + word + r'"', panel) is not None)
check("the right click toggles through Model.rightClickAction; other clicks open and close the panel",
      re.search(r"function press\(buttonCode\)\s*\{\s*if \(buttonCode === Qt\.RightButton\) root\.toggleCamera\(\)\s*else root\.toggle\(\)\s*\}", bar_src) is not None
      and "var action = Model.rightClickAction(root.record, Daemon.toggleBusy)" in block(bar_src, "function toggleCamera")
      and "Model.rightClickAction(record, toggleBusy) !== \"toggle\"" in block(daemon, "function toggleEnabled")
      and "readonly property bool toggleBusy: Model.toggleBlocked(runningIntent, pendingIntents)" in daemon
      and "if (!root.available || Daemon.toggleBusy) return false" in block(panel, "function toggleSwitch")
      and re.search(r'objectName: "enableSwitch"[^}]*busy: Daemon\.toggleBusy', panel) is not None
      and "leftClickAction" not in model)
check("settings are written only through Model.settingsEntry, by persistSettings",
      bar_src.count("updateEntryInline(") == 1 and "var entry = Model.settingsEntry(root.moduleName, root.settings, values)"
      in block(bar_src, "function persistSettings") and "updateEntryInline" in block(bar_src, "function persistSettings"))
check("a widget configures the preview only from onSettingsChanged (never with the base's empty default)",
      re.findall(r"Preview\.configure\(([^)]*)\)", bar_src) == ["root, root.settings"]
      and re.search(r"onSettingsChanged:\s*Preview\.configure\(root, root\.settings\)", bar_src) is not None
      and "Preview.configure" not in block(bar_src, "Component.onCompleted"),
      str(re.findall(r"Preview\.configure\(([^)]*)\)", bar_src)))
check("persistSettings checks what updateEntryInline answered",
      "updateEntryInline(root.moduleName, entry) === true" in block(bar_src, "function persistSettings"))
check("a frame-rate or CLI change restarts only on the next turn, when the argv differs",
      "onFpsChanged: Qt.callLater(root.restartIfStale)" in preview
      and "onCliPathChanged: Qt.callLater(root.restartIfStale)" in preview
      and "JSON.stringify(Model.previewArgv(cliPath, fps)) !== JSON.stringify(lastArgv)" in block(preview, "function restartIfStale"))
check("a preview exit is a failure only while the preview is wanted",
      re.search(r"if \(!wanted\) \{[^}]*return\s*\}\s*failed = true", block(preview, "function previewEnded")) is not None)
check("the preview Image loads only while its own panel is open",
      re.search(r"^\s*source:\s*root\.opened && root\.preview\.mode === \"image\" \? Preview\.frameSource : \"\"\s*$", image_block, re.M) is not None,
      image_block[:300])
check("the preview Image decodes at most 480x270",
      re.search(r"^\s*sourceSize\.width:\s*480\s*$", image_block, re.M) is not None
      and re.search(r"^\s*sourceSize\.height:\s*270\s*$", image_block, re.M) is not None)
colour_literals = re.findall(r'(?:color|fill)\s*:[^\n]*"(#[0-9a-fA-F]{3,8}|[A-Za-z]+)"', panel)
check("the only hard-coded colour is black behind a frame",
      colour_literals == ["black"] and 'color: root.preview.mode === "image" ? "black" : root.hoverFill' in panel,
      str(colour_literals))
check("the preview rate uses the shell's ButtonGroup, driven by the panel cursor",
      re.search(r'ButtonGroup \{\s*id: fpsChoices[^}]*focusable: false[^}]*cursorIndex: root\.hasCursor\("fps", -1\) \? root\.fpsCursor : -1',
                panel) is not None)

# ---- pending re-arm through Qt.callLater (rule 8) ---------------------------
check("command retry deferred with Qt.callLater", "Qt.callLater(root.flushPending)" in daemon_src)
check("watch re-arm deferred with Qt.callLater", "Qt.callLater(root.syncWatch)" in daemon_src)

print("ALL OK" if not failures else f"{len(failures)} FAILED")
sys.exit(1 if failures else 0)
