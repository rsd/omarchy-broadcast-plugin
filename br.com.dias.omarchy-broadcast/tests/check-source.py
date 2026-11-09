#!/usr/bin/env python3
"""Source-level invariants of the plugin, each one a bug class that a running
widget would hide.

  - every `Text {` sets `textFormat: Text.PlainText` (AutoText renders markup,
    and `<img src=...>` in a camera name would fetch a URL);
  - the qmldir declares the Daemon singleton (without it, `Daemon` is the
    component type and every read off it is undefined);
  - the manifest id equals the directory name (or the shell does not load it);
  - Component.onDestruction only hands back registrations: no stop, no
    `running = false`, no `off`, no `bar.run`, no pkill (it runs on every
    hot reload);
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
    and the shown path sits in a left-to-right Unicode isolate.

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
daemon_src = (PLUGIN / "Daemon.qml").read_text(encoding="utf-8")
check("Daemon.qml has pragma Singleton", "pragma Singleton" in daemon_src)
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
schema_keys = [s.get("key") for s in manifest.get("barWidget", {}).get("schema", [])]
check("one cliPath setting", schema_keys == ["cliPath"], str(schema_keys))

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
        only_detach = all(re.fullmatch(r"Daemon\.detach\(\s*root\s*\)", s) for s in statements)
        check(f"{path.name}: onDestruction only unregisters", only_detach and statements != [], body.strip())
        for bad in ("running", "stop", "\"off\"", "bar.run", "pkill", "kill", "signal("):
            check(f"{path.name}: onDestruction has no {bad}", bad not in body, body.strip())
check("the widget unregisters on destruction", len(all_bodies) >= 1, "no Component.onDestruction")

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
      "pendingIntent" in daemon and "pendingArgv" not in daemon and "Model.intentArgv(intent, cliPath, record)" in block(daemon, "function armCommand"))

panel = sources[PLUGIN / "BroadcastPanel.qml"]
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
check("effect hint and its command share one Column at Style.space(6)",
      re.match(r'\{\s*objectName:\s*"effectHintBlock"', hint_block) is not None
      and re.search(r"^ {12}spacing: Style\.space\(6\)$", hint_block, re.M) is not None
      and 'objectName: "effectHint"' in hint_block and 'objectName: "effectHintCommand"' in hint_block,
      hint_block[:200])
check("the image path is isolated (LRI U+2066 ... PDI U+2069) after sanitising",
      'return "\\u2066" + record.backgroundImage + "\\u2069"' in model)
check("the Replace gate reads the raw field, not the display copy",
      re.search(r"function hasBackgroundImage\(record\)\s*\{\s*return !!record && record\.backgroundImageSet === true\s*\}", model) is not None)
check("camera rows are CursorSurfaces", re.search(r"delegate:\s*CursorSurface\s*\{", panel) is not None)
check("the panel scrolls (Flickable)", "Flickable {" in panel)
check("the panel height is capped at Style.space(560)",
      "fittedContentHeight(panel.loadedContentHeight, Style.space(560))" in sources[PLUGIN / "BarWidget.qml"])
check("no stale reference to check-source.sh (comments included)",
      all("check-source.sh" not in p.read_text(encoding="utf-8") for p in list(everything) + [PLUGIN / "manifest.json"]))

# ---- every Process is in the singleton --------------------------------------
for path, src in sources.items():
    if path.parent == PLUGIN and path.name != "Daemon.qml":
        check(f"{path.name}: spawns no Process", re.search(r"\bProcess\s*\{", src) is None)

# ---- pending re-arm through Qt.callLater (rule 8) ---------------------------
check("command retry deferred with Qt.callLater", "Qt.callLater(root.flushPending)" in daemon_src)
check("watch re-arm deferred with Qt.callLater", "Qt.callLater(root.syncWatch)" in daemon_src)

print("ALL OK" if not failures else f"{len(failures)} FAILED")
sys.exit(1 if failures else 0)
