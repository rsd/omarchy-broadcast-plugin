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
  - no effect is named: no list of effect words, no `effect` or `denoise`
    command; the background effect's choice is written as its setting
    (Daemon.commitSetting with the row's id and one of its options, from
    Model.effectModeView), and the Effect tab needs interface revision 9;
  - the effect chips carry the shell ButtonGroup's fill and fade from
    Model's `faded`; the image gate reads the raw image field, and the shown
    path sits in a left-to-right Unicode isolate;
  - the preview: one Process, in the Preview singleton, armed with an argv
    from Model.previewArgv (15 or 30 only), read in line mode with the line
    cap that stops it, no Timer anywhere in its path, re-armed through
    Qt.callLater; the Image is never cached and its source comes from
    Model.previewSource (the validated path); no video device and no D-Bus
    tool named anywhere; preview preferences written only from the panel's
    two user actions, through Model.settingsEntry;
  - the camera settings: a write reaches the command line only through an
    intent re-checked when it runs (Daemon.flushSettings, runSettingAction,
    resetSettings -> Model.settingIntentArgv / resetSettingsArgv): the
    camera of the set the row showed in its own `--camera=` element, then
    `--`, then the id (its grammar) and the value (one of the row's, as a
    checked word); bound to that camera (Model.settingIntentBound) and
    dropped from the queue when the set changes camera; queued writes
    coalesce per id through Model.enqueueIntent; the write debounce is the
    Daemon's one one-shot Timer, restarted only by a user's move, and the
    panel has no Timer; the renderer (SettingsView.qml) names no setting
    (no string literal of the id grammar in any QML file), its repeaters
    have count models (a delta never rebuilds the row being dragged), it
    uses the shell's PanelSlider and hands no daemon text to
    PanelActionButton or PanelToolTip; both Flickables let go of a held
    slider; the set's lines, options and changes are capped before they are
    walked;
  - the bar clicks, through Model.clickAction: left opens and closes the
    panel, middle turns the camera on or off through Model.middleClickAction
    (its guards, with Daemon.toggleBusy: slider writes never hold it), right
    opens the setup dialog through the shell's toggle with
    Model.setupPayloadJson, after closing the open panels;
  - the setup dialog: an overlay entry point of the manifest (kept loaded);
    open() reads its payload only through Model.setupPayload and forwards
    anything but the setup view to Daemon.openPanel; `opened` covers the
    panels too, close() closes them; its reads are fixed argv
    (Model.setupReadArgv) on one more Process of the Daemon, stdout in line
    mode and bounded, stderr chunked; its writes are setup intents of the
    command queue (Daemon.setModuleEnabled, moveStage, resetOrder,
    setConfig), each word checked again when it runs (Model.setupIntentArgv),
    a config value after `--`, a stage move only one the daemon offered
    (Model.orderAfterMove);
  - the panel tab: a stored `panelTab` is read only through
    Model.panelTabValue (anything but a word of Model.PANEL_TABS reads as the
    default), written only by the panel's chooseTab as a word of
    Model.PANEL_TABS through Model.settingsEntry, and the manifest's enum
    options are exactly Model.PANEL_TABS (three: the Status tab is the
    header's Details view, drawn only while open, with Copy through a
    read-only text edit); each tab page is drawn only for its own word; the
    card is Model.panelLayout's width (920 for two columns, 520 for one, from
    the `narrowPanel` setting and the user's preview switch, never the
    preview's placeholder) and as tall as its content,
    capped at 860 and by the screen; past it only the body (one Flickable,
    none in the renderer) scrolls;
  - the visibility rule: `enabled` is the daemon's word; `enabled_when` and
    `disabled_kind` are read for layout only (settingPlacement, rowMaster),
    never to decide a row's `enabled` or a write;
  - the plugin's version in Model.PLUGIN_VERSION is the manifest's;
  - the battery saver: the panel's switch and its Mode dropdown are drawn
    from Model.batterySaverView only, the panel holds the configuration read
    only while it is open (Daemon.holdConfig/releaseConfig), writes the row
    only through Daemon.setConfig of the word that view chose (the switch)
    or Model.batterySaverModeChoice checked against it (the dropdown), and
    stores the mode it remembers (`batterySaverMode`) only as a word of
    Model.BATTERY_SAVER_MODES, read back only through
    Model.batterySaverModeValue against the daemon's record;
  - the microphone: the Mic tab is drawn from Model.micView and
    Model.micSettingsView only (the groups of surface "mic", routed in
    Model by the group's surface, never by an id), its switch runs only
    `mic on|off` (Model.micHostArgv, fixed words) as an intent of the queue
    from Daemon.setMicHost, a microphone setting is written as a global one
    after `--` with its own word grammar (Model.settingArgvMic), and the
    bar's microphone glyph follows Model.micIndicator, a pure function of
    the watch's record (no timer, no other process);
  - the background gallery (interface revision 15): the Gallery... and
    Add... flows run on one more Process of the Daemon (mediaProc), each step
    an argv of Model.mediaStepArgv only, stdout in line mode (the list's
    lines LINE_CAP each and counted, a picker's first line only, capped),
    stderr chunked, every step bounded by a watchdog Timer; the two tools
    are looked up with a fixed script (Model.toolsArgv) whose tool names are
    positional arguments, never script text; a picked path is used only when
    it is exactly the path of an item of the gallery just read
    (Model.galleryChoice), and goes on as an intent of the command queue
    (`effect replace --image PATH`, `media import background PATH --select`);
    the dialog's Remove is a setup intent for a user item of the read gallery
    only (Daemon.removeMedia, Model.mediaUserItem); the thumbnail
    (MediaThumbnail, drawn by the panel's Background row and the dialog's
    Away image row) is the plugin's second Image, its source only
    Model.mediaImageSource of a checked path;
  - the away image (interface revision 17): the dialog's Choose... and Add...
    are the same flows over the `away` gallery, ending in setup intents
    (`config set -- effect.fallback_image PATH`, `media import away PATH
    --select`, each re-checked when it runs); Clear writes the empty value;
    the overlay hides while a flow runs;
  - the camera's health (interface revision 20): drawn only from
    Model.healthView, only for the active camera; a suggestion's button
    writes its setting as a row's (Daemon.commitSetting, a global row Model
    matched it to), and Use recommended settings runs only `recommended
    apply` (fixed words) as an intent of the queue, re-checked when it runs
    against the camera whose changes were listed; its lists are capped, and
    the suggestions past the first and the changes fold (healthView), so
    opening or folding them writes nothing.

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
# The plugin is the repository root, so the directory name is the checkout's;
# the id is what the shell installs it under.
check("manifest id is the plugin id", manifest.get("id") == "br.com.dias.omarchy-broadcast",
      f"id {manifest.get('id')!r}")
check("entry point is BarWidget.qml", manifest.get("entryPoints", {}).get("barWidget") == "BarWidget.qml")
check("allowMultiple is false", manifest.get("barWidget", {}).get("allowMultiple") is False)
schema = manifest.get("barWidget", {}).get("schema", [])
schema_keys = [s.get("key") for s in schema]
check("settings: cliPath, previewEnabled, previewFps, panelTab, batterySaverMode, narrowPanel",
      schema_keys == ["cliPath", "previewEnabled", "previewFps", "panelTab", "batterySaverMode", "narrowPanel"], str(schema_keys))
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
check("narrowPanel is a boolean, default false, read only through Model.narrowPanelValue (a real true)",
      by_key.get("narrowPanel", {}).get("type") == "boolean" and by_key["narrowPanel"].get("defaultValue") is False
      and defaults.get("narrowPanel") is False
      and re.search(r'function narrowPanelValue\(value\)\s*\{\s*return value === true\s*\}', (PLUGIN / "Model.js").read_text(encoding="utf-8")) is not None,
      str(by_key.get("narrowPanel")))
_version = re.search(r'^var PLUGIN_VERSION = "([^"]+)"$', (PLUGIN / "Model.js").read_text(encoding="utf-8"), re.M)
check("Model.PLUGIN_VERSION (the Details view's) is the manifest's version",
      _version is not None and _version.group(1) == manifest.get("version"), f"{_version.group(1) if _version else None} vs {manifest.get('version')}")
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

bs_schema = by_key.get("batterySaverMode", {})
bs_match = re.search(r'^var BATTERY_SAVER_MODES = (\[[^\]]*\])$', model_src, re.M)
bs_modes = json.loads(bs_match.group(1)) if bs_match else None
bs_default = re.search(r'^var BATTERY_SAVER_MODE_DEFAULT = "(\w+)"$', model_src, re.M)
check("batterySaverMode is an enum of exactly Model.BATTERY_SAVER_MODES, default Model.BATTERY_SAVER_MODE_DEFAULT (the first, never off)",
      bs_schema.get("type") == "enum" and bs_modes is not None and bs_schema.get("options") == bs_modes and "off" not in bs_modes
      and bs_default is not None and bs_default.group(1) == bs_modes[0]
      and bs_schema.get("defaultValue") == bs_modes[0] and defaults.get("batterySaverMode") == bs_modes[0],
      f"{bs_schema} vs {bs_modes}")

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
        # SettingsView's slider gives back the panel's held count when it
        # is destroyed mid-drag: a registration handed back, nothing stopped.
        allowed = r"Daemon\.detach\(\s*root\s*\)|Preview\.release\(\s*root\s*\)|Daemon\.releaseConfig\(\s*root\s*\)"
        if path.name == "SettingsView.qml":
            allowed += r"|if \(dragging\) root\.heldChanged\(-1\)"
        only_detach = all(re.fullmatch(allowed, s) for s in statements)
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

# The only `sh -c` are the resolver and the gallery tools' lookup: fixed
# scripts that look on PATH only.
sh_uses = [p.name for p, s in everything.items() if '"sh", "-c"' in s]
check("sh -c only in Model.resolverArgv and Model.toolsArgv", sh_uses == ["Model.js"], str(sh_uses))
model = js_sources[PLUGIN / "Model.js"]
check("resolver argv is the fixed script", 'return ["sh", "-c", RESOLVER_SCRIPT, "omarchy-broadcast-resolve"]' in model)
check("the tools lookup is a fixed script, its tool names positional arguments, and the only other sh -c",
      'return ["sh", "-c", TOOLS_SCRIPT, "omarchy-broadcast-tools", GALLERY_TOOL, CHOOSER_TOOL]' in model
      and model.count('"sh", "-c"') == 2
      and re.search(r'var TOOLS_SCRIPT = ""\n(\s*\+ "[^"\n]*(\\"[^"\n]*)*"\n)+', model) is not None
      and "GALLERY_TOOL" not in model[model.find("var TOOLS_SCRIPT"):model.find("function toolsArgv")]
      and '"for t do "' in model)
check("no development-build fallback", "target/release" not in model and "development" not in everything[PLUGIN / "Daemon.qml"])


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
check("no effect vocabulary: no effect words, no `effect` or `denoise` command, no legacy setting ids",
      re.search(r"\bEFFECTS\b", model + daemon) is None
      and all(n not in model + daemon for n in ("effectArgv", "denoiseArgv", "DENOISE_WORDS", "setEffect", "setDenoise",
                                            '"effect", effect', '"denoise"', "LEGACY_", "effectKey", "cliEffects"))
      and re.search(r'case "(effect|denoise)":', model) is None)
check("the Effect tab draws from the schema only from interface revision 9",
      "if (!moduleEffects(record)) { out.hint = DAEMON_NO_EFFECTS; return out }" in block(model, "function effectModeView")
      and "if (!moduleEffects(record) || !settingsSupported(record) || !isPlainObject(record.settings)) return out" in block(model, "function effectSettingsView")
      and "record.interfaceRevision >= MODULES_REVISION" in block(model, "function moduleEffects"))
check("queued commands are intents re-checked when armed",
      "pendingIntents" in daemon and "pendingArgv" not in daemon and "Model.intentArgv(intent, cliPath, record)" in block(daemon, "function armCommand"))
check("the queue changes only through Model.enqueueIntent (coalescing) and flushPending",
      re.findall(r"pendingIntents\s*=\s*([^\n]*)", daemon)
      == ["Model.dropSettingIntents(pendingIntents)", "Model.enqueueIntent(pendingIntents, intent)", "pendingIntents.slice(1)"]
      and ".push(" not in block(daemon, "function request"), str(re.findall(r"pendingIntents\s*=\s*([^\n]*)", daemon)))

panel = sources[PLUGIN / "BroadcastPanel.qml"]
bar_src = sources[PLUGIN / "BarWidget.qml"]
for name, src in ((p.name, sources[p]) for p in plugin_qml):
    check(f"{name}: no containsMouse-driven colour",
          re.search(r"(color|border\.color|fill)\s*:[^\n]*containsMouse", src) is None)
check("the panel writes the effect choice as its setting, from the row's own options",
      "var row = root.effectMode" in block(panel, "function chooseEffect")
      and "return Daemon.commitSetting(row.id, option.value)" in block(panel, "function chooseEffect")
      and "if (!option || option.selected || !row.enabled || !root.available) return false" in block(panel, "function chooseEffect")
      and "readonly property var effectMode: Model.effectModeView(record, Daemon.settingDrafts)" in panel
      and re.search(r"id: effectRepeater\s*objectName: \"effectRepeater\"\s*model: root\.effectMode\.options", panel) is not None)
effect_chips = block(panel, "id: effectRepeater")
check("effect chips have the ButtonGroup fill (Commons.Color.background)",
      re.search(r"^\s*background:\s*Commons\.Color\.background\s*$", effect_chips, re.M) is not None, effect_chips[:200])
check("effect chips fade from Model's `faded`, not a local rule",
      re.search(r"opacity:\s*modelData\.faded \? 0\.45 : 1\.0", effect_chips) is not None)
check("the effect hint is the daemon's reason or the view's hint, plain text",
      re.search(r'objectName: "effectHint"\s*textFormat: Text\.PlainText[^}]*text: root\.effectMode\.visible \? root\.effectMode\.reason : root\.effectMode\.hint', panel) is not None)
check("the image path is isolated (LRI U+2066 ... PDI U+2069) after sanitising",
      'return "\\u2066" + record.backgroundImage + "\\u2069"' in model)
check("the image gate reads the raw field, not the display copy",
      re.search(r"function hasBackgroundImage\(record\)\s*\{\s*return !!record && record\.backgroundImageSet === true\s*\}", model) is not None)
check("the camera is chosen from one dropdown of Model.cameraPickerView, its choice through Model.cameraChoice",
      "readonly property var cameraPicker: Model.cameraPickerView(record)" in panel
      and "options: root.cameraPicker.options" in panel[panel.find("id: cameraDropdown"):panel.find("onPopupOpenChanged", panel.find("id: cameraDropdown"))]
      and "root.chooseCamera(value)" in panel[panel.find("id: cameraDropdown"):panel.find("onPopupOpenChanged", panel.find("id: cameraDropdown"))]
      and "var id = Model.cameraChoice(root.record, value)" in block(panel, "function chooseCamera")
      and re.findall(r"Daemon\.selectCamera\(([^)]*)\)", panel) == ["id"]
      and "Daemon.nextCamera" not in panel)
check("the panel's body scrolls (one Flickable), the renderer has none",
      panel.count("Flickable {") == 1 and "Flickable" not in sources[PLUGIN / "SettingsView.qml"]
      and re.search(r'Flickable \{\s*id: bodyFlick\s*objectName: "panelFlick"', panel) is not None)
check("the card is Model.panelLayout's width (920 two columns, 520 one) and as tall as its content, capped at 860 and by the screen",
      "contentWidth: panel.fittedContentWidth(Style.space(root.layout.width))" in sources[PLUGIN / "BarWidget.qml"]
      and "contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(Model.PANEL_HEIGHT_CAP))" in sources[PLUGIN / "BarWidget.qml"]
      and re.search(r"readonly property var layout: Model\.panelLayout\(storedNarrow, Preview\.switchOn,\s*Model\.previewControlsShown\(Daemon\.record, Preview\.pathReason\)\)",
                    sources[PLUGIN / "BarWidget.qml"]) is not None
      and "placeholder" not in block(model, "function panelLayout")
      and 'readonly property bool storedNarrow: Model.narrowPanelValue(Model.settingValue(settings, "narrowPanel"))' in sources[PLUGIN / "BarWidget.qml"]
      and "var PANEL_WIDE_WIDTH = 920" in model and "var PANEL_NARROW_WIDTH = 520" in model and "var PANEL_HEIGHT_CAP = 860" in model
      and "return { wide: wide, width: wide ? PANEL_WIDE_WIDTH : PANEL_NARROW_WIDTH }" in block(model, "function panelLayout"))
check("no stale reference to check-source.sh (comments included)",
      all("check-source.sh" not in p.read_text(encoding="utf-8") for p in list(everything) + [PLUGIN / "manifest.json"]))

# ---- camera settings ----------------------------------------------------------
settings_view = sources[PLUGIN / "SettingsView.qml"]
check("settingArgv: the camera in --camera=, then --, then the id and the value, each checked",
      re.search(r'function settingArgv\(cli, camera, id, word\)\s*\{\s*var cam = selectableId\(camera\)\s*'
                r'if \(!cliUsable\(cli\) \|\| cam === "" \|\| settingId\(id\) === "" \|\| typeof word !== "string" \|\| !SETTING_VALUE_RE\.test\(word\)\)\s*'
                r'return null\s*return \[cli, "settings", "set", "--camera=" \+ cam, "--", id, word\]', model) is not None
      and 'var SETTING_VALUE_RE = /^(-?[0-9]{1,10}|true|false|[a-z0-9_@/]{1,32})$/' in model
      and 'var SETTING_ID_RE = /^[a-z0-9]+(\\.[a-z0-9_]+){1,3}$/' in model)
check("a reset is the constant `settings reset` with the checked camera",
      re.search(r'function resetSettingsArgv\(cli, camera\)\s*\{\s*var cam = selectableId\(camera\)\s*'
                r'return cliUsable\(cli\) && cam !== "" \? \[cli, "settings", "reset", "--camera=" \+ cam\] : null\s*\}', model) is not None)
check("a value is written only as a word of its row's type (Model.settingArgvValue)",
      all(t in block(model, "function settingArgvValue") for t in (
          'var v = settingInt(snapSetting(row, value))', 'return v === null ? null : String(v)',
          'return typeof value === "boolean" ? (value ? "true" : "false") : null',
          'return typeof value === "string" && optionIndex(row.options, value) >= 0 ? value : null',
          'return value === true ? "true" : null')))
check("setting intents run only while offered, bound to the set's camera, on an enabled row",
      'case "setting": return settingIntentArgv(cli, record, intent)' in model
      and 'case "reset-settings": return settingsSupported(record) && settingIntentBound(intent, record) ? resetSettingsArgv(cli, record.settings.camera) : null' in model
      and "intent.camera === record.settings.camera" in block(model, "function settingIntentBound")
      and all(t in block(model, "function settingIntentArgv") for t in (
          "if (!settingsSupported(record)) return null",
          'if (row.scope !== "global" && !settingIntentBound(intent, record)) return null',
          "if (!row || !row.enabled) return null", "var word = settingArgvValue(row, intent.value)",
          "settingArgv(cli, record.settings.camera, row.id, word)",
          "settingArgvGlobal(cli, row.id, word)")))
check("a global setting is written as `settings set -- ID VALUE`, the id and the value checked, no camera named",
      re.search(r'function settingArgvGlobal\(cli, id, word\)\s*\{\s*'
                r'if \(!cliUsable\(cli\) \|\| settingId\(id\) === "" \|\| typeof word !== "string" \|\| !SETTING_VALUE_RE\.test\(word\)\)\s*'
                r'return null\s*return \[cli, "settings", "set", "--", id, word\]', model) is not None)
# The Effect tab now also draws the rows whose rule names the choice under
# it (effectSettingsView's `follows`), and lists the choice in "Not available
# now" when it cannot run: still the one setting named.
check("Model.js names one setting, the background effect's choice: its row, and the Effect tab's rows that follow it",
      'var EFFECT_MODE_SETTING = "effect.background.mode"' in model
      and model.count("EFFECT_MODE_SETTING") == 5
      and block(model, "function effectSettingsView").count("EFFECT_MODE_SETTING") == 3
      and "var follows = function(row) { return rowMaster(row) === EFFECT_MODE_SETTING }" in block(model, "function effectSettingsView")
      and "findSetting(record, EFFECT_MODE_SETTING)" in block(model, "function effectModeRow")
      and [x for x in re.findall(r"[a-z0-9]+\.[a-z0-9_]+\.[a-z0-9_]+", " ".join(re.findall(r'"([^"\n]*)"', model)))
           if x != manifest.get("version")] == ["effect.background.mode"])
check("a change of the set's camera drops the queued setting writes; cameras compared raw",
      'if ((after ? after.camera : "") !== (before ? before.camera : "")) dropQueuedSettings()' in block(daemon, "function ingest")
      and "var before = record.settings" in block(daemon, "function ingest")
      and "var camera = m.camera" in block(model, "function settingsGroupLine")
      and 'typeof m.camera !== "string"' in block(model, "function settingsGroupLine"))
check("Daemon requests settings only as intents from flushSettings, runSettingAction and resetSettings",
      re.findall(r'request\(\{ verb: "(setting|reset-settings)"[^)]*\)', daemon) == ["setting", "reset-settings"]
      and 'var intent = { verb: "setting", id: id, value: v, camera: camera }' in block(daemon, "function flushSettings")
      and "if (request(intent))" in block(daemon, "function flushSettings")
      and 'request({ verb: "setting", id: row.id, value: true, camera: record.settings.camera, quick: true })' in block(daemon, "function runSettingAction")
      and 'request({ verb: "reset-settings", camera: record.settings.camera })' in block(daemon, "function resetSettings"))
check("flushSettings walks only the drafts, bounded by Model.withSetting",
      'var drafts = Model.withSetting(settingDrafts, "", undefined)' in block(daemon, "function flushSettings")
      and "if (n >= SETTINGS_ROW_CAP) break" in block(model, "function withSetting"))
check("a move is made a value of its enabled row before it is kept",
      "var v = row && row.enabled ? Model.rowValue(row, value) : null" in block(daemon, "function moveSetting"))
timers = re.findall(r"property Timer (\w+): Timer \{", daemon)
check("the Daemon's timers are the backoff, the settings debounce, the microphone switch's bounded wait and the gallery step's watchdog",
      sorted(timers) == ["backoffTimer", "mediaWatchdog", "micWaitTimer", "settingsTimer"], str(timers))
media_timer = block(daemon, "property Timer mediaWatchdog")
check("the gallery watchdog is a one-shot, (re)started only by startMediaStep and stopped when a step ends",
      "repeat: false" in media_timer and "onTriggered: root.mediaTimeout()" in media_timer
      and re.findall(r"mediaWatchdog\.(\w+)\(", daemon) == ["restart", "stop"])
mic_timer = block(daemon, "property Timer micWaitTimer")
check("the microphone switch's wait is a one-shot of Model.MIC_SWITCH_WAIT_MS, started only when a mic on/off command ended",
      re.search(r"^\s*repeat:\s*false\s*$", mic_timer, re.M) is not None
      and "interval: Model.MIC_SWITCH_WAIT_MS" in mic_timer and "running:" not in mic_timer
      and "triggeredOnStart" not in mic_timer and "var MIC_SWITCH_WAIT_MS = 3000" in model
      and re.findall(r"micWaitTimer\.(start|restart)\(\)", daemon) == ["restart"]
      and "micWaitTimer.restart()" in block(daemon, "function commandEnded"), mic_timer[:200])
settings_timer = block(daemon, "property Timer settingsTimer")
check("the settings debounce is a one-shot of Model.CONTROLS_DEBOUNCE_MS",
      re.search(r"^\s*repeat:\s*false\s*$", settings_timer, re.M) is not None
      and "interval: Model.CONTROLS_DEBOUNCE_MS" in settings_timer and "running:" not in settings_timer
      and "triggeredOnStart" not in settings_timer and "var CONTROLS_DEBOUNCE_MS = 150" in model, settings_timer[:200])
check("the settings debounce is (re)started only by moveSetting, a user's move",
      re.findall(r"settingsTimer\.(start|restart)\(\)", daemon) == ["restart"]
      and "settingsTimer.restart()" in block(daemon, "function moveSetting"))
check("no Timer in the panel or the renderer", all(re.search(r"\bTimer\b", sources[PLUGIN / n]) is None
                                                   for n in ("BroadcastPanel.qml", "SettingsView.qml")))
qml_writes = re.findall(r"Daemon\.(?:moveSetting|commitSetting|runSettingAction)\(([^,)]*)", panel + settings_view)
check("QML writes a setting only by the id of a row of the view (or of a suggestion Model matched to one)",
      qml_writes != [] and all(w in ("row.id", "settingRow.row.id", "s.setting") for w in qml_writes)
      and qml_writes.count("s.setting") == 1
      and "Daemon.commitSetting(s.setting, s.value)" in block(panel, "function applySuggestion")
      and "var s = root.health.suggestions[index]" in block(panel, "function applySuggestion")
      and "setting: row.id" in block(model, "function healthView")
      and "var row = Model.viewRow(root.activeView, stop)" in block(panel, "function nudgeSetting"), str(qml_writes))
literals = [(p.name, lit) for p in plugin_qml for lit in re.findall(r'"([^"\n]*)"', sources[p])]
named = [x for x in literals if re.fullmatch(r"[a-z0-9]+(\.[a-z0-9_]+){1,3}", x[1]) or "camera." in x[1]]
check("no QML file names a setting (no string literal of the id grammar)", named == [], str(named))
check("the panel resets the settings only from resetSettings",
      panel.count("Daemon.resetSettings()") == 1 and "Daemon.resetSettings()" in block(panel, "function resetSettings")
      and "Daemon.resetSettings" not in settings_view)
check("the renderer's repeaters have count models (a delta never rebuilds a row)",
      re.findall(r"^\s*model:\s*([^\n]+)$", settings_view, re.M) == ["root.view.groups.length", "groupBlock.group.rows.length",
                                                                   "root.notAvailable.open ? root.notAvailable.entries.length : 0"],
      str(re.findall(r"^\s*model:\s*([^\n]+)$", settings_view, re.M)))
check("the sliders are the shell's PanelSlider, integer, only in the renderer",
      sum(len(re.findall(r"\bPanelSlider\s*\{", sources[p])) for p in plugin_qml) == 1
      and len(re.findall(r"\bPanelSlider\s*\{", settings_view)) == 1
      and re.search(r"^\s*integer:\s*true\s*$", block(settings_view, "PanelSlider {"), re.M) is not None)
check("the renderer hands no daemon text to PanelActionButton or PanelToolTip",
      "PanelActionButton" not in settings_view and "PanelToolTip" not in settings_view
      and all(re.search(r"\bsettingText\(" + f, model) for f in (r"o\.label", r"s\.label", r"s\.disabled_reason", r"s\.unit", r"g\.label", r"c\.disabled_reason")))
check("a held slider keeps the body (the one Flickable) from taking the drag",
      panel.count("interactive: contentHeight > height + 0.5 && root.slidersHeld === 0") == 1
      and "interactive:" not in block(settings_view, "PanelSlider {")
      and panel.count("onHeldChanged: function(delta) { root.slidersHeld = Math.max(0, root.slidersHeld + delta) }") == 3
      and settings_view.count("root.heldChanged(") == 2)
check("the settings section is drawn only from Model.settingsView",
      "readonly property var settingsView: Model.settingsView(record, settingsOpen, Daemon.settingDrafts)" in panel
      and re.search(r'objectName: "settingsArea"[^}]*visible: root\.settingsView\.visible \|\| root\.recommendedShown\n', panel) is not None
      and "view: root.settingsView" in panel
      and "readonly property var effectSettings: Model.effectSettingsView(record, Daemon.settingDrafts)" in panel
      and "readonly property var stops: Model.cursorStops(record, {" in panel
      and "settings: settingsView, effectSettings: effectSettings, micSettings: micSettings, health: health, batterySaver: batterySaver," in panel
      and re.search(r'objectName: "effectSettingsArea"[^}]*visible: root\.effectSettings\.visible', panel) is not None
      and "view: root.effectSettings" in panel)
check("the set's lines, options and changes are capped before they are walked",
      "var n = Math.min(src.length, SETTINGS_LINE_LOOK)" in block(model, "function settingsGroupLine")
      and "var n = Math.min(changes.length, SETTINGS_LINE_LOOK)" in block(model, "function settingsDelta")
      and "var n = Math.min(src.length, SETTING_OPTION_CAP)" in block(model, "function settingOptions")
      and "var count = lineIndex(m.count, 1, SETTINGS_LINES_CAP)" in block(model, "function settingsGroupLine"))
check("the revision-6 controls code is gone (no fallback below 0.22)",
      all(n not in model + daemon + panel for n in ("CONTROL_NAMES", "controlArgv", "controlsSection", "camera_controls", '"controls"')))

# ---- the microphone -------------------------------------------------------------
check("the Mic tab is drawn only from Model.micView and Model.micSettingsView",
      "readonly property var micView: Model.micView(record)" in panel
      and "readonly property var micSettings: Model.micSettingsView(record, Daemon.settingDrafts)" in panel
      and "view: root.micSettings" in panel
      and re.search(r'objectName: "micSettingsArea"[^}]*visible: root\.micSettings\.visible', panel) is not None
      and 'readonly property var activeView: tab === "effect" ? effectSettings : (tab === "mic" ? micSettings : settingsView)' in panel)
check("the mic groups are routed by the group's surface, only for global settings",
      re.search(r'function groupSurface\(g, scope\)\s*\{\s*return scope === "global" && isPlainObject\(g\) && g\.surface === MIC_SURFACE \? MIC_SURFACE : ""\s*\}', model) is not None
      and 'var MIC_SURFACE = "mic"' in model
      and "if (set.groups[a].scope === \"global\" && set.groups[a].surface !== MIC_SURFACE) effectGroups.push(set.groups[a])" in block(model, "function effectSettingsView")
      and "if (group.surface !== MIC_SURFACE) continue" in block(model, "function micSettingsView"))
check("the microphone's switch runs only `mic on|off`, as an intent from Daemon.setMicHost",
      re.search(r'function micHostArgv\(cli, on\)\s*\{\s*return cliUsable\(cli\) && typeof on === "boolean" \? \[cli, "mic", on \? "on" : "off"\] : null\s*\}', model) is not None
      and 'case "mic-host": return micSupported(record) ? micHostArgv(cli, intent.on === true) : null' in model
      and re.findall(r'request\(\{ verb: "mic-host"[^)]*\)', daemon) == ['request({ verb: "mic-host", on: on === true })']
      and "request({ verb: \"mic-host\", on: on === true })" in block(daemon, "function setMicHost")
      and "if (micBusy || !Model.micSupported(record)) return false" in block(daemon, "function setMicHost")
      and "Daemon.setMicHost(!root.micView.hostOn)" in block(panel, "function toggleMic")
      and "if (!root.available || !root.micView.visible || Daemon.micBusy) return false" in block(panel, "function toggleMic")
      and re.search(r'objectName: "micSwitch"[^}]*busy: Daemon\.micBusy', panel) is not None)
check("a microphone setting is written as `settings set -- ID VALUE`, its word of the mic grammar",
      re.search(r'function settingArgvMic\(cli, id, word\)\s*\{\s*'
                r'if \(!cliUsable\(cli\) \|\| settingId\(id\) === "" \|\| typeof word !== "string" \|\| !MIC_SETTING_VALUE_RE\.test\(word\)\)\s*'
                r'return null\s*return \[cli, "settings", "set", "--", id, word\]', model) is not None
      and "var MIC_SETTING_VALUE_RE = /^(-?[0-9]{1,10}|true|false|[A-Za-z0-9][A-Za-z0-9_.:@/+-]{0,127})$/" in model
      and "var MIC_OPTION_VALUE_RE = /^[A-Za-z0-9][A-Za-z0-9_.:@/+-]{0,127}$/" in model
      and "if (row.surface === MIC_SURFACE) return settingArgvMic(cli, row.id, word)" in block(model, "function settingIntentArgv"))
check("the bar's microphone glyph follows Model.micIndicator only; its clicks go through Model.micClickAction",
      "readonly property var micIndicator: Model.micIndicator(record)" in bar_src
      and re.search(r'id: micIcon\s*objectName: "micIndicator"\s*visible: root\.micIndicator\.visible', bar_src) is not None
      and "var action = Model.micClickAction(" in block(bar_src, "function pressMic")
      and "toggleCamera" not in block(bar_src, "function pressMic"))
check("the mic's on/off holds neither the camera's switch nor is held by it",
      "!isSettingIntent(intent) && !isSetupIntent(intent) && !isMicIntent(intent)" in block(model, "function toggleBlocked")
      and "readonly property bool micBusy: Model.micBlocked(runningIntent, pendingIntents) || micAwaiting !== null" in daemon)

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
check("two Images in the plugin: the preview and the gallery thumbnail (MediaThumbnail)",
      sum(len(re.findall(r"(?<![\w.])Image\s*\{", s)) for p, s in sources.items() if p.parent == PLUGIN) == 2)
_panel = sources[PLUGIN / "BroadcastPanel.qml"]
_thumb = sources[PLUGIN / "MediaThumbnail.qml"]
_at = _thumb.find("id: thumbImage")
thumb_block = _thumb[_at:_thumb.find("}", _at)] if _at >= 0 else ""
_dialog = sources[PLUGIN / "SetupDialog.qml"]
_dialog_thumbs = [block(_dialog[m.start():], "MediaThumbnail {") for m in re.finditer(r"(?<![\w.])MediaThumbnail\s*\{", _dialog)]
check("the thumbnails (MediaThumbnail: the panel's Background row, the dialog's Backgrounds rows and Away image row) read only"
      " the checked path's URL (a still's own, a video's poster from the cache), async, decoded at twice their size, only while shown",
      "source: root.source" in thumb_block
      and "asynchronous: true" in thumb_block and "sourceSize.width: root.width * 2" in thumb_block
      and "source: root.opened && root.backgroundRow.visible ? root.backgroundRow.source : \"\"" in block(_panel, "MediaThumbnail {")
      and len(_dialog_thumbs) == 2
      and "source: root.shown && root.section === \"backgrounds\" ? mediaRow.modelData.source : \"\"" in _dialog_thumbs[1]
      and "source: root.shown && awayLine.visible && root.awayView.visible ? root.awayView.source : \"\"" in _dialog_thumbs[0]
      and len(re.findall(r"(?<![\w.])MediaThumbnail\s*\{", _panel + _dialog)) == 3
      and "var thumb = mediaThumb(record.backgroundImagePath, media)" in block(model, "function backgroundRowView")
      and "out.source = thumb.source" in block(model, "function backgroundRowView")
      and "var thumb = mediaItemThumb(byPath[it.path], media.posterDir)" in block(model, "function mediaSectionView")
      and "if (out.rows.length >= MEDIA_ROW_CAP) continue" in block(model, "function mediaSectionView")
      and "return mediaItemThumb(it, media.posterDir)" in block(model, "function mediaThumb")
      and re.findall(r"source: (mediaImageSource\([^)]*\)+)", block(model, "function mediaThumb"))
          == ["mediaImageSource(p)"]
      and re.findall(r"source: (mediaImageSource\([^)]*\)+)", block(model, "function mediaItemThumb"))
          == ["mediaImageSource(it.path)", "mediaImageSource(mediaPoster(it.poster, posterDir))"]
      and 'if (root !== "") return parent === root ? p : ""' in block(model, "function mediaPoster")
      and 'parent.slice(-POSTER_DIR_SUFFIX.length) === POSTER_DIR_SUFFIX ? p : ""' in block(model, "function mediaPoster")
      and 'readonly property string posterDir: Model.posterDir(Quickshell.env("XDG_CACHE_HOME"), Quickshell.env("HOME"))' in sources[PLUGIN / "Daemon.qml"]
      and 'if (p === "" || !/\\.jpe?g$/i.test(p)) return ""' in block(model, "function mediaPoster")
      and 'var POSTER_DIR_SUFFIX = "/omarchy-broadcast/posters"' in model
      and "out.source = mediaImageSource(row.rawPath)" in block(model, "function awayImageView")
      and "if (s.type === \"path\") e.rawPath = mediaPath(s.value)" in block(model, "function configEntry")
      and 'return "file://" + p.split("/").map(function(seg) { return encodeURIComponent(seg) }).join("/")' in block(model, "function mediaImageSource"),
      thumb_block[:200])
for path, src in everything.items():
    raw = path.read_text(encoding="utf-8")
    check(f"{path.name}: no video device", "/dev/video" not in raw)
    check(f"{path.name}: no D-Bus tool", re.search(r"\b(busctl|gdbus|dbus-send|qdbus)\b", raw) is None)
check("preview holders are registered only by the widget, on open/close",
      re.findall(r"Preview\.(hold|release)\(([^)]*)\)", "\n".join(s for p, s in sources.items() if p.parent == PLUGIN))
      == [("hold", "root"), ("release", "root"), ("release", "root")])
check("panel preferences are requested only by togglePreview, chooseFps, chooseTab, toggleBatterySaver and chooseBatteryMode",
      re.findall(r"root\.settingsRequested\(([^)]*\))", panel)
      == ["{ previewEnabled: !Preview.switchOn })", "{ previewFps: option.value })", "{ panelTab: value })",
          "{ batterySaverMode: memory })", "{ batterySaverMode: word })"]
      and "root.settingsRequested(" not in panel.replace(block(panel, "function togglePreview"), "")
      .replace(block(panel, "function chooseFps"), "").replace(block(panel, "function chooseTab"), "")
      .replace(block(panel, "function toggleBatterySaver"), "").replace(block(panel, "function chooseBatteryMode"), ""),
      str(re.findall(r"root\.settingsRequested\(([^)]*\))", panel)))
check("the battery saver: the panel holds the configuration only while open, writes the row only through Daemon.setConfig of a word Model.batterySaverView chose, and the stored mode only as a word of BATTERY_SAVER_MODES",
      "if (root.opened) Daemon.holdConfig(root)" in block(panel, "function syncConfigHold")
      and "else Daemon.releaseConfig(root)" in block(panel, "function syncConfigHold")
      and "Daemon.setConfig(Model.BATTERY_SAVER_KEY, view.mode)" in block(panel, "function toggleBatterySaver")
      and "if (!root.available || !view.visible || view.mode === null) return false" in block(panel, "function toggleBatterySaver")
      and "var word = Model.batterySaverModeChoice(view, value)" in block(panel, "function chooseBatteryMode")
      and "if (!root.available || word === null || Daemon.setupBusy) return false" in block(panel, "function chooseBatteryMode")
      and "Daemon.setConfig(Model.BATTERY_SAVER_KEY, word)" in block(panel, "function chooseBatteryMode")
      and re.findall(r"Daemon\.setConfig\(([^)]*)\)", panel) == ["Model.BATTERY_SAVER_KEY, view.mode", "Model.BATTERY_SAVER_KEY, word"]
      and "if (value === view.modeValue || configOptionIndex(view.modes, value) < 0) return null" in block(model, "function batterySaverModeChoice")
      and "return BATTERY_SAVER_MODES.indexOf(value) >= 0 ? value : null" in block(model, "function batterySaverModeChoice")
      and "root.chooseBatteryMode(value)" in panel and panel.count("chooseBatteryMode(") == 2
      and re.findall(r"Daemon\.holdConfig\(([^)]*)\)", "\n".join(sources[p] for p in sources if p.parent == PLUGIN)) == ["root"]
      and "if (BATTERY_SAVER_MODES.indexOf(values.batterySaverMode) < 0) return null" in block(model, "function settingsEntry")
      and 'readonly property string storedBatteryMode: Model.batterySaverModeValue(Model.settingValue(settings, "batterySaverMode"), record)' in bar_src
      and "var remembered = batterySaverModeValue(stored, record)" in block(model, "function batterySaverView")
      and "return batterySaverSupported(record) ? [\"config\"] : []" in block(model, "function panelReads"))
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
for word, name in (("effect", "effectTab"), ("camera", "cameraTab"), ("mic", "micTab")):
    check(f"the {word} tab is drawn only while it is the tab shown (and the Details view is not)",
          re.search(r'objectName: "' + name + r'"[^}]*visible: root\.tab === "' + word + r'" && !root\.detailsOpen', panel) is not None)
check("the Status tab is gone: no `status` tab word; its rows are the Details view's (Model.detailsRows), drawn only while open",
      '"status"' not in re.search(r'^var PANEL_TABS = (\[[^\]]*\])$', model, re.M).group(1)
      and "statusRows" not in model + panel
      and "readonly property var detailsRows: Model.detailsRows(record)" in panel
      and re.search(r'objectName: "detailsView"[^}]*visible: root\.detailsOpen', panel) is not None)
check("Copy puts Model.detailsText on the clipboard through a read-only, plain-text TextEdit, only from copyDetails",
      "detailsCopy.text = Model.detailsText(root.detailsRows)" in block(panel, "function copyDetails")
      and "detailsCopy.copy()" in block(panel, "function copyDetails")
      and panel.count(".copy()") == 1
      and re.search(r"TextEdit \{\s*id: detailsCopy\s*objectName: \"detailsCopyText\"\s*textFormat: TextEdit\.PlainText[^}]*readOnly: true", panel) is not None)
check("enabled_when and disabled_kind are read for layout only: `enabled` is the daemon's, never the rule's",
      "enabled = s.enabled === true" in block(model, "function settingEntry")
      and re.findall(r"whenHolds\(", model) == ["whenHolds(", "whenHolds("]
      and "whenHolds(" in block(model, "function settingPlacement")
      and "when" not in block(model, "function settingIntentArgv")
      and "placement" not in block(model, "function settingIntentArgv").lower()
      and "kind" not in block(model, "function settingIntentArgv")
      and re.search(r"\.enabled\s*=\s*[^=\n]*(when|kind|placement)", model, re.I) is None)
check("the clicks go through Model.clickAction: middle toggles through Model.middleClickAction, right opens the setup, left the panel",
      re.search(r'var action = Model\.clickAction\(buttonCode === Qt\.MiddleButton \? "middle" : \(buttonCode === Qt\.RightButton \? "right" : "left"\),\s*'
                r'root\.record, Daemon\.toggleBusy\)\s*if \(action === "setup"\) root\.openSetup\(\)\s*'
                r'else if \(action === "panel"\) root\.toggle\(\)\s*else root\.toggleCamera\(\)', block(bar_src, "function press")) is not None
      and "var action = Model.middleClickAction(root.record, Daemon.toggleBusy)" in block(bar_src, "function toggleCamera")
      and "Model.middleClickAction(record, toggleBusy) !== \"toggle\"" in block(daemon, "function toggleEnabled")
      and "rightClickAction" not in model + daemon + bar_src
      and "readonly property bool toggleBusy: Model.toggleBlocked(runningIntent, pendingIntents)" in daemon
      and "if (!root.available || Daemon.toggleBusy) return false" in block(panel, "function toggleSwitch")
      and re.search(r'objectName: "enableSwitch"[^}]*busy: Daemon\.toggleBusy', panel) is not None
      and "leftClickAction" not in model)
check("settings are written only through Model.settingsEntry, by persistSettings",
      bar_src.count("updateEntryInline(") == 1 and "var entry = Model.settingsEntry(root.moduleName, root.settings, values)"
      in block(bar_src, "function persistSettings") and "updateEntryInline" in block(bar_src, "function persistSettings"))
check("a widget configures the preview only from onSettingsChanged, for the bar's hand-over only (never with the base's empty default)",
      re.findall(r"Preview\.configure\(([^)]*)\)", bar_src) == ["root, root.settings"]
      and re.search(r"onSettingsChanged:\s*if \(Model\.barHandOver\(root\.completed\)\) Preview\.configure\(root, root\.settings\)", bar_src) is not None
      and "return completed === true" in block(model, "function barHandOver")
      and "root.completed = true" in block(bar_src, "Component.onCompleted")
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

# ---- the setup dialog -----------------------------------------------------------
dialog = sources[PLUGIN / "SetupDialog.qml"]
check("the manifest adds the overlay kind, kept loaded, with SetupDialog.qml as its entry point",
      manifest.get("kinds") == ["bar-widget", "overlay"] and manifest.get("keepLoaded") is True
      and manifest.get("entryPoints") == {"barWidget": "BarWidget.qml", "overlay": "SetupDialog.qml"}, str(manifest.get("kinds")))
check("the right click opens the setup through the shell's toggle with the setup payload, after closing the panels"
      " (only once the shell has a toggle)",
      re.search(r"var shell = root\.bar \? root\.bar\.shell : null\s*"
                r'if \(!shell \|\| typeof shell\.toggle !== "function"\) return false\s*'
                r"Daemon\.closePanels\(\)\s*"
                r"return shell\.toggle\(root\.moduleName, Model\.setupPayloadJson\(focus\)\) === true",
                block(bar_src, "function openSetup")) is not None)
# shell.qml panelEntry onLoaded: `if ("<name>" in item) item.<name> = ...` for
# each of these; an assignment to a readonly one throws before the overlay is
# registered, and the overlay never opens.
loader_names = ("omarchyPath", "shell", "manifest", "barWidgetRegistry", "pluginRegistry", "service")
readonly_injected = [n for n in loader_names if re.search(r"readonly property \S+ " + n + r"\b", dialog)]
check("the setup dialog declares none of the names the shell's loader assigns as readonly, and no `service`",
      readonly_injected == [] and re.search(r"property \S+ service\b", dialog) is None
      and "property var shell: null" in dialog and "property var manifest: null" in dialog, str(readonly_injected))
check("the setup dialog's no-widget branch configures the Daemon with no program (`Daemon.configure(root, null)`), and nothing"
      " of the payload (a cliPath or cliSetting) reaches Daemon.configure",
      re.search(r"if \(Daemon\.attachedCount === 0\) \{\s*Daemon\.attach\(root\)\s*Daemon\.configure\(root, null\)\s*root\.attached = true\s*\}",
                block(dialog, "function open(payloadJson)")) is not None
      and re.findall(r"Daemon\.configure\(([^)]*)\)", dialog) == ["root, null"]
      and re.search(r"cliPath|cliSetting", dialog) is None, str(re.findall(r"Daemon\.configure\([^)]*\)", dialog)))
check("the overlay window has the plugin's layer-shell namespace",
      re.search(r'OverlayWindow \{\s*id: overlay\s*shown: root\.shown && !root\.suspended\s*WlrLayershell\.namespace: "omarchy-broadcast"', dialog) is not None
      and "readonly property bool suspended: Daemon.mediaBusy" in dialog
      and "import Quickshell.Wayland" in dialog)
check("the setup dialog's writes do not hold the on/off toggle",
      "!isSettingIntent(intent) && !isSetupIntent(intent)" in block(model, "function toggleBlocked"))
check("open() reads its payload through Model.setupPayload and forwards anything else to the panel",
      "var payload = Model.setupPayload(payloadJson)" in block(dialog, "function open(")
      and re.search(r'if \(payload\.view !== "setup"\) \{\s*hideDialog\(\)[^}]*Daemon\.openPanel\(', block(dialog, "function open(")) is not None
      and "readonly property bool opened: shown || Daemon.panelOpen" in dialog
      and "Daemon.closePanels()" in block(dialog, "function close()"))
check("the dialog holds the setup only while shown",
      "Daemon.holdSetup(root)" in block(dialog, "function open(") and "Daemon.releaseSetup(root)" in block(dialog, "function hideDialog"))
read_block = block(daemon, "property Process readProc")
check("the setup reads: fixed argv, stdout in line mode and bounded, stderr chunked",
      read_block != "" and re.search(r"stdout:\s*SplitParser\s*\{\s*onRead", read_block) is not None
      and re.search(r'stderr:\s*SplitParser\s*\{\s*splitMarker:\s*""', read_block) is not None
      and "var argv = Model.setupReadArgv(cliPath, kind)" in block(daemon, "function nextRead")
      and "line.length > Model.LINE_CAP" in block(daemon, "function readLine")
      and "readLines.length >= Model.readLinesCap(readKind)" in block(daemon, "function readLine")
      and 'return kind === "media" ? MEDIA_ITEM_CAP + 2 : READ_LINES_CAP' in block(model, "function readLinesCap")
      and all(w in block(model, "function setupReadArgv") for w in (
          'return [cli, "modules", "list", "--json"]', 'return [cli, "order", "show", "--json"]',
          'return [cli, "config", "show", "--json"]', 'return [cli, "config", "files", "--json"]',
          'if (kind === "media") return mediaListArgv(cli)'))
      and 'return cliUsable(cli) ? [cli, "media", "list", mediaKindOf(kind), "--json"] : null' in block(model, "function mediaListArgv")
      and 'return kind === AWAY_KIND ? AWAY_KIND : MEDIA_KIND' in block(model, "function mediaKindOf"))
setup_requests = re.findall(r'request\(\{ verb: "setup", op: "([a-z-]+)"', daemon)
check("setup writes are intents of the queue, from the six Daemon functions only (and a gallery flow's end)",
      setup_requests == ["module", "order", "order-reset", "config", "away-image", "media-remove"]
      and 'return request({ verb: "setup", op: "away-image", path: "" })' in block(daemon, "function clearAwayImage")
      and "var item = setupBusy ? null : Model.mediaUserItem(setup.media, path)" in block(daemon, "function removeMedia")
      and 'request({ verb: "setup", op: "module", id: m.id, on: on })' in block(daemon, "function setModuleEnabled")
      and "Model.orderAfterMove(setup.order, index, direction)" in block(daemon, "function moveStage")
      and "var word = row ? Model.configWord(row, value) : null" in block(daemon, "function setConfig")
      and 'case "setup": return setupIntentArgv(cli, record, intent)' in model, str(setup_requests))
check("a config value goes after `--`, key and word checked; a stage order is ids of the grammar, each once",
      re.search(r'function configSetArgv\(cli, key, word\)\s*\{\s*if \(!cliUsable\(cli\) \|\| configKeyOf\(key\) === "" \|\| typeof word !== "string" \|\| !CONFIG_WORD_RE\.test\(word\)\) return null\s*'
                r'return \[cli, "config", "set", "--", key, word\]', model) is not None
      and "if (stageIdOf(order[i]) === \"\" || seen[order[i]] === true) return null" in block(model, "function orderSetArgv")
      and "if (direction === -1 ? !st.up : !st.down) return null" in block(model, "function orderAfterMove"))
dialog_writes = re.findall(r"Daemon\.(setModuleEnabled|moveStage|resetOrder|setConfig|commitSetting|moveSetting|removeMedia)\(([^,)]*)", dialog)
check("the dialog writes only by ids (or gallery paths) of rows it was given",
      dialog_writes != [] and all(a in ("row.id", "configRow.row.id", "index", "", "row.path") for _, a in dialog_writes), str(dialog_writes))
media_block = block(daemon, "property Process mediaProc")
check("the gallery flows: one Process, argv of Model.mediaStepArgv only, stdout lines capped and counted (an import's counted only),"
      " stderr chunked, a watchdog (the import's too)",
      media_block != "" and re.search(r"stdout:\s*SplitParser\s*\{\s*onRead", media_block) is not None
      and re.search(r'stderr:\s*SplitParser\s*\{\s*splitMarker:\s*""', media_block) is not None
      and re.findall(r"mediaProc\.command\s*=\s*([^\n]*)", daemon) == ["argv"]
      and "var argv = Model.mediaStepArgv(flow, cliPath, mediaTools, Model.mediaCurrent(flow, record, setup.config), record)" in block(daemon, "function startMediaStep")
      and 'if (mediaFlow !== null && mediaFlow.step === "import") return' in block(daemon, "function mediaLine")
      and 'return flowGallery(flow) === MEDIA_KIND && backgroundRowShown(record) ? mediaImportArgv(cli, flow.path) : null' in block(model, "function mediaStepArgv")
      and 'else out.flow = { kind: "add", step: "import", path: picked, gallery: gallery }' in block(model, "function mediaStepEnd")
      and "if (!list && mediaLines > 1) return" in block(daemon, "function mediaLine")
      and "var cap = list ? Model.LINE_CAP : Model.PATH_CAP" in block(daemon, "function mediaLine")
      and 'mediaLines > Model.readLinesCap("media")' in block(daemon, "function mediaLine")
      and "mediaWatchdog.restart()" in block(daemon, "function startMediaStep")
      and "mediaWatchdog.stop()" in block(daemon, "function mediaEnded")
      and "var MEDIA_WATCHDOG_MS = 610000" in model
      and re.findall(r"toolsProc\.command\s*=\s*([^\n]*)", daemon) == ["Model.toolsArgv()"])
check("a picked path is used only when it is an item of the gallery just read, then queued as an intent",
      "var chosen = r.rejected === true ? \"\" : galleryChoice(first, lines, flow.media)" in block(model, "function mediaStepEnd")
      and "if (media.items[i].path === p) return p" in block(model, "function galleryChoice")
      and 'p.indexOf(d + "/") !== 0' in block(model, "function mediaInDir")
      and "if (end.intent !== null && !request(end.intent))" in block(daemon, "function mediaEnded")
      and 'return cliUsable(cli) && p !== "" ? [cli, "effect", BACKGROUND_REPLACE, "--image", p] : null' in block(model, "function backgroundArgv")
      and 'return cliUsable(cli) && p !== "" ? [cli, "media", "import", mediaKindOf(kind), p, "--select"] : null' in block(model, "function mediaImportArgv")
      and 'out.intent = away ? { verb: "setup", op: "away-image", path: chosen } : { verb: "background", path: chosen }' in block(model, "function mediaStepEnd")
      and 'var p = path === "" ? "" : mediaPath(path)' in block(model, "function awayImageArgv")
      and 'return path === "" || p !== "" ? [cli, "config", "set", "--", AWAY_IMAGE_KEY, p] : null' in block(model, "function awayImageArgv")
      and 'case "away-image": return placeholderSupported(record) ? awayImageArgv(cli, intent.path) : null' in block(model, "function setupIntentArgv")
      and 'case "away-import": return placeholderSupported(record) ? mediaImportArgv(cli, intent.path, AWAY_KIND) : null' in block(model, "function setupIntentArgv"))
check("the dialog names no command: every argv is the Model's",
      all(w not in dialog for w in ('"set"', '"--"', '"enable"', '"disable"', '"reset"', '"show"', '"list"', '"--json"')))

# ---- live stage values: one documented exception ----------------------------
# LIVE_GROUPS is the one place the plugin names a live stage value; a second
# entry is a deliberate decision that must change this rule too.
live_table = block(model, "var LIVE_GROUPS")
live_entries = re.findall(r"^\s*(\w+):\s*\{([^}]*)\}", live_table, re.M)
check("LIVE_GROUPS holds exactly the auto-frame zoom entry",
      len(live_entries) == 1 and live_entries[0][0] == "auto_frame"
      and re.fullmatch(r'\s*stage: "auto-frame", name: "zoom", label: zoomLabel\s*', live_entries[0][1]) is not None
      and len(re.findall(r"\bLIVE_GROUPS\b", model)) == 3, str(live_entries))

# ---- the camera's health (interface revision 20) ----------------------------
check("the camera's health is drawn only from Model.healthView, for the active camera",
      "readonly property var health: Model.healthView(record, healthOpen)" in panel
      and "readonly property var tabOptions: Model.panelTabOptions(tab, health)" in panel
      and "readonly property bool recommendedShown: Model.recommendedShown(health)" in panel
      and re.search(r'objectName: "healthBlock"[^}]*visible: root\.health\.visible\n', panel) is not None
      and re.search(r'objectName: "recommendedBlock"[^}]*visible: root\.recommendedShown\n', panel) is not None
      and "return h.camera !== \"\" && h.camera === record.activeCamera ? h : null" in block(model, "function shownHealth")
      and "var h = shownHealth(record)" in block(model, "function healthView"))
check("Use recommended settings runs only `recommended apply` from its click, re-checked when it runs",
      panel.count("Daemon.applyRecommended()") == 1 and "Daemon.applyRecommended()" in block(panel, "function applyRecommended")
      and "Daemon.applyRecommended" not in settings_view
      and 'return request({ verb: "recommended", camera: view.camera })' in block(daemon, "function applyRecommended")
      and 'return [cli, "recommended", "apply"]' in block(model, "function recommendedArgv")
      and "var h = shownHealth(record)" in block(model, "function recommendedArgv")
      and "h.camera !== intent.camera" in block(model, "function recommendedArgv")
      and 'case "recommended": return recommendedArgv(cli, record, intent)' in block(model, "function intentArgv"))
check("the health's suggestions and changes fold, drawn and walked from healthView alone (nothing written)",
      "model: root.health.shownSuggestions" in panel
      and "model: root.health.changes.open ? root.health.recommended.length : 0" in panel
      and "root.healthOpen = Model.healthOpenAfter(root.healthOpen, root.health, which)" in block(panel, "function toggleHealthList")
      and "Daemon." not in block(panel, "function toggleHealthList")
      and "Math.min(Number(health.shownSuggestions) || 0, hints.length)" in block(model, "function cursorStops"))
check("the health's lists are capped before they are walked",
      all(c in block(model, "function healthFields") for c in ("i < HEALTH_WARNINGS_CAP", "j < HEALTH_SUGGESTIONS_CAP", "k < HEALTH_RECOMMENDED_CAP")))

# ---- pending re-arm through Qt.callLater (rule 8) ---------------------------
check("command retry deferred with Qt.callLater", "Qt.callLater(root.flushPending)" in daemon_src)
check("watch re-arm deferred with Qt.callLater", "Qt.callLater(root.syncWatch)" in daemon_src)

print("ALL OK" if not failures else f"{len(failures)} FAILED")
sys.exit(1 if failures else 0)
