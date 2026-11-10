import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui

// Runtime checks of the bar widget in a throwaway Quickshell, never the
// user's shell. tests/run-harness.sh builds the scratch config this runs from
// (qs.Commons linked, qs.Ui copied with a KeyboardPanel stub) and passes
// everything through the environment:
//
//   OBH_MODE     mock | live
//   OBH_PLUGIN   absolute path of the plugin directory (loaded by file URL,
//                as the shell loads a plugin)
//   OBH_CLI      CLI for the widgets' cliPath (the fake's copy, or live a
//                symlink to the real CLI of OMARCHY_BROADCAST_CLI; either
//                path is unique to the run, the marker watches are counted by)
//   OBH_FAKE     the fake's state directory (mock)
//   OBH_SCREENS  where PNG grabs go
//   OBH_LINKED   a symlink to the plugin dir, for the resolver checks (mock)
//   OBH_NOREPO   a plugin-named dir outside any repository (mock)
//   OBH_DAEMON   omarchy-broadcastd binary (OMARCHY_BROADCASTD); OBH_LIVE
//                the live scratch dir (live)
//   OBH_DEVLINK  a symlink to a plugin copy inside a scratch development tree
//                whose target/release/omarchy-broadcast is the fake,
//                OBH_DEVCLI, three levels above the plugin dir (mock)
//   OBH_NLPLUGIN a plugin dir whose path holds a newline; OBH_NLBIN a PATH
//                entry whose name holds one, with a CLI in it (mock)
//   OBH_RESOLVER_PATH the PATH every resolver case runs with (plus a CLI dir
//                where a case wants one): a dir holding only links to the
//                tools the resolver script needs, never an omarchy-broadcast,
//                so one installed in /usr/bin cannot answer (mock)
//   OBH_REALLINK a symlink to a plugin copy in the same layout whose
//                target/release/omarchy-broadcast links to the real CLI of
//                OMARCHY_BROADCAST_CLI; OBH_REALCLI that CLI's resolved path.
//                Empty when the variable is unset: the case prints SKIP. The
//                resolver only prints the path; nothing runs it (mock)
//
// Nothing here depends on where the plugin's own checkout lives: every
// resolver case runs against the scratch trees run-harness.sh builds.
//
// Two widgets stand for two monitors. Steps run in order; each may wait for a
// condition. Prints "ok"/"FAIL" per check and "ALL OK" or "N FAILED" at the
// end (Quickshell does not wire Qt.exit; the runner stops it).
ShellRoot {
  id: shellRoot

  readonly property string mode: Quickshell.env("OBH_MODE") || "mock"
  readonly property string pluginPath: Quickshell.env("OBH_PLUGIN") || ""
  // A copy of the plugin at another URL: a reload that yields a new singleton.
  readonly property string pluginCopy: Quickshell.env("OBH_PLUGIN_COPY") || ""
  readonly property string cli: Quickshell.env("OBH_CLI") || ""
  readonly property string fakeDir: Quickshell.env("OBH_FAKE") || ""
  readonly property string screens: Quickshell.env("OBH_SCREENS") || ""
  readonly property string moduleName: "br.com.dias.omarchy-broadcast"
  // The card's room on a 1080-pixel screen, as KeyboardPanel computes it
  // (screen height - bar - gap - margin), less the 4 px of card border this
  // stub does not draw: "fits at the normal size" means below this.
  readonly property real card1080: 1080 - Commons.Style.bar.sizeHorizontal - 2 * Commons.Style.gapsOut - 4

  PluginBarApi {
    id: barA
    pluginId: "br.com.dias.omarchy-broadcast"
    moduleName: "br.com.dias.omarchy-broadcast"
    foreground: Commons.Color.bar.text
    barForeground: Commons.Color.bar.text
    background: Commons.Color.bar.background
    urgent: Commons.Color.urgent
    fontFamily: Commons.Style.font.family
    barSize: Commons.Style.bar.sizeHorizontal
    shell: fakeShell
  }
  PluginBarApi {
    id: barB
    pluginId: "br.com.dias.omarchy-broadcast"
    moduleName: "br.com.dias.omarchy-broadcast"
    foreground: Commons.Color.bar.text
    barForeground: Commons.Color.bar.text
    background: Commons.Color.bar.background
    urgent: Commons.Color.urgent
    fontFamily: Commons.Style.font.family
    barSize: Commons.Style.bar.sizeHorizontal
    shell: fakeShell
  }

  // The shell's updateEntryInline, as a bar entry sees it: records each write
  // and hands the entry back to every widget as the bar does (without its id).
  // `refuse`: stands for a shell that finds no layout entry to write; the
  // call is recorded in `refused`, nothing is handed back, and it answers
  // false, as the real one does.
  QtObject {
    id: fakeShell
    property var calls: []
    property bool refuse: false
    property var refused: []
    function updateEntryInline(id, settings) {
      if (refuse) {
        refused = refused.concat([{ id: id, entry: JSON.parse(JSON.stringify(settings)) }])
        return false
      }
      calls = calls.concat([{ id: id, entry: JSON.parse(JSON.stringify(settings)) }])
      var copy = {}
      for (var k in settings) if (k !== "id") copy[k] = settings[k]
      if (h.widgetA) h.widgetA.settings = JSON.parse(JSON.stringify(copy))
      if (h.widgetB) h.widgetB.settings = JSON.parse(JSON.stringify(copy))
      return true
    }
  }

  FloatingWindow {
    id: window
    implicitWidth: 620
    implicitHeight: 1200
    color: Commons.Color.background

    Rectangle {
      id: strip
      x: 10
      y: 10
      width: Math.max(80, stripRow.implicitWidth + 16)
      height: Commons.Style.bar.sizeHorizontal
      color: Commons.Color.bar.background
      Row {
        id: stripRow
        x: 8
        height: parent.height
        spacing: 4
      }
    }

    // Real key events (QtTest), delivered to the focused item of this window:
    // the panel's PanelKeyCatcher once the popup stub has given it focus.
    TestCase {
      id: keys
      name: "harness-keys"
      when: false
    }
  }

  // Longest gap between two ticks of a 10 ms timer: a UI stall.
  Timer {
    id: gapTimer
    interval: 10
    repeat: true
    running: true
    property real last: Date.now()
    property real maxGap: 0
    onTriggered: {
      var now = Date.now()
      if (now - last > maxGap) maxGap = now - last
      last = now
    }
  }

  // ---- helpers ---------------------------------------------------------------

  QtObject {
    id: h

    property int failures: 0
    property int checks: 0
    property var steps: []
    property int index: 0
    property bool ran: false
    property real started: 0
    property bool finished: false

    property var widgetA: null
    property var widgetB: null
    property var oldService: null
    property var model: null

    // async results
    property int watchCount: -1
    property bool countFresh: false
    property bool grabDone: false
    property string resolverOut: ""
    property int resolverExit: -99
    property bool resolverDone: false
    property int logMark: 0
    property real mark: 0
    property var notes: ({})

    function check(name, ok, detail) {
      checks++
      if (ok) console.log("  ok   " + name)
      else {
        failures++
        console.log("  FAIL " + name + (detail !== undefined ? ": " + detail : ""))
      }
    }
    function eq(name, got, want) {
      check(name, String(got) === String(want), "got " + JSON.stringify(got) + ", wanted " + JSON.stringify(want))
    }
    function note(text) { console.log("  note " + text) }

    function step(name, run, until, timeout) {
      steps.push({ name: name, run: run, until: until, timeout: timeout || 6000 })
    }
    function wait(ms) {
      step("wait " + ms, function() { h.mark = Date.now() }, function() { return Date.now() - h.mark >= ms }, ms + 1000)
    }

    function tick() {
      if (finished) return
      if (index >= steps.length) {
        finished = true
        console.log(failures === 0 ? "ALL OK (" + checks + " checks)" : failures + " FAILED")
        return
      }
      var s = steps[index]
      if (!ran) {
        ran = true
        started = Date.now()
        console.log("step: " + s.name)
        try { if (s.run) s.run() } catch (e) { check(s.name + " ran", false, String(e) + "\n" + e.stack) }
        return
      }
      var done = true
      try { done = s.until ? !!s.until() : true } catch (e) { done = false }
      if (done) { index++; ran = false; return }
      if (Date.now() - started > s.timeout) {
        check("in time: " + s.name, false, "timed out after " + s.timeout + " ms")
        index++
        ran = false
      }
    }

    // A widget as the bar makes one: created, then given bar, moduleName and
    // settings (the bar injects them after completion).
    function makeWidget(bar, settings, dir) {
      var comp = Qt.createComponent("file://" + (dir || shellRoot.pluginPath) + "/BarWidget.qml")
      if (comp.status !== Component.Ready) {
        check("BarWidget.qml compiles", false, comp.errorString())
        return null
      }
      var w = comp.createObject(stripRow, {})
      w.bar = bar
      w.moduleName = shellRoot.moduleName
      w.settings = settings
      if (w.popup) w.popup.availableCardHeight = shellRoot.card1080
      return w
    }

    function findByName(item, name) {
      if (!item) return null
      if (item.objectName === name) return item
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) {
        var found = findByName(kids[i], name)
        if (found) return found
      }
      return null
    }

    function content(w) { return w && w.popup ? w.popup.loadedContent : null }
    // Shows a tab of w's panel as a stored value would, without writing
    // anything (the tab checks below drive the user's paths).
    function tab(w, id) { var c = content(w); if (c) c.showTab(id) }
    // Shows tab `id` of w's panel, lets the layout settle, then runs
    // `checks` (a Column lays out on the next frame, not in the same turn).
    function tabStep(w, id, label, checks) {
      step("show the " + id + " tab: " + label, function() { h.tab(w(), id) })
      wait(250)
      step(id + " tab: " + label, function() { checks() })
    }
    // The open panel shows all of the tab in force without the scroll
    // fallback, and the card stays below a 1080-pixel screen's room. Only
    // after the layout settled (see tabStep).
    function fits(w, label) {
      var flick = find(w, "panelFlick")
      check(label + ": no scroll (content " + (flick ? Math.round(flick.contentHeight) : "?") + " in "
            + (flick ? Math.round(flick.height) : "?") + ")",
            !!flick && !flick.interactive && flick.contentHeight <= flick.height + 0.5,
            flick ? flick.contentHeight + " in " + flick.height + ", interactive " + flick.interactive : "no flick")
      check(label + ": card below the 1080 screen's room (" + w.popup.contentHeight + " < " + Math.round(w.popup.availableCardHeight) + ")",
            w.popup.contentHeight < w.popup.availableCardHeight, w.popup.contentHeight + " vs " + w.popup.availableCardHeight)
    }
    // A chip of the preview-rate ButtonGroup (its delegates have no name).
    function fpsChip(w, value) {
      var group = find(w, "fpsChoices")
      var kids = group ? group.children : []
      for (var i = 0; i < kids.length; i++) if (kids[i].text === value + " fps") return kids[i]
      return null
    }
    // A light palette for one screenshot, and back: the theme's foundational
    // colours, with the per-surface roles dropped so every surface follows.
    property var savedPalette: null
    function lightPalette(on) {
      var C = Commons.Color
      if (on) {
        // Strings: a colour read off a property is a live reference in Qt 6,
        // and would come back as the light value.
        savedPalette = { foreground: String(C.foreground), background: String(C.background), accent: String(C.accent),
                         urgent: String(C.urgent), muted: String(C.muted), shellValues: C.shellValues }
        C.shellValues = ({})
        C.foreground = "#2b2f33"
        C.background = "#f4f1ea"
        C.accent = "#2a6fb0"
        C.urgent = "#b0302a"
        C.muted = "#8a8f94"
      } else if (savedPalette) {
        C.foreground = savedPalette.foreground
        C.background = savedPalette.background
        C.accent = savedPalette.accent
        C.urgent = savedPalette.urgent
        C.muted = savedPalette.muted
        C.shellValues = savedPalette.shellValues
        savedPalette = null
      }
    }
    function find(w, name) { return findByName(content(w), name) }
    function row(w, i) {
      var rep = find(w, "cameraRepeater")
      return rep ? rep.itemAt(i) : null
    }

    function regexEscape(s) { return String(s).replace(/[.[\]{}()*+?^$|\\\/]/g, "\\$&") }

    function countWatches(cli) {
      countFresh = false
      // The fake is a script (run as /bin/sh <path>); the live CLI is the binary.
      var prefix = shellRoot.mode === "live" ? "^" : "^/bin/sh "
      pgrepProc.command = ["pgrep", "-cf", prefix + regexEscape(cli || shellRoot.cli) + " watch --json$"]
      pgrepProc.running = true
    }
    // Preview children of the fake: `--fps N` when given, else either.
    function countPreviews(fps) {
      countFresh = false
      pgrepProc.command = ["pgrep", "-cf", "^/bin/sh " + regexEscape(shellRoot.cli) + " preview --json --fps "
                           + (fps ? String(fps) : "(15|30)") + "$"]
      pgrepProc.running = true
    }
    function previewCountStep(want, label, fps) {
      step("count preview processes (" + label + ")", function() { h.countPreviews(fps) },
           function() {
             if (!h.countFresh) return false
             h.eq("preview processes" + (fps ? " at " + fps + " fps " : " ") + label, h.watchCount, want)
             return true
           })
    }
    function countStep(want, label, cli) {
      step("count watch processes (" + label + ")", function() { h.countWatches(cli) },
           function() {
             if (!h.countFresh) return false
             h.eq("watch processes " + label, h.watchCount, want)
             return true
           })
    }

    function grab(item, file) {
      grabDone = false
      if (!item || !shellRoot.screens) { grabDone = true; return }
      var scale = 3
      item.grabToImage(function(result) {
        var path = shellRoot.screens + "/" + file
        h.check("screenshot " + file, result.saveToFile(path), path)
        h.grabDone = true
      }, Qt.size(Math.ceil(item.width * scale), Math.ceil(item.height * scale)))
    }
    function grabStep(itemFn, file) {
      step("grab " + file, function() { h.grab(itemFn(), file) }, function() { return h.grabDone }, 5000)
    }

    // ---- fake CLI control (mock) ----
    property var writeQueue: []
    function enqueue(argv) {
      writeQueue = writeQueue.concat([argv])
      Qt.callLater(h.pumpWriter)
    }
    function pumpWriter() {
      if (writerProc.running || writeQueue.length === 0) return
      var argv = writeQueue[0]
      writeQueue = writeQueue.slice(1)
      writerProc.command = argv
      writerProc.running = true
    }
    function writerIdle() { return !writerProc.running && writeQueue.length === 0 }
    function writeFile(name, lines) {
      enqueue(["sh", "-c", ': > "$0"; for l in "$@"; do printf "%s\\n" "$l" >> "$0"; done',
               shellRoot.fakeDir + "/" + name].concat(lines))
    }
    function removeFile(name) {
      enqueue(["rm", "-f", "--", shellRoot.fakeDir + "/" + name])
    }
    function feed(lines) {
      enqueue(["sh", "-c", 'for l in "$@"; do printf "%s\\n" "$l"; done >> "$0"',
               shellRoot.fakeDir + "/feed"].concat(lines))
    }
    function logLines() {
      logView.reload()
      var text = logView.text()
      var lines = text ? text.split("\n") : []
      var out = []
      for (var i = 0; i < lines.length && i < 10000; i++) if (lines[i] !== "") out.push(lines[i])
      return out
    }
    // "<pid> [a] [b]" -> ["a", "b"]
    function logArgs(line) {
      var out = []
      var re = /\[([^\]]*)\]/g
      var m
      while ((m = re.exec(line)) !== null) out.push(m[1])
      return out
    }
    function markLog() { logMark = logLines().length }
    function newLogArgs() {
      var lines = logLines().slice(logMark)
      var out = []
      for (var i = 0; i < lines.length; i++) {
        var a = logArgs(lines[i])
        if (!(a[0] === "watch")) out.push(a)
      }
      return out
    }
    // What the shell does on a plugin reload. This Qt build has no
    // Qt.clearComponentCache in JS (the shell guards the call the same way),
    // so a same-URL reload keeps the singleton; a new URL gets a new one.
    function clearCache() {
      var available = typeof Qt.clearComponentCache === "function"
      if (available) Qt.clearComponentCache()
      return available
    }
    function killPid(pid, signal) {
      // Never 0 or negative: kill(1) would signal a whole process group.
      if (!(Number(pid) > 1)) { check("kill target is a real PID", false, String(pid)); return }
      killProc.command = ["kill", "-" + (signal || "TERM"), String(pid)]
      killProc.running = true
    }
    function key(k) { keys.keyClick(k) }
    function catcher(w) { var c = content(w); return c ? c.keyCatcher : null }
    // "[watch]" lines of the fake's log: one per watch process started.
    function watchSpawns() {
      var lines = logLines()
      var n = 0
      for (var i = 0; i < lines.length; i++) if (lines[i].indexOf(" [watch] [--json]") !== -1) n++
      return n
    }
    // A text as printf octal escapes of its UTF-8 bytes (and the byte offsets
    // of each character), so a file can be cut inside a character.
    function utf8Bytes(text) {
      var enc = unescape(encodeURIComponent(text))
      var out = []
      for (var i = 0; i < enc.length; i++) out.push(enc.charCodeAt(i))
      return out
    }
    function octal(bytes) {
      var s = ""
      for (var i = 0; i < bytes.length; i++) {
        var o = bytes[i].toString(8)
        while (o.length < 3) o = "0" + o
        s += "\\" + o
      }
      return s
    }
    function writeBytes(name, bytes) {
      enqueue(["sh", "-c", 'printf "$1" > "$0"', shellRoot.fakeDir + "/" + name, octal(bytes)])
    }
    property string rss: ""
    function measureRss() {
      rssDone = false
      rssProc.command = ["sh", "-c", 'grep -E "^(VmRSS|VmHWM)" "/proc/$PPID/status" | tr -s " \t\n" " "']
      rssProc.running = true
    }
    property bool rssDone: false
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: h.tick()
  }

  Process {
    id: pgrepProc
    stdout: StdioCollector { id: pgrepOut }
    onExited: function(code) {
      h.watchCount = parseInt(String(pgrepOut.text).trim(), 10) || 0
      h.countFresh = true
    }
  }
  Process { id: writerProc; onRunningChanged: if (!running) Qt.callLater(h.pumpWriter) }
  Process { id: killProc }
  Process {
    id: rssProc
    stdout: StdioCollector { id: rssOut }
    onExited: function() { h.rss = String(rssOut.text).trim(); h.rssDone = true }
  }
  Process {
    id: resolverProc
    stdout: StdioCollector { id: resolverOut }
    onExited: function(code) {
      h.resolverOut = String(resolverOut.text).trim()
      h.resolverExit = code
      h.resolverDone = true
    }
  }
  FileView {
    id: logView
    path: shellRoot.fakeDir !== "" ? shellRoot.fakeDir + "/log" : ""
    blockLoading: true
    blockAllReads: true
    printErrors: false
  }

  // ---- mock scenario -----------------------------------------------------------

  readonly property string brioId: "usb-046d_0944-video-index0"
  readonly property string fhdId: "pci-0000:00:14.0-usb-0:5:1.0-video-index0"
  readonly property string hostileId: "--flag; $(id) `id` ~"

  function cams(active) {
    return [
      { id: brioId, name: "Logitech MX Brio", usb: "046d:0944", active: active === brioId },
      { id: fhdId, name: "FHD Camera", usb: "5986:1193", active: active === fhdId },
      { id: hostileId, name: "<img src='http://127.0.0.1:9/beacon'> & Co\nNext", usb: "dead:beef", active: false }
    ]
  }
  function scalars(o) {
    var m = { state: "idle", enabled: true, error: "", active_camera: brioId,
              active_camera_name: "Logitech MX Brio", consumers: 0, output_mode: "NV12 1920x1080@30",
              effect: "none", blur_strength: 0.5, background_image: "", denoise: false, interface_revision: 4 }
    for (var k in o) m[k] = o[k]
    return m
  }
  function snapshotLine(o) {
    var m = scalars(o || {})
    m.v = 1
    m.type = "snapshot"
    m.cameras = cams(m.active_camera)
    m.cameras_truncated = false
    return JSON.stringify(m)
  }
  function stateLine(o) {
    var m = scalars(o || {})
    m.v = 1
    m.type = "state"
    m.changed = Object.keys(o || {}).length ? Object.keys(o) : ["state"]
    return JSON.stringify(m)
  }
  function camerasLine(active) {
    return JSON.stringify({ v: 1, type: "cameras", active_camera: active, cameras: cams(active), cameras_truncated: false })
  }
  function overlongLine() {
    var pad = ""
    for (var i = 0; i < 9000; i++) pad += "x"
    return JSON.stringify({ v: 1, type: "snapshot", state: "off", pad: pad })
  }

  function glyphOf(key) { return h.model.visualFor(key).glyph }

  function manyCamerasLine(n, truncated) {
    var list = []
    for (var i = 0; i < n; i++)
      list.push({ id: "usb-cam-" + i + "-video-index0", name: "Camera number " + (i + 1), usb: "0bda:" + (5000 + i), active: i === 0 })
    return JSON.stringify({ v: 1, type: "cameras", active_camera: list[0].id, cameras: list, cameras_truncated: truncated })
  }
  // Multi-byte name and id, for the read-boundary check.
  readonly property string utfName: "Câmera ação 日本 😀"
  readonly property string utfId: "usb-câmera-日本-😀-video-index0"

  function mockScenario() {
    var A = function() { return h.widgetA }
    var B = function() { return h.widgetB }
    var S = function() { return h.widgetA.service }
    var lastArgs = function() { var a = h.newLogArgs(); return a.length ? JSON.stringify(a[a.length - 1]) : "" }

    h.wait(800) // theme files load

    h.step("seed the fake", function() {
      h.writeFile("snapshot", [snapshotLine({}), "this is not json <b>"])
      h.writeFile("feed", [])
      h.removeFile("delay")
      h.removeFile("stderr")
      h.removeFile("watch-exit")
      h.removeFile("snapshot.1")
      h.removeFile("snapshot.2")
      h.writeFile("exit", ["0"])
      h.writeFile("log", [])
    }, function() { return h.writerIdle() })

    h.step("two widgets connect", function() {
      h.widgetA = h.makeWidget(barA, { cliPath: shellRoot.cli })
      h.widgetB = h.makeWidget(barB, { cliPath: shellRoot.cli })
    }, function() { return h.widgetA && h.widgetA.service.record.link === "ok" }, 8000)

    h.step("snapshot", function() {
      var s = S()
      h.check("both widgets share one service", A().service === B().service)
      h.eq("attached widgets", s.attachedCount, 2)
      h.eq("watch started once", s.watchStarts, 1)
      h.eq("CLI from the setting", s.cliSource, "setting")
      h.eq("no line dropped", s.droppedLines, 0)
      h.check("garbage line ignored", s.ignoredLines >= 1, s.ignoredLines)
      h.eq("cameras", s.record.cameras.length, 3)
      var hostile = s.record.cameras[2]
      h.check("hostile name sanitised", !/[<>&\n]/.test(hostile.name), hostile.name)
      h.eq("hostile id kept for argv", hostile.selectId, hostileId)
      h.eq("idle glyph (A)", A().iconButton.text, glyphOf("idle"))
      h.eq("idle glyph (B)", B().iconButton.text, glyphOf("idle"))
      h.eq("idle not dimmed", A().iconButton.dimmed, false)
      h.eq("idle uses the foreground", A().iconButton.active, false)
      h.eq("tooltip (A)", A().iconButton.tooltipText, "Omarchy Broadcast: idle · Logitech MX Brio · 0 consumers")
      h.eq("tooltip (B)", B().iconButton.tooltipText, A().iconButton.tooltipText)
    })
    h.countStep(1, "with two widgets")

    h.grabStep(function() { return strip }, "bar-idle.png")
    h.step("open the panel", function() { A().open() }, function() { return h.content(A()) !== null })
    h.wait(300)
    h.step("panel idle", function() {
      h.eq("unavailable block hidden", h.find(A(), "unavailableBlock").visible, false)
      h.eq("opens on the Effect tab (the default)", h.content(A()).tab, "effect")
      h.eq("tab row shown", h.find(A(), "tabRow").visible, true)
      h.eq("Effect chip selected", h.find(A(), "tab-effect").selected, true)
      h.eq("Effect tab shown", h.find(A(), "effectTab").visible, true)
      h.eq("Camera tab hidden", h.find(A(), "cameraTab").visible, false)
      h.eq("Status tab hidden", h.find(A(), "statusTab").visible, false)
      h.eq("tab labels", ["effect", "camera", "status"].map(function(t) { return h.find(A(), "tab-" + t).text }).join(","), "Effect,Camera,Status")
      h.eq("camera rows", h.find(A(), "cameraRepeater").count, 3)
      h.eq("switch shown", h.find(A(), "enableSwitch").visible, true)
      h.eq("noise removal row shown", h.find(A(), "denoiseRow").visible, true)
      h.eq("noise removal off", h.find(A(), "denoiseToggle").checked, false)
      h.eq("noise removal label", h.find(A(), "denoiseLabel").text, "Noise removal")
      h.eq("hero status line", h.content(A()).heroMeta, "idle")
      h.check("active row marked", h.row(A(), 0).isActive && !h.row(A(), 1).isActive)
      h.check("active row painted as current", h.row(A(), 0).current && !h.row(A(), 1).current)
      h.eq("no cursor before a key", h.content(A()).cursorActive, false)
      h.check("panel took the keyboard focus", h.catcher(A()) && h.catcher(A()).activeFocus)
      h.fits(A(), "Effect tab, idle")
    })
    h.grabStep(function() { return A().popup }, "panel-idle.png")
    h.tabStep(A, "camera", "idle", function() {
      h.eq("cameras block shown on the Camera tab", h.find(A(), "camerasBlock").visible, true)
      h.eq("next camera shown", h.find(A(), "nextCameraButton").visible, true)
      h.eq("noise removal on the Effect tab only", h.find(A(), "denoiseRow").visible, false)
      h.fits(A(), "Camera tab, idle")
    })
    h.tabStep(A, "status", "idle", function() {
      h.eq("stats hidden while idle", h.find(A(), "statsBlock").visible, false)
      h.eq("status rows", h.find(A(), "statusRepeater").count, 6)
      h.fits(A(), "Status tab, idle")
      h.tab(A(), "effect")
      h.eq("nothing written by showing a tab", fakeShell.calls.length, 0)
    })

    // camera selection by clicking a row
    h.step("select FHD by its row", function() {
      h.markLog()
      h.row(A(), 1).choose()
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("select argv", function() {
      h.eq("argv", JSON.stringify(h.newLogArgs()[0]), JSON.stringify(["camera", "--", fhdId]))
      h.eq("no optimistic change", S().record.activeCamera, brioId)
      h.feed([stateLine({ active_camera: fhdId, active_camera_name: "FHD Camera" }), camerasLine(fhdId)])
    }, function() { return S().record.activeCamera === fhdId })
    h.step("selection arrives on the stream", function() {
      h.check("row 1 now marked", h.row(A(), 1).isActive && !h.row(A(), 0).isActive)
      h.eq("tooltip names FHD", A().iconButton.tooltipText, "Omarchy Broadcast: idle · FHD Camera · 0 consumers")
    })

    h.step("hostile id stays one argv element after --", function() {
      h.markLog()
      h.row(A(), 2).choose()
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("hostile argv", function() {
      h.eq("argv", JSON.stringify(h.newLogArgs()[0]), JSON.stringify(["camera", "--", hostileId]))
    }, function() { return !S().commandBusy })

    h.step("next camera", function() {
      h.markLog()
      h.find(A(), "nextCameraButton").clicked()
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("next argv", function() { h.eq("argv", JSON.stringify(h.newLogArgs()[0]), JSON.stringify(["camera", "next"])) },
           function() { return !S().commandBusy })

    // ---- keyboard: real key events through the panel's PanelKeyCatcher
    h.step("key: first Down shows the cursor on the switch", function() {
      h.check("catcher focused", h.catcher(A()).activeFocus)
      h.key(Qt.Key_Down)
    }, function() { return h.content(A()).cursorActive })
    h.step("cursor on the switch", function() {
      var c = h.content(A())
      h.eq("stop", c.currentStop.kind, "switch")
      h.eq("switch has the cursor", h.find(A(), "enableSwitch").hasCursor, true)
      h.eq("stops = switch + tab row + effect + noise removal (the Effect tab)", c.stops.length, 4)
      h.key(Qt.Key_Down)
    })
    h.step("Down: the tab row, on the tab shown", function() {
      var c = h.content(A())
      h.eq("stop", c.currentStop.kind, "tabs")
      h.eq("tab cursor on Effect", c.tabCursor, 0)
      h.eq("Effect chip has the cursor", h.find(A(), "tab-effect").hasCursor, true)
      h.eq("the other chips have none", h.find(A(), "tab-camera").hasCursor || h.find(A(), "tab-status").hasCursor, false)
      h.key(Qt.Key_Down)
    })
    // the effect row: one stop; Left/Right walk its choices
    h.step("Down: the effect row, on the current effect", function() {
      var c = h.content(A())
      h.eq("stop", c.currentStop.kind, "effect")
      h.eq("cursor on None (the current effect)", c.effectCursor, 0)
      h.eq("None has the cursor", h.find(A(), "effectChoice-none").hasCursor, true)
      h.eq("None is selected", h.find(A(), "effectChoice-none").selected, true)
      h.eq("switch lost it", h.find(A(), "enableSwitch").hasCursor, false)
      h.check("Replace faded without a background image", h.find(A(), "effectChoice-replace").opacity < 1)
      h.eq("hint command", h.find(A(), "effectHintCommand").text, "omarchy-broadcast effect replace --image PATH")
      h.key(Qt.Key_Right)
      h.key("l")
      h.key(Qt.Key_Right)
      h.markLog()
      h.key(Qt.Key_Return)
    })
    h.step("Enter on Replace without an image runs nothing", function() {
      h.eq("cursor on Replace, and no further", h.content(A()).effectCursor, 2)
      h.eq("Replace has the cursor", h.find(A(), "effectChoice-replace").hasCursor, true)
      h.eq("nothing armed", S().commandBusy, false)
      h.eq("nothing ran", h.newLogArgs().length, 0)
    })
    h.grabStep(function() { return A().popup }, "panel-cursor-effect.png")
    h.step("Left, Enter: Blur", function() {
      h.key(Qt.Key_Left)
      h.markLog()
      h.key(Qt.Key_Return)
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("effect argv", function() {
      h.eq("argv", lastArgs(), JSON.stringify(["effect", "blur"]))
      h.eq("no optimistic change", S().record.effectKey, "none")
      h.feed([stateLine({ effect: "blur", blur_strength: 0.5, active_camera: fhdId, active_camera_name: "FHD Camera" })])
    }, function() { return S().record.effectKey === "blur" && !S().commandBusy })
    h.step("Blur arrives on the stream", function() {
      h.eq("Blur selected", h.find(A(), "effectChoice-blur").selected, true)
      h.eq("None no longer selected", h.find(A(), "effectChoice-none").selected, false)
      h.check("tooltip names the effect", A().iconButton.tooltipText.indexOf("background blurred") !== -1, A().iconButton.tooltipText)
      h.markLog()
      h.key(Qt.Key_Return)
    })
    h.step("Enter on the current effect runs nothing", function() {
      h.eq("nothing armed", S().commandBusy, false)
      h.eq("nothing ran", h.newLogArgs().length, 0)
      h.feed([stateLine({ effect: "none", active_camera: fhdId, active_camera_name: "FHD Camera" })])
    }, function() { return S().record.effectKey === "none" })
    // noise removal: a switch of its own below the effect row; Enter flips it
    h.step("Down from the effect row: the noise removal switch", function() {
      h.key(Qt.Key_Down)
      var c = h.content(A())
      h.eq("stop", c.currentStop.kind, "denoise")
      h.eq("noise removal has the cursor", h.find(A(), "denoiseToggle").hasCursor, true)
      h.eq("no effect chip has it", ["none", "blur", "replace"].filter(function(e) {
        return h.find(A(), "effectChoice-" + e).hasCursor }).length, 0)
      h.markLog()
      h.key(Qt.Key_Return)
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("denoise on argv", function() {
      h.eq("argv", lastArgs(), JSON.stringify(["denoise", "on"]))
      h.eq("no optimistic change", S().record.denoise, false)
      h.eq("switch still off", h.find(A(), "denoiseToggle").checked, false)
      h.feed([stateLine({ denoise: true, active_camera: fhdId, active_camera_name: "FHD Camera" })])
    }, function() { return S().record.denoise === true && !S().commandBusy })
    h.step("noise removal arrives on the stream", function() {
      h.eq("switch on", h.find(A(), "denoiseToggle").checked, true)
      h.eq("None still selected (it stacks with any effect)", h.find(A(), "effectChoice-none").selected, true)
      h.eq("tooltip", A().iconButton.tooltipText, "Omarchy Broadcast: idle · FHD Camera · 0 consumers · noise removal on")
    })
    h.step("with Blur too", function() {
      h.feed([stateLine({ effect: "blur", denoise: true, active_camera: fhdId, active_camera_name: "FHD Camera" })])
    }, function() { return S().record.effectKey === "blur" })
    h.step("tooltip names both", function() {
      h.eq("tooltip", B().iconButton.tooltipText,
           "Omarchy Broadcast: idle · FHD Camera · 0 consumers · background blurred, noise removal on")
      h.eq("switch still on", h.find(A(), "denoiseToggle").checked, true)
    })
    h.grabStep(function() { return A().popup }, "panel-denoise-on.png")
    // busy: a second flip while the first runs is refused, as the effect
    // choices refuse one
    h.step("slow commands for the denoise double click", function() { h.writeFile("delay", ["0.6"]) },
           function() { return h.writerIdle() })
    h.step("click the switch twice", function() {
      h.markLog()
      h.find(A(), "denoiseToggle").toggled()
      h.check("busy after the first click", S().commandBusy)
      h.eq("the switch shows busy", h.find(A(), "denoiseToggle").busy, true)
      h.check("second flip refused", !h.content(A()).toggleDenoise())
      h.check("an effect refused meanwhile", !h.content(A()).chooseEffect(0))
    }, function() { return h.newLogArgs().length >= 1 })
    h.wait(900)
    h.step("denoise off argv, once", function() {
      var got = h.newLogArgs()
      h.eq("runs", JSON.stringify(got), JSON.stringify([["denoise", "off"]]))
      h.eq("no optimistic change", S().record.denoise, true)
      h.removeFile("delay")
      h.feed([stateLine({ effect: "none", denoise: false, active_camera: fhdId, active_camera_name: "FHD Camera" })])
    }, function() { return S().record.denoise === false && S().record.effectKey === "none" && !S().commandBusy })
    h.step("noise removal off again", function() {
      h.eq("switch off", h.find(A(), "denoiseToggle").checked, false)
      h.eq("tooltip", A().iconButton.tooltipText, "Omarchy Broadcast: idle · FHD Camera · 0 consumers")
      h.content(A()).setCursor("denoise", -1)
    })
    h.step("Down from the noise removal switch: the last stop of the tab; Up twice: the tab row", function() {
      var c = h.content(A())
      h.key(Qt.Key_Down)
      h.eq("still on noise removal", c.currentStop.kind, "denoise")
      h.key("k")
      h.key("k")
      h.eq("the tab row", c.currentStop.kind, "tabs")
      h.eq("on the tab shown", c.tabCursor, 0)
      h.notes.calls = fakeShell.calls.length
      h.markLog()
      h.key(Qt.Key_Right)
    })
    h.step("Right on the tab row: the Camera tab at once, remembered", function() {
      var c = h.content(A())
      h.eq("tab", c.tab, "camera")
      h.eq("Camera tab shown", h.find(A(), "cameraTab").visible, true)
      h.eq("Effect tab hidden", h.find(A(), "effectTab").visible, false)
      h.eq("Camera chip selected", h.find(A(), "tab-camera").selected, true)
      h.eq("Effect chip no longer selected", h.find(A(), "tab-effect").selected, false)
      h.eq("the cursor stays on the tab row", c.currentStop.kind, "tabs")
      h.eq("Camera chip has the cursor", h.find(A(), "tab-camera").hasCursor, true)
      h.eq("one write", fakeShell.calls.length, h.notes.calls + 1)
      h.eq("entry", JSON.stringify(fakeShell.calls[fakeShell.calls.length - 1].entry),
           JSON.stringify({ id: shellRoot.moduleName, cliPath: shellRoot.cli, panelTab: "camera" }))
      h.eq("both widgets hold the stored tab", A().storedTab + "," + B().storedTab, "camera,camera")
      h.eq("no command ran", h.newLogArgs().length, 0)
      h.eq("stops = switch + tab row + rendered rows + next (the Camera tab)", c.stops.length, h.find(A(), "cameraRepeater").count + 3)
      h.key(Qt.Key_Right)
      h.key(Qt.Key_Right)
      h.eq("Right twice: Status, and no further", c.tab, "status")
      h.key(Qt.Key_Left)
      h.eq("Left: Camera again", c.tab, "camera")
      h.eq("a write per change", fakeShell.calls.length, h.notes.calls + 3)
      h.key(Qt.Key_Down)
    })
    h.step("Down: first camera row", function() {
      h.eq("row 0 has the cursor", h.row(A(), 0).hasCursor, true)
      h.eq("switch lost it", h.find(A(), "enableSwitch").hasCursor, false)
      h.eq("one highlight", [0, 1, 2].filter(function(i) { return h.row(A(), i).hasCursor }).length, 1)
    })
    h.grabStep(function() { return A().popup }, "panel-cursor-row.png")
    h.step("Enter selects the row under the cursor", function() {
      h.markLog()
      h.key(Qt.Key_Return)
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("keyboard select argv", function() {
      h.eq("argv", lastArgs(), JSON.stringify(["camera", "--", brioId]))
      h.feed([stateLine({ active_camera: brioId, active_camera_name: "Logitech MX Brio" }), camerasLine(brioId)])
    }, function() { return S().record.activeCamera === brioId && !S().commandBusy })
    h.step("j, j, j, Down: to Next camera and no further", function() {
      h.key("j")
      h.key("j")
      h.key("j")
      h.key(Qt.Key_Down)
    })
    h.step("cursor on Next camera", function() {
      h.eq("stop", h.content(A()).currentStop.kind, "next")
      h.eq("Next camera has the cursor", h.find(A(), "nextCameraButton").hasCursor, true)
      h.markLog()
      h.key(Qt.Key_Space)
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("Space runs Next camera", function() {
      h.eq("argv", lastArgs(), JSON.stringify(["camera", "next"]))
    }, function() { return !S().commandBusy })
    h.step("k x6 back to the switch, Enter turns off", function() {
      for (var i = 0; i < 6; i++) h.key("k")
      h.eq("on the switch", h.content(A()).currentStop.kind, "switch")
      h.markLog()
      h.key(Qt.Key_Enter)
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("switch argv from the keyboard", function() {
      h.eq("argv", lastArgs(), JSON.stringify(["off"]))
      h.feed([stateLine({ state: "off", enabled: false })])
    }, function() { return S().record.state === "off" && !S().commandBusy })
    h.step("Enter again turns on", function() {
      h.markLog()
      h.key(Qt.Key_Return)
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("on argv from the keyboard", function() {
      h.eq("argv", lastArgs(), JSON.stringify(["on"]))
      h.feed([stateLine({ state: "idle", enabled: true, active_camera: fhdId, active_camera_name: "FHD Camera" }), camerasLine(fhdId)])
    }, function() { return S().record.state === "idle" && S().record.activeCamera === fhdId && !S().commandBusy })
    h.step("hovering a row moves the same cursor", function() {
      h.content(A()).setCursor("camera", 2)
      h.eq("row 2 has the cursor", h.row(A(), 2).hasCursor, true)
      h.eq("switch has none", h.find(A(), "enableSwitch").hasCursor, false)
      h.key(Qt.Key_Escape)
    }, function() { return !A().opened })
    h.step("Escape closed the panel", function() {
      A().open()
    }, function() { return A().opened })
    h.step("reopened: no cursor until a key", function() {
      h.eq("cursor reset", h.content(A()).cursorActive, false)
      h.eq("reopened on the tab last shown", h.content(A()).tab, "camera")
    })

    // ---- the tabs: number keys, mouse, hover, persistence, an invalid value
    h.step("tabs: number keys", function() {
      var c = h.content(A())
      h.notes.calls = fakeShell.calls.length
      h.key("3")
      h.eq("3: Status", c.tab, "status")
      h.eq("a number key shows no cursor", c.cursorActive, false)
      h.key("1")
      h.eq("1: Effect", c.tab, "effect")
      h.key("2")
      h.eq("2: Camera", c.tab, "camera")
      h.key("4")
      h.key("0")
      h.key("9")
      h.eq("other digits do nothing", c.tab, "camera")
      h.key("2")
      h.eq("a write per change, none for the tab shown", fakeShell.calls.length, h.notes.calls + 3)
    })
    h.step("tabs: a click on a chip", function() {
      var chip = h.find(A(), "tab-status")
      keys.mouseClick(chip, chip.width / 2, chip.height / 2)
    }, function() { return h.content(A()).tab === "status" })
    h.step("tabs: hovering moves the cursor, not the tab; Enter shows the tab under it", function() {
      var c = h.content(A())
      h.eq("written", JSON.stringify(fakeShell.calls[fakeShell.calls.length - 1].entry.panelTab), JSON.stringify("status"))
      c.setTabCursor(0)
      h.eq("Effect chip has the cursor", h.find(A(), "tab-effect").hasCursor, true)
      h.eq("Status still shown", c.tab, "status")
      h.eq("Status still selected", h.find(A(), "tab-status").selected, true)
      h.key(Qt.Key_Return)
      h.eq("Enter: Effect", c.tab, "effect")
      c.setCursor("denoise", -1)
      h.key("2")
      h.eq("a number key from inside a tab: Camera", c.tab, "camera")
      h.eq("the cursor left the hidden rows for the tab row", c.currentStop.kind, "tabs")
      h.eq("stored", A().settings.panelTab, "camera")
      A().close()
      h.notes.widgetC = h.makeWidget(barB, JSON.parse(JSON.stringify(A().settings)))
      h.notes.calls = fakeShell.calls.length
      h.notes.widgetC.open()
    }, function() { return h.content(h.notes.widgetC) !== null })
    h.step("tabs: a new widget with the stored entry opens on its tab", function() {
      var w = h.notes.widgetC
      h.eq("tab", h.content(w).tab, "camera")
      h.eq("Camera tab shown", h.find(w, "cameraTab").visible, true)
      h.eq("Camera chip selected", h.find(w, "tab-camera").selected, true)
      h.eq("nothing written on open", fakeShell.calls.length, h.notes.calls)
      w.close()
      w.destroy()
      // stored values that are no tab
      h.notes.widgetC = h.makeWidget(barB, { cliPath: shellRoot.cli, panelTab: "Camera; $(id)" })
      h.notes.widgetC.open()
    }, function() { return h.content(h.notes.widgetC) !== null })
    h.step("tabs: an invalid stored tab falls back to Effect", function() {
      var w = h.notes.widgetC
      h.eq("read as the default", w.storedTab, "effect")
      h.eq("tab", h.content(w).tab, "effect")
      h.eq("Effect tab shown", h.find(w, "effectTab").visible, true)
      w.settings = { cliPath: shellRoot.cli, panelTab: 2 }
      h.eq("a number reads as the default", h.content(w).tab, "effect")
      w.settings = { cliPath: shellRoot.cli, panelTab: ["status"] }
      h.eq("an array reads as the default", h.content(w).tab, "effect")
      w.settings = { cliPath: shellRoot.cli, panelTab: "status" }
      h.eq("a valid stored change is followed", h.content(w).tab, "status")
      h.eq("nothing written back", fakeShell.calls.length, h.notes.calls)
      w.close()
      w.destroy()
      h.notes.widgetC = null
      // a write the shell refuses: the tab holds for the session
      fakeShell.refuse = true
      A().open()
    }, function() { return A().opened })
    h.step("tabs: a refused write holds for the session", function() {
      var c = h.content(A())
      h.check("chosen", c.chooseTab(2))
      h.eq("one refused write", fakeShell.refused.length, 1)
      h.eq("the refused entry", JSON.stringify(fakeShell.refused[0].entry),
           JSON.stringify({ id: shellRoot.moduleName, cliPath: shellRoot.cli, panelTab: "status" }))
      h.eq("shown", c.tab, "status")
      h.eq("the settings stay as the bar gave them", A().settings.panelTab, "camera")
      A().settings = JSON.parse(JSON.stringify(A().settings))
      h.eq("re-injected stale settings do not undo it", c.tab, "status")
      h.eq("the preview's note does not claim it", h.find(A(), "previewUnsaved").visible, false)
      fakeShell.refuse = false
      fakeShell.refused = []
      // back to a widget entry without a tab, and no writes on record
      A().settings = { cliPath: shellRoot.cli }
      B().settings = { cliPath: shellRoot.cli }
      fakeShell.calls = []
      h.eq("a changed stored tab is followed", c.tab, "effect")
      A().close()
    })

    // left click: off, then on from the other monitor; a second click while
    // the first runs is ignored
    h.step("slow commands for the double click", function() { h.writeFile("delay", ["0.6"]) }, function() { return h.writerIdle() })
    h.step("right click turns off; a second one in flight is ignored", function() {
      A().close()
      h.markLog()
      A().iconButton.triggerPress(Qt.RightButton)
      h.check("busy after the first click", S().commandBusy)
      A().iconButton.triggerPress(Qt.RightButton)
      B().iconButton.triggerPress(Qt.RightButton)
    }, function() { return h.newLogArgs().length >= 1 })
    h.wait(900)
    h.step("off argv, once", function() {
      var got = h.newLogArgs()
      h.eq("runs", got.length, 1)
      h.eq("argv", JSON.stringify(got[0]), JSON.stringify(["off"]))
      h.eq("no optimistic change", S().record.enabled, true)
      h.eq("right click does not open the panel", A().opened, false)
      h.eq("nor on the other monitor", B().opened, false)
      h.removeFile("delay")
      h.feed([stateLine({ state: "off", enabled: false, active_camera: fhdId, active_camera_name: "FHD Camera" })])
    }, function() { return S().record.state === "off" && !S().commandBusy })
    h.step("off icon", function() {
      h.eq("off glyph", A().iconButton.text, glyphOf("off"))
      h.eq("off dimmed", A().iconButton.dimmed, true)
      h.eq("off foreground", A().iconButton.active, false)
      h.eq("off tooltip", B().iconButton.tooltipText, "Omarchy Broadcast: off")
    })
    h.grabStep(function() { return strip }, "bar-off.png")
    h.step("accessible text names the clicks", function() {
      h.eq("role", A().iconButton.Accessible.role, Accessible.Button)
      h.eq("name: the tooltip's state", A().iconButton.Accessible.name, "Omarchy Broadcast: off")
      h.eq("description", A().iconButton.Accessible.description, "Click: open the panel. Right click: turn the camera on.")
    })
    h.step("right click on the other monitor turns on", function() {
      h.markLog()
      B().iconButton.triggerPress(Qt.RightButton)
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("on argv", function() {
      h.eq("argv", JSON.stringify(h.newLogArgs()[0]), JSON.stringify(["on"]))
      h.feed([stateLine({ state: "idle", enabled: true, active_camera: fhdId, active_camera_name: "FHD Camera" })])
    }, function() { return S().record.state === "idle" && S().record.enabled })
    h.step("left click opens and closes the panel, middle click too", function() {
      h.markLog()
      A().iconButton.triggerPress(Qt.LeftButton)
      h.eq("left click opens it", A().opened, true)
      A().iconButton.triggerPress(Qt.LeftButton)
      h.eq("a second left click closes it", A().opened, false)
      A().iconButton.triggerPress(Qt.MiddleButton)
      h.eq("middle click opens it", A().opened, true)
      A().iconButton.triggerPress(Qt.MiddleButton)
      h.eq("and closes it", A().opened, false)
      h.eq("the other monitor's panel stays closed", B().opened, false)
      h.eq("description once on", A().iconButton.Accessible.description, "Click: open the panel. Right click: turn the camera off.")
    })
    h.wait(400)
    h.step("the panel clicks run nothing", function() { h.eq("commands run", h.newLogArgs().length, 0) })

    // starting, active, stats
    h.step("starting", function() {
      h.feed([stateLine({ consumers: 1, active_camera: fhdId, active_camera_name: "FHD Camera" }),
              stateLine({ state: "starting", consumers: 1, active_camera: fhdId, active_camera_name: "FHD Camera" })])
    }, function() { return S().record.state === "starting" })
    h.step("starting icon", function() {
      h.eq("starting glyph", A().iconButton.text, glyphOf("starting"))
      h.eq("starting uses the accent", A().iconButton.active, true)
      h.eq("starting accent colour", String(A().iconButton.activeColor), String(Commons.Color.accent))
      h.eq("starting not dimmed", A().iconButton.dimmed, false)
      h.check("starting differs from active", glyphOf("starting") !== glyphOf("active"))
    })
    h.grabStep(function() { return strip }, "bar-starting.png")
    h.step("active with stats", function() {
      h.feed([stateLine({ state: "active", consumers: 1, active_camera: fhdId, active_camera_name: "FHD Camera" }),
              '{"v":1,"type":"stats","fps":30.0,"latency_p50_ms":41.2,"cpu_percent":6.5,"gpu_percent":-1.0}'])
      A().open()
    }, function() { return S().record.state === "active" && S().record.stats !== null })
    h.wait(300)
    h.step("the Status tab", function() { h.tab(A(), "status") })
    h.wait(250)
    h.step("active icon and panel", function() {
      h.eq("active glyph", A().iconButton.text, glyphOf("active"))
      h.eq("active accent", A().iconButton.active, true)
      h.eq("tooltip", A().iconButton.tooltipText, "Omarchy Broadcast: active · FHD Camera · 1 consumer")
      h.eq("stats block shown", h.find(A(), "statsBlock").visible, true)
      h.eq("hero status line", h.content(A()).heroMeta, "active")
      var rows = h.model.statsRows(S().record)
      h.eq("fps", rows[0].value, "30.0 fps")
      h.eq("latency", rows[1].value, "41.2 ms")
      h.eq("cpu", rows[2].value, "6.5 %")
      h.eq("gpu -1 is unknown", rows[3].value, "—")
      h.eq("Status tab shown", h.find(A(), "statusTab").visible, true)
      h.fits(A(), "Status tab, active with figures")
    })
    h.grabStep(function() { return strip }, "bar-active.png")
    h.grabStep(function() { return A().popup }, "panel-active.png")

    h.step("error state", function() {
      h.feed([stateLine({ state: "error", consumers: 1, active_camera: fhdId, active_camera_name: "FHD Camera",
                          error: "loopback device <b>Omarchy Broadcast</b> not found & retrying\nevery 2 s" })])
    }, function() { return S().record.state === "error" })
    h.wait(200)
    h.step("error icon and panel", function() {
      h.eq("error glyph", A().iconButton.text, glyphOf("error"))
      h.eq("error uses urgent", String(A().iconButton.activeColor), String(barA.urgent))
      h.eq("error active", A().iconButton.active, true)
      h.eq("stats cleared on leaving active", S().record.stats, null)
      h.eq("stats block hidden", h.find(A(), "statsBlock").visible, false)
      var e = h.find(A(), "daemonError")
      h.eq("daemon error shown", e.visible, true)
      h.check("daemon error sanitised", !/[<>&\n]/.test(e.text), e.text)
    })
    h.grabStep(function() { return strip }, "bar-error.png")
    h.grabStep(function() { return A().popup }, "panel-error.png")

    // pending re-arm: three asks while one runs -> the first and the latest
    h.step("slow commands", function() { h.writeFile("delay", ["0.6"]) }, function() { return h.writerIdle() })
    h.step("three asks in one turn", function() {
      h.markLog()
      S().setEnabled(true)
      S().setEnabled(false)
      S().selectCamera(brioId)
      h.check("busy while running", S().commandBusy)
    }, function() { return h.newLogArgs().length >= 2 }, 5000)
    h.wait(900)
    h.step("the latest ask ran after the first", function() {
      var got = h.newLogArgs()
      h.eq("runs", got.length, 2)
      h.eq("first", JSON.stringify(got[0]), JSON.stringify(["on"]))
      h.eq("latest", JSON.stringify(got[1]), JSON.stringify(["camera", "--", brioId]))
      h.eq("idle again", S().commandBusy, false)
    })

    // a queued ask is re-checked when it runs: the daemon went meanwhile
    h.step("queue an `on` behind a slow command", function() {
      h.notes.dropped = S().droppedIntents
      h.markLog()
      h.check("next runs", S().nextCamera())
      h.check("on queued", S().setEnabled(true))
      h.feed(['{"v":1,"type":"error","code":"daemon-not-running","error":"gone"}'])
    }, function() { return S().record.link === "not-running" })
    h.wait(1000)
    h.step("the queued `on` was dropped, not run", function() {
      var got = h.newLogArgs()
      h.eq("runs", JSON.stringify(got), JSON.stringify([["camera", "next"]]))
      h.eq("dropped intents", S().droppedIntents - h.notes.dropped, 1)
      h.eq("not busy", S().commandBusy, false)
      h.removeFile("delay")
      h.feed([snapshotLine({})])
    }, function() { return S().record.link === "ok" && h.writerIdle() })

    // a failing command shows a capped, sanitised message; a success clears it
    h.step("failing command", function() {
      h.writeFile("exit", ["1"])
      h.writeFile("stderr", ["omarchy-broadcast: no camera matches <img src=x> & more", "second line"])
    }, function() { return h.writerIdle() })
    h.step("run it", function() { S().selectCamera(fhdId) }, function() { return S().commandError !== "" })
    h.step("failure shown", function() {
      var t = S().commandError
      h.check("refusal text", t.indexOf("The daemon refused the request: no camera matches") === 0, t)
      h.check("first line only", t.indexOf("second") === -1, t)
      h.check("sanitised", !/[<>&]/.test(t), t)
      h.eq("panel shows it", h.find(A(), "commandError").visible, true)
      // 1 MB of stderr on one line, no newline at all
      h.enqueue(["sh", "-c", 'head -c 1000000 /dev/zero | tr "\\000" e > "$0"', shellRoot.fakeDir + "/stderr"])
    }, function() { return h.writerIdle() })
    h.step("1 MB stderr line", function() { S().commandError = ""; S().selectCamera(fhdId) },
           function() { return S().commandError !== "" && !S().commandBusy })
    h.step("stderr kept to its cap", function() {
      h.eq("kept", S().commandStderr.text.length, h.model.STDERR_CAP)
      h.check("shown capped", S().commandError.length <= h.model.DETAIL_CAP + 60, S().commandError.length)
      h.check("refusal text", S().commandError.indexOf("The daemon refused the request: eee") === 0, S().commandError.slice(0, 60))
      h.writeFile("exit", ["3"])
      h.removeFile("stderr")
    }, function() { return h.writerIdle() })
    h.step("exit 3", function() { S().nextCamera() }, function() { return S().commandError === "omarchy-broadcastd is not running" })
    h.step("success clears", function() {
      h.writeFile("exit", ["0"])
    }, function() { return h.writerIdle() })
    h.step("run a good one", function() { S().nextCamera() }, function() { return S().commandError === "" && !S().commandBusy })

    // a state string this plugin does not know: unavailable everywhere
    h.step("unknown state", function() {
      h.feed([stateLine({ state: "dancing" })])
    }, function() { return S().record.state === "unknown" })
    h.wait(200)
    h.step("unknown state is unavailable", function() {
      h.eq("glyph", A().iconButton.text, glyphOf("unavailable"))
      h.eq("tooltip", A().iconButton.tooltipText, "Omarchy Broadcast: unsupported state")
      h.eq("switch hidden", h.find(A(), "enableSwitch").visible, false)
      h.eq("cameras hidden", h.find(A(), "camerasBlock").visible, false)
      h.check("panel says so", h.find(A(), "unavailableTitle").text.indexOf("dancing") !== -1, h.find(A(), "unavailableTitle").text)
      h.eq("no cursor stops", h.content(A()).stops.length, 0)
      h.eq("no tab row", h.find(A(), "tabRow").visible, false)
      h.check("no tab chosen while unavailable", !h.content(A()).chooseTab(2))
      A().close()
      h.markLog()
      A().iconButton.triggerPress(Qt.RightButton)
      h.eq("right click opens the panel instead", A().opened, true)
      h.eq("description", A().iconButton.Accessible.description, "Click or right click: open the panel.")
    })
    h.wait(400)
    h.step("no command for an unknown state", function() {
      h.eq("commands run", h.newLogArgs().length, 0)
      h.feed([stateLine({ state: "idle" })])
    }, function() { return S().record.state === "idle" })

    // daemon goes away
    h.step("daemon-not-running", function() {
      h.feed(['{"v":1,"type":"error","code":"daemon-not-running","error":"omarchy-broadcastd is not running (no owner); start it with: systemctl --user start omarchy-broadcastd"}'])
    }, function() { return S().record.link === "not-running" })
    h.step("unavailable icon and panel", function() {
      h.eq("unavailable glyph", A().iconButton.text, glyphOf("unavailable"))
      h.eq("unavailable dimmed", A().iconButton.dimmed, true)
      h.check("distinct from off", glyphOf("unavailable") !== glyphOf("off"))
      h.eq("tooltip", A().iconButton.tooltipText, "Omarchy Broadcast: daemon not running")
      h.eq("hero status line", h.content(A()).heroMeta, "unavailable")
      h.eq("unavailable title", h.find(A(), "unavailableTitle").text, "omarchy-broadcastd is not running")
      h.eq("start command as text", h.find(A(), "unavailableCommand").text, "systemctl --user start omarchy-broadcastd")
      h.eq("switch hidden", h.find(A(), "enableSwitch").visible, false)
      h.eq("cameras hidden", h.find(A(), "camerasBlock").visible, false)
      A().close()
      h.markLog()
      A().iconButton.triggerPress(Qt.RightButton)
      h.eq("right click opens the panel instead", A().opened, true)
      h.feed([stateLine({ state: "idle" })])
    })
    h.wait(500)
    h.step("no command while unavailable", function() {
      h.eq("commands run", h.newLogArgs().length, 0)
      h.eq("state line ignored until a snapshot", S().record.link, "not-running")
    })
    h.grabStep(function() { return strip }, "bar-unavailable.png")
    h.grabStep(function() { return A().popup }, "panel-unavailable.png")
    h.step("new snapshot recovers", function() { h.feed([snapshotLine({})]) },
           function() { return S().record.link === "ok" && S().record.state === "idle" })

    // a CLI that predates effects: no blur_strength on its lines (JSON drops
    // undefined), and no `effect` command; the row offers nothing
    h.step("snapshot from a CLI without effects", function() {
      h.tab(A(), "effect")
      h.feed([snapshotLine({ blur_strength: undefined, background_image: undefined, denoise: undefined })])
    }, function() { return S().record.link === "ok" && S().record.cliEffects === false })
    h.step("the effect row is faded and names the CLI", function() {
      ["none", "blur", "replace"].forEach(function(e) {
        h.check(e + " faded", h.find(A(), "effectChoice-" + e).opacity < 1)
      })
      h.eq("hint", h.find(A(), "effectHint").text, "The omarchy-broadcast CLI needs updating for effects.")
      h.eq("no command", h.find(A(), "effectHintCommand").visible, false)
      h.eq("no effect stop", h.content(A()).stops.filter(function(st) { return st.kind === "effect" }).length, 0)
      // nor does it report noise removal: no switch, rather than an off one
      h.eq("unknown noise removal", S().record.denoise, null)
      h.eq("no noise removal row", h.find(A(), "denoiseRow").visible, false)
      h.eq("no noise removal stop", h.content(A()).stops.filter(function(st) { return st.kind === "denoise" }).length, 0)
      h.markLog()
      h.check("Blur refused", !h.content(A()).chooseEffect(1))
      h.check("noise removal refused", !h.content(A()).toggleDenoise())
      h.check("setDenoise refused", !S().setDenoise(true))
      h.eq("nothing ran", h.newLogArgs().length, 0)
    })
    h.grabStep(function() { return A().popup }, "panel-denoise-unknown.png")
    // a new CLI still talking to a daemon started before the upgrade
    // (interface revision 1): the row offers nothing and names the daemon
    h.step("snapshot from a daemon without effects", function() {
      h.feed([snapshotLine({ interface_revision: 1 })])
    }, function() { return S().record.cliEffects === true && S().record.interfaceRevision === 1 })
    h.step("the effect row is faded and names the daemon", function() {
      ["none", "blur", "replace"].forEach(function(e) {
        h.check(e + " faded", h.find(A(), "effectChoice-" + e).opacity < 1)
      })
      h.eq("hint", h.find(A(), "effectHint").text, "The daemon needs updating for effects.")
      h.eq("no command", h.find(A(), "effectHintCommand").visible, false)
      h.eq("no effect stop", h.content(A()).stops.filter(function(st) { return st.kind === "effect" }).length, 0)
      h.markLog()
      h.check("Blur refused", !h.content(A()).chooseEffect(1))
      h.eq("nothing ran", h.newLogArgs().length, 0)
    })
    // a background image with bidi and zero-width characters, while replacing
    h.step("replacing with a hostile image path", function() {
      h.feed([snapshotLine({ effect: "replace", background_image: "/h/\u202egnp.exe\u061c\u200b\ufeff<b>.png" })])
    }, function() { return S().record.effectKey === "replace" })
    h.step("the image row is sanitised and isolated", function() {
      var rows = h.content(A()).effectRows
      h.eq("one row", rows.length, 1)
      h.eq("value", rows[0].value, "\u2066/h/gnp.exeb.png\u2069")
      h.eq("no hint", h.find(A(), "effectHintBlock").visible, false)
      h.feed([snapshotLine({})])
    }, null)
    h.step("effects back", function() {}, function() { return S().record.cliEffects === true && S().record.effectKey === "none" })

    // the watch is killed by a signal; the respawned one reads a snapshot
    // whose multi-byte characters straddle a read boundary
    h.step("split snapshot for the respawn", function() {
      var line = JSON.stringify({ v: 1, type: "snapshot", state: "idle", enabled: true, error: "",
        active_camera: utfId, active_camera_name: utfName, consumers: 0, output_mode: "NV12 1920x1080@30",
        effect: "none", blur_strength: 0.5, background_image: "", interface_revision: 2,
        cameras: [{ id: utfId, name: utfName, usb: "1234:abcd", active: true },
                  { id: brioId, name: "Logitech MX Brio", usb: "046d:0944", active: false }],
        cameras_truncated: false }) + "\n"
      var bytes = h.utf8Bytes(line)
      // cut inside the first emoji: F0 9F | 98 80
      var cut = -1
      for (var i = 0; i < bytes.length; i++) if (bytes[i] === 0xf0) { cut = i + 2; break }
      h.check("cut found", cut > 0)
      h.notes.cut = cut
      h.writeBytes("snapshot.1", bytes.slice(0, cut))
      h.writeBytes("snapshot.2", bytes.slice(cut))
      h.writeFile("snapshot", [])
    }, function() { return h.writerIdle() })
    h.step("kill the watch by its PID (SIGKILL)", function() {
      h.check("watch pid known", S().watchPid > 0, S().watchPid)
      h.notes.starts = S().watchStarts
      h.mark = Date.now()
      h.killPid(S().watchPid, "KILL")
    }, function() { return S().backingOff })
    h.step("backing off", function() {
      h.eq("unavailable while respawning", S().record.link, "cli-failed")
      h.check("signal named", S().record.linkText.indexOf("omarchy-broadcast watch stopped by signal 9") === 0, S().record.linkText)
    }, function() { return S().watchStarts === h.notes.starts + 1 && S().record.link === "ok" }, 6000)
    h.step("respawned; the split name arrived whole", function() {
      var waited = Date.now() - h.mark
      h.check("respawn waited the backoff (~1 s)", waited >= 900, waited + " ms")
      h.note("respawn after " + waited + " ms; snapshot cut at byte " + h.notes.cut)
      h.eq("camera name intact", S().record.cameras[0].name, utfName)
      h.eq("camera id intact", S().record.cameras[0].selectId, utfId)
      h.eq("active camera name intact", S().record.activeCameraName, utfName)
      h.markLog()
      S().selectCamera(utfId)
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("multi-byte id reaches argv whole", function() {
      h.eq("argv", JSON.stringify(h.newLogArgs()[0]), JSON.stringify(["camera", "--", utfId]))
      h.removeFile("snapshot.1")
      h.removeFile("snapshot.2")
      h.writeFile("snapshot", [snapshotLine({})])
      h.feed([snapshotLine({})])
    }, function() { return h.writerIdle() && S().record.activeCamera === brioId && !S().commandBusy })
    h.countStep(1, "after respawn")

    // a line no v1 producer prints: the watch is stopped and backs off
    h.step("over-cap line", function() {
      h.notes.dropped = S().droppedLines
      h.notes.starts = S().watchStarts
      h.feed([overlongLine()])
    }, function() { return S().droppedLines === h.notes.dropped + 1 })
    h.step("over-cap line stops the watch", function() {
      h.eq("record", S().record.link, "unsupported")
      h.check("says why", S().record.linkText.indexOf("longer than 8192 characters") !== -1, S().record.linkText)
      h.eq("backing off", S().backingOff, true)
    }, function() { return S().watchStarts === h.notes.starts + 1 && S().record.link === "ok" }, 8000)
    h.step("over-cap: respawned and recovered", function() { h.note("over-cap respawn ok, backoff now " + S().backoffMs + " ms") })
    // F1 re-measure: an 8 MB line (the fallback reads it whole, then stops)
    h.step("RSS before an 8 MB line", function() { h.measureRss() }, function() { return h.rssDone })
    h.step("8 MB line", function() {
      h.notes.rssBefore = h.rss
      h.notes.dropped = S().droppedLines
      h.notes.starts = S().watchStarts
      gapTimer.maxGap = 0
      h.enqueue(["sh", "-c", '{ head -c 8000000 /dev/zero | tr "\\000" x; printf "\\n"; } >> "$0"', shellRoot.fakeDir + "/feed"])
    }, function() { return S().droppedLines === h.notes.dropped + 1 }, 15000)
    h.step("RSS after", function() { h.measureRss() }, function() { return h.rssDone })
    h.step("8 MB line: one line dropped, watch stopped", function() {
      h.note("8 MB line: RSS " + h.notes.rssBefore + " -> " + h.rss + ", max UI gap " + gapTimer.maxGap + " ms")
      h.eq("record", S().record.link, "unsupported")
    }, function() { return S().watchStarts === h.notes.starts + 1 && S().record.link === "ok" }, 12000)
    h.countStep(1, "after the over-cap lines")

    // reload (same URL): widgets destroyed, cache cleared if possible, rebuilt
    h.step("reload, same URL", function() {
      h.oldService = S()
      h.notes.startsBefore = S().watchStarts
      A().destroy()
      B().destroy()
      h.widgetA = null
      h.widgetB = null
      h.note("Qt.clearComponentCache available: " + h.clearCache())
    })
    h.wait(500)
    h.step("no readers, no watch", function() {
      h.eq("old service has no readers", h.oldService.attachedCount, 0)
      h.eq("old watch stopped", h.oldService.watchProc.running, false)
    })
    h.countStep(0, "between destroy and rebuild")
    h.step("rebuilt widgets reconnect", function() {
      h.widgetA = h.makeWidget(barA, { cliPath: shellRoot.cli })
      h.widgetB = h.makeWidget(barB, { cliPath: shellRoot.cli })
    }, function() { return h.widgetA && S().watchStarts > (S() === h.oldService ? h.notes.startsBefore : 0) && S().record.link === "ok" }, 8000)
    h.step("rebuilt", function() {
      h.note(S() === h.oldService ? "same-URL reload kept the singleton" : "same-URL reload made a new singleton")
      h.eq("attached widgets", S().attachedCount, 2)
    })
    h.countStep(1, "after a same-URL reload")

    // the shell's fast path: destroy and rebuild in one turn, no pause
    h.step("reload, same URL, rebuilt at once", function() {
      h.oldService = S()
      h.notes.startsBefore = S().watchStarts
      A().destroy()
      B().destroy()
      h.clearCache()
      h.widgetA = h.makeWidget(barA, { cliPath: shellRoot.cli })
      h.widgetB = h.makeWidget(barB, { cliPath: shellRoot.cli })
    }, function() { return h.widgetA && S().attachedCount === 2 && S().record.link === "ok" && S().watchProc.running }, 8000)
    h.wait(1500)
    h.step("rebuilt at once", function() {
      h.check("same singleton", S() === h.oldService)
      h.check("at most one restart", S().watchStarts - h.notes.startsBefore <= 1, S().watchStarts - h.notes.startsBefore)
      h.eq("still connected", S().record.link, "ok")
      h.eq("attached widgets", S().attachedCount, 2)
    })
    h.countStep(1, "after an immediate rebuild")

    // reload into a new singleton: the old one is stranded and must go silent
    h.step("reload into a new singleton (plugin at another URL)", function() {
      h.oldService = S()
      A().destroy()
      B().destroy()
      h.clearCache()
      h.widgetA = h.makeWidget(barA, { cliPath: shellRoot.cli }, shellRoot.pluginCopy)
      h.widgetB = h.makeWidget(barB, { cliPath: shellRoot.cli }, shellRoot.pluginCopy)
    }, function() { return h.widgetA && S().record.link === "ok" }, 8000)
    h.step("a new singleton, the old one silent", function() {
      h.check("new service instance", S() !== h.oldService)
      h.eq("new service watch started once", S().watchStarts, 1)
      h.eq("stranded service has no readers", h.oldService.attachedCount, 0)
      h.eq("stranded service watch stopped", h.oldService.watchProc.running, false)
    })
    h.countStep(1, "after reload (not 2)")
    h.wait(2500)
    h.countStep(1, "after reload, 2.5 s later")
    h.step("stranded service stayed silent", function() {
      h.eq("stranded watch still stopped", h.oldService.watchProc.running, false)
      h.eq("stranded backoff idle", h.oldService.backingOff, false)
    })

    // F2: a watch that prints its snapshot and exits keeps doubling its wait
    h.step("watch exits right after its snapshot", function() { h.writeFile("watch-exit", ["0"]) },
           function() { return h.writerIdle() })
    h.step("kill the running watch once", function() {
      h.notes.starts = S().watchStarts
      h.notes.spawns = h.watchSpawns()
      h.notes.times = []
      h.notes.lastSeen = S().watchStarts
      h.mark = Date.now()
      h.killPid(S().watchPid)
    }, function() { return S().backingOff })
    h.step("watch the respawns for 10.5 s", function() {}, function() {
      if (S().watchStarts !== h.notes.lastSeen) {
        h.notes.lastSeen = S().watchStarts
        h.notes.times.push(Date.now() - h.mark)
      }
      return Date.now() - h.mark >= 10500
    }, 12000)
    h.step("respawns doubled", function() {
      var t = h.notes.times
      var gaps = []
      for (var i = 1; i < t.length; i++) gaps.push(t[i] - t[i - 1])
      h.note("respawns at " + JSON.stringify(t) + " ms; gaps " + JSON.stringify(gaps) + "; fake log watch spawns "
             + (h.watchSpawns() - h.notes.spawns) + "; next delay " + S().backoffMs + " ms")
      h.check("at most 4 respawns in 10.5 s (1, 2, 4 s ...)", t.length >= 3 && t.length <= 4, t.length)
      for (var j = 1; j < gaps.length; j++)
        h.check("gap " + j + " about double the one before", gaps[j] >= gaps[j - 1] * 1.6, JSON.stringify(gaps))
      h.eq("spawns seen by the fake", h.watchSpawns() - h.notes.spawns, t.length)
      h.removeFile("watch-exit")
    }, function() { return h.writerIdle() })

    // search mode: no cliPath -> omarchy-broadcast on PATH (the fake)
    h.step("no cliPath: resolved from PATH", function() {
      h.oldService = S()
      A().destroy()
      B().destroy()
      h.clearCache()
      h.widgetA = h.makeWidget(barA, {})
      h.widgetB = null
    }, function() { return h.widgetA && S().record.link === "ok" && S().cliSource === "path" }, 8000)
    h.step("resolution", function() {
      h.eq("source", S().cliSource, "path")
      h.eq("path", S().cliPath, shellRoot.cli)
      h.notes.resolves = S().resolverRuns
      h.notes.starts = S().watchStarts
      h.widgetB = h.makeWidget(barB, {})
    }, function() { return S().resolverRuns > h.notes.resolves && !S().resolving })
    h.step("a searched path is looked up again on attach", function() {
      h.eq("one resolver run for the new widget", S().resolverRuns - h.notes.resolves, 1)
      h.eq("same answer, watch untouched", S().watchStarts, h.notes.starts)
      B().destroy()
      h.widgetB = null
    })

    // setting changed at runtime to a missing binary: bounded retries
    h.step("cliPath -> missing binary", function() {
      h.markLog()
      h.notes.failures = S().watchStartFailures
      h.notes.resolves = S().resolverRuns
      A().settings = { cliPath: "/nonexistent/omarchy-broadcast" }
      h.mark = Date.now()
    }, function() { return S().record.link === "cli-missing" })
    h.step("CLI not found", function() {
      h.eq("text", S().record.linkText, "omarchy-broadcast CLI not found: /nonexistent/omarchy-broadcast")
      h.eq("tooltip", A().iconButton.tooltipText, "Omarchy Broadcast: omarchy-broadcast CLI not found")
      h.eq("unavailable glyph", A().iconButton.text, glyphOf("unavailable"))
      A().close()
      A().iconButton.triggerPress(Qt.RightButton)
      h.eq("right click opens the panel", A().opened, true)
    })
    h.countStep(0, "with a missing CLI")
    h.step("the path is on a line of its own, never wrapped at a slash", function() {
      var title = h.find(A(), "unavailableTitle")
      var path = h.find(A(), "unavailablePath")
      h.eq("title", title.text, "omarchy-broadcast CLI not found:")
      h.eq("path", path.text, "/nonexistent/omarchy-broadcast")
      h.eq("path visible", path.visible, true)
      h.eq("path wraps anywhere", path.wrapMode, Text.WrapAnywhere)
      h.check("title holds no slash to wrap at", title.text.indexOf("/") === -1, title.text)
      h.eq("title on one line", title.lineCount, 1)
      h.eq("path on one line", path.lineCount, 1)
    })
    h.grabStep(function() { return A().popup }, "panel-cli-missing.png")
    h.step("3.5 s of a missing binary", function() {}, function() { return Date.now() - h.mark >= 3500 }, 5000)
    h.step("start attempts bounded by the backoff", function() {
      var n = S().watchStartFailures - h.notes.failures
      h.note("start failures in 3.5 s: " + n + ", next delay " + S().backoffMs + " ms")
      h.check("2 or 3 attempts in 3.5 s (0, 1, 3 s)", n >= 2 && n <= 3, n)
      h.eq("a configured path is not re-resolved", S().resolverRuns - h.notes.resolves, 0)
    })

    // a path longer than the panel is wide wraps inside the name, never at a slash
    h.step("cliPath -> a long path", function() {
      h.notes.longPath = "/nonexistent/a-rather-long-directory-name/another-long-directory/omarchy-broadcast-build/release/omarchy-broadcast"
      A().settings = { cliPath: h.notes.longPath }
    }, function() { return S().record.linkText === h.model.CLI_MISSING_TEXT + ": " + h.notes.longPath })
    h.step("long path on its own wrapping line", function() {
      var path = h.find(A(), "unavailablePath")
      h.eq("title", h.find(A(), "unavailableTitle").text, "omarchy-broadcast CLI not found:")
      h.eq("path kept whole", path.text, h.notes.longPath)
      h.check("it needs more than one line", path.lineCount > 1, path.lineCount)
    })
    h.grabStep(function() { return A().popup }, "panel-cli-missing-long.png")

    // the same path in a failed control command (the CLI would not start)
    h.step("command error with a long path", function() {
      S().commandError = h.model.commandFailureText(-1, "", h.notes.longPath)
    }, function() { return h.find(A(), "commandErrorPath").visible })
    h.step("command error path on its own line, close to its text", function() {
      var block = h.find(A(), "commandErrorBlock")
      var text = h.find(A(), "commandError")
      var path = h.find(A(), "commandErrorPath")
      h.eq("text", text.text, "omarchy-broadcast CLI not found:")
      h.eq("path kept whole", path.text, h.notes.longPath)
      h.eq("block visible", block.visible, true)
      h.eq("path wraps anywhere", path.wrapMode, Text.WrapAnywhere)
      h.check("path needs more than one line", path.lineCount > 1, path.lineCount)
      h.check("path sits below the text, closer than the panel's row spacing",
              path.y > text.y && path.y - (text.y + text.height) < 12, path.y - (text.y + text.height))
    })
    h.grabStep(function() { return A().popup }, "panel-command-error-long.png")
    h.step("command error cleared", function() { S().commandError = "" })

    // a relative cliPath runs nothing
    h.step("cliPath -> bare name", function() {
      h.markLog()
      h.notes.failures = S().watchStartFailures
      A().settings = { cliPath: "omarchy-broadcast" }
    }, function() { return S().record.linkText === "cliPath must be an absolute path" })
    h.wait(1200)
    h.step("bare name refused", function() {
      h.eq("link", S().record.link, "cli-missing")
      h.eq("nothing ran (fake log unchanged)", h.logLines().length - h.logMark, 0)
      h.eq("no start attempt", S().watchStartFailures - h.notes.failures, 0)
      h.eq("no CLI in force", S().cliPath, "")
      h.eq("panel says so", h.find(A(), "unavailableTitle").text, "cliPath must be an absolute path")
      h.eq("no path line", h.find(A(), "unavailablePath").visible, false)
      h.check("controls refuse", !S().setEnabled(true) && !S().nextCamera())
    })
    h.grabStep(function() { return A().popup }, "panel-cli-relative.png")
    h.step("cliPath restored", function() {
      A().close()
      A().settings = { cliPath: shellRoot.cli }
    }, function() { return S().record.link === "ok" }, 8000)
    h.countStep(1, "after the setting is restored")

    // 12 cameras (the producer's maximum) and a truncation flag on a screen
    // too short for the card: the screen caps its height, the content scrolls
    // (the fallback), and the cursor row is kept in view
    h.step("12 cameras", function() {
      h.feed([manyCamerasLine(12, true)])
      A().open()
    }, function() { return S().record.cameras.length === 12 && h.content(A()) !== null })
    h.step("on a short screen", function() {
      h.tab(A(), "camera")
      A().popup.availableCardHeight = 600
    })
    h.wait(400)
    h.step("panel capped and scrollable", function() {
      var flick = h.find(A(), "panelFlick")
      h.eq("rows", h.find(A(), "cameraRepeater").count, 12)
      h.check("card height capped by the screen", A().popup.height <= 600, A().popup.height + " > 600")
      h.check("content taller than the card", flick.contentHeight > flick.height, flick.contentHeight + " vs " + flick.height)
      h.eq("scrolls", flick.interactive, true)
      h.eq("truncation row", h.find(A(), "camerasTruncated").text, "More cameras are connected; they are not shown")
      h.eq("stops", h.content(A()).stops.length, 15)
    })
    h.grabStep(function() { return A().popup }, "panel-12-cameras.png")
    h.step("cursor to the last camera row", function() {
      h.key(Qt.Key_Down)
      for (var i = 0; i < 13; i++) h.key(Qt.Key_Down)
    })
    h.wait(400)
    h.step("cursor row kept in view", function() {
      var flick = h.find(A(), "panelFlick")
      var row = h.row(A(), 11)
      h.eq("row 11 has the cursor", row.hasCursor, true)
      h.check("scrolled", flick.contentY > 0, flick.contentY)
      var top = row.mapToItem(flick, 0, 0).y
      h.check("row inside the viewport", top >= 0 && top + row.height <= flick.height, top + " / " + flick.height)
    })
    h.grabStep(function() { return A().popup }, "panel-12-cameras-cursor.png")
    h.step("back to three cameras", function() {
      A().close()
      A().popup.availableCardHeight = shellRoot.card1080
      h.tab(A(), "effect")
      h.feed([snapshotLine({})])
    }, function() { return S().record.cameras.length === 3 })

    previewScenario()
    settingsScenario()

    // the resolver itself: PATH first, then the development build behind a
    // symlink (in the scratch development tree, not the plugin's checkout)
    var resolverCase = function(label, argv, path, wantOut, wantExit) {
      h.step("resolver: " + label, function() {
        h.resolverDone = false
        resolverProc.environment = { PATH: path }
        resolverProc.command = argv
        resolverProc.running = true
      }, function() { return h.resolverDone })
      h.step("resolver result: " + label, function() {
        h.eq("resolver " + label + " output", h.resolverOut, wantOut)
        h.eq("resolver " + label + " status", h.resolverExit, wantExit)
      })
    }
    // no system dir: an installed omarchy-broadcast would win over the case
    var rpath = Quickshell.env("OBH_RESOLVER_PATH") || ""
    var fakeBin = shellRoot.cli.replace(/\/omarchy-broadcast$/, "")
    var direct = function(dir) { return ["sh", "-c", h.model.RESOLVER_SCRIPT, "omarchy-broadcast-resolve", dir] }
    var nlPlugin = Quickshell.env("OBH_NLPLUGIN")
    var nlBin = Quickshell.env("OBH_NLBIN")
    resolverCase("PATH wins", h.model.resolverArgv(Quickshell.env("OBH_LINKED")), fakeBin + ":" + rpath, shellRoot.cli, 0)
    var devLink = Quickshell.env("OBH_DEVLINK")
    var devBuild = Quickshell.env("OBH_DEVCLI")
    resolverCase("development build through the symlink", h.model.resolverArgv(devLink), rpath, devBuild, 0)
    resolverCase("nothing found", h.model.resolverArgv(Quickshell.env("OBH_NOREPO")), rpath, "", 1)
    resolverCase("empty plugin dir still searches PATH", h.model.resolverArgv(""), fakeBin + ":" + rpath, shellRoot.cli, 0)
    resolverCase("empty plugin dir, nothing on PATH", h.model.resolverArgv(""), rpath, "", 1)
    resolverCase("plugin dir with a newline (argv refuses it)", h.model.resolverArgv(nlPlugin), rpath, "", 1)
    resolverCase("plugin dir with a newline (script refuses it)", direct(nlPlugin), rpath, "", 1)
    resolverCase("PATH entry with a newline is skipped", h.model.resolverArgv(devLink), nlBin + ":" + rpath, devBuild, 0)
    // a real omarchy-broadcast binary, found (not run) through a symlinked
    // plugin dir; optional, as the plugin's checkout carries no CLI
    var realLink = Quickshell.env("OBH_REALLINK") || ""
    var realCli = Quickshell.env("OBH_REALCLI") || ""
    if (realLink !== "" && realCli !== "")
      resolverCase("real CLI through the symlink (OMARCHY_BROADCAST_CLI)", h.model.resolverArgv(realLink), rpath, realCli, 0)
    else
      h.step("resolver: real CLI through the symlink", function() {
        console.log("  SKIP resolver real CLI through the symlink: OMARCHY_BROADCAST_CLI is not set")
      })
    h.step("newline fixtures exist", function() {
      h.check("resolver PATH set", rpath !== "" && rpath.charAt(0) === "/", rpath)
      h.check("plugin dir has a newline", nlPlugin.indexOf("\n") !== -1)
      h.check("PATH entry has a newline", nlBin.indexOf("\n") !== -1)
    })

    // the development build, found through Daemon.pluginDir of a symlinked
    // plugin dir in a scratch repository; re-resolved after a start failure
    var devCli = Quickshell.env("OBH_DEVCLI")
    h.step("hide the PATH CLI", function() {
      A().destroy()
      h.widgetA = null
      h.enqueue(["mv", "--", shellRoot.cli, shellRoot.cli + ".off"])
    }, function() { return h.writerIdle() })
    h.step("widget from the symlinked dev plugin", function() {
      h.widgetA = h.makeWidget(barA, {}, Quickshell.env("OBH_DEVLINK"))
    }, function() { return h.widgetA && S().record.link === "ok" }, 8000)
    h.step("development build resolved", function() {
      h.eq("pluginDir is the symlink path", S().pluginDir, Quickshell.env("OBH_DEVLINK"))
      h.eq("source", S().cliSource, "development")
      h.eq("path", S().cliPath, devCli)
      // replaced (new inode) by a file the resolver accepts but cannot start
      h.enqueue(["sh", "-c", 'printf "#!/nonexistent/interpreter\\n" > "$0.new" && chmod +x "$0.new" && mv -f "$0.new" "$0"', devCli])
    }, function() { return h.writerIdle() })
    h.step("kill the dev watch", function() {
      h.notes.failures = S().watchStartFailures
      h.notes.resolves = S().resolverRuns
      h.notes.killedAt = Date.now()
      h.killPid(S().watchPid)
    }, function() { return S().watchStartFailures - h.notes.failures >= 2 }, 8000)
    h.wait(300)
    h.step("one re-resolution per failed start", function() {
      var f = S().watchStartFailures - h.notes.failures
      var r = S().resolverRuns - h.notes.resolves
      var since = Date.now() - h.notes.killedAt
      h.note("dev build unstartable: " + f + " failures, " + r + " resolver runs in " + since + " ms")
      h.eq("resolver runs = failures", r, f)
      h.check("second failure waited the doubled backoff (>= ~3 s)", since >= 2700, since)
      h.eq("still the dev path", S().cliPath, devCli)
      h.enqueue(["rm", "-f", "--", devCli])
    }, function() { return h.writerIdle() })
    h.step("dev build removed: the next failure re-resolves to nothing", function() {},
           function() { return S().cliPath === "" && S().record.link === "cli-missing" }, 10000)
    h.step("says what was searched", function() {
      var t = S().record.linkText
      h.check("names PATH and the dev path", t.indexOf("not on PATH") !== -1
              && t.indexOf(Quickshell.env("OBH_DEVLINK") + "/../../../target/release/omarchy-broadcast") !== -1, t)
      h.notes.failures = S().watchStartFailures
      h.notes.resolves = S().resolverRuns
    })
    h.wait(3000)
    h.step("then nothing runs on a timer", function() {
      h.eq("no more start attempts", S().watchStartFailures - h.notes.failures, 0)
      h.eq("no more resolver runs", S().resolverRuns - h.notes.resolves, 0)
      h.enqueue(["sh", "-c", 'cp -- "$1" "$0" && chmod +x "$0"', devCli, shellRoot.cli + ".off"])
    }, function() { return h.writerIdle() })
    h.step("dev build back; a new widget attaches and re-resolves", function() {
      h.notes.resolves = S().resolverRuns
      h.widgetB = h.makeWidget(barB, {}, Quickshell.env("OBH_DEVLINK"))
    }, function() { return S().record.link === "ok" && S().cliPath === devCli }, 8000)
    h.step("recovered on attach", function() {
      h.eq("one resolver run", S().resolverRuns - h.notes.resolves, 1)
      h.eq("source", S().cliSource, "development")
      A().destroy()
      B().destroy()
      h.widgetA = null
      h.widgetB = null
      h.enqueue(["mv", "--", shellRoot.cli + ".off", shellRoot.cli])
    }, function() { return h.writerIdle() })

    // zero widgets -> zero watch processes
    h.wait(500)
    h.countStep(0, "with zero widgets at the end")
    h.countStep(0, "of the dev build at the end", devCli)
  }

  // ---- the live preview (mock): R1, one process, ingestion, settings -------------
  //
  // The fake's `preview --json` writes real JPEGs into this shell's scratch
  // XDG_RUNTIME_DIR (run-harness.sh) and prints the CLI's NDJSON lines.
  function previewScenario() {
    var A = function() { return h.widgetA }
    var B = function() { return h.widgetB }
    var S = function() { return h.widgetA.service }
    var P = function() { return h.widgetA.previewService }
    var rt = Quickshell.env("XDG_RUNTIME_DIR")
    var framePath = rt + "/omarchy-broadcast/preview.jpg"
    var rev5 = function(o) {
      var m = { interface_revision: 5, loopback_consumers: 0, pipewire_consumers: 0 }
      for (var k in o) m[k] = o[k]
      return m
    }
    // Every source the Image is given, and how many reloads it does.
    // (Whether the last frame stays painted during a reload is not visible
    // in any property here — paintedWidth keeps its value either way — so
    // retainWhileLoading is asserted by check-source.py instead.)
    var probe = function() {
      var img = h.find(A(), "previewImage")
      if (!img || h.notes.probed === img) return
      h.notes.probed = img
      h.notes.sources = []
      h.notes.loads = 0
      img.sourceChanged.connect(function() { h.notes.sources.push(String(img.source)) })
      img.statusChanged.connect(function() { if (img.status === Image.Loading) h.notes.loads++ })
    }
    var foreignSources = function() {
      var bad = []
      var want = "file://" + framePath + "?"
      for (var i = 0; i < h.notes.sources.length; i++) {
        var src = h.notes.sources[i]
        if (src !== "" && !(src.indexOf(want) === 0 && /^\d+$/.test(src.slice(want.length)))) bad.push(src)
      }
      return bad
    }

    h.step("preview: a revision-5 daemon, idle, panel closed, two monitors", function() {
      // The second monitor's widget, from the same URL as the first (one
      // singleton); destroyed again at the end of these checks.
      if (h.widgetB) h.widgetB.destroy()
      h.widgetB = h.makeWidget(barB, { cliPath: shellRoot.cli })
      h.removeFile("preview-hostile")
      h.removeFile("preview-exit")
      h.removeFile("preview-error")
      h.feed([snapshotLine(rev5({}))])
    }, function() { return S().record.interfaceRevision === 5 && S().attachedCount === 2 && h.writerIdle() })
    h.wait(300)
    h.step("preview: nothing while no panel is open", function() {
      h.eq("expected path under the scratch XDG_RUNTIME_DIR", P().expectedPath, framePath)
      h.check("XDG_RUNTIME_DIR is the harness's", rt === shellRoot.fakeDir.replace(/\/fake$/, "/runtime"), rt)
      h.eq("both widgets share one preview service", A().previewService === B().previewService, true)
      h.eq("supported", P().supported, true)
      h.eq("switch off by default", P().switchOn, false)
      h.eq("fps 15 by default", P().fps, 15)
      h.eq("not wanted", P().wanted, false)
      h.eq("never started", P().starts, 0)
    })
    h.previewCountStep(0, "panel closed")

    h.step("preview: open the panel while idle", function() { A().open() }, function() { return h.content(A()) !== null })
    h.wait(500)
    h.step("preview: the panel does not start the camera", function() {
      probe()
      h.eq("held by the open panel", P().heldCount, 1)
      h.eq("not wanted", P().wanted, false)
      h.eq("never started", P().starts, 0)
      h.eq("note", h.find(A(), "previewNote").text, "Camera idle; turn on Preview to start it")
      h.eq("note shown", h.find(A(), "previewNote").visible, true)
      h.eq("in the 16:9 frame area, which keeps its place", h.find(A(), "previewFrame").visible
           && h.find(A(), "previewNote").parent === h.find(A(), "previewFrame"), true)
      h.eq("image hidden", h.find(A(), "previewImage").visible, false)
      h.eq("note in the dim colour", h.find(A(), "previewNote").color, h.content(A()).dim)
      h.eq("switch shown, off", h.find(A(), "previewToggle").visible && !h.find(A(), "previewToggle").checked, true)
      h.eq("rate label", h.find(A(), "fpsRow") !== null, true)
      h.eq("15 fps selected", h.fpsChip(A(), 15).selected, true)
      h.eq("nothing written on open", fakeShell.calls.length, 0)
      h.eq("nothing unsaved", h.find(A(), "previewUnsaved").visible, false)
      // Column order (hidden items keep no place, so order, not y)
      var block = h.find(A(), "previewBlock")
      var kids = block.parent.children
      var at = function(name) { for (var i = 0; i < kids.length; i++) if (kids[i].objectName === name) return i; return -1 }
      h.check("the preview follows the header and the error blocks, before the tabs",
              at("previewBlock") > at("daemonError") && at("previewBlock") > at("commandErrorBlock")
              && at("daemonError") > at("hero") && at("previewBlock") < at("tabBlock"),
              [at("hero"), at("daemonError"), at("commandErrorBlock"), at("previewBlock"), at("tabBlock")].join(","))
      var row = h.find(A(), "previewControls")
      h.check("the switch and the rate share one row under the frame",
              row.visible && h.find(A(), "previewRow").parent === row && h.find(A(), "fpsRow").parent === row
              && row.y > h.find(A(), "previewFrame").y, String(row.y))
    })
    h.previewCountStep(0, "panel open, idle, switch off")
    h.grabStep(function() { return A().popup }, "v1-preview-off.png")

    h.step("preview: active for preview leases only", function() {
      h.feed([stateLine(rev5({ state: "active", consumers: 1 }))])
    }, function() { return S().record.state === "active" })
    h.wait(400)
    h.step("preview: switch off + active + only a preview consumer: nothing (R1)", function() {
      h.eq("not wanted", P().wanted, false)
      h.eq("never started", P().starts, 0)
      h.eq("note", h.find(A(), "previewNote").text, "Preview off")
      h.eq("the frame area keeps its place", h.find(A(), "previewFrame").visible, true)
    })
    h.previewCountStep(0, "active for preview leases only")

    h.step("preview: an app opens the loopback: shown at once", function() {
      h.feed([stateLine(rev5({ state: "active", consumers: 2, loopback_consumers: 1 }))])
    }, function() { return P().frames >= 3 && h.find(A(), "previewImage").status === Image.Ready }, 8000)
    h.step("preview: frames", function() {
      var img = h.find(A(), "previewImage")
      h.eq("started once", P().starts, 1)
      h.eq("argv", JSON.stringify(P().lastArgv), JSON.stringify([shellRoot.cli, "preview", "--json", "--fps", "15"]))
      h.eq("the fake, never an installed CLI", P().lastArgv[0], shellRoot.cli)
      h.eq("lease held", P().leaseActive, true)
      h.eq("image shown", img.visible, true)
      h.eq("placeholder hidden", h.find(A(), "previewPlaceholder").visible, false)
      h.eq("frame size", img.implicitWidth + "x" + img.implicitHeight, "480x270")
      h.eq("decoded at most at the frame size", img.sourceSize.width + "x" + img.sourceSize.height, "480x270")
      h.eq("frame area is 16:9", Math.abs(h.find(A(), "previewFrame").height - h.find(A(), "previewFrame").width * 9 / 16) <= 1, true)
      h.eq("note hidden", h.find(A(), "previewNote").visible, false)
      h.check("source is the expected path", String(img.source).indexOf("file://" + framePath + "?") === 0, String(img.source))
      h.eq("no frame dropped", P().droppedFrames, 0)
      h.notes.seq = P().seq
      h.notes.source = String(img.source)
    })
    h.wait(600)
    h.step("preview: the image updates", function() {
      var img = h.find(A(), "previewImage")
      h.check("seq moved", P().seq > h.notes.seq, P().seq + " vs " + h.notes.seq)
      h.check("source moved", String(img.source) !== h.notes.source, String(img.source))
      h.note("preview at 15 fps: " + P().frames + " frames, " + h.notes.loads + " image loads")
      h.check("one load per frame shown", h.notes.loads >= 3, h.notes.loads)
    })
    h.previewCountStep(1, "active with a loopback consumer", 15)
    h.grabStep(function() { return A().popup }, "v1-preview-active.png")

    h.step("preview: the loopback consumer leaves", function() {
      h.feed([stateLine(rev5({ state: "active", consumers: 1, loopback_consumers: 0 }))])
    }, function() { return !P().running })
    h.step("preview: its own lease does not hold it (R1)", function() {
      h.eq("note", h.find(A(), "previewNote").text, "Preview off")
      h.eq("image hidden", h.find(A(), "previewImage").visible, false)
      h.eq("no error", P().exitError, "")
    })
    h.previewCountStep(0, "after the other consumer left")

    // the switch: a user's action, persisted through updateEntryInline
    h.step("preview: click the Preview switch", function() {
      h.find(A(), "previewToggle").toggled()
    }, function() { return P().running && P().frames >= 1 }, 8000)
    h.step("preview: a frame shown with the switch on", null,
           function() { return P().frames >= 3 && h.find(A(), "previewImage").status === Image.Ready }, 8000)
    h.grabStep(function() { return A().popup }, "v1-preview-on.png")
    h.step("preview: a light palette", function() { h.lightPalette(true) })
    h.wait(300)
    h.step("preview: theme colours on a light palette", function() {
      h.eq("panel foreground follows the theme", h.content(A()).foreground, Commons.Color.bar.text)
      h.check("the frame area is black only behind a frame", String(h.find(A(), "previewFrame").color) === "#000000",
              String(h.find(A(), "previewFrame").color))
    })
    h.grabStep(function() { return A().popup }, "v1-preview-light.png")
    h.step("preview: the theme's palette again", function() {
      h.notes.lightAccent = String(Commons.Color.accent)
      h.lightPalette(false)
      h.check("the accent is back", String(Commons.Color.accent) !== h.notes.lightAccent, String(Commons.Color.accent))
    })
    h.step("preview: the switch is persisted and starts it", function() {
      h.eq("one write", fakeShell.calls.length, 1)
      var call = fakeShell.calls[0]
      h.eq("entry id", call.id, shellRoot.moduleName)
      h.eq("entry", JSON.stringify(call.entry), JSON.stringify({ id: shellRoot.moduleName, cliPath: shellRoot.cli, previewEnabled: true }))
      h.eq("switch on", P().switchOn, true)
      h.eq("switch drawn on", h.find(A(), "previewToggle").checked, true)
      h.eq("second start", P().starts, 2)
      // the other monitor's panel
      B().open()
    }, function() { return h.content(B()) !== null })
    h.wait(400)
    h.step("preview: two panels, one process", function() {
      h.eq("held twice", P().heldCount, 2)
      h.eq("still the second start", P().starts, 2)
      h.eq("B shows the frame too", h.find(B(), "previewImage").visible, true)
      var bimg = h.find(B(), "previewImage")
      h.notes.bLoads = 0
      if (h.notes.bProbed !== bimg) {
        h.notes.bProbed = bimg
        bimg.statusChanged.connect(function() { if (bimg.status === Image.Loading) h.notes.bLoads++ })
      }
      A().close()
      h.notes.loadsAtClose = h.notes.loads
    })
    h.wait(1000)
    h.step("preview: A closed, B still holds it", function() {
      h.eq("held once", P().heldCount, 1)
      h.eq("running", P().running, true)
      h.eq("no restart", P().starts, 2)
      // A's content is kept once built: its Image must not follow the frames.
      h.eq("the closed panel's Image has no source", String(h.find(A(), "previewImage").source), "")
      h.eq("the closed panel loads nothing", h.notes.loads - h.notes.loadsAtClose, 0)
      h.check("while the open one loads frames", h.notes.bLoads >= 5, h.notes.bLoads)
      h.note("1 s with A closed: A " + (h.notes.loads - h.notes.loadsAtClose) + " loads, B " + h.notes.bLoads)
    })
    h.previewCountStep(1, "two panels, then one")
    h.step("preview: close the last panel", function() { B().close() }, function() { return !P().running })
    h.previewCountStep(0, "every panel closed")
    h.step("preview: no stray frame file left by the fake", function() {
      h.eq("held by nobody", P().heldCount, 0)
      h.eq("no restart", P().starts, 2)
    })

    // hostile lines on the stream, delivered by the next start
    h.step("preview: hostile lines for the next start", function() {
      h.writeFile("preview-hostile", [
        JSON.stringify({ v: 1, type: "frame", seq: 999999, path: "/etc/passwd" }),
        JSON.stringify({ v: 1, type: "frame", seq: 999998, path: framePath + "?x=1" }),
        JSON.stringify({ v: 1, type: "frame", seq: 999997, path: rt + "/omarchy-broadcast/../../../etc/shadow" }),
        JSON.stringify({ v: 1, type: "frame", seq: "7", path: framePath }),
        JSON.stringify({ v: 2, type: "frame", seq: 999996, path: framePath }),
        JSON.stringify({ v: 1, type: "bogus", path: "/etc/passwd" }),
        "<img src='http://127.0.0.1:9/beacon'>"
      ])
    }, function() { return h.writerIdle() })
    h.step("preview: reopen the panel (switch on)", function() { A().open() }, function() { return P().running && P().frames >= 1 }, 8000)
    h.step("preview: reopened, the switch persisted, it restarts", function() {
      h.eq("third start", P().starts, 3)
      h.eq("one panel", P().heldCount, 1)
    })
    h.wait(300)
    h.step("preview: hostile lines dropped", function() {
      h.eq("frame lines dropped (3 paths, 1 seq)", P().droppedFrames, 4)
      h.check("other lines ignored", P().ignoredLines >= 3, P().ignoredLines)
      h.check("seq not advanced by a hostile line", P().seq > 0 && P().seq < 1000, P().seq)
      h.eq("no source but the expected path", JSON.stringify(foreignSources()), "[]")
      h.removeFile("preview-hostile")
    }, function() { return h.writerIdle() })

    // the frame rate: a user's action; a restart with the new argv
    h.step("preview: choose 30 fps", function() {
      h.fpsChip(A(), 30).clicked()
    }, function() { return P().running && P().fps === 30 && P().lastArgv && P().lastArgv[4] === "30" && P().frames >= 1 }, 8000)
    h.step("preview: restarted at 30 fps", function() {
      h.eq("second write", fakeShell.calls.length, 2)
      h.eq("entry", JSON.stringify(fakeShell.calls[1].entry),
           JSON.stringify({ id: shellRoot.moduleName, cliPath: shellRoot.cli, previewEnabled: true, previewFps: 30 }))
      h.eq("argv", JSON.stringify(P().lastArgv), JSON.stringify([shellRoot.cli, "preview", "--json", "--fps", "30"]))
      h.eq("fourth start", P().starts, 4)
      h.eq("30 fps selected", h.fpsChip(A(), 30).selected, true)
      h.eq("argv in the fake's log", h.logLines().some(function(l) { return l.indexOf(" [preview] [--json] [--fps] [30]") !== -1 }), true)
    })
    h.previewCountStep(1, "after the change", 30)
    h.previewCountStep(0, "after the change", 15)

    // a monitor plugged in while a 30 fps preview runs: the new widget is
    // created, then handed the same entry, as the bar does (S2)
    h.step("preview: a third widget while previewing at 30 fps", function() {
      h.notes.starts = P().starts
      h.notes.widgetC = h.makeWidget(barB, JSON.parse(JSON.stringify(A().settings)))
    })
    h.wait(600)
    h.step("preview: the new widget restarts nothing", function() {
      h.eq("no restart", P().starts, h.notes.starts)
      h.eq("still 30 fps", P().fps, 30)
      h.eq("still running", P().running, true)
      h.eq("argv", P().lastArgv[4], "30")
      h.notes.widgetC.destroy()
      h.notes.widgetC = null
      // settings that blip within one turn (another entry, then this one
      // again): the restart is looked at on the next turn only
      var keep = JSON.parse(JSON.stringify(A().settings))
      A().settings = { cliPath: shellRoot.cli }
      A().settings = keep
    })
    h.wait(600)
    h.step("preview: a blip within one turn restarts nothing", function() {
      h.eq("no restart", P().starts, h.notes.starts)
      h.eq("still 30 fps", P().fps, 30)
      h.eq("no failure", P().failed, false)
    })
    h.previewCountStep(1, "after the new widget", 30)

    // keyboard: the preview switch and the frame-rate row are cursor stops
    h.step("preview: first Down shows the cursor", function() { h.key(Qt.Key_Down) }, function() { return h.content(A()).cursorActive })
    h.step("preview: Down to the Preview switch", function() {
      h.eq("on the on/off switch first", h.content(A()).currentStop.kind, "switch")
      h.key(Qt.Key_Down)
    }, function() { return h.content(A()).currentStop.kind === "preview" })
    h.step("preview: the switch has the cursor; Down to the frame rate", function() {
      h.eq("preview switch has the cursor", h.find(A(), "previewToggle").hasCursor, true)
      h.eq("stops = switch + preview + fps + tab row + effect + noise removal (the Effect tab)",
           h.content(A()).stops.length, 6)
      h.key(Qt.Key_Down)
    }, function() { return h.content(A()).currentStop.kind === "fps" })
    h.step("preview: lands on the current rate; Left, Enter: 15 fps", function() {
      h.eq("cursor on 30 (current)", h.fpsChip(A(), 30).hasCursor, true)
      h.key(Qt.Key_Left)
      h.eq("cursor on 15", h.fpsChip(A(), 15).hasCursor, true)
      h.eq("cursor not on 30", h.fpsChip(A(), 30).hasCursor, false)
      h.key(Qt.Key_Return)
    }, function() { return P().running && P().lastArgv[4] === "15" && P().frames >= 1 }, 8000)
    h.step("preview: 15 fps from the keyboard", function() {
      h.eq("third write", fakeShell.calls.length, 3)
      h.eq("fifth start", P().starts, 5)
      h.key(Qt.Key_Down)
      h.eq("then the tab row", h.content(A()).currentStop.kind, "tabs")
      h.key(Qt.Key_Up)
      h.key(Qt.Key_Up)
      h.eq("back on the Preview switch", h.content(A()).currentStop.kind, "preview")
      h.key(Qt.Key_Return)
    }, function() { return !P().running })
    h.step("preview: Enter turned it off (active for previews only)", function() {
      h.eq("fourth write", fakeShell.calls.length, 4)
      h.eq("entry", JSON.stringify(fakeShell.calls[3].entry),
           JSON.stringify({ id: shellRoot.moduleName, cliPath: shellRoot.cli, previewEnabled: false, previewFps: 15 }))
      h.eq("note", h.find(A(), "previewNote").text, "Preview off")
    })
    h.previewCountStep(0, "switched off from the keyboard")

    // an unexpected exit: shown, and not respawned until the rule re-arms
    h.step("preview: PipeWire consumer: shown at once", function() {
      h.feed([stateLine(rev5({ state: "active", consumers: 2, pipewire_consumers: 1 }))])
    }, function() { return P().running && P().frames >= 1 }, 8000)
    h.step("preview: kill the preview child (SIGKILL)", function() {
      h.notes.starts = P().starts
      h.killPid(P().pid, "KILL")
    }, function() { return !P().running })
    h.wait(1500)
    h.step("preview: the exit is shown, nothing respawns", function() {
      h.eq("no restart", P().starts, h.notes.starts)
      h.eq("failed", P().failed, true)
      var t = h.find(A(), "previewNote").text
      h.check("the reason", t.indexOf("stopped by signal 9") !== -1 && t.indexOf("Reopen the panel to retry.") !== -1, t)
      h.eq("drawn as an error", h.find(A(), "previewNote").color, Commons.Color.urgent)
      h.eq("in the frame area", h.find(A(), "previewFrame").visible, true)
    })
    h.previewCountStep(0, "after the crash")
    h.step("preview: the next start exits on its own", function() { h.writeFile("preview-exit", ["1"]) },
           function() { return h.writerIdle() })
    h.step("preview: close and reopen re-arms", function() {
      A().close()
      Qt.callLater(function() { A().open() })
    }, function() { return P().starts === h.notes.starts + 1 && !P().running && P().failed }, 8000)
    h.step("preview: an exit status is shown too", function() {
      var t = h.find(A(), "previewNote").text
      h.check("status 1", t.indexOf("exited with status 1") !== -1, t)
      h.removeFile("preview-exit")
    }, function() { return h.writerIdle() })

    // a choice the shell cannot store (S7: an entry over the key cap; S8: no
    // layout entry): in force for the session, said so, and not undone by a
    // widget re-injected with the same entry. Here the switch moves nothing
    // (a PipeWire consumer already wants the preview).
    h.step("preview: an entry over the key cap", function() {
      h.notes.calls = fakeShell.calls.length
      h.notes.saved = JSON.parse(JSON.stringify(A().settings))
      var huge = JSON.parse(JSON.stringify(A().settings))
      for (var i = 0; i <= 300; i++) huge["junk" + i] = i
      A().settings = huge
      h.notes.switchBefore = P().switchOn
      h.find(A(), "previewToggle").toggled()
    })
    h.wait(200)
    h.step("preview: not written, in force, and said so", function() {
      h.eq("no write", fakeShell.calls.length, h.notes.calls)
      h.eq("switch moved for the session", P().switchOn, !h.notes.switchBefore)
      h.eq("unsaved", P().unsaved, true)
      h.eq("message shown", h.find(A(), "previewUnsaved").visible, true)
      h.eq("message", h.find(A(), "previewUnsaved").text, "Could not save the preview setting")
      h.find(A(), "previewToggle").toggled()
    })
    h.wait(200)
    h.step("preview: switched back, nothing unsaved", function() {
      h.eq("no write", fakeShell.calls.length, h.notes.calls)
      h.eq("switch as stored", P().switchOn, h.notes.switchBefore)
      h.eq("message hidden", h.find(A(), "previewUnsaved").visible, false)
      A().settings = h.notes.saved
      fakeShell.refuse = true
      h.find(A(), "previewToggle").toggled()
    })
    h.wait(200)
    h.step("preview: the shell finds no entry (answers false)", function() {
      h.eq("one refused write", fakeShell.refused.length, 1)
      h.eq("the refused entry", JSON.stringify(fakeShell.refused[0].entry),
           JSON.stringify({ id: shellRoot.moduleName, cliPath: shellRoot.cli, previewEnabled: !h.notes.switchBefore, previewFps: 15 }))
      h.eq("switch moved for the session", P().switchOn, !h.notes.switchBefore)
      h.eq("message shown", h.find(A(), "previewUnsaved").visible, true)
      h.eq("the widget's settings stay as the bar gave them", A().settings.previewEnabled, h.notes.switchBefore)
      // the other monitor's widget handed the same, stale entry again, and a
      // monitor plugged in with it
      B().settings = JSON.parse(JSON.stringify(h.notes.saved))
      A().settings = JSON.parse(JSON.stringify(h.notes.saved))
      h.notes.widgetC = h.makeWidget(barB, JSON.parse(JSON.stringify(h.notes.saved)))
    })
    h.wait(300)
    h.step("preview: re-injected stale settings do not undo it", function() {
      h.eq("switch still as chosen", P().switchOn, !h.notes.switchBefore)
      h.eq("message still shown", h.find(A(), "previewUnsaved").visible, true)
      h.notes.widgetC.destroy()
      h.notes.widgetC = null
      // a value the stored entry itself changes does replace it
      var changed = JSON.parse(JSON.stringify(h.notes.saved))
      changed.previewEnabled = !h.notes.switchBefore
      B().settings = changed
    })
    h.wait(200)
    h.step("preview: a stored change wins", function() {
      h.eq("switch as stored", P().switchOn, !h.notes.switchBefore)
      h.eq("nothing unsaved", P().unsaved, false)
      var back = JSON.parse(JSON.stringify(h.notes.saved))
      A().settings = back
      B().settings = JSON.parse(JSON.stringify(back))
      fakeShell.refuse = false
    })
    h.wait(200)
    h.step("preview: back as stored", function() {
      h.eq("switch", P().switchOn, h.notes.switchBefore)
      h.eq("nothing unsaved", P().unsaved, false)
      h.eq("no write but the refused one", fakeShell.calls.length, h.notes.calls)
    })

    // an exit that lands once the panel is closed is no failure (S5): the
    // next open starts it, the first time
    h.step("preview: reopen after the failure", function() {
      A().close()
      Qt.callLater(function() { A().open() })
    }, function() { return P().running && P().frames >= 1 && !P().failed }, 8000)
    // A rejected line stops the child (not a deliberate stop); the panel is
    // closed in that same turn, so the exit lands with the rule already false.
    h.step("preview: an over-cap line for the next start", function() {
      var long = ""
      while (long.length <= 9000) long += "x"
      h.writeFile("preview-hostile", [long])
      if (!h.notes.rejectHooked) {
        h.notes.rejectHooked = true
        P().rejectedChanged.connect(function() {
          if (h.notes.closeOnReject && P().rejected) { h.notes.closeOnReject = false; A().close() }
        })
      }
    }, function() { return h.writerIdle() })
    h.step("preview: the line is rejected as the panel closes", function() {
      h.notes.starts = P().starts
      h.notes.droppedLines = P().droppedLines
      A().close()
      Qt.callLater(function() { h.notes.closeOnReject = true; A().open() })
    }, function() { return P().starts === h.notes.starts + 1 && !P().running && P().heldCount === 0 && !h.notes.closeOnReject }, 8000)
    h.wait(300)
    h.step("preview: no failure kept for a closed panel", function() {
      h.eq("the line was rejected", P().droppedLines, h.notes.droppedLines + 1)
      h.eq("not failed", P().failed, false)
      h.eq("no error kept", P().exitError, "")
      h.removeFile("preview-hostile")
    }, function() { return h.writerIdle() })
    h.step("preview: reopen", function() {
      h.notes.starts = P().starts
      A().open()
    }, function() { return P().running && P().frames >= 1 }, 8000)
    h.step("preview: the first reopen starts it", function() {
      h.eq("one more start", P().starts, h.notes.starts + 1)
      h.notes.starts = P().starts
    })

    // a daemon below revision 5: a note, no controls, nothing runs
    h.step("preview: a revision-4 daemon", function() {
      h.feed([snapshotLine({ state: "active", consumers: 2, loopback_consumers: 1, pipewire_consumers: 1 })])
    }, function() { return S().record.interfaceRevision === 4 })
    h.wait(600)
    h.step("preview: needs 0.18", function() {
      h.eq("note", h.find(A(), "previewNote").text, "Preview needs omarchy-broadcast 0.18 or newer")
      h.eq("note shown", h.find(A(), "previewNote").visible, true)
      h.eq("the frame area keeps its place", h.find(A(), "previewFrame").visible, true)
      h.eq("switch hidden", h.find(A(), "previewRow").visible, false)
      h.eq("rate hidden", h.find(A(), "fpsRow").visible, false)
      h.eq("not supported", P().supported, false)
      h.eq("no restart", P().starts, h.notes.starts)
      h.eq("no preview stops", h.content(A()).stops.map(function(st) { return st.kind }).indexOf("preview"), -1)
    })
    h.previewCountStep(0, "revision 4")
    h.grabStep(function() { return A().popup }, "v1-preview-old-daemon.png")
    h.step("preview: back to the default fixture", function() {
      A().close()
      A().settings = { cliPath: shellRoot.cli }
      B().destroy()
      h.widgetB = null
      h.feed([snapshotLine({})])
    }, function() { return S().record.interfaceRevision === 4 && !P().running && P().switchOn === false
                           && S().attachedCount === 1 && h.writerIdle() })
    h.previewCountStep(0, "at the end of the preview checks")
  }

  // ---- the layout screenshots: each tab of A's open panel, checked to fit -------
  //
  // c1-layout-<tab>-<kind>.png; `back`: the tab shown again afterwards.
  function layoutGrabs(kind, back) {
    var A = function() { return h.widgetA }
    var tabs = ["effect", "camera", "status"]
    for (var i = 0; i < tabs.length; i++) {
      var t = tabs[i]
      h.step("layout: the " + t + " tab, " + kind, (function(t) { return function() { h.tab(A(), t) } })(t))
      h.wait(250)
      h.step("layout: the " + t + " tab fits, " + kind, (function(t) { return function() {
        h.eq(t + " tab shown", h.find(A(), t + "Tab").visible, true)
        h.fits(A(), t + " tab, " + kind)
        h.note("layout " + t + " " + kind + ": card " + A().popup.contentWidth + "x" + A().popup.contentHeight)
      } })(t))
      h.grabStep(function() { return A().popup }, "c1-layout-" + t + "-" + kind + ".png")
    }
    h.step("layout: back to the " + back + " tab", function() { h.tab(A(), back) })
  }

  // ---- camera settings (mock): capability, the generic renderer, writes, reset ---
  //
  // The fake follows every snapshot it prints with the settings set of its
  // settings-state (settings-mode list), cut at settings-per-line settings a
  // line, and answers `settings set|reset` by updating settings-state and
  // printing the settings_delta lines on the feed, as the daemon's signal
  // reaches a watch: a write that flips a dependent setting carries both.

  // One settings-state line: group|label|id|type|label|value|default|stored|
  // min|max|step|unit|options|master|when|reason|fixed.
  function stateRow(group, groupLabel, id, type, label, value, def, o) {
    var x = o || {}
    var f = function(v) { return v === undefined ? "" : String(v) }
    return [group, groupLabel, id, type, label, f(value), f(def), x.stored ? "1" : "0", f(x.min), f(x.max), f(x.step), f(x.unit),
            f(x.options), f(x.master), f(x.when), f(x.reason), x.fixed ? "1" : ""].join("|")
  }
  // The MX Brio as the daemon publishes it (its starting values).
  function brioState() {
    var img = function(id, label, v, d, o) {
      var m = { min: 0, max: 255, step: 1 }
      for (var k in o) m[k] = o[k]
      return stateRow("image", "Image", "camera.image." + id, "int", label, v, d, m)
    }
    return [
      img("brightness", "Brightness", 128, 128), img("contrast", "Contrast", 128, 128), img("saturation", "Saturation", 128, 128),
      img("sharpness", "Sharpness", 128, 128), img("backlight_compensation", "Backlight compensation", 1, 1, { max: 1 }),
      stateRow("white_balance", "White balance", "camera.white_balance.white_balance_automatic", "bool", "Automatic white balance", "true", "true"),
      stateRow("white_balance", "White balance", "camera.white_balance.white_balance_temperature", "int", "Temperature", 2975, 5000,
               { min: 2000, max: 7500, step: 1, unit: "K", master: "camera.white_balance.white_balance_automatic", when: "false",
                 reason: "Turn off automatic white balance to change this" }),
      stateRow("exposure", "Exposure", "camera.exposure.auto_exposure", "enum", "Exposure mode", "aperture_priority", "aperture_priority",
               { options: "manual:Manual,aperture_priority:Auto" }),
      stateRow("exposure", "Exposure", "camera.exposure.exposure_time_absolute", "int", "Exposure time", 1250, 156,
               { min: 3, max: 2047, step: 1, unit: "×100 µs", master: "camera.exposure.auto_exposure", when: "manual,shutter_priority",
                 reason: "Set exposure to manual to change this" }),
      stateRow("exposure", "Exposure", "camera.exposure.gain", "int", "Gain", 0, 0, { min: 0, max: 255, step: 1 }),
      stateRow("exposure", "Exposure", "camera.exposure.keep_framerate", "bool", "Keep 30 fps in low light", "false", "true"),
      stateRow("exposure", "Exposure", "camera.exposure.power_line_frequency", "enum", "Anti-flicker", "60hz", "60hz",
               { options: "disabled:Off,50hz:50 Hz,60hz:60 Hz,auto:Auto" }),
      stateRow("focus", "Focus & zoom", "camera.focus.focus_automatic_continuous", "bool", "Continuous autofocus", "true", "true"),
      stateRow("focus", "Focus & zoom", "camera.focus.focus_absolute", "int", "Focus", 40, 0,
               { min: 0, max: 255, step: 1, master: "camera.focus.focus_automatic_continuous", when: "false",
                 reason: "Turn off continuous autofocus to change this" }),
      stateRow("focus", "Focus & zoom", "camera.focus.zoom_absolute", "int", "Zoom", 100, 100, { min: 100, max: 500, step: 1 }),
      stateRow("focus", "Focus & zoom", "camera.focus.pan_absolute", "int", "Pan", 14400, 0, { min: -36000, max: 36000, step: 3600 }),
      stateRow("focus", "Focus & zoom", "camera.focus.tilt_absolute", "int", "Tilt", -14400, 0, { min: -36000, max: 36000, step: 3600 }),
      stateRow("focus", "Focus & zoom", "camera.focus.pan_reset", "action", "Recentre pan", "-", "-"),
      stateRow("focus", "Focus & zoom", "camera.focus.tilt_reset", "action", "Recentre tilt", "-", "-"),
      stateRow("focus", "Focus & zoom", "camera.focus.field_of_view", "enum", "Field of view", "65", "90", { options: "90:90°,78:78°,65:65°" })
    ]
  }

  function settingsScenario() {
    var A = function() { return h.widgetA }
    var S = function() { return h.widgetA.service }
    var P = function() { return h.widgetA.previewService }
    var C = function() { return h.content(A()) }
    var rev7 = function(o) {
      var m = { interface_revision: 7, settings_schema: 1, settings_revision: 5, loopback_consumers: 0, pipewire_consumers: 0,
                preview_consumers: 0, pipewire_output: "ready" }
      for (var k in o) m[k] = o[k]
      return m
    }
    var value = function(id) { var r = h.model.findSetting(S().record, id); return r ? r.value : null }
    var row = function(id) { return h.find(A(), "setting-" + id) }
    var shown = function(id) { var r = row(id); return !!r && r.visible }
    var setArgs = function() { return h.newLogArgs().filter(function(a) { return a[0] === "settings" }) }
    var write = function(id, v) { return ["settings", "set", "--camera=" + brioId, "--", id, String(v)] }
    var kinds = function() {
      return C().stops.map(function(st) { return st.kind + (st.index >= 0 ? st.index : "") }).join(",")
    }
    var header = function(id) { return h.find(A(), "settingsGroupHeader-" + id) }
    var click = function(item) { keys.mouseClick(item, item.width / 2, item.height / 2) }
    var chip = function(id, label) {
      var group = h.find(A(), "settingChoices-" + id)
      var kids = group ? group.children : []
      for (var i = 0; i < kids.length; i++) if (kids[i].text === label) return kids[i]
      return null
    }
    var stopOf = function(id) { var r = row(id); return r ? r.row.stop : -1 }
    // The panel's choice of open group, as a header click makes it.
    var openOnly = function(ids) { C().settingsOpen = ids.length > 0 ? ids[0] : "" }
    var noInnerScroll = function(label) {
      var f = h.find(A(), "settingsFlick")
      h.check(label + ": the settings do not scroll (" + Math.round(f.contentHeight) + " in " + Math.round(f.height) + ")",
              !f.interactive && f.contentHeight <= f.height + 0.5, f.contentHeight + " in " + f.height)
      h.eq(label + ": no scroll cue", h.find(A(), "settingsMoreBelow").visible, false)
    }
    var openGroups = function() { return C().settingsView.groups.filter(function(g) { return g.expanded }).map(function(g) { return g.id }).join(",") }
    // M3: the one highlight of the row at stop `id` ("row", "chip:<label>",
    // "dropdown", "button", or "" for none).
    var highlights = function(id) {
      var out = []
      var r = row(id)
      if (r && r.hasCursor) out.push("row")
      var group = h.find(A(), "settingChoices-" + id)
      var kids = group ? group.children : []
      for (var i = 0; i < kids.length; i++) if (kids[i].hasCursor === true) out.push("chip:" + kids[i].text)
      var dd = h.find(A(), "settingDropdown-" + id)
      if (dd && dd.hasCursor) out.push("dropdown")
      var b = h.find(A(), "settingAction-" + id)
      if (b && b.hasCursor) out.push("button")
      var sw = h.find(A(), "settingSwitch-" + id)
      if (sw && sw.hasCursor) out.push("switch")
      return out.join(",")
    }
    var within = function(item, ancestor) {
      for (var p = item; p; p = p.parent) if (p === ancestor) return true
      return false
    }

    h.step("settings: a revision-7 daemon with the MX Brio", function() {
      h.writeFile("settings-state", brioState())
      h.writeFile("settings-camera", [brioId])
      h.writeFile("settings-rev", ["5"])
      h.writeFile("settings-serial", ["2"])
      h.writeFile("settings-per-line", ["4"])
      h.writeFile("settings-mode", ["list"])
      h.removeFile("delay")
      h.removeFile("stderr")
      h.writeFile("exit", ["0"])
      h.feed([snapshotLine(rev7({}))])
    }, function() { return !!S().record.settings && S().record.settings.groups.length === 4 && h.writerIdle() })
    h.step("settings: open the panel on the Camera tab", function() { A().open(); h.tab(A(), "camera") }, function() { return C() !== null })
    h.wait(300)
    h.step("settings: drawn from the set, Image open, the rest closed", function() {
      var set = S().record.settings
      h.eq("assembled from seven lines into four groups", set.groups.map(function(g) { return g.id + ":" + g.rows.length }).join(","),
           "image:5,white_balance:2,exposure:5,focus:8")
      h.eq("the section's title", h.find(A(), "settingsTitle").text + "/" + h.find(A(), "settingsTitle").visible, "SETTINGS/true")
      var hl = h.find(A(), "settingsGroupLabel-image"), rl = h.find(A(), "settingLabel-camera.image.brightness")
      h.eq("a group's label is aligned with its rows' labels", Math.round(hl.mapToItem(C(), 0, 0).x), Math.round(rl.mapToItem(C(), 0, 0).x))
      h.check("Reset to defaults is outside the scrolling area", !within(h.find(A(), "settingsReset"), h.find(A(), "settingsFlick")))
      h.check("on the settings' title line", Math.abs(h.find(A(), "settingsReset").mapToItem(C(), 0, h.find(A(), "settingsReset").height / 2).y
              - h.find(A(), "settingsTitle").mapToItem(C(), 0, h.find(A(), "settingsTitle").height / 2).y) < 2)
      h.eq("area shown", h.find(A(), "settingsArea").visible, true)
      h.eq("group labels", ["image", "white_balance", "exposure", "focus"].map(function(g) {
        return h.find(A(), "settingsGroupLabel-" + g).text }).join(","), "Image,White balance,Exposure,Focus & zoom")
      h.eq("Image rows", ["brightness", "contrast", "saturation", "sharpness", "backlight_compensation"].map(function(n) {
        return shown("camera.image." + n) }).join(","), "true,true,true,true,true")
      h.eq("closed groups draw no rows", row("camera.white_balance.white_balance_temperature"), null)
      h.eq("labels", h.find(A(), "settingLabel-camera.image.brightness").text + "," + h.find(A(), "settingLabel-camera.image.backlight_compensation").text,
           "Brightness,Backlight compensation")
      h.eq("value", h.find(A(), "settingValue-camera.image.brightness").text, "128")
      h.eq("slider range", h.find(A(), "settingSlider-camera.image.contrast").minimum + ".." + h.find(A(), "settingSlider-camera.image.contrast").maximum, "0..255")
      h.eq("idle note", h.find(A(), "settingsNote").text, "Not in use: changes apply when an app next uses the camera.")
      h.eq("no hint", h.find(A(), "settingsHint").visible, false)
      h.eq("reset shown", h.find(A(), "settingsReset").visible, true)
      h.eq("cursor stops: the rows drawn", kinds(),
           "switch,preview,fps,tabs,camera0,camera1,camera2,next,reset,group0,setting0,setting1,setting2,setting3,setting4,group1,group2,group3")
      h.eq("accessible row", row("camera.image.brightness").Accessible.name, "Brightness")
      h.eq("accessible header", header("exposure").Accessible.name + "/" + header("exposure").Accessible.description, "Exposure/Collapsed")
      h.fits(A(), "Camera tab with the MX Brio, Image open")
      noInnerScroll("Image open")
    })
    h.grabStep(function() { return A().popup }, "s1-camera-default.png")
    layoutGrabs("nopreview", "camera")

    // the keyboard walks the rows that are drawn; Right moves a slider
    h.step("settings: the keyboard reaches the brightness slider", function() {
      h.find(A(), "panelFlick").contentY = 0
      h.markLog()
      h.key(Qt.Key_Down)                              // shows the cursor
      // preview, fps, the tab row, three cameras, Next camera, Reset, Image, brightness
      for (var i = 0; i < 10; i++) h.key(Qt.Key_Down)
    }, function() { return C().currentStop && C().currentStop.kind === "setting" })
    h.step("settings: Right nudges brightness, written once after the debounce, with -- before id and value", function() {
      h.eq("cursor on brightness", JSON.stringify(C().currentStop), JSON.stringify({ kind: "setting", index: 0 }))
      h.eq("brightness row has the cursor", row("camera.image.brightness").hasCursor, true)
      h.key(Qt.Key_Right)
      h.key("l")
      h.eq("shown at once (a draft)", h.find(A(), "settingValue-camera.image.brightness").text, "154")
      h.eq("nothing written yet", setArgs().length, 0)
    }, function() { return setArgs().length >= 1 && value("camera.image.brightness") === 154 }, 3000)
    h.step("settings: one write for two presses, confirmed by the delta", function() {
      h.eq("writes", JSON.stringify(setArgs()), JSON.stringify([write("camera.image.brightness", 154)]))
      h.eq("draft settled", JSON.stringify(S().settingDrafts), "{}")
      h.eq("stored by the fake", h.model.findSetting(S().record, "camera.image.brightness").stored, true)
      h.eq("rev moved", S().record.settings.rev, 6)
    })

    // a group header opens and closes, by key and by click
    h.step("settings: Up to the Image header, Enter closes it", function() {
      h.key(Qt.Key_Up)
      h.eq("on the header", JSON.stringify(C().currentStop), JSON.stringify({ kind: "group", index: 0 }))
      h.key(Qt.Key_Return)
    }, function() { return !shown("camera.image.brightness") })
    h.step("settings: closed; the stops follow; Space opens it again", function() {
      h.eq("stops", kinds(), "switch,preview,fps,tabs,camera0,camera1,camera2,next,reset,group0,group1,group2,group3")
      h.eq("cursor kept on the header", JSON.stringify(C().currentStop), JSON.stringify({ kind: "group", index: 0 }))
      h.key(Qt.Key_Space)
    }, function() { return shown("camera.image.brightness") })
    h.step("settings: Left closes, Right opens", function() {
      h.key(Qt.Key_Left)
      h.eq("closed", C().settingsView.groups[0].expanded, false)
      h.key(Qt.Key_Right)
      h.eq("open", C().settingsView.groups[0].expanded, true)
      h.eq("nothing written by the headers", setArgs().length, 1)
    })
    h.step("settings: click White balance", function() { click(header("white_balance")) },
           function() { return shown("camera.white_balance.white_balance_temperature") })
    h.wait(200)
    h.step("settings: one group open at a time: White balance closed Image", function() {
      h.eq("open", openGroups(), "white_balance")
      h.eq("Image's rows are gone", row("camera.image.brightness"), null)
      C().setCursor("group", 1)
      h.key(Qt.Key_Down)
      h.eq("a switch row draws the one highlight (not the switch)", highlights("camera.white_balance.white_balance_automatic"), "row")
    })
    h.step("settings: the greyed temperature shows its reason and takes no input", function() {
      var t = row("camera.white_balance.white_balance_temperature")
      var reason = h.find(A(), "settingReason-camera.white_balance.white_balance_temperature")
      h.eq("reason shown", reason.visible, true)
      h.eq("reason", reason.text, "Turn off automatic white balance to change this")
      h.eq("accessible description: unavailable, the value and the reason", t.Accessible.description,
           "Unavailable. 2975 K. Turn off automatic white balance to change this")
      h.eq("its widget is disabled", h.find(A(), "settingWidget-camera.white_balance.white_balance_temperature").enabled, false)
      // M6: only the control fades; the label is dim (not faint), the value
      // and the reason keep full opacity, the reason in the panel's hint size
      var temp = "camera.white_balance.white_balance_temperature"
      h.eq("the slider fades", h.find(A(), "settingSlider-" + temp).opacity, 0.45)
      h.eq("the widget's box does not", h.find(A(), "settingWidget-" + temp).opacity, 1)
      h.eq("the value does not", h.find(A(), "settingValue-" + temp).opacity, 1)
      h.eq("the label is the dim colour (not faint)", String(h.find(A(), "settingLabel-" + temp).color), String(C().dim))
      h.eq("the reason's size is the panel's hint size", reason.font.pixelSize, h.find(A(), "settingsNote").font.pixelSize)
      h.eq("unit", h.find(A(), "settingValue-camera.white_balance.white_balance_temperature").text, "2975 K")
      h.eq("the switch above it is on", h.find(A(), "settingSwitch-camera.white_balance.white_balance_automatic").checked, true)
      h.eq("no reason under an enabled row", h.find(A(), "settingReason-camera.white_balance.white_balance_automatic").visible, false)
      C().setCursor("setting", stopOf("camera.white_balance.white_balance_temperature"))
      h.markLog()
      h.key(Qt.Key_Right)
      h.eq("a key moves nothing", JSON.stringify(S().settingDrafts), "{}")
      h.eq("a greyed write is refused", S().moveSetting("camera.white_balance.white_balance_temperature", 3000), false)
    })

    // Exposure: the greyed exposure time, then Manual enables it
    h.step("settings: only Exposure open", function() { openOnly(["exposure"]) }, function() { return shown("camera.exposure.exposure_time_absolute") })
    h.wait(250)
    h.step("settings: exposure time greyed with its reason", function() {
      h.eq("reason", h.find(A(), "settingReason-camera.exposure.exposure_time_absolute").text, "Set exposure to manual to change this")
      h.eq("reason shown", h.find(A(), "settingReason-camera.exposure.exposure_time_absolute").visible, true)
      h.eq("unit", h.find(A(), "settingValue-camera.exposure.exposure_time_absolute").text, "1250 ×100 µs")
      h.eq("the mode is Auto", h.find(A(), "settingChoices-camera.exposure.auto_exposure").value, "aperture_priority")
      h.eq("anti-flicker: four choices", h.find(A(), "settingChoices-camera.exposure.power_line_frequency").options.length, 4)
      h.eq("keep framerate off", h.find(A(), "settingSwitch-camera.exposure.keep_framerate").checked, false)
      h.fits(A(), "Exposure open")
      noInnerScroll("Exposure open")
      h.markLog()
    })
    h.grabStep(function() { return A().popup }, "s1-exposure-greyed.png")
    // M1/M3: Left/Right walk a chip cursor that starts on the choice made;
    // nothing is written until Enter
    h.step("settings: the cursor on Anti-flicker lands on 60 Hz, one highlight", function() {
      h.markLog()
      C().setCursor("setting", stopOf("camera.exposure.power_line_frequency"))
      h.eq("one highlight: the chip of the current choice", highlights("camera.exposure.power_line_frequency"), "chip:60 Hz")
      h.key(Qt.Key_Left)
      h.key("h")
      h.eq("the cursor walked to Off", highlights("camera.exposure.power_line_frequency"), "chip:Off")
      h.eq("60 Hz still the choice", h.find(A(), "settingChoices-camera.exposure.power_line_frequency").value, "60hz")
      h.eq("no draft", JSON.stringify(S().settingDrafts), "{}")
      h.mark = Date.now()
    }, function() { return Date.now() - h.mark > 400 })
    h.step("settings: walking wrote nothing", function() {
      h.eq("no command", setArgs().length, 0)
      h.eq("still on Off", highlights("camera.exposure.power_line_frequency"), "chip:Off")
    })
    h.grabStep(function() { return A().popup }, "s1-keyboard-enum.png")
    h.step("settings: Enter chooses Off", function() { h.key(Qt.Key_Return) },
           function() { return value("camera.exposure.power_line_frequency") === "disabled" && !S().commandBusy }, 4000)
    h.step("settings: one write, Off", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.exposure.power_line_frequency", "disabled")]))
      h.eq("Off selected", h.find(A(), "settingChoices-camera.exposure.power_line_frequency").value, "disabled")
      h.key(Qt.Key_Return)
      h.eq("Enter on the choice made writes nothing more", JSON.stringify(S().settingDrafts), "{}")
      h.markLog()
    })
    h.step("settings: click Manual", function() { click(chip("camera.exposure.auto_exposure", "Manual")) },
           function() { return value("camera.exposure.auto_exposure") === "manual" && !S().commandBusy }, 4000)
    h.wait(250)
    h.step("settings: the fake's delta enabled exposure time", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.exposure.auto_exposure", "manual")]))
      var t = h.model.findSetting(S().record, "camera.exposure.exposure_time_absolute")
      h.eq("enabled", t.enabled, true)
      h.eq("reason gone", h.find(A(), "settingReason-camera.exposure.exposure_time_absolute").visible, false)
      h.eq("widget enabled", h.find(A(), "settingWidget-camera.exposure.exposure_time_absolute").enabled, true)
      h.eq("Manual selected", h.find(A(), "settingChoices-camera.exposure.auto_exposure").value, "manual")
      h.eq("no draft left", JSON.stringify(S().settingDrafts), "{}")
    })
    h.grabStep(function() { return A().popup }, "s1-exposure-manual.png")
    h.step("settings: Left on the exposure mode walks to Manual and writes nothing; on exposure time it moves", function() {
      h.markLog()
      C().setCursor("setting", stopOf("camera.exposure.auto_exposure"))
      h.key(Qt.Key_Left)
      h.eq("no draft for a walk", JSON.stringify(S().settingDrafts), "{}")
      h.eq("the walk stops at the end", highlights("camera.exposure.auto_exposure"), "chip:Manual")
      C().setCursor("setting", stopOf("camera.exposure.exposure_time_absolute"))
      h.key(Qt.Key_Right)
    }, function() { return setArgs().length === 1 && value("camera.exposure.exposure_time_absolute") === 1352 }, 3000)
    h.step("settings: exposure time written", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.exposure.exposure_time_absolute", 1352)]))
    })

    // Focus & zoom: the field of view's buttons, a negative value after --, a switch
    h.step("settings: only Focus & zoom open", function() { openOnly(["focus"]) }, function() { return shown("camera.focus.field_of_view") })
    h.wait(250)
    h.step("settings: Focus & zoom alone open, with its two Recentre buttons", function() {
      h.eq("open", openGroups(), "focus")
      h.eq("rows", C().settingsView.groups[3].rows.length, 8)
      h.eq("the buttons", h.find(A(), "settingAction-camera.focus.pan_reset").text + "," + h.find(A(), "settingAction-camera.focus.tilt_reset").text,
           "Recentre pan,Recentre tilt")
      C().setCursor("setting", stopOf("camera.focus.pan_reset"))
      h.eq("an action row: the button draws the one highlight", highlights("camera.focus.pan_reset"), "button")
      C().setCursor("setting", stopOf("camera.focus.zoom_absolute"))
      h.eq("a slider row: the row draws it", highlights("camera.focus.zoom_absolute"), "row")
      h.check("a switch row's label takes the room the switch leaves",
              h.find(A(), "settingLabel-camera.focus.focus_automatic_continuous").width > row("camera.focus.focus_automatic_continuous").width * 0.6,
              h.find(A(), "settingLabel-camera.focus.focus_automatic_continuous").width + " of " + row("camera.focus.focus_automatic_continuous").width)
      C().cursorActive = false
    })
    h.grabStep(function() { return A().popup }, "s1-focus-actions.png")
    h.step("settings: the field of view is three buttons, 65 selected", function() {
      var fov = h.find(A(), "settingChoices-camera.focus.field_of_view")
      h.eq("choices", fov.options.map(function(o) { return o.label }).join(","), "90°,78°,65°")
      h.eq("selected", fov.value, "65")
      h.eq("65 lit", chip("camera.focus.field_of_view", "65°").selected, true)
      h.eq("focus greyed", h.find(A(), "settingReason-camera.focus.focus_absolute").text, "Turn off continuous autofocus to change this")
      h.eq("pan value", h.find(A(), "settingValue-camera.focus.pan_absolute").text, "14400")
      h.eq("tilt value", h.find(A(), "settingValue-camera.focus.tilt_absolute").text, "-14400")
      h.fits(A(), "Focus & zoom open (the largest group, two actions included)")
      noInnerScroll("Focus & zoom open")
      h.note("height: card " + A().popup.contentHeight + " in " + Math.round(A().popup.availableCardHeight))
    })
    h.grabStep(function() { return A().popup }, "s1-focus-fov.png")
    h.step("settings: Left on tilt writes a negative value after --", function() {
      h.markLog()
      C().setCursor("setting", stopOf("camera.focus.tilt_absolute"))
      h.key(Qt.Key_Left)
    }, function() { return setArgs().length === 1 && value("camera.focus.tilt_absolute") === -18000 }, 3000)
    h.step("settings: tilt argv", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([["settings", "set", "--camera=" + brioId, "--", "camera.focus.tilt_absolute", "-18000"]]))
      h.markLog()
      C().setCursor("setting", stopOf("camera.focus.focus_automatic_continuous"))
      h.key(Qt.Key_Return)
    }, function() { return value("camera.focus.focus_automatic_continuous") === false && !S().commandBusy }, 3000)
    h.wait(200)
    h.step("settings: Enter flipped continuous autofocus; focus is enabled", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.focus.focus_automatic_continuous", "false")]))
      h.eq("focus enabled", h.model.findSetting(S().record, "camera.focus.focus_absolute").enabled, true)
      h.eq("switch off", h.find(A(), "settingSwitch-camera.focus.focus_automatic_continuous").checked, false)
      h.markLog()
      click(chip("camera.focus.field_of_view", "90°"))
    }, function() { return value("camera.focus.field_of_view") === "90" }, 3000)
    h.step("settings: the field of view chosen by a click", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.focus.field_of_view", "90")]))
    })

    // a drag: one write for the whole move, at its end
    h.step("settings: drag zoom", function() {
      h.markLog()
      var sl = h.find(A(), "settingSlider-camera.focus.zoom_absolute")
      keys.mousePress(sl, sl.width * 0.2, sl.height / 2)
      for (var i = 3; i <= 8; i++) keys.mouseMove(sl, sl.width * i / 10, sl.height / 2, -1, Qt.LeftButton)
    }, function() { return h.find(A(), "settingSlider-camera.focus.zoom_absolute").dragging })
    h.step("settings: release", function() {
      var sl = h.find(A(), "settingSlider-camera.focus.zoom_absolute")
      h.notes.dragged = h.model.clampSetting(h.model.findSetting(S().record, "camera.focus.zoom_absolute"), sl.liveValue)
      h.eq("neither Flickable takes a held slider", h.find(A(), "panelFlick").interactive || h.find(A(), "settingsFlick").interactive, false)
      keys.mouseRelease(sl, sl.width * 0.8, sl.height / 2)
    }, function() { return value("camera.focus.zoom_absolute") === h.notes.dragged }, 3000)
    h.wait(400)
    h.step("settings: the drag wrote one command", function() {
      h.check("moved", h.notes.dragged !== 100, h.notes.dragged)
      h.eq("one write, the end of the drag", JSON.stringify(setArgs()), JSON.stringify([write("camera.focus.zoom_absolute", h.notes.dragged)]))
      h.eq("value text", h.find(A(), "settingValue-camera.focus.zoom_absolute").text, String(h.notes.dragged))
      h.eq("held count back to 0", C().slidersHeld, 0)
    })

    // F4: a slider held while a new set commits under it (another camera
    // with the same ids, then the same camera with its rows moved; each is
    // the set alone, as the CLI prints it after a serial change, so the row
    // items stay) lets go and writes nothing, to that setting or to the one
    // now at its place
    var heldThrough = function(label, held, change, changed, restore, serialAfter) {
      h.step("settings: hold " + held + " (" + label + ")", function() {
        h.markLog()
        var sl = h.find(A(), "settingSlider-" + held)
        h.notes.held = sl
        keys.mousePress(sl, sl.width * 0.2, sl.height / 2)
      }, function() {
        // the press's own move is written after the debounce, as any held
        // slider's is: let it go out before the set changes
        return h.notes.held.dragging && C().slidersHeld === 1 && setArgs().length === 1 && !S().commandBusy
          && JSON.stringify(S().settingDrafts) === "{}"
      }, 4000)
      h.step("settings: " + label + " while it is held", function() { h.markLog(); change() }, changed, 4000)
      h.wait(200)
      h.step("settings: " + label + ": the drag let go; moving and releasing write nothing", function() {
        var sl = h.notes.held
        h.eq("not held", sl.dragging, false)
        h.eq("held count back to 0", C().slidersHeld, 0)
        keys.mouseMove(sl, sl.width * 0.7, sl.height / 2, -1, Qt.LeftButton)
        keys.mouseRelease(sl, sl.width * 0.7, sl.height / 2)
      })
      h.wait(500)
      h.step("settings: " + label + ": nothing written", function() {
        h.eq("no settings command", JSON.stringify(setArgs()), "[]")
        h.eq("no draft", JSON.stringify(S().settingDrafts), "{}")
        restore()
      }, function() {
        return !!S().record.settings && S().record.settings.camera === brioId && S().record.settings.serial === serialAfter
          && h.writerIdle() && !S().commandBusy
      }, 4000)
      h.wait(200)
    }
    var setAlone = '{"fake":"settings-set"}'
    heldThrough("another camera's set", "camera.focus.zoom_absolute", function() {
      h.writeFile("settings-camera", [fhdId])
      h.writeFile("settings-serial", ["5"])
      h.feed([setAlone])
    }, function() { return !!S().record.settings && S().record.settings.camera === fhdId }, function() {
      h.writeFile("settings-camera", [brioId])
      h.writeFile("settings-serial", ["6"])
      h.feed([snapshotLine(rev7({}))])
    }, 6)
    heldThrough("the same camera, its rows moved", "camera.focus.zoom_absolute", function() {
      // pan before zoom: the same rows, so the held item stays, and shows Pan
      var st = brioState()
      var zi = -1, pi = -1
      for (var i = 0; i < st.length; i++) {
        if (st[i].indexOf("|camera.focus.zoom_absolute|") >= 0) zi = i
        if (st[i].indexOf("|camera.focus.pan_absolute|") >= 0) pi = i
      }
      var z = st[zi]
      st[zi] = st[pi]
      st[pi] = z
      h.writeFile("settings-state", st)
      h.writeFile("settings-serial", ["7"])
      h.feed([setAlone])
    }, function() { return !!S().record.settings && S().record.settings.serial === 7 }, function() {
      h.eq("the held item now shows Pan", h.notes.held.objectName, "settingSlider-camera.focus.pan_absolute")
      h.writeFile("settings-state", brioState())
      h.writeFile("settings-serial", ["8"])
      h.feed([snapshotLine(rev7({}))])
    }, 8)

    // a slow command: moves behind it coalesce into one queued write per id
    h.step("settings: a slow CLI", function() { h.writeFile("delay", ["0.8"]) }, function() { return h.writerIdle() })
    h.step("settings: three nudges while the first write runs", function() {
      h.markLog()
      h.notes.maxQueue = 0
      h.notes.zoom = value("camera.focus.zoom_absolute")
      C().setCursor("setting", stopOf("camera.focus.zoom_absolute"))
      h.key(Qt.Key_Right)                                // +20, written after 150 ms
      h.mark = Date.now()
    }, function() { return S().commandBusy && Date.now() - h.mark > 300 })
    h.step("settings: a second", function() {
      h.key(Qt.Key_Right)                                // queued
      h.mark = Date.now()
    }, function() { h.notes.maxQueue = Math.max(h.notes.maxQueue, S().pendingIntents.length); return Date.now() - h.mark > 300 })
    h.step("settings: and the last", function() {
      h.key(Qt.Key_Right)                                // replaces it
    }, function() {
      h.notes.maxQueue = Math.max(h.notes.maxQueue, S().pendingIntents.length)
      return !S().commandBusy && value("camera.focus.zoom_absolute") === h.notes.zoom + 60
    }, 6000)
    h.step("settings: the queued write was replaced, not added", function() {
      h.eq("writes", JSON.stringify(setArgs()), JSON.stringify([write("camera.focus.zoom_absolute", h.notes.zoom + 20),
                                                              write("camera.focus.zoom_absolute", h.notes.zoom + 60)]))
      h.eq("at most one queued", h.notes.maxQueue, 1)
    })

    // a camera switch behind the slow CLI: a write made for the Brio's set
    // never lands on the next camera's
    h.step("settings: switch to FHD, then move zoom while it runs", function() {
      h.markLog()
      h.check("switch asked", S().selectCamera(fhdId))
      h.check("move taken", S().commitSetting("camera.focus.zoom_absolute", 300))
      h.eq("queued, bound to the Brio", JSON.stringify(S().pendingIntents.map(function(i) { return i.verb + ":" + i.camera })),
           JSON.stringify(["setting:" + brioId]))
      // the switch lands: the daemon's set is the FHD camera's
      h.writeFile("settings-camera", [fhdId])
      h.writeFile("settings-serial", ["3"])
      h.feed([snapshotLine(rev7({ active_camera: fhdId, active_camera_name: "FHD Camera" }))])
    }, function() { return !!S().record.settings && S().record.settings.camera === fhdId && !S().commandBusy }, 6000)
    h.wait(400)
    h.step("settings: the queued write was dropped, not run on the FHD camera", function() {
      h.eq("no settings command", JSON.stringify(setArgs()), "[]")
      h.check("the switch ran", h.newLogArgs().some(function(a) { return a[0] === "camera" }), JSON.stringify(h.newLogArgs()))
      h.eq("queue empty", S().pendingIntents.length, 0)
      h.eq("no draft", JSON.stringify(S().settingDrafts), "{}")
      h.writeFile("settings-camera", [brioId])
      h.writeFile("settings-serial", ["4"])
      h.removeFile("delay")
      h.feed([snapshotLine(rev7({}))])
    }, function() { return !!S().record.settings && S().record.settings.camera === brioId && h.writerIdle() })

    // F3: more distinct writes than the queue holds, and an on/off ask,
    // behind a slow command: every write runs once, the ask too, and no
    // draft is left behind
    h.step("settings: eleven writes and an on/off ask behind a slow command", function() {
      h.writeFile("delay", ["0.3"])
    }, function() { return h.writerIdle() })
    h.step("settings: queue them in one turn", function() {
      h.markLog()
      h.notes.wanted = [["camera.image.brightness", 100], ["camera.image.contrast", 101], ["camera.image.saturation", 102],
                        ["camera.image.sharpness", 103], ["camera.image.backlight_compensation", 0], ["camera.exposure.gain", 10],
                        ["camera.focus.zoom_absolute", 222], ["camera.focus.field_of_view", "78"], ["camera.focus.tilt_absolute", 7200],
                        ["camera.exposure.keep_framerate", true], ["camera.exposure.power_line_frequency", "50hz"]]
      for (var i = 0; i < h.notes.wanted.length; i++)
        h.check("taken: " + h.notes.wanted[i][0], S().commitSetting(h.notes.wanted[i][0], h.notes.wanted[i][1]))
      h.check("the on/off ask is taken", S().setEnabled(true))
      var q = S().pendingIntents
      h.eq("the queue: the ask first, then the writes it holds", q.length, h.model.SETTING_QUEUE_CAP + 1)
      h.eq("the ask first", q[0].verb, "enable")
      h.eq("the rest wait as drafts", S().settingsDeferred, true)
      h.eq("every draft kept", Object.keys(S().settingDrafts).length, h.notes.wanted.length)
    }, function() { return !S().commandBusy && JSON.stringify(S().settingDrafts) === "{}" && !S().settingsDeferred }, 20000)
    h.step("settings: every write ran once, and the ask", function() {
      var args = setArgs().map(function(a) { return a[4] + "=" + a[5] }).sort()
      var want = h.notes.wanted.map(function(w) { return w[0] + "=" + String(w[1]) }).sort()
      h.eq("writes", JSON.stringify(args), JSON.stringify(want))
      h.check("on ran", h.newLogArgs().some(function(a) { return a[0] === "on" }), JSON.stringify(h.newLogArgs()))
      h.eq("no draft left", JSON.stringify(S().settingDrafts), "{}")
      h.eq("power line", value("camera.exposure.power_line_frequency"), "50hz")
      h.removeFile("delay")
    }, function() { return h.writerIdle() })

    // a refused write: the row goes back to what the daemon reports
    h.step("settings: the daemon refuses", function() {
      h.writeFile("exit", ["1"])
      h.writeFile("stderr", ["omarchy-broadcast: the camera refused the value"])
    }, function() { return h.writerIdle() })
    h.step("settings: nudge pan", function() {
      h.markLog()
      C().setCursor("setting", stopOf("camera.focus.pan_absolute"))
      h.key(Qt.Key_Left)
    }, function() { return setArgs().length === 1 && !S().commandBusy && JSON.stringify(S().settingDrafts) === "{}" }, 3000)
    h.step("settings: back to the reported value, error shown", function() {
      h.eq("argv", JSON.stringify(setArgs()[0]), JSON.stringify(write("camera.focus.pan_absolute", 10800)))
      h.eq("shown", h.find(A(), "settingValue-camera.focus.pan_absolute").text, "14400")
      h.check("error", S().commandError.indexOf("The daemon refused the request: the camera refused the value") === 0, S().commandError)
      h.writeFile("exit", ["0"])
      h.removeFile("stderr")
    }, function() { return h.writerIdle() })

    // M5: on a screen too short for the open group the groups scroll on
    // their own, with a cue, and Reset stays pinned under them (the room is
    // forced here; the panel's binding is put back after)
    h.step("settings: a short screen: the groups scroll, Reset stays in reach", function() {
      openOnly(["focus"])
      h.find(A(), "settingsView").room = 300
    }, function() { return h.find(A(), "settingsFlick").interactive })
    h.wait(250)
    h.step("settings: the scroll cue and the pinned Reset", function() {
      var f = h.find(A(), "settingsFlick")
      h.check("it scrolls", f.contentHeight > f.height + 0.5, f.contentHeight + " in " + f.height)
      // ScrollBar.AlwaysOn is Qt.ScrollBarAlwaysOn, 2
      h.eq("a scroll bar at rest", h.find(A(), "settingsScrollBar").policy, 2)
      h.eq("shown", h.find(A(), "settingsScrollBar").visible, true)
      h.eq("the fade says more is below", h.find(A(), "settingsMoreBelow").visible, true)
      var b = h.find(A(), "settingsReset")
      var bottom = b.mapToItem(h.find(A(), "settingsView"), 0, b.height).y
      h.check("Reset is shown, inside the section's room", b.visible && bottom <= 300 + 0.5, bottom)
      C().cursorActive = false
    })
    h.grabStep(function() { return A().popup }, "s1-scroll-fallback.png")
    h.step("settings: scroll to the end", function() {
      var f = h.find(A(), "settingsFlick")
      f.contentY = f.contentHeight - f.height
    })
    h.wait(150)
    h.step("settings: at the end the cue goes", function() { h.eq("no fade at the end", h.find(A(), "settingsMoreBelow").visible, false) })
    h.step("settings: the room is the panel's again", function() {
      var v = h.find(A(), "settingsView")
      v.room = Qt.binding(function() { var c = C(); return c && c.contentRoom > 0 ? c.contentRoom - v.areaTop : 0 })
      h.find(A(), "settingsFlick").contentY = 0
    }, function() { var v = h.find(A(), "settingsView"); return Math.abs(v.room - (C().contentRoom - v.areaTop)) < 0.5 })
    // (the refused write's error line above the tabs still takes room here:
    // Focus & zoom may scroll until Reset clears it, with the cue)
    h.step("settings: the room after it", function() {
      var v = h.find(A(), "settingsView"), f = h.find(A(), "settingsFlick")
      h.note("room " + Math.round(v.room) + ", groups " + Math.round(f.height) + " of " + Math.round(f.contentHeight)
             + ", cue " + h.find(A(), "settingsMoreBelow").visible)
      h.eq("a cue whenever it scrolls", h.find(A(), "settingsMoreBelow").visible || !f.interactive, true)
    })

    // reset to defaults, by the button
    h.step("settings: Reset to defaults", function() {
      h.markLog()
      click(h.find(A(), "settingsReset"))
    }, function() { return value("camera.image.brightness") === 128 && value("camera.focus.field_of_view") === "90"
                           && value("camera.exposure.auto_exposure") === "aperture_priority" }, 3000)
    h.step("settings: reset ran and came back as deltas", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([["settings", "reset", "--camera=" + brioId]]))
      h.eq("nothing stored", S().record.settings.groups.some(function(g) { return g.rows.some(function(r) { return r.stored }) }), false)
      h.eq("exposure time greyed again", h.model.findSetting(S().record, "camera.exposure.exposure_time_absolute").enabled, false)
      h.eq("no error", S().commandError, "")
    })

    // a generic camera: an enum of many choices is a dropdown, an action a button
    h.step("settings: a camera with a long menu and an action", function() {
      var opts = []
      for (var i = 0; i < 6; i++) opts.push("m" + i + ":Item " + i)
      h.writeFile("settings-state", [stateRow("other", "Other", "camera.other.mode", "enum", "Mode", "m1", "m0", { options: opts.join(",") }),
                                     stateRow("other", "Other", "camera.other.pan_reset", "action", "Recentre", "-", "-")])
      h.feed([snapshotLine(rev7({}))])
    }, function() { return !!S().record.settings && S().record.settings.groups[0].id === "other" && h.writerIdle() })
    h.wait(250)
    h.step("settings: the dropdown and the button", function() {
      var dd = h.find(A(), "settingDropdown-camera.other.mode")
      h.check("a dropdown", !!dd, "none")
      h.eq("its choice", dd ? dd.value : "", "m1")
      h.eq("the only group is open", C().settingsView.groups[0].expanded, true)
      h.markLog()
      C().setCursor("setting", stopOf("camera.other.mode"))
      h.eq("a dropdown row: the box draws the one highlight", highlights("camera.other.mode"), "dropdown")
      h.key(Qt.Key_Right)
      h.key(Qt.Key_Left)
      h.eq("Left/Right do nothing on a dropdown", JSON.stringify(S().settingDrafts), "{}")
      // the mouse away from where the list opens (its rows follow the mouse)
      keys.mouseMove(h.find(A(), "settingsTitle"), 1, 1)
      h.key(Qt.Key_Return)
    }, function() { return h.find(A(), "settingDropdown-camera.other.mode").popupOpen })
    h.step("settings: the list is open; Down, Enter", function() {
      h.eq("nothing written by opening it", setArgs().length, 0)
      h.key(Qt.Key_Down)
      h.key(Qt.Key_Return)
    }, function() { return value("camera.other.mode") === "m2" && !h.find(A(), "settingDropdown-camera.other.mode").popupOpen }, 3000)
    h.step("settings: Enter runs the action", function() {
      h.eq("the choice made in the list", JSON.stringify(setArgs()), JSON.stringify([write("camera.other.mode", "m2")]))
      h.eq("the box shows the daemon's word", h.find(A(), "settingDropdown-camera.other.mode").value, "m2")
      h.check("the keyboard is the panel's again", h.catcher(A()).activeFocus)
      h.markLog()
      C().setCursor("setting", stopOf("camera.other.pan_reset"))
      h.key(Qt.Key_Return)
    }, function() { return setArgs().length === 1 }, 3000)
    h.step("settings: action argv", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.other.pan_reset", "true")]))
      h.writeFile("settings-state", brioState())
      h.feed([snapshotLine(rev7({}))])
    }, function() { return !S().commandBusy && h.writerIdle() })

    // an old daemon, an old CLI, a newer schema, no camera: a hint, no settings
    var hintCase = function(label, snapshot, mode, text, file) {
      h.step("settings: " + label, function() {
        h.writeFile("settings-mode", [mode])
        h.feed([snapshotLine(snapshot)])
      }, function() { return S().record.settings === null && h.find(A(), "settingsHint").text === text && h.writerIdle() }, 4000)
      h.wait(250)
      h.step("settings: " + label + ": the hint, no groups, no stops", function() {
        h.eq("hint shown", h.find(A(), "settingsHint").visible, true)
        h.eq("no groups", C().settingsView.groups.length, 0)
        h.eq("no reset", h.find(A(), "settingsReset").visible, false)
        h.eq("no settings stops", kinds().indexOf("group") === -1 && kinds().indexOf("setting") === -1 && kinds().indexOf("reset") === -1, true)
        h.eq("a write is refused", S().moveSetting("camera.image.brightness", 10), false)
        h.eq("a reset is refused", S().resetSettings(), false)
      })
      if (file) h.grabStep(function() { return A().popup }, file)
    }
    hintCase("a daemon below revision 7", { interface_revision: 6, settings_schema: null, settings_revision: null }, "none",
             "The daemon needs updating for camera settings (omarchy-broadcastd 0.22 or newer).", "s1-old-daemon.png")
    hintCase("an old CLI", { interface_revision: 7 }, "none",
             "The omarchy-broadcast CLI needs updating for camera settings (omarchy-broadcast 0.22 or newer).", "s1-old-cli.png")
    hintCase("a newer settings schema", rev7({ settings_schema: 2 }), "none", "Update the plugin to show these camera settings.", "s1-newer-schema.png")
    hintCase("settings_clear", rev7({}), "clear", "This camera reports no settings.", "")

    // closed: nothing runs, nothing is written
    h.step("settings: close", function() {
      A().close()
      h.markLog()
      h.removeFile("settings-mode")
      h.removeFile("settings-state")
      h.removeFile("settings-camera")
      h.removeFile("settings-rev")
      h.removeFile("settings-serial")
      h.removeFile("settings-per-line")
      h.feed([snapshotLine({})])
    }, function() { return S().record.interfaceRevision === 4 && !P().running && h.writerIdle() })
    h.wait(1000)
    h.step("settings: nothing while closed", function() {
      h.eq("no command", setArgs().length, 0)
      h.eq("debounce idle", S().settingsTimer.running, false)
      h.eq("no draft", JSON.stringify(S().settingDrafts), "{}")
      h.eq("queue empty", S().pendingIntents.length, 0)
    })
  }

  // ---- live scenario (real daemon, real CLI) --------------------------------------

  Process {
    id: daemonProc
    onStarted: h.note("daemon started, pid " + processId)
    onExited: function(code, status) { h.note("daemon exited " + code + "/" + status) }
  }
  Process {
    id: consumerProc
    onExited: function(code) { h.note("consumer exited " + code) }
  }

  function startDaemon() {
    var live = Quickshell.env("OBH_LIVE")
    daemonProc.command = ["sh", "-c", 'exec "$0" --config "$1" --state "$2" 2>>"$3"',
                          Quickshell.env("OBH_DAEMON"), live + "/config.toml", live + "/state.toml", live + "/daemon.log"]
    daemonProc.running = true
  }

  function liveScenario() {
    var A = function() { return h.widgetA }
    var S = function() { return h.widgetA.service }
    var ids = []

    h.wait(800)
    h.step("start omarchy-broadcastd", function() { shellRoot.startDaemon() }, function() { return daemonProc.running })
    h.step("widgets connect to the real daemon", function() {
      h.widgetA = h.makeWidget(barA, { cliPath: shellRoot.cli })
      h.widgetB = h.makeWidget(barB, { cliPath: shellRoot.cli })
    }, function() { return h.widgetA && S().record.link === "ok" }, 20000)
    h.step("snapshot from the daemon", function() {
      var r = S().record
      var usbs = r.cameras.map(function(c) { return c.usb })
      h.note("cameras: " + JSON.stringify(r.cameras.map(function(c) { return c.label + " (" + c.usb + ") " + c.selectId })))
      h.note("state " + r.state + ", enabled " + r.enabled + ", active " + r.activeCameraName + ", mode " + r.outputMode)
      h.check("MX Brio listed", usbs.indexOf("046d:0944") !== -1, JSON.stringify(usbs))
      h.check("FHD Camera listed", usbs.indexOf("5986:1193") !== -1, JSON.stringify(usbs))
      for (var i = 0; i < r.cameras.length; i++) ids.push(r.cameras[i].selectId)
      if (!r.enabled) S().setEnabled(true)
      A().open()
    }, function() { return S().record.enabled && h.content(A()) !== null }, 15000)
    h.countStep(1, "live, two widgets")
    h.wait(400)
    h.grabStep(function() { return strip }, "live-bar-idle.png")
    h.grabStep(function() { return A().popup }, "live-panel-idle.png")

    var selectRow = function(which) {
      h.step("click camera row #" + which, function() {
        h.row(A(), h.notes.order[which]).choose()
      }, function() { return S().record.activeCamera === ids[h.notes.order[which]] && !S().commandBusy }, 15000)
      h.step("row #" + which + " active", function() {
        var i = h.notes.order[which]
        h.check("row " + i + " marked active", !!h.row(A(), i) && h.row(A(), i).isActive)
        h.note("active camera now " + S().record.activeCameraName)
      })
    }
    h.step("pick a non-active row first", function() {
      var first = S().record.activeCamera === ids[0] ? 1 : 0
      h.notes.order = [first, 1 - first]
    })
    selectRow(0)
    selectRow(1)
    h.step("next camera", function() {
      h.notes.before = S().record.activeCamera
      h.find(A(), "nextCameraButton").clicked()
    }, function() { return S().record.activeCamera !== h.notes.before && !S().commandBusy }, 15000)
    h.step("next camera result", function() { h.note("after next: " + S().record.activeCameraName) })

    h.step("right click: off", function() {
      A().close()
      A().iconButton.triggerPress(Qt.RightButton)
    }, function() { return S().record.state === "off" && !S().commandBusy }, 15000)
    h.step("off icon", function() {
      h.eq("off glyph", A().iconButton.text, glyphOf("off"))
      h.eq("enabled false", S().record.enabled, false)
    })
    h.grabStep(function() { return strip }, "live-bar-off.png")
    h.step("right click: on", function() { A().iconButton.triggerPress(Qt.RightButton) },
           function() { return S().record.state === "idle" && S().record.enabled }, 15000)

    h.step("a consumer opens the virtual camera", function() {
      consumerProc.command = ["gst-launch-1.0", "-q", "v4l2src", "device=/dev/video11", "num-buffers=360", "!", "fakesink"]
      consumerProc.running = true
      A().open()
    }, function() { return S().record.state === "active" }, 30000)
    h.step("stats arrive", function() {}, function() {
      var st = S().record.stats
      return st !== null && st.fps !== null && st.fps > 0
    }, 15000)
    h.wait(2500)
    h.step("live figures", function() {
      h.tab(A(), "status")
      var rows = h.model.statsRows(S().record)
      h.note("stats: " + JSON.stringify(rows))
      h.note("consumers " + S().record.consumers + ", tooltip: " + A().iconButton.tooltipText)
      h.eq("active glyph", A().iconButton.text, glyphOf("active"))
      h.eq("stats block shown", h.find(A(), "statsBlock").visible, true)
      h.check("consumer counted", S().record.consumers >= 1, S().record.consumers)
    })
    h.grabStep(function() { return strip }, "live-bar-active.png")
    h.grabStep(function() { return A().popup }, "live-panel-active.png")
    h.step("consumer ends, stream stops", function() {}, function() {
      return !consumerProc.running && S().record.state !== "active" && S().record.stats === null
    }, 40000)
    h.step("after the consumer", function() { h.note("state after consumer: " + S().record.state) })

    h.step("kill the daemon by its PID", function() {
      h.killPid(daemonProc.processId)
    }, function() { return S().record.link === "not-running" && !daemonProc.running }, 15000)
    h.step("daemon gone", function() {
      h.eq("unavailable glyph", A().iconButton.text, glyphOf("unavailable"))
      h.eq("tooltip", A().iconButton.tooltipText, "Omarchy Broadcast: daemon not running")
      A().open()
    })
    h.wait(400)
    h.grabStep(function() { return strip }, "live-bar-unavailable.png")
    h.grabStep(function() { return A().popup }, "live-panel-unavailable.png")
    h.step("restart the daemon", function() { shellRoot.startDaemon() },
           function() { return S().record.link === "ok" }, 20000)
    h.step("recovered without restarting the harness", function() {
      h.eq("the watch was never respawned", S().watchStarts, 1)
      h.note("recovered: state " + S().record.state + ", cameras " + S().record.cameras.length)
    })
    h.step("stop the daemon", function() {
      daemonProc.running = false
    }, function() { return !daemonProc.running && S().record.link === "not-running" }, 15000)
    h.step("destroy the widgets", function() {
      A().destroy()
      h.widgetB.destroy()
      h.widgetA = null
      h.widgetB = null
    })
    h.wait(500)
    h.countStep(0, "live, zero widgets")
  }

  Component.onCompleted: {
    h.model = Qt.createQmlObject('import QtQuick; import "file://' + pluginPath + '/Model.js" as M; QtObject { property var m: M }',
                                 shellRoot, "modelLoader").m
    console.log("harness mode " + mode + ", plugin " + pluginPath)
    if (mode === "live") liveScenario()
    else mockScenario()
  }
}
