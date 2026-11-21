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
//                as the shell loads a plugin): run-harness.sh's copy of the
//                checkout's files, SetupDialog.qml without its layer-shell
//                namespace line (see OverlayWindow.qml)
//   OBH_CLI      CLI for the widgets' cliPath (the fake's copy, or live a
//                symlink to the real CLI of OMARCHY_BROADCAST_CLI; either
//                path is unique to the run, the marker watches are counted by)
//   OBH_FAKE     the fake's state directory (mock)
//   OBH_SCREENS  where PNG grabs go
//   OBH_DAEMON   omarchy-broadcastd binary (OMARCHY_BROADCASTD); OBH_LIVE
//                the live scratch dir (live)
//   OBH_NLBIN    a PATH entry whose name holds a newline, with a CLI in it (mock)
//   OBH_RESOLVER_PATH the PATH every resolver case runs with (plus a CLI dir
//                where a case wants one): an empty dir, never an
//                omarchy-broadcast, so one installed in /usr/bin cannot
//                answer (mock)
//   OBH_REALCLI  the path of a symlink to the real CLI of OMARCHY_BROADCAST_CLI
//                in a dir of its own, which one resolver case puts on PATH.
//                Empty when the variable is unset: the case prints SKIP. The
//                resolver only prints the path; nothing runs it (mock)
//
// The shell's own PATH holds the fake and the system tools, never another
// omarchy-broadcast (run-harness.sh refuses to start otherwise).
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
  // Its toggle and hide, as the shell routes them to the plugin's overlay
  // (the setup dialog, h.dialog): toggle hides it while it reports itself
  // open (`opened`), else summons it with the payload (open()); hide calls
  // its close(). Each call is recorded.
  QtObject {
    id: fakeShell
    property var calls: []
    property bool refuse: false
    property var refused: []
    property var toggles: []
    property var hides: []
    function toggle(id, payload) {
      toggles = toggles.concat([{ id: id, payload: payload }])
      if (!h.dialog) return false
      if (h.dialog.opened) h.dialog.close()
      else h.dialog.open(payload)
      return true
    }
    function hide(id) {
      hides = hides.concat([id])
      if (h.dialog) h.dialog.close()
      return true
    }
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

  // A shell with no toggle (openSetup has nothing to open).
  QtObject {
    id: noToggleShell
    function hide(id) { return false }
  }

  FloatingWindow {
    id: window
    implicitWidth: 960
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
    // The setup dialog, as the shell's panel loader makes it (setupScenario).
    property var dialog: null
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
    // The first item under `item` whose text is `text`.
    function findByText(item, text) {
      if (!item) return null
      if (item.text === text) return item
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) {
        var found = findByText(kids[i], text)
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
      for (var i = 0; i < kids.length; i++) if (kids[i].text === (value === 30 ? "30 fps" : String(value))) return kids[i]
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
                         urgent: String(C.urgent), muted: String(C.muted), shellValues: C.shellValues,
                         styleOverrides: Commons.Style.styleOverrides }
        C.shellValues = ({})
        // The installed theme's control state colours are hex values of its
        // own palette (a dark theme's foreground as the selected text): a
        // light theme's file names its own, so they follow the palette here.
        Commons.Style.styleOverrides = ({})
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
        Commons.Style.styleOverrides = savedPalette.styleOverrides
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
  // A warning of several clauses and one line break, near the 512 bytes the
  // daemon allows (interface revision 12 sets clauses like these).
  function longWarning() {
    return "Output 1280x720@30 applies when zoom, obs release the virtual camera; capture mode 3840x2160@30 is not offered by "
      + "this camera, so it streams at 1920x1080@30 instead; effect blur, noise removal unavailable: NVIDIA Maxine video effects: Disabled"
      + "\nOutput rate 60 fps cannot be made by frame generation, which no module provides; the video is sent at 30 fps; "
      + "close the applications that hold the virtual camera, then start it again"
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
      h.eq("Mic tab hidden", h.find(A(), "micTab").visible, false)
      h.eq("no Status tab", h.find(A(), "tab-status"), null)
      h.eq("tab labels", ["effect", "camera", "mic"].map(function(t) { return h.find(A(), "tab-" + t).text }).join(","), "Effects,Camera,Mic")
      h.eq("cameras in the dropdown", h.find(A(), "cameraDropdown").options.length, 3)
      h.eq("switch shown", h.find(A(), "enableSwitch").visible, true)
      h.eq("the switch is labelled", h.find(A(), "enableLabel").text, "Virtual camera")
      h.eq("the (i) shown", h.find(A(), "infoButton").visible, true)
      h.eq("preview off: a one-line strip", h.find(A(), "previewStrip").visible, true)
      h.eq("no frame area", h.find(A(), "previewBlock").visible, false)
      h.eq("one column", A().layout.wide, false)
      h.eq("a revision-4 daemon: no effect choices", h.find(A(), "effectChoices").visible, false)
      h.eq("the Effect tab says the daemon needs updating", h.find(A(), "effectHint").text, h.model.DAEMON_NO_EFFECTS)
      h.eq("no generic effect rows", h.find(A(), "effectSettingsArea").visible, false)
      h.eq("hero status line", h.content(A()).heroMeta, "Ready: starts when an app uses the camera")
      h.eq("in words, as drawn", h.find(A(), "heroState").text, "Ready: starts when an app uses the camera")
      h.eq("the active camera shown", h.find(A(), "cameraDropdown").value, brioId)
      h.eq("no cursor before a key", h.content(A()).cursorActive, false)
      h.check("panel took the keyboard focus", h.catcher(A()) && h.catcher(A()).activeFocus)
      h.fits(A(), "Effect tab, idle")
    })
    h.grabStep(function() { return A().popup }, "panel-idle.png")
    h.tabStep(A, "camera", "idle", function() {
      h.eq("cameras block shown on the Camera tab", h.find(A(), "camerasBlock").visible, true)
      h.eq("one camera row: a dropdown", h.find(A(), "cameraRow").visible, true)
      h.eq("no Next camera button", h.find(A(), "nextCameraButton"), null)
      h.eq("the effect hint on the Effect tab only", h.find(A(), "effectHint").visible && h.find(A(), "effectTab").visible, false)
      h.fits(A(), "Camera tab, idle")
    })
    h.step("the (i): the Details view in place of the tabs", function() {
      h.check("opened", h.content(A()).toggleDetails())
    }, function() { return h.find(A(), "detailsView").visible })
    h.wait(250)
    h.step("Details: the rows, Copy, no tab", function() {
      h.eq("tab row hidden", h.find(A(), "tabRow").visible, false)
      h.eq("Camera tab hidden", h.find(A(), "cameraTab").visible, false)
      h.eq("rows", h.find(A(), "detailsRepeater").count, h.model.detailsRows(S().record).length)
      h.eq("the camera's USB id is a row", h.model.detailsRows(S().record).filter(function(r) { return r.label === "USB id" })[0].value, "046d:0944")
      h.eq("the plugin's version is a row", h.model.detailsRows(S().record).slice(-1)[0].value, h.model.PLUGIN_VERSION)
      h.check("Copy", h.content(A()).copyDetails())
      h.eq("the text copied", h.find(A(), "detailsCopyText").text, h.model.detailsText(h.model.detailsRows(S().record)))
      h.eq("said so", h.find(A(), "detailsCopied").visible, true)
      h.eq("stops: the header, Back and Copy", h.content(A()).stops.map(function(st) { return st.kind }).join(","), "switch,info,details-back,details-copy")
      h.fits(A(), "Details view")
      h.check("closed again", h.content(A()).toggleDetails())
      h.eq("the tabs back", h.find(A(), "tabRow").visible, true)
      h.tab(A(), "effect")
      h.eq("nothing written by showing a tab or the details", fakeShell.calls.length, 0)
    })

    // camera selection by a choice of the dropdown
    h.step("select FHD from the dropdown", function() {
      h.markLog()
      h.check("chosen", h.content(A()).chooseCamera(fhdId))
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("select argv", function() {
      h.eq("argv", JSON.stringify(h.newLogArgs()[0]), JSON.stringify(["camera", "--", fhdId]))
      h.eq("no optimistic change", S().record.activeCamera, brioId)
      h.feed([stateLine({ active_camera: fhdId, active_camera_name: "FHD Camera" }), camerasLine(fhdId)])
    }, function() { return S().record.activeCamera === fhdId })
    h.step("selection arrives on the stream", function() {
      h.eq("the dropdown shows FHD", h.find(A(), "cameraDropdown").value, fhdId)
      h.eq("choosing the active one runs nothing", h.content(A()).chooseCamera(fhdId), false)
      h.eq("tooltip names FHD", A().iconButton.tooltipText, "Omarchy Broadcast: idle · FHD Camera · 0 consumers")
    })

    h.step("hostile id stays one argv element after --", function() {
      h.markLog()
      h.check("chosen", h.content(A()).chooseCamera(hostileId))
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("hostile argv", function() {
      h.eq("argv", JSON.stringify(h.newLogArgs()[0]), JSON.stringify(["camera", "--", hostileId]))
    }, function() { return !S().commandBusy })


    // ---- keyboard: real key events through the panel's PanelKeyCatcher
    h.step("key: first Down shows the cursor on the switch", function() {
      h.check("catcher focused", h.catcher(A()).activeFocus)
      h.key(Qt.Key_Down)
    }, function() { return h.content(A()).cursorActive })
    h.step("cursor on the switch", function() {
      var c = h.content(A())
      h.eq("stop", c.currentStop.kind, "switch")
      h.eq("switch has the cursor", h.find(A(), "enableSwitch").hasCursor, true)
      h.eq("stops = switch, (i), the strip's Show preview, the tab row (the Effect tab of a revision-4 daemon has no control)",
           c.stops.map(function(st) { return st.kind }).join(","), "switch,info,tabs")
      h.key(Qt.Key_Down)
      h.eq("Down: the (i)", c.currentStop.kind, "info")
      h.eq("the (i) has the cursor", h.find(A(), "infoButton").hasCursor, true)
      h.key(Qt.Key_Down)
    })
    h.step("Down: the tab row, on the tab shown", function() {
      var c = h.content(A())
      h.eq("stop", c.currentStop.kind, "tabs")
      h.eq("tab cursor on Effect", c.tabCursor, 0)
      h.eq("Effect chip has the cursor", h.find(A(), "tab-effect").hasCursor, true)
      h.eq("the other chips have none", h.find(A(), "tab-camera").hasCursor || h.find(A(), "tab-mic").hasCursor, false)
      h.eq("switch lost it", h.find(A(), "enableSwitch").hasCursor, false)
      h.check("no effect verb is left to call", c.toggleDenoise === undefined && S().setEffect === undefined && S().setDenoise === undefined)
      h.check("an effect choice with no options runs nothing", !c.chooseEffect(0))
      h.markLog()
      h.key(Qt.Key_Down)
      h.eq("Down from the last stop stays", c.currentStop.kind, "tabs")
      h.key("k")
      h.key("j")
      h.eq("the tab row", c.currentStop.kind, "tabs")
      h.eq("on the tab shown", c.tabCursor, 0)
      h.notes.calls = fakeShell.calls.length
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
      h.eq("stops = switch, (i), tab row, the camera dropdown (the Camera tab)", c.stops.map(function(st) { return st.kind }).join(","), "switch,info,tabs,camera")
      h.key(Qt.Key_Right)
      h.eq("Right: Mic", c.tab, "mic")
      h.key(Qt.Key_Right)
      h.eq("Right once more: Mic, and no further", c.tab, "mic")
      h.key(Qt.Key_Left)
      h.eq("Left: Camera again", c.tab, "camera")
      h.eq("a write per change", fakeShell.calls.length, h.notes.calls + 3)
      h.key(Qt.Key_Down)
    })
    h.step("Down: the camera dropdown", function() {
      h.eq("the dropdown has the cursor", h.find(A(), "cameraDropdown").hasCursor, true)
      h.eq("switch lost it", h.find(A(), "enableSwitch").hasCursor, false)
    })
    h.grabStep(function() { return A().popup }, "panel-cursor-row.png")
    h.step("Down from the last stop stays; k x3 back to the switch, Enter turns off", function() {
      h.key(Qt.Key_Down)
      h.eq("still the dropdown", h.content(A()).currentStop.kind, "camera")
      for (var i = 0; i < 3; i++) h.key("k")
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
    h.step("hovering the dropdown moves the same cursor", function() {
      h.content(A()).setCursor("camera", -1)
      h.eq("the dropdown has the cursor", h.find(A(), "cameraDropdown").hasCursor, true)
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
      h.key("4")
      h.eq("4: nothing (three tabs)", c.tab, "camera")
      h.eq("a number key shows no cursor", c.cursorActive, false)
      h.key("3")
      h.eq("3: Mic", c.tab, "mic")
      h.key("1")
      h.eq("1: Effect", c.tab, "effect")
      h.key("2")
      h.eq("2: Camera", c.tab, "camera")
      h.key("5")
      h.key("0")
      h.key("9")
      h.eq("other digits do nothing", c.tab, "camera")
      h.key("2")
      h.eq("a write per change, none for the tab shown", fakeShell.calls.length, h.notes.calls + 3)
    })
    h.step("tabs: a click on a chip", function() {
      var chip = h.find(A(), "tab-mic")
      keys.mouseClick(chip, chip.width / 2, chip.height / 2)
    }, function() { return h.content(A()).tab === "mic" })
    h.step("tabs: hovering moves the cursor, not the tab; Enter shows the tab under it", function() {
      var c = h.content(A())
      h.eq("written", JSON.stringify(fakeShell.calls[fakeShell.calls.length - 1].entry.panelTab), JSON.stringify("mic"))
      c.setTabCursor(0)
      h.eq("Effect chip has the cursor", h.find(A(), "tab-effect").hasCursor, true)
      h.eq("Mic still shown", c.tab, "mic")
      h.eq("Mic still selected", h.find(A(), "tab-mic").selected, true)
      h.key(Qt.Key_Return)
      h.eq("Enter: Effect", c.tab, "effect")
      h.key("2")
      h.eq("a number key from inside a tab: Camera", c.tab, "camera")
      h.eq("the cursor stays on the tab row", c.currentStop.kind, "tabs")
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
      w.settings = { cliPath: shellRoot.cli, panelTab: ["mic"] }
      h.eq("an array reads as the default", h.content(w).tab, "effect")
      w.settings = { cliPath: shellRoot.cli, panelTab: "status" }
      h.eq("the Status tab of an older version reads as the default", h.content(w).tab, "effect")
      w.settings = { cliPath: shellRoot.cli, panelTab: "mic" }
      h.eq("a valid stored change is followed", h.content(w).tab, "mic")
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
           JSON.stringify({ id: shellRoot.moduleName, cliPath: shellRoot.cli, panelTab: "mic" }))
      h.eq("shown", c.tab, "mic")
      h.eq("the settings stay as the bar gave them", A().settings.panelTab, "camera")
      A().settings = JSON.parse(JSON.stringify(A().settings))
      h.eq("re-injected stale settings do not undo it", c.tab, "mic")
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
    h.step("middle click turns off; a second one in flight is ignored", function() {
      A().close()
      h.markLog()
      A().iconButton.triggerPress(Qt.MiddleButton)
      h.check("busy after the first click", S().commandBusy)
      A().iconButton.triggerPress(Qt.MiddleButton)
      B().iconButton.triggerPress(Qt.MiddleButton)
    }, function() { return h.newLogArgs().length >= 1 })
    h.wait(900)
    h.step("off argv, once", function() {
      var got = h.newLogArgs()
      h.eq("runs", got.length, 1)
      h.eq("argv", JSON.stringify(got[0]), JSON.stringify(["off"]))
      h.eq("no optimistic change", S().record.enabled, true)
      h.eq("middle click does not open the panel", A().opened, false)
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
      h.eq("description", A().iconButton.Accessible.description,
           "Click: open the panel. Middle click: turn the camera on. Right click: open the setup.")
    })
    h.step("middle click on the other monitor turns on", function() {
      h.markLog()
      B().iconButton.triggerPress(Qt.MiddleButton)
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("on argv", function() {
      h.eq("argv", JSON.stringify(h.newLogArgs()[0]), JSON.stringify(["on"]))
      h.feed([stateLine({ state: "idle", enabled: true, active_camera: fhdId, active_camera_name: "FHD Camera" })])
    }, function() { return S().record.state === "idle" && S().record.enabled })
    h.step("left click opens and closes the panel", function() {
      h.markLog()
      A().iconButton.triggerPress(Qt.LeftButton)
      h.eq("left click opens it", A().opened, true)
      A().iconButton.triggerPress(Qt.LeftButton)
      h.eq("a second left click closes it", A().opened, false)
      h.eq("the other monitor's panel stays closed", B().opened, false)
      h.eq("description once on", A().iconButton.Accessible.description,
           "Click: open the panel. Middle click: turn the camera off. Right click: open the setup.")
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
      h.eq("starting is faded (the kit dims it)", A().iconButton.dimmed, true)
      h.eq("starting shares the webcam glyph with active", glyphOf("starting"), glyphOf("active"))
    })
    h.grabStep(function() { return strip }, "bar-starting.png")
    h.step("active with stats", function() {
      h.feed([stateLine({ state: "active", consumers: 1, active_camera: fhdId, active_camera_name: "FHD Camera" }),
              '{"v":1,"type":"stats","fps":30.0,"latency_p50_ms":41.2,"cpu_percent":6.5,"gpu_percent":-1.0}'])
      A().open()
    }, function() { return S().record.state === "active" && S().record.stats !== null })
    h.wait(300)
    h.step("the Details view", function() { h.content(A()).toggleDetails() })
    h.wait(250)
    h.step("active icon and panel", function() {
      h.eq("active glyph", A().iconButton.text, glyphOf("active"))
      h.eq("active accent", A().iconButton.active, true)
      h.eq("tooltip", A().iconButton.tooltipText, "Omarchy Broadcast: active · FHD Camera · 1 consumer")
      h.eq("the live figures are Details rows", h.model.detailsRows(S().record).filter(function(r) { return r.label === "Frame rate" }).length, 1)
      h.eq("hero status line", h.content(A()).heroMeta, "In use, 30 fps")
      var rows = h.model.statsRows(S().record)
      h.eq("fps", rows[0].value, "30.0 fps")
      h.eq("latency", rows[1].value, "41.2 ms")
      h.eq("cpu", rows[2].value, "6.5 %")
      h.eq("gpu -1 is unknown", rows[3].value, "—")
      h.eq("Details shown", h.find(A(), "detailsView").visible, true)
      h.fits(A(), "Details, active with figures")
    })
    h.grabStep(function() { return strip }, "bar-active.png")
    h.grabStep(function() { return A().popup }, "panel-active.png")

    h.step("error state", function() {
      if (h.content(A()).detailsOpen) h.content(A()).toggleDetails()
      h.feed([stateLine({ state: "error", consumers: 1, active_camera: fhdId, active_camera_name: "FHD Camera",
                          error: "loopback device <b>Omarchy Broadcast</b> not found & retrying\nevery 2 s" })])
    }, function() { return S().record.state === "error" })
    h.wait(200)
    h.step("error icon and panel", function() {
      h.eq("error glyph", A().iconButton.text, glyphOf("error"))
      h.eq("error uses urgent", String(A().iconButton.activeColor), String(barA.urgent))
      h.eq("error active", A().iconButton.active, true)
      h.eq("stats cleared on leaving active", S().record.stats, null)
      h.eq("no live figures in the Details", h.model.detailsRows(S().record).filter(function(r) { return r.label === "Frame rate" }).length, 0)
      var e = h.find(A(), "daemonError")
      h.eq("daemon error shown", e.visible, true)
      h.check("daemon error sanitised", !/[<>&\n]/.test(e.text), e.text)
    })
    h.grabStep(function() { return strip }, "bar-error.png")
    h.grabStep(function() { return A().popup }, "panel-error.png")

    // a daemon warning is not an error: the state stays active, the line is not urgent
    h.step("warning state", function() {
      h.feed([stateLine({ state: "active", consumers: 1, active_camera: fhdId, active_camera_name: "FHD Camera", error: "",
                          warning: "effect blur unavailable: no effect module provides the background effect" })])
    }, function() { return S().record.state === "active" && S().record.warning !== "" })
    h.wait(200)
    h.step("warning glyph and panel", function() {
      h.eq("not the alert glyph", A().iconButton.text, glyphOf("active"))
      h.check("not the error glyph", A().iconButton.text !== glyphOf("error"))
      h.eq("not urgent", String(A().iconButton.activeColor), String(Commons.Color.accent))
      h.eq("visual key stays active", h.model.visualKey(S().record), "active")
      h.eq("no error status", h.content(A()).heroMeta, "In use")
      h.eq("daemon error line hidden", h.find(A(), "daemonError").visible, false)
      var w = h.find(A(), "daemonWarning")
      h.eq("warning line shown", w.visible, true)
      h.check("warning text present", w.text.indexOf("effect blur unavailable") >= 0, w.text)
      h.check("warning line not urgent", String(w.color) !== String(barA.urgent), String(w.color))
      h.check("tooltip names it a warning", A().iconButton.tooltipText.indexOf("warning: effect blur unavailable") >= 0, A().iconButton.tooltipText)
      h.check("tooltip does not call it an error", A().iconButton.tooltipText.indexOf("error") < 0, A().iconButton.tooltipText)
    })
    // revision 12: a warning of several clauses (and one line break), near the 512 bytes
    // the daemon allows: wrapped whole in the panel, never cut to one line
    h.step("a long, multi-line warning", function() {
      h.feed([stateLine({ state: "active", consumers: 1, active_camera: fhdId, active_camera_name: "FHD Camera", error: "",
                          warning: longWarning() })])
    }, function() { return S().record.warning.indexOf("start it again") >= 0 })
    h.wait(200)
    h.step("the long warning wraps in full", function() {
      var w = h.find(A(), "daemonWarning")
      h.eq("shown", w.visible, true)
      h.check("under 512 characters, and none cut", longWarning().length < 512 && w.text.indexOf("start it again") >= 0 && w.text.indexOf("\u2026") < 0, w.text.length)
      h.check("the line break reads as a space", w.text.indexOf("\n") < 0 && w.text.indexOf("Disabled Output rate") >= 0, w.text)
      h.check("wrapped onto several lines", w.lineCount > 3, w.lineCount)
      h.check("not elided or truncated", !w.truncated, "truncated")
      h.check("the Text is as tall as its lines", w.height >= w.contentHeight - 0.5, w.height + " for " + w.contentHeight)
      h.check("within its column", w.width <= w.parent.width + 0.5, w.width + " of " + w.parent.width)
      h.fits(A(), "Effects tab with a long warning")
    })
    h.grabStep(function() { return A().popup }, "panel-long-warning.png")
    h.step("back to the error state", function() {
      h.feed([stateLine({ state: "error", consumers: 1, active_camera: fhdId, active_camera_name: "FHD Camera",
                          error: "loopback device not found", warning: "" })])
    }, function() { return S().record.state === "error" && S().record.warning === "" })
    h.step("the warning line is gone", function() { h.eq("hidden", h.find(A(), "daemonWarning").visible, false) })

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
      A().iconButton.triggerPress(Qt.MiddleButton)
      h.eq("middle click opens the panel instead", A().opened, true)
      h.eq("description", A().iconButton.Accessible.description, "Click or middle click: open the panel. Right click: open the setup.")
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
      h.eq("hero status line", h.content(A()).heroMeta, "Unavailable")
      h.eq("unavailable title", h.find(A(), "unavailableTitle").text, "omarchy-broadcastd is not running")
      h.eq("start command as text", h.find(A(), "unavailableCommand").text, "systemctl --user enable --now omarchy-broadcastd")
      h.eq("switch hidden", h.find(A(), "enableSwitch").visible, false)
      h.eq("cameras hidden", h.find(A(), "camerasBlock").visible, false)
      A().close()
      h.markLog()
      A().iconButton.triggerPress(Qt.MiddleButton)
      h.eq("middle click opens the panel instead", A().opened, true)
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

    // a revision-1 daemon (before effects): the Effect tab says it needs updating
    h.step("snapshot from a daemon without effects", function() {
      h.tab(A(), "effect")
      h.feed([snapshotLine({ interface_revision: 1 })])
    }, function() { return S().record.link === "ok" && S().record.interfaceRevision === 1 })
    h.step("the Effect tab names the daemon, offers nothing", function() {
      h.eq("hint", h.find(A(), "effectHint").text, h.model.DAEMON_NO_EFFECTS)
      h.eq("no choices", h.find(A(), "effectChoices").visible, false)
      h.eq("no effect stop", h.content(A()).stops.filter(function(st) { return st.kind === "effect" }).length, 0)
      h.markLog()
      h.check("a choice refused", !h.content(A()).chooseEffect(1))
      h.eq("nothing ran", h.newLogArgs().length, 0)
    })
    h.grabStep(function() { return A().popup }, "panel-effect-old-daemon.png")
    h.step("effects back", function() { h.feed([snapshotLine({})]) }, function() { return S().record.interfaceRevision === 4 })

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
      A().iconButton.triggerPress(Qt.MiddleButton)
      h.eq("middle click opens the panel", A().opened, true)
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
    // too short for the card: the screen caps its height, only the body (the
    // tab's content) scrolls, and the cursor's row is kept in view
    h.step("12 cameras", function() {
      h.feed([manyCamerasLine(12, true)])
      A().open()
    }, function() { return S().record.cameras.length === 12 && h.content(A()) !== null })
    h.step("on a short screen", function() {
      h.tab(A(), "camera")
      A().popup.availableCardHeight = 230
    })
    h.wait(400)
    h.step("panel capped; the body scrolls, the header and the tabs stay", function() {
      var flick = h.find(A(), "panelFlick")
      h.eq("cameras in the dropdown", h.find(A(), "cameraDropdown").options.length, 12)
      h.check("card height capped by the screen", A().popup.height <= 230, A().popup.height + " > 230")
      h.check("body taller than its room", flick.contentHeight > flick.height, flick.contentHeight + " vs " + flick.height)
      h.eq("scrolls", flick.interactive, true)
      h.eq("the tab row is not in the scroller", h.content(A()).inBody(h.find(A(), "tabRow")), false)
      h.eq("truncation row", h.find(A(), "camerasTruncated").text, "More cameras are connected; they are not shown")
      h.eq("stops", h.content(A()).stops.map(function(st) { return st.kind }).join(","), "switch,info,tabs,camera")
      flick.contentY = flick.contentHeight - flick.height
    })
    h.grabStep(function() { return A().popup }, "panel-12-cameras.png")
    h.step("cursor to the camera dropdown", function() {
      h.key(Qt.Key_Down)
      for (var i = 0; i < 3; i++) h.key(Qt.Key_Down)
    })
    h.wait(400)
    h.step("cursor row kept in view", function() {
      var flick = h.find(A(), "panelFlick")
      var row = h.find(A(), "cameraRow")
      h.eq("the dropdown has the cursor", h.find(A(), "cameraDropdown").hasCursor, true)
      var top = row.mapToItem(flick, 0, 0).y
      h.check("row inside the viewport", top >= -0.5 && top + row.height <= flick.height + 0.5, top + " / " + flick.height)
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
    healthScenario()
    setupScenario()
    mediaScenario()
    measureScenario()

    // the resolver itself: omarchy-broadcast on PATH, nothing else
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
    var nlBin = Quickshell.env("OBH_NLBIN")
    resolverCase("PATH wins", h.model.resolverArgv(), fakeBin + ":" + rpath, shellRoot.cli, 0)
    resolverCase("nothing found", h.model.resolverArgv(), rpath, "", 1)
    resolverCase("PATH entry with a newline is skipped", h.model.resolverArgv(), nlBin + ":" + rpath, "", 1)
    // a real omarchy-broadcast binary, found (not run) on PATH; optional,
    // as the plugin's checkout carries no CLI
    var realCli = Quickshell.env("OBH_REALCLI") || ""
    if (realCli !== "")
      resolverCase("real CLI on PATH (OMARCHY_BROADCAST_CLI)", h.model.resolverArgv(),
                   realCli.replace(/\/omarchy-broadcast$/, "") + ":" + rpath, realCli, 0)
    else
      h.step("resolver: real CLI on PATH", function() {
        console.log("  SKIP resolver real CLI on PATH: OMARCHY_BROADCAST_CLI is not set")
      })
    h.step("newline fixtures exist", function() {
      h.check("resolver PATH set", rpath !== "" && rpath.charAt(0) === "/", rpath)
      h.check("PATH entry has a newline", nlBin.indexOf("\n") !== -1)
    })

    // the CLI found on PATH; re-resolved after a start failure and on attach
    var devCli = shellRoot.cli
    h.step("back up the PATH CLI", function() {
      A().destroy()
      h.widgetA = null
      h.enqueue(["cp", "--", shellRoot.cli, shellRoot.cli + ".off"])
    }, function() { return h.writerIdle() })
    h.step("widget searching PATH", function() {
      h.widgetA = h.makeWidget(barA, {})
    }, function() { return h.widgetA && S().record.link === "ok" }, 8000)
    h.step("PATH CLI resolved", function() {
      h.eq("source", S().cliSource, "path")
      h.eq("path", S().cliPath, devCli)
      // replaced (new inode) by a file the resolver accepts but cannot start
      h.enqueue(["sh", "-c", 'printf "#!/nonexistent/interpreter\\n" > "$0.new" && chmod +x "$0.new" && mv -f "$0.new" "$0"', devCli])
    }, function() { return h.writerIdle() })
    h.step("kill the watch", function() {
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
      h.note("CLI unstartable: " + f + " failures, " + r + " resolver runs in " + since + " ms")
      h.eq("resolver runs = failures", r, f)
      h.check("second failure waited the doubled backoff (>= ~3 s)", since >= 2700, since)
      h.eq("still the PATH path", S().cliPath, devCli)
      h.enqueue(["rm", "-f", "--", devCli])
    }, function() { return h.writerIdle() })
    h.step("CLI removed: the next failure re-resolves to nothing", function() {},
           function() { return S().cliPath === "" && S().record.link === "cli-missing" }, 10000)
    h.step("says what was searched", function() {
      h.eq("names PATH", S().record.linkText, "omarchy-broadcast is not on PATH")
      h.notes.failures = S().watchStartFailures
      h.notes.resolves = S().resolverRuns
    })
    h.wait(3000)
    h.step("then nothing runs on a timer", function() {
      h.eq("no more start attempts", S().watchStartFailures - h.notes.failures, 0)
      h.eq("no more resolver runs", S().resolverRuns - h.notes.resolves, 0)
      h.enqueue(["sh", "-c", 'cp -- "$1" "$0" && chmod +x "$0"', devCli, shellRoot.cli + ".off"])
    }, function() { return h.writerIdle() })
    h.step("CLI back; a new widget attaches and re-resolves", function() {
      h.notes.resolves = S().resolverRuns
      h.widgetB = h.makeWidget(barB, {})
    }, function() { return S().record.link === "ok" && S().cliPath === devCli }, 8000)
    h.step("recovered on attach", function() {
      h.eq("one resolver run", S().resolverRuns - h.notes.resolves, 1)
      h.eq("source", S().cliSource, "path")
      A().destroy()
      B().destroy()
      h.widgetA = null
      h.widgetB = null
      h.enqueue(["rm", "-f", "--", shellRoot.cli + ".off"])
    }, function() { return h.writerIdle() })

    // zero widgets -> zero watch processes
    h.wait(500)
    h.countStep(0, "with zero widgets at the end")
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
      h.eq("note", h.find(A(), "previewNote").text, "Preview off")
      h.eq("note shown", h.find(A(), "previewNote").visible, true)
      h.eq("a one-line strip, no frame area", h.find(A(), "previewStrip").visible && !h.find(A(), "previewFrame").visible, true)
      h.eq("the strip is one line", h.find(A(), "previewStrip").height < h.find(A(), "previewNote").font.pixelSize * 4, true)
      h.eq("image hidden", h.find(A(), "previewImage").visible, false)
      h.eq("note in the dim colour", h.find(A(), "previewNote").color, h.content(A()).dim)
      h.eq("Show preview offered", h.find(A(), "previewToggle").visible && h.find(A(), "previewToggle").text === "Show preview", true)
      h.eq("one column, 520", A().layout.wide + "," + A().popup.contentWidth, "false,520")
      h.eq("nothing written on open", fakeShell.calls.length, 0)
      h.eq("nothing unsaved", h.find(A(), "previewUnsaved").visible, false)
      // the strip under the tab row (narrow: the tabs stay put from tab to tab)
      var strip = h.find(A(), "previewStrip")
      h.check("the strip follows the tab row",
              strip.mapToItem(null, 0, 0).y > h.find(A(), "tabRow").mapToItem(null, 0, 0).y, String(strip.y))
      h.eq("stops", h.content(A()).stops.map(function(st) { return st.kind }).join(","), "switch,info,tabs,preview")
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
      h.eq("still the strip", h.find(A(), "previewStrip").visible, true)
    })
    h.previewCountStep(0, "active for preview leases only")

    h.step("preview: an app opens the loopback: hidden stays hidden", function() {
      h.feed([stateLine(rev5({ state: "active", consumers: 2, loopback_consumers: 1 }))])
    }, function() { return S().record.loopbackConsumers === 1 })
    h.wait(600)
    h.step("preview: hidden, nothing runs whoever uses the camera", function() {
      h.eq("not wanted", P().wanted, false)
      h.eq("never started", P().starts, 0)
      h.eq("still the strip", h.find(A(), "previewStrip").visible, true)
    })
    h.previewCountStep(0, "hidden, active with a loopback consumer")

    // Show preview: a user's action, persisted through updateEntryInline
    h.step("preview: Show preview", function() {
      h.find(A(), "previewToggle").clicked()
    }, function() { return P().frames >= 3 && h.find(A(), "previewImage").status === Image.Ready }, 8000)
    h.wait(300)
    h.step("preview: frames, beside the settings", function() {
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
      h.eq("the strip gone", h.find(A(), "previewStrip").visible, false)
      h.eq("two columns, 920", A().layout.wide + "," + A().popup.contentWidth, "true,920")
      h.eq("the frame in the left column", h.find(A(), "previewColumn").visible && h.find(A(), "previewBlock").parent.parent === h.find(A(), "previewColumn"), true)
      h.eq("the summary under it", h.find(A(), "previewSummary").visible, true)
      h.eq("its controls under the frame", h.find(A(), "previewOverlay").visible && h.find(A(), "previewHide").visible, true)
      h.check("the controls row is below the frame, not over it", h.find(A(), "previewControlsRow").mapToItem(h.find(A(), "previewFrame"), 0, 0).y >= h.find(A(), "previewFrame").height)
      h.check("source is the expected path", String(img.source).indexOf("file://" + framePath + "?") === 0, String(img.source))
      h.eq("no frame dropped", P().droppedFrames, 0)
      h.eq("stops", h.content(A()).stops.map(function(st) { return st.kind }).join(","), "switch,info,preview,grid,fps,tabs")
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
    h.previewCountStep(1, "shown, active with a loopback consumer", 15)
    h.grabStep(function() { return A().popup }, "v1-preview-active.png")
    h.step("preview: the grid over the frame", function() {
      h.check("on", h.content(A()).toggleGrid())
      h.eq("four lines", h.find(A(), "previewGrid").count, 4)
    })
    h.grabStep(function() { return A().popup }, "v1-preview-grid.png")
    h.step("preview: the grid off; the loopback consumer leaves", function() {
      h.check("off", h.content(A()).toggleGrid())
      h.eq("no lines", h.find(A(), "previewGrid").count, 0)
      h.feed([stateLine(rev5({ state: "active", consumers: 1, loopback_consumers: 0 }))])
    }, function() { return S().record.loopbackConsumers === 0 })
    h.wait(400)
    h.step("preview: shown, it runs on (the switch holds it)", function() {
      h.eq("running", P().running, true)
      h.eq("no restart", P().starts, 1)
    })
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
    h.step("preview: the shown state is persisted (restored at the next open)", function() {
      h.eq("one write", fakeShell.calls.length, 1)
      var call = fakeShell.calls[0]
      h.eq("entry id", call.id, shellRoot.moduleName)
      h.eq("entry", JSON.stringify(call.entry), JSON.stringify({ id: shellRoot.moduleName, cliPath: shellRoot.cli, previewEnabled: true }))
      h.eq("switch on", P().switchOn, true)
      h.eq("Hide offered under the frame", h.find(A(), "previewHide").visible, true)
      h.eq("still the first start", P().starts, 1)
      // the other monitor's panel
      B().open()
    }, function() { return h.content(B()) !== null })
    h.wait(400)
    h.step("preview: two panels, one process", function() {
      h.eq("held twice", P().heldCount, 2)
      h.eq("still the first start", P().starts, 1)
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
      h.eq("no restart", P().starts, 1)
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
      h.eq("no restart", P().starts, 1)
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
    h.step("preview: reopened, the shown state persisted, it restarts", function() {
      h.eq("second start", P().starts, 2)
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
      h.eq("third start", P().starts, 3)
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
    h.step("preview: Down to Hide", function() {
      h.eq("on the on/off switch first", h.content(A()).currentStop.kind, "switch")
      h.key(Qt.Key_Down)
      h.key(Qt.Key_Down)
    }, function() { return h.content(A()).currentStop.kind === "preview" })
    h.step("preview: Hide has the cursor; Down to the grid, then the rate", function() {
      h.eq("Hide has the cursor", h.find(A(), "previewHide").hasCursor, true)
      h.eq("stops (the Effect tab of a revision-5 daemon has no control)",
           h.content(A()).stops.map(function(st) { return st.kind }).join(","), "switch,info,preview,grid,fps,tabs")
      h.key(Qt.Key_Down)
      h.eq("the grid has the cursor", h.find(A(), "gridToggle").hasCursor, true)
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
      h.eq("fourth start", P().starts, 4)
      h.key(Qt.Key_Down)
      h.eq("then the tab row", h.content(A()).currentStop.kind, "tabs")
      h.key(Qt.Key_Up)
      h.key(Qt.Key_Up)
      h.key(Qt.Key_Up)
      h.eq("back on Hide", h.content(A()).currentStop.kind, "preview")
      h.key(Qt.Key_Return)
    }, function() { return !P().running })
    h.step("preview: Enter hid it", function() {
      h.eq("fourth write", fakeShell.calls.length, 4)
      h.eq("entry", JSON.stringify(fakeShell.calls[3].entry),
           JSON.stringify({ id: shellRoot.moduleName, cliPath: shellRoot.cli, previewEnabled: false, previewFps: 15 }))
      h.eq("note", h.find(A(), "previewNote").text, "Preview off")
      h.eq("the strip back, one column", h.find(A(), "previewStrip").visible + "," + A().layout.wide, "true,false")
      h.eq("the cursor stays on the strip's button", h.content(A()).currentStop.kind, "preview")
    })
    h.previewCountStep(0, "hidden from the keyboard")

    // an unexpected exit: shown, and not respawned until the rule re-arms
    h.step("preview: shown again", function() {
      h.check("shown", h.content(A()).togglePreview())
    }, function() { return P().running && P().frames >= 1 }, 8000)
    h.step("preview: kill the preview child (SIGKILL)", function() {
      h.notes.starts = P().starts
      h.killPid(P().pid, "KILL")
    }, function() { return !P().running })
    h.wait(1500)
    h.step("preview: the exit is shown, nothing respawns", function() {
      h.eq("no restart", P().starts, h.notes.starts)
      h.eq("failed", P().failed, true)
      var t = h.find(A(), "previewPlaceholder").text
      h.check("the reason", t.indexOf("stopped by signal 9") !== -1 && t.indexOf("Reopen the panel to retry.") !== -1, t)
      h.eq("drawn as an error", h.find(A(), "previewPlaceholder").color, Commons.Color.urgent)
      h.eq("wide (the layout does not follow the error): in the frame area, with Hide",
           A().layout.wide + "," + h.find(A(), "previewBlock").visible + "," + h.find(A(), "previewStrip").visible + "," + h.find(A(), "previewHide").visible,
           "true,true,false,true")
    })
    h.previewCountStep(0, "after the crash")
    h.step("preview: the next start exits on its own", function() { h.writeFile("preview-exit", ["1"]) },
           function() { return h.writerIdle() })
    h.step("preview: close and reopen re-arms", function() {
      A().close()
      Qt.callLater(function() { A().open() })
    }, function() { return P().starts === h.notes.starts + 1 && !P().running && P().failed }, 8000)
    h.step("preview: an exit status is shown too", function() {
      var t = h.find(A(), "previewPlaceholder").text
      h.check("status 1", t.indexOf("exited with status 1") !== -1, t)
      h.removeFile("preview-exit")
    }, function() { return h.writerIdle() })

    // a choice the shell cannot store (S7: an entry over the key cap; S8: no
    // layout entry): in force for the session, said so, and not undone by a
    // widget re-injected with the same entry, nor by a widget made then (a
    // monitor plugged in: its creation emits the base widget's empty
    // settings before the bar hands it the entry). From the shown state, as
    // stored, so the choice is to hide it: an empty hand-over taken as one
    // would read as hidden, and the entry after it would show it again.
    h.step("preview: shown, stored", function() {
      if (!(P().switchOn && A().settings.previewEnabled === true)) h.content(A()).togglePreview()
    }, function() { return P().switchOn && A().settings.previewEnabled === true && h.writerIdle() })
    h.step("preview: an entry over the key cap", function() {
      h.notes.calls = fakeShell.calls.length
      h.notes.saved = JSON.parse(JSON.stringify(A().settings))
      var huge = JSON.parse(JSON.stringify(A().settings))
      for (var i = 0; i <= 300; i++) huge["junk" + i] = i
      A().settings = huge
      h.notes.switchBefore = P().switchOn
      h.content(A()).togglePreview()
    })
    h.wait(200)
    h.step("preview: not written, in force, and said so", function() {
      h.eq("no write", fakeShell.calls.length, h.notes.calls)
      h.eq("switch moved for the session", P().switchOn, !h.notes.switchBefore)
      h.eq("unsaved", P().unsaved, true)
      h.eq("message shown", h.find(A(), "previewUnsaved").visible, true)
      h.eq("message", h.find(A(), "previewUnsaved").text, "Could not save the preview setting")
      h.content(A()).togglePreview()
    })
    h.wait(200)
    h.step("preview: switched back, nothing unsaved", function() {
      h.eq("no write", fakeShell.calls.length, h.notes.calls)
      h.eq("switch as stored", P().switchOn, h.notes.switchBefore)
      h.eq("message hidden", h.find(A(), "previewUnsaved").visible, false)
      A().settings = h.notes.saved
      fakeShell.refuse = true
      h.content(A()).togglePreview()
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
      if (!P().switchOn) h.check("shown again, stored", h.content(A()).togglePreview())
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
      h.eq("a strip, no frame area", h.find(A(), "previewStrip").visible && !h.find(A(), "previewFrame").visible, true)
      h.eq("no button", h.find(A(), "previewToggle").visible, false)
      h.eq("no rate stop", h.content(A()).stops.map(function(st) { return st.kind }).indexOf("fps"), -1)
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
    var tabs = ["effect", "camera", "mic"]
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
  // min|max|step|unit|options|master|when|reason|fixed|scope ("global" for a
  // setting of the daemon's own, else empty)|surface (the group's: "mic" for
  // the microphone's, else empty)|offset|scale|description|kind (a fixed
  // row's disabled_kind, revision 28; default device).
  function stateRow(group, groupLabel, id, type, label, value, def, o) {
    var x = o || {}
    var f = function(v) { return v === undefined ? "" : String(v) }
    return [group, groupLabel, id, type, label, f(value), f(def), x.stored ? "1" : "0", f(x.min), f(x.max), f(x.step), f(x.unit),
            f(x.options), f(x.master), f(x.when), f(x.reason), x.fixed ? "1" : "", f(x.scope), f(x.surface), f(x.offset), f(x.scale), f(x.description),
            f(x.kind)].join("|")
  }
  // The MX Brio as the daemon publishes it (its starting values). `current`
  // true: as today's daemon (interface revision 28) orders its camera
  // catalogue: "Framing & focus" first (after Capture, for a camera with
  // modes; field of view, then zoom, first in it), then Image, White
  // balance, Exposure. Else as an older daemon did: Image, White balance,
  // Exposure, then "Focus & zoom" (the settings scenario's revision-7 daemon).
  function brioState(current) {
    var img = function(id, label, v, d, o) {
      var m = { min: 0, max: 255, step: 1 }
      for (var k in o) m[k] = o[k]
      return stateRow("image", "Image", "camera.image." + id, "int", label, v, d, m)
    }
    if (current === true) {
      var rows = brioState(false)
      var framing = [
        stateRow("focus", "Framing & focus", "camera.focus.field_of_view", "enum", "Field of view", "65", "90", { options: "90:90°,78:78°,65:65°" }),
        stateRow("focus", "Framing & focus", "camera.focus.zoom_absolute", "int", "Zoom", 100, 100, { min: 100, max: 500, step: 1 }),
        stateRow("focus", "Framing & focus", "camera.focus.focus_automatic_continuous", "bool", "Continuous autofocus", "true", "true"),
        stateRow("focus", "Framing & focus", "camera.focus.focus_absolute", "int", "Focus", 40, 0,
                 { min: 0, max: 255, step: 1, master: "camera.focus.focus_automatic_continuous", when: "false",
                   reason: "Turn off continuous autofocus to change this" }),
        stateRow("focus", "Framing & focus", "camera.focus.pan_absolute", "int", "Pan", 14400, 0, { min: -36000, max: 36000, step: 3600 }),
        stateRow("focus", "Framing & focus", "camera.focus.tilt_absolute", "int", "Tilt", -14400, 0, { min: -36000, max: 36000, step: 3600 }),
        stateRow("focus", "Framing & focus", "camera.focus.pan_reset", "action", "Recentre pan", "-", "-"),
        stateRow("focus", "Framing & focus", "camera.focus.tilt_reset", "action", "Recentre tilt", "-", "-"),
        stateRow("focus", "Framing & focus", "camera.focus.show_mode", "bool", "Show Mode", "true", "false")
      ]
      return framing.concat(rows.filter(function(r) { return r.indexOf("focus|") !== 0 }))
    }
    return [
      img("brightness", "Brightness", 128, 128), img("contrast", "Contrast", 128, 128), img("saturation", "Saturation", 128, 128),
      img("sharpness", "Sharpness", 128, 128), img("backlight_compensation", "Backlight compensation", 1, 1, { max: 1 }),
      img("vibrance", "Vibrance", 128, 128),
      stateRow("white_balance", "White balance", "camera.white_balance.white_balance_automatic", "bool", "Automatic white balance", "true", "true"),
      stateRow("white_balance", "White balance", "camera.white_balance.white_balance_temperature", "int", "Temperature", 2975, 5000,
               { min: 2000, max: 7500, step: 1, unit: "K", master: "camera.white_balance.white_balance_automatic", when: "false",
                 reason: "Turn off automatic white balance to change this" }),
      stateRow("white_balance", "White balance", "camera.white_balance.temperature_compensation", "int", "Temperature compensation", 57, 50,
               { min: 0, max: 100, step: 1, unit: "K", offset: 50, scale: 40, description: "Shifts the picture warmer or cooler" }),
      stateRow("exposure", "Exposure", "camera.exposure.auto_exposure", "enum", "Exposure mode", "aperture_priority", "aperture_priority",
               { options: "manual:Manual,aperture_priority:Auto" }),
      stateRow("exposure", "Exposure", "camera.exposure.exposure_compensation", "int", "Exposure compensation", 128, 128,
               { min: 0, max: 255, step: 1, offset: 128 }),
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
      stateRow("focus", "Focus & zoom", "camera.focus.field_of_view", "enum", "Field of view", "65", "90", { options: "90:90°,78:78°,65:65°" }),
      stateRow("focus", "Focus & zoom", "camera.focus.show_mode", "bool", "Show Mode", "true", "false")
    ]
  }

  function settingsScenario() {
    var A = function() { return h.widgetA }
    var S = function() { return h.widgetA.service }
    var P = function() { return h.widgetA.previewService }
    var C = function() { return h.content(A()) }
    var rev7 = function(o, revision) {
      var m = { interface_revision: revision || 7, settings_schema: 1, settings_revision: 5, loopback_consumers: 0, pipewire_consumers: 0,
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
    // Scroll the body so the item is inside the viewport, then click it.
    var clickAt = function(id, item) {
      var f = h.find(A(), "panelFlick")
      var y = item.mapToItem(f, 0, 0).y
      if (y + item.height > f.height) f.contentY += y + item.height - f.height + 8
      else if (y < 0) f.contentY += y - 8
      click(item)
    }
    // The panel's choice of open group, as a header click makes it.
    var openOnly = function(ids) { C().settingsOpen = ids.length > 0 ? ids[0] : "" }
    // The settings have no scroller of their own: the panel's body is the one.
    var noInnerScroll = function(label) {
      h.eq(label + ": no scroller in the settings", h.find(A(), "settingsFlick"), null)
      var f = h.find(A(), "panelFlick")
      h.check(label + ": the body does not scroll (" + Math.round(f.contentHeight) + " in " + Math.round(f.height) + ")",
              !f.interactive && f.contentHeight <= f.height + 0.5, f.contentHeight + " in " + f.height)
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
           "image:6,white_balance:3,exposure:6,focus:9")
      h.eq("no section title", h.find(A(), "settingsTitle"), null)
      var hl = h.find(A(), "settingsGroupLabel-image"), rl = h.find(A(), "settingLabel-camera.image.brightness")
      h.eq("a group's label is aligned with its rows' labels", Math.round(hl.mapToItem(C(), 0, 0).x), Math.round(rl.mapToItem(C(), 0, 0).x))
      var reset = h.find(A(), "settingsReset"), last = header("focus")
      h.check("Reset to defaults: a quiet link at the bottom, under the groups",
              reset.mapToItem(C(), 0, 0).y > last.mapToItem(C(), 0, 0).y && reset.bordered === false, String(reset.mapToItem(C(), 0, 0).y))
      h.check("right-aligned", Math.abs(reset.mapToItem(C(), reset.width, 0).x - last.mapToItem(C(), last.width, 0).x) < 2)
      h.eq("area shown", h.find(A(), "settingsArea").visible, true)
      h.eq("group labels", ["image", "white_balance", "exposure", "focus"].map(function(g) {
        return h.find(A(), "settingsGroupLabel-" + g).text }).join(","), "Image,White balance,Exposure,Focus & zoom")
      h.eq("Image rows", ["brightness", "contrast", "saturation", "sharpness", "backlight_compensation"].map(function(n) {
        return shown("camera.image." + n) }).join(","), "true,true,true,true,true")
      h.eq("an int of two values is a switch", !!h.find(A(), "settingSwitch-camera.image.backlight_compensation")
           && h.find(A(), "settingSwitch-camera.image.backlight_compensation").checked, true)
      h.eq("closed groups draw no rows", row("camera.white_balance.white_balance_temperature"), null)
      h.eq("labels", h.find(A(), "settingLabel-camera.image.brightness").text + "," + h.find(A(), "settingLabel-camera.image.backlight_compensation").text,
           "Brightness,Backlight compensation")
      h.eq("value", h.find(A(), "settingValue-camera.image.brightness").text, "128")
      h.eq("slider range", h.find(A(), "settingSlider-camera.image.contrast").minimum + ".." + h.find(A(), "settingSlider-camera.image.contrast").maximum, "0..255")
      h.eq("idle note", h.find(A(), "settingsNote").text, "Not in use: changes apply when an app next uses the camera.")
      h.eq("no hint", h.find(A(), "settingsHint").visible, false)
      h.eq("reset shown", h.find(A(), "settingsReset").visible, true)
      h.eq("cursor stops: the rows drawn", kinds(),
           "switch,info,tabs,preview,camera,group0,setting0,setting1,setting2,setting3,setting4,setting5,group1,group2,group3,reset")
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
      // the (i), the tab row, Show preview, the camera, Image, brightness
      for (var i = 0; i < 6; i++) h.key(Qt.Key_Down)
    }, function() { return C().currentStop && C().currentStop.kind === "setting" })
    h.step("settings: Right nudges brightness, written once after the debounce, with -- before id and value", function() {
      h.eq("cursor on brightness", JSON.stringify(C().currentStop), JSON.stringify({ kind: "setting", index: 0, id: "camera.image.brightness" }))
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
      h.eq("on the header", JSON.stringify(C().currentStop), JSON.stringify({ kind: "group", index: 0, id: "image" }))
      h.key(Qt.Key_Return)
    }, function() { return !shown("camera.image.brightness") })
    h.step("settings: closed; the stops follow; Space opens it again", function() {
      h.eq("stops", kinds(), "switch,info,tabs,preview,camera,group0,group1,group2,group3,reset")
      h.eq("cursor kept on the header", JSON.stringify(C().currentStop), JSON.stringify({ kind: "group", index: 0, id: "image" }))
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
           function() { return shown("camera.white_balance.white_balance_automatic") })
    h.wait(200)
    h.step("settings: one group open at a time: White balance closed Image", function() {
      h.eq("open", openGroups(), "white_balance")
      h.eq("Image's rows are gone", row("camera.image.brightness"), null)
      C().setCursor("group", 1)
      h.key(Qt.Key_Down)
      h.eq("a switch row draws the one highlight (not the switch)", highlights("camera.white_balance.white_balance_automatic"), "row")
    })
    h.step("settings: the manual temperature is hidden while automatic white balance is on", function() {
      h.eq("hidden (its master is on: parent_off)", row("camera.white_balance.white_balance_temperature"), null)
      h.eq("the daemon's kind", h.model.findSetting(S().record, "camera.white_balance.white_balance_temperature").kind, "parent_off")
      h.eq("no reason line under every row", h.find(A(), "settingReason-camera.white_balance.white_balance_automatic"), null)
      h.eq("the switch is on", h.find(A(), "settingSwitch-camera.white_balance.white_balance_automatic").checked, true)
      h.markLog()
      C().setCursor("setting", stopOf("camera.white_balance.white_balance_automatic"))
      h.key(Qt.Key_Return)
    }, function() { return value("camera.white_balance.white_balance_automatic") === false && !S().commandBusy }, 3000)
    h.wait(250)
    h.step("settings: automatic off reveals the temperature under it", function() {
      var t = row("camera.white_balance.white_balance_temperature")
      h.eq("shown", !!t && t.visible, true)
      h.eq("enabled", t.row.enabled, true)
      h.eq("under its master", t.row.depth, 1)
      h.check("drawn in", h.find(A(), "settingLabel-camera.white_balance.white_balance_temperature").mapToItem(C(), 0, 0).x
              > h.find(A(), "settingLabel-camera.white_balance.white_balance_automatic").mapToItem(C(), 0, 0).x + 4)
      h.eq("unit", h.find(A(), "settingValue-camera.white_balance.white_balance_temperature").text, "2975 K")
      h.markLog()
      C().setCursor("setting", stopOf("camera.white_balance.white_balance_automatic"))
      h.key(Qt.Key_Return)
    }, function() { return value("camera.white_balance.white_balance_automatic") === true && !S().commandBusy }, 3000)
    h.wait(250)
    h.step("settings: automatic on hides it again", function() {
      h.eq("hidden", row("camera.white_balance.white_balance_temperature"), null)
      C().cursorActive = false
    })

    // Exposure: the greyed exposure time, then Manual enables it
    h.step("settings: only Exposure open", function() { openOnly(["exposure"]) }, function() { return shown("camera.exposure.auto_exposure") })
    h.wait(250)
    h.step("settings: the exposure time hidden while the mode is Auto", function() {
      h.eq("hidden", row("camera.exposure.exposure_time_absolute"), null)
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
    h.step("settings: the fake's delta enabled exposure time: revealed under the mode", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.exposure.auto_exposure", "manual")]))
      var t = h.model.findSetting(S().record, "camera.exposure.exposure_time_absolute")
      h.eq("enabled", t.enabled, true)
      h.eq("shown under its master", row("camera.exposure.exposure_time_absolute").row.depth, 1)
      h.eq("unit", h.find(A(), "settingValue-camera.exposure.exposure_time_absolute").text, "1250 ×100 µs")
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
      h.eq("rows (the manual focus hidden while autofocus is on)", C().settingsView.groups[3].rows.length, 8)
      h.eq("the buttons", h.find(A(), "settingAction-camera.focus.pan_reset").text + "," + h.find(A(), "settingAction-camera.focus.tilt_reset").text,
           "Recentre pan,Recentre tilt")
      C().setCursor("setting", stopOf("camera.focus.pan_reset"))
      h.eq("an action row: the button draws the one highlight", highlights("camera.focus.pan_reset"), "button")
      C().setCursor("setting", stopOf("camera.focus.zoom_absolute"))
      h.eq("a slider row: the row draws it", highlights("camera.focus.zoom_absolute"), "row")
      var cl = h.find(A(), "settingLabel-camera.focus.focus_automatic_continuous")
      h.check("a switch row's label is never cut: its whole text fits", cl.implicitWidth <= cl.width + 0.5 && !cl.truncated,
              cl.implicitWidth + " in " + cl.width)
      C().cursorActive = false
    })
    h.grabStep(function() { return A().popup }, "s1-focus-actions.png")
    h.step("settings: the field of view is three buttons, 65 selected", function() {
      var fov = h.find(A(), "settingChoices-camera.focus.field_of_view")
      h.eq("choices", fov.options.map(function(o) { return o.label }).join(","), "90°,78°,65°")
      h.eq("selected", fov.value, "65")
      h.eq("65 lit", chip("camera.focus.field_of_view", "65°").selected, true)
      h.eq("the manual focus hidden", row("camera.focus.focus_absolute"), null)
      h.eq("pan value", h.find(A(), "settingValue-camera.focus.pan_absolute").text, "14400")
      h.eq("tilt value", h.find(A(), "settingValue-camera.focus.tilt_absolute").text, "-14400")
      h.check("Focus & zoom open: the card stays within its cap and the screen's room (" + A().popup.contentHeight + ")",
              A().popup.contentHeight <= Math.min(A().popup.availableCardHeight, 860) + 0.5, A().popup.contentHeight + " vs " + A().popup.availableCardHeight)
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
      h.eq("revealed under autofocus", row("camera.focus.focus_absolute").row.depth, 1)
      h.eq("switch off", h.find(A(), "settingSwitch-camera.focus.focus_automatic_continuous").checked, false)
      h.markLog()
      click(chip("camera.focus.field_of_view", "90°"))
    }, function() { return value("camera.focus.field_of_view") === "90" }, 3000)
    h.step("settings: the field of view chosen by a click", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.focus.field_of_view", "90")]))
    })

    // MX Brio: Show Mode is drawn by the generic renderer like any other row
    h.step("settings: the last Focus row is Show Mode, a switch, on", function() {
      var ids = C().settingsView.groups[3].rows.map(function(r) { return r.id }).slice(-1).join(",")
      h.eq("order after the field of view", ids, "camera.focus.show_mode")
      h.eq("Show Mode is a switch, on", h.find(A(), "settingSwitch-camera.focus.show_mode").checked, true)
      h.markLog()
      C().setCursor("setting", stopOf("camera.focus.show_mode"))
      h.key(Qt.Key_Return)
    }, function() { return value("camera.focus.show_mode") === false && !S().commandBusy }, 3000)
    h.step("settings: Show Mode flipped by Enter", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.focus.show_mode", "false")]))
      C().cursorActive = false
    })

    // a greyed row (enabled false with a reason) and an enum the daemon sets
    // to a value outside its options: reason shown, no input, no chip lit
    h.step("settings: the camera reports a value Show Mode and the field of view do not know", function() {
      var st = brioState().map(function(line) {
        if (line.indexOf("|camera.focus.show_mode|") >= 0)
          return stateRow("focus", "Focus & zoom", "camera.focus.show_mode", "bool", "Show Mode", "true", "false", { reason: "The camera reports a mode this version does not know", fixed: true, kind: "device" })
        if (line.indexOf("|camera.focus.field_of_view|") >= 0)
          return stateRow("focus", "Focus & zoom", "camera.focus.field_of_view", "enum", "Field of view", "turbo", "90", { options: "90:90°,78:78°,65:65°" })
        return line
      })
      h.writeFile("settings-state", st)
      h.writeFile("settings-serial", ["9"])
      h.feed([snapshotLine(rev7({}))])
    }, function() { return !!S().record.settings && S().record.settings.serial === 9 && h.writerIdle() })
    h.wait(300)
    h.step("settings: greyed row shows its reason and takes no input; unknown enum value lights nothing", function() {
      var sm = h.model.findSetting(S().record, "camera.focus.show_mode")
      h.eq("Show Mode greyed", sm.enabled, false)
      h.eq("kind device: greyed in place", sm.kind + "/" + row("camera.focus.show_mode").visible, "device/true")
      var help = h.find(A(), "settingHelp-camera.focus.show_mode")
      h.eq("its reason only under the cursor", help.visible, false)
      h.eq("a help mark says there is one", h.find(A(), "settingHelpMark-camera.focus.show_mode").visible, true)
      C().setCursor("setting", stopOf("camera.focus.show_mode"))
      h.eq("its reason on focus", help.visible + "/" + help.text, "true/The camera reports a mode this version does not know")
      h.eq("the reason's size: a caption", help.font.pixelSize, Commons.Style.font.caption)
      h.eq("only the control fades", h.find(A(), "settingSwitch-camera.focus.show_mode").opacity + "/" + h.find(A(), "settingWidget-camera.focus.show_mode").opacity, "0.45/1")
      h.eq("the label is the dim colour", String(h.find(A(), "settingLabel-camera.focus.show_mode").color), String(C().dim))
      h.eq("accessible description: unavailable, the value and the reason", row("camera.focus.show_mode").Accessible.description,
           "Unavailable. On. The camera reports a mode this version does not know")
      C().cursorActive = false
      h.eq("its switch takes no input", h.find(A(), "settingSwitch-camera.focus.show_mode").enabled, false)
      h.markLog()
      clickAt("camera.focus.show_mode", h.find(A(), "settingSwitch-camera.focus.show_mode"))
      h.eq("no chip lit", ["90°", "78°", "65°"].map(function(l) { return chip("camera.focus.field_of_view", l).selected }).join(","), "false,false,false")
      h.eq("the row's value is empty", value("camera.focus.field_of_view"), "")
    })
    h.wait(300)
    h.step("settings: the click on the greyed switch wrote nothing", function() {
      h.eq("no settings command", JSON.stringify(setArgs()), "[]")
      h.writeFile("settings-state", brioState())
      h.writeFile("settings-serial", ["10"])
      h.feed([snapshotLine(rev7({}))])
    }, function() { return !!S().record.settings && S().record.settings.serial === 10 && h.writerIdle() })
    h.wait(300)

    // the Image, White balance and Exposure rows added in 0.51: plain sliders
    h.step("settings: Vibrance, Temperature compensation and Exposure compensation are sliders with their values", function() {
      openOnly(["image"])
    }, function() { return shown("camera.image.vibrance") })
    h.step("settings: Vibrance is a slider reading 128, last of its group", function() {
      var ids = C().settingsView.groups[0].rows.map(function(r) { return r.id })
      h.eq("last in Image", ids[ids.length - 1], "camera.image.vibrance")
      h.eq("value text", h.find(A(), "settingValue-camera.image.vibrance").text, "128")
      h.eq("a slider", !!h.find(A(), "settingSlider-camera.image.vibrance"), true)
      h.markLog()
      C().setCursor("setting", stopOf("camera.image.vibrance"))
      h.key(Qt.Key_Right)
    }, function() { return setArgs().length === 1 && value("camera.image.vibrance") === 141 }, 3000)
    h.step("settings: Right on Vibrance steps by 13", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.image.vibrance", 141)]))
      C().cursorActive = false
      openOnly(["white_balance"])
    }, function() { return shown("camera.white_balance.temperature_compensation") })
    h.step("settings: Temperature compensation reads +280 K (raw 57), with its description, and steps by 5", function() {
      h.eq("value text", h.find(A(), "settingValue-camera.white_balance.temperature_compensation").text, "+280 K")
      h.eq("slider keeps the raw range", h.find(A(), "settingSlider-camera.white_balance.temperature_compensation").minimum + ".." + h.find(A(), "settingSlider-camera.white_balance.temperature_compensation").maximum, "0..100")
      var d = h.find(A(), "settingHelp-camera.white_balance.temperature_compensation")
      h.eq("description: only under the cursor", d.text + "/" + d.visible, "Shifts the picture warmer or cooler/false")
      C().setCursor("setting", stopOf("camera.white_balance.temperature_compensation"))
      h.eq("shown on focus", d.visible, true)
      C().cursorActive = false
      h.eq("plain text", d.textFormat, Text.PlainText)
      h.eq("a row without one draws no mark", h.find(A(), "settingHelpMark-camera.white_balance.white_balance_automatic").visible, false)
      h.eq("accessible description", row("camera.white_balance.temperature_compensation").Accessible.description, "+280 K. Shifts the picture warmer or cooler")
      h.markLog()
      C().setCursor("setting", stopOf("camera.white_balance.temperature_compensation"))
      h.key(Qt.Key_Right)
    }, function() { return setArgs().length === 1 && value("camera.white_balance.temperature_compensation") === 62 }, 3000)
    h.step("settings: Temperature compensation argv", function() {
      h.eq("argv: the raw value is written", JSON.stringify(setArgs()), JSON.stringify([write("camera.white_balance.temperature_compensation", 62)]))
      h.eq("value text moved on, +480 K", h.find(A(), "settingValue-camera.white_balance.temperature_compensation").text, "+480 K")
      C().cursorActive = false
      openOnly(["exposure"])
    }, function() { return shown("camera.exposure.exposure_compensation") })
    h.step("settings: Exposure compensation reads +0 (raw 128, offset only) and Left steps it down", function() {
      h.eq("value text", h.find(A(), "settingValue-camera.exposure.exposure_compensation").text, "+0")
      h.markLog()
      C().setCursor("setting", stopOf("camera.exposure.exposure_compensation"))
      h.key(Qt.Key_Left)
    }, function() { return setArgs().length === 1 && value("camera.exposure.exposure_compensation") === 115 }, 3000)
    h.step("settings: Exposure compensation argv", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.exposure.exposure_compensation", 115)]))
      h.eq("value text, a minus sign", h.find(A(), "settingValue-camera.exposure.exposure_compensation").text, "\u221213")
      C().cursorActive = false
      openOnly(["focus"])
    }, function() { return shown("camera.focus.field_of_view") })
    h.wait(250)

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
      h.eq("the body does not take a held slider", h.find(A(), "panelFlick").interactive, false)
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

    // F3: more slider writes than the queue holds, three discrete writes, all
    // behind a slow on/off ask: the queue refuses the ninth slider write (it
    // stays a draft, settingsDeferred), and every write, the refused one
    // too, runs once; no draft is left behind
    h.step("settings: twelve writes behind a slow on/off ask", function() {
      h.writeFile("delay", ["0.3"])
    }, function() { return h.writerIdle() })
    h.step("settings: queue them in one turn", function() {
      h.markLog()
      h.check("the on/off ask is taken", S().setEnabled(true))
      h.notes.wanted = [["camera.image.brightness", 100], ["camera.image.contrast", 101], ["camera.image.saturation", 102],
                        ["camera.image.sharpness", 103], ["camera.image.backlight_compensation", 0], ["camera.exposure.gain", 10],
                        ["camera.focus.zoom_absolute", 222], ["camera.focus.tilt_absolute", 7200],
                        ["camera.focus.field_of_view", "78"], ["camera.exposure.keep_framerate", true],
                        ["camera.exposure.power_line_frequency", "50hz"], ["camera.focus.pan_absolute", 7200]]
      for (var i = 0; i < h.notes.wanted.length; i++)
        h.check("taken: " + h.notes.wanted[i][0], S().commitSetting(h.notes.wanted[i][0], h.notes.wanted[i][1]))
      var q = S().pendingIntents
      var held = q.filter(function(x) { return x.verb === "setting" && !h.model.isQuickIntent(x) }).length
      h.eq("the slider writes held are at the cap", held, h.model.SETTING_QUEUE_CAP)
      h.eq("every discrete write is queued, ahead of the sliders", q.length, h.model.SETTING_QUEUE_CAP + 3)
      h.check("within the queue's bound", q.length <= h.model.INTENT_QUEUE_CAP, String(q.length))
      h.check("the ninth slider write is not queued", !h.model.queuedSetting(q, "camera.focus.pan_absolute"))
      h.check("its draft waits: deferred", S().settingsDeferred)
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
    h.step("settings: put pan back for the steps after", function() {
      h.markLog()
      h.check("taken", S().commitSetting("camera.focus.pan_absolute", 14400))
    }, function() { return value("camera.focus.pan_absolute") === 14400 && !S().commandBusy && JSON.stringify(S().settingDrafts) === "{}" }, 5000)

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

    // M5: on a screen too short for the open group only the body scrolls
    // (one scroller: the header and the tab row stay), and Reset at its
    // bottom is reached by scrolling
    h.step("settings: a short screen: the body scrolls, Reset at its end", function() {
      openOnly(["focus"])
      A().popup.availableCardHeight = 420
    }, function() { return h.find(A(), "panelFlick").interactive })
    h.wait(250)
    h.step("settings: one scroller, the header and the tabs pinned", function() {
      var f = h.find(A(), "panelFlick")
      h.check("it scrolls", f.contentHeight > f.height + 0.5, f.contentHeight + " in " + f.height)
      h.eq("no scroller in the settings", h.find(A(), "settingsFlick"), null)
      h.eq("the tab row is pinned", C().inBody(h.find(A(), "tabRow")), false)
      h.eq("Reset is in the body", C().inBody(h.find(A(), "settingsReset")), true)
      // a key moves the cursor there (hovering never scrolls)
      C().setCursor("reset", -1)
      C().scrollCursorIntoView()
    })
    h.wait(250)
    h.step("settings: the cursor on Reset scrolled it into view", function() {
      var f = h.find(A(), "panelFlick")
      var b = h.find(A(), "settingsReset")
      var top = b.mapToItem(f, 0, 0).y
      h.check("scrolled", f.contentY > 0, f.contentY)
      h.check("Reset inside the viewport", top >= -0.5 && top + b.height <= f.height + 0.5, top + " / " + f.height)
      C().cursorActive = false
    })
    h.grabStep(function() { return A().popup }, "s1-scroll-fallback.png")
    h.step("settings: the screen's room again", function() {
      A().popup.availableCardHeight = shellRoot.card1080
      h.find(A(), "panelFlick").contentY = 0
    })
    h.wait(250)

    // reset to defaults, by the button
    h.step("settings: Reset to defaults", function() {
      h.markLog()
      click(h.find(A(), "settingsReset"))
    }, function() { return value("camera.image.brightness") === 128 && value("camera.focus.field_of_view") === "90"
                           && value("camera.exposure.auto_exposure") === "aperture_priority" }, 3000)
    h.step("settings: reset ran and came back as deltas", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([["settings", "reset", "--camera=" + brioId]]))
      h.eq("nothing stored", S().record.settings.groups.some(function(g) { return g.rows.some(function(r) { return r.stored }) }), false)
      h.eq("exposure time disabled again (hidden)", h.model.findSetting(S().record, "camera.exposure.exposure_time_absolute").enabled, false)
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
      keys.mouseMove(h.find(A(), "hero"), 1, 1)
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

    // revision 12: the Capture group, first, with the camera's capture mode:
    // "auto", the modes it offers and, at most, one it no longer does (16)
    function captureOptions() {
      var modes = ["3840x2160@30", "3840x2160@24", "2560x1440@30", "1920x1200@30", "1920x1080@60", "1920x1080@30", "1920x1080@24",
                   "1600x900@30", "1280x960@30", "1280x720@60", "1280x720@30", "1024x576@30", "960x540@30", "640x360@30"]
      var opts = ["auto:Automatic"]
      for (var i = 0; i < modes.length; i++) {
        var wh = modes[i].split("@")
        opts.push(modes[i] + ":" + wh[0] + " \u00b7 " + wh[1] + " fps")
      }
      opts.push("4096x2160@30:4096x2160 \u00b7 30 fps (gone)")
      return opts.join(",")
    }
    h.step("settings: a revision-12 camera with the Capture group first", function() {
      h.writeFile("settings-state", [stateRow("capture", "Capture", "camera.capture.mode", "enum", "Capture mode", "3840x2160@30", "auto",
                                              { options: captureOptions(), stored: true })].concat(brioState()))
      h.feed([snapshotLine(rev7({ interface_revision: 12 }))])
    }, function() { return !!S().record.settings && S().record.settings.groups.length === 5 && S().record.settings.groups[0].id === "capture" && h.writerIdle() })
    h.wait(250)
    h.step("settings: the capture mode is a dropdown of 16, labelled with a dot", function() {
      var r = S().record.settings.groups[0].rows[0]
      h.eq("the row", r.id + ":" + h.model.settingWidget(r) + ":" + r.options.length, "camera.capture.mode:dropdown:16")
      h.eq("the first group, the first option", S().record.settings.groups[0].label + "/" + r.options[0].value + "/" + r.options[0].label, "Capture/auto/Automatic")
      h.eq("a mode's label", r.options[1].value + "/" + r.options[1].label, "3840x2160@30/3840x2160 \u00b7 30 fps")
      h.eq("the mode that is gone keeps its words", r.options[15].label, "4096x2160 \u00b7 30 fps (gone)")
      openOnly(["capture"])
    }, function() { return !!h.find(A(), "settingDropdown-camera.capture.mode") })
    h.wait(250)
    h.step("settings: the capture mode's box", function() {
      var dd = h.find(A(), "settingDropdown-camera.capture.mode")
      h.eq("its value", dd.value + "/" + dd.currentLabel(), "3840x2160@30/3840x2160 \u00b7 30 fps")
      h.eq("the row's label", h.find(A(), "settingLabel-camera.capture.mode").text, "Capture mode")
      // the widest label (a mode that is gone) fits the box and the list rows, so
      // "(gone)" is never cut off
      var probe = Qt.createQmlObject('import QtQuick; TextMetrics { }', h, "labelProbe")
      probe.font.family = Commons.Style.font.family
      probe.font.pixelSize = Commons.Style.font.body
      var widest = 0
      for (var i = 0; i < dd.options.length; i++) { probe.text = dd.options[i].label; widest = Math.max(widest, probe.advanceWidth) }
      probe.destroy()
      var room = dd.width - 2 * Commons.Style.spacing.controlPaddingX - 8 // the list's border and padding
      h.check("the widest label fits a list row (" + Math.round(widest) + " in " + Math.round(room) + ")", widest <= room, widest + " in " + room)
      var lbl = h.find(A(), "settingLabel-camera.capture.mode")
      h.check("the label's text is not elided by the box", lbl.implicitWidth <= lbl.width + 0.5, lbl.implicitWidth + " in " + lbl.width)
      h.fits(A(), "Camera tab with the Capture group open")
      h.markLog()
      C().setCursor("setting", stopOf("camera.capture.mode"))
      keys.mouseMove(h.find(A(), "hero"), 1, 1)
      h.key(Qt.Key_Return)
    }, function() { return h.find(A(), "settingDropdown-camera.capture.mode").popupOpen })
    h.step("settings: the capture list is open; Down, Enter", function() {
      h.eq("nothing written by opening it", setArgs().length, 0)
      h.key(Qt.Key_Down)
      h.key(Qt.Key_Return)
    }, function() { return value("camera.capture.mode") === "3840x2160@24" && !h.find(A(), "settingDropdown-camera.capture.mode").popupOpen }, 3000)
    h.step("settings: a capture mode is written by settings set", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([write("camera.capture.mode", "3840x2160@24")]))
      h.eq("the box shows the daemon's word", h.find(A(), "settingDropdown-camera.capture.mode").value, "3840x2160@24")
      h.check("the keyboard is the panel's again", h.catcher(A()).activeFocus)
      h.writeFile("settings-state", brioState())
      h.feed([snapshotLine(rev7({}))])
    }, function() { return !S().commandBusy && S().record.settings.groups[0].id === "image" && h.writerIdle() })

    // global settings (revision 9): the Effect tab draws the background
    // effect's choices from its mode setting, the others generically below
    // them; the Camera tab never does
    var globalRows = function(mode) {
      var g = function(id, type, label, v, d, o) {
        var x = { scope: "global" }
        for (var k in o) x[k] = o[k]
        return stateRow(id.split(".")[1], id.split(".")[1] === "video" ? "Video" : "Background effect", id, type, label, v, d, x)
      }
      return [
        g("effect.background.mode", "enum", "Effect", mode, "none", { options: "none:Off,blur:Blur,replace:Replace" }),
        g("effect.background.blur_strength", "int", "Blur strength", 50, 50,
          { min: 0, max: 100, step: 1, unit: "%", master: "effect.background.mode", when: "blur", reason: "Choose Blur to change this" }),
        g("effect.video.denoise", "bool", "Noise removal", "false", "false", {})
      ]
    }
    var gwrite = function(id, v) { return ["settings", "set", "--", id, String(v)] }
    h.step("global settings: a revision-9 daemon publishes them after the camera's", function() {
      h.writeFile("settings-state", brioState().concat(globalRows("none")))
      h.feed([snapshotLine(rev7({ interface_revision: 9, effect: "none", blur_strength: 0.5, denoise: false }))])
    }, function() { return !!S().record.settings && S().record.settings.groups.length === 6 && h.writerIdle() })
    h.step("global settings: the Effect tab", function() { h.tab(A(), "effect") }, function() { return h.find(A(), "effectSettingsArea").visible })
    h.wait(300)
    h.step("global settings: generic rows, no dedicated strength or noise removal", function() {
      h.eq("the camera's view has no global group", C().settingsView.groups.map(function(g) { return g.id }).join(","), "image,white_balance,exposure,focus")
      h.eq("the Effect view's groups (the strength hidden while the effect is off)", C().effectSettings.groups.map(function(g) { return g.id }).join(","), "video")
      h.eq("no row for the effect choice", row("effect.background.mode"), null)
      h.eq("the strength hidden", row("effect.background.blur_strength"), null)
      h.eq("the noise removal switch", !!h.find(A(), "settingSwitch-effect.video.denoise"), true)
      h.eq("the image row only under Replace", h.find(A(), "backgroundLine").visible, false)
      h.eq("the choices are the schema's options", [0, 1, 2].map(function(i) { return h.find(A(), "effectChoice-" + i).text }).join(","), "Off,Blur,Replace")
      h.eq("the current one selected", h.find(A(), "effectChoice-0").selected, true)
      h.eq("no fourth choice", h.find(A(), "effectChoice-3"), null)
      h.eq("no hint", h.find(A(), "effectHint").visible, false)
      h.eq("a group that is one setting draws no heading", h.find(A(), "effect-settingsGroupHeader-video").visible, false)
      h.eq("no title, no reset", h.find(A(), "effect-settingsTitle") === null && !h.find(A(), "effect-settingsReset").visible, true)
      h.eq("stops", kinds(), "switch,info,tabs,preview,effect,setting0")
      h.fits(A(), "Effect tab with the generic rows")
    })
    h.grabStep(function() { return A().popup }, "e1-effect-generic.png")
    h.step("global settings: a disabled row refuses a write", function() {
      h.markLog()
      h.eq("no stop for a hidden row", stopOf("effect.background.blur_strength"), -1)
      h.check("refused", !S().moveSetting("effect.background.blur_strength", 70))
      h.eq("no draft", JSON.stringify(S().settingDrafts), "{}")
    })
    h.wait(300)
    h.step("global settings: Enter on Blur writes the mode as a setting", function() {
      h.markLog()
      C().setCursor("effect", -1)
      h.eq("lands on the current choice", C().effectCursor, 0)
      h.eq("the chip has the cursor", h.find(A(), "effectChoice-0").hasCursor, true)
      h.key(Qt.Key_Right)
      h.eq("Right: Blur", C().effectCursor, 1)
      h.key(Qt.Key_Return)
    }, function() { return setArgs().length >= 1 && value("effect.background.mode") === "blur" && !S().commandBusy }, 3000)
    h.step("global settings: Blur chosen; the strength opens under it", function()  {
      h.eq("argv: the setting, no camera", JSON.stringify(setArgs()), JSON.stringify([gwrite("effect.background.mode", "blur")]))
      h.eq("Blur selected", h.find(A(), "effectChoice-1").selected, true)
      h.check("tooltip names it", A().iconButton.tooltipText.indexOf("background: Blur") !== -1, A().iconButton.tooltipText)
      h.markLog()
      h.key(Qt.Key_Return)
      h.eq("Enter on the current choice runs nothing", S().commandBusy, false)
    }, function() { return h.model.findSetting(S().record, "effect.background.blur_strength").enabled === true && h.writerIdle() })
    h.wait(250)
    h.step("global settings: the strength under the choice", function() {
      h.eq("shown", shown("effect.background.blur_strength"), true)
      h.eq("in the lead group, under the choice", C().effectSettings.groups[0].lead + "/" + row("effect.background.blur_strength").row.depth, "true/1")
      h.check("between the choices and the effects",
              row("effect.background.blur_strength").mapToItem(C(), 0, 0).y > h.find(A(), "effectChoices").mapToItem(C(), 0, 0).y
              && row("effect.background.blur_strength").mapToItem(C(), 0, 0).y < row("effect.video.denoise").mapToItem(C(), 0, 0).y)
    })
    h.grabStep(function() { return A().popup }, "e2-effect-blur.png")
    h.step("global settings: Right moves the slider; the write names no camera", function() {
      h.markLog()
      C().setCursor("setting", stopOf("effect.background.blur_strength"))
      h.key(Qt.Key_Right)
    }, function() { return setArgs().length >= 1 && value("effect.background.blur_strength") === 55 }, 3000)
    h.step("global settings: the write", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([gwrite("effect.background.blur_strength", 55)]))
      h.eq("shown", h.find(A(), "settingValue-effect.background.blur_strength").text, "55 %")
      h.markLog()
      C().setCursor("setting", stopOf("effect.video.denoise"))
      h.key(Qt.Key_Return)
    }, function() { return setArgs().length >= 1 && value("effect.video.denoise") === true }, 3000)
    h.step("global settings: the switch", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([gwrite("effect.video.denoise", true)]))
      h.eq("the switch follows the daemon", h.find(A(), "settingSwitch-effect.video.denoise").checked, true)
      h.eq("no error", S().commandError, "")
    })
    // auto-frame's zoom (stage_values): a read-only line under the group's
    // rows, only while the stage is on, the camera active and a value reported
    var autoFrameRows = function(on) {
      return [
        stateRow("auto_frame", "Auto-frame", "effect.auto_frame.enabled", "bool", "Auto-frame", on ? "true" : "false", "false", { scope: "global" }),
        stateRow("auto_frame", "Auto-frame", "effect.auto_frame.framing", "enum", "Framing", "loose", "loose",
                 { scope: "global", options: "loose:Loose,tight:Tight" })
      ]
    }
    var zoomLine = function() { return h.find(A(), "effect-settingsGroupLive-auto_frame") }
    var zoomState = function(o) {
      var m = { effect: "none", blur_strength: 0.5, denoise: false }
      for (var k in o) m[k] = o[k]
      return rev7(m, 9)
    }
    var zoomZ = function(v) { return [{ stage: "auto-frame", name: "zoom", value: v }] }
    h.step("zoom readout: an active camera reports a zoom", function() {
      h.writeFile("settings-state", brioState().concat(globalRows("none"), autoFrameRows(true)))
      h.feed([snapshotLine(zoomState({ state: "active", consumers: 1, stage_values: zoomZ(1.24) }))])
    }, function() { return !!S().record.settings && S().record.settings.groups.length === 7 && h.writerIdle() && !!zoomLine() })
    h.wait(300)
    h.step("zoom readout: shown under the group's rows", function() {
      h.eq("the group is drawn", C().effectSettings.groups.map(function(g) { return g.id }).join(","), "video,auto_frame")
      h.eq("text", zoomLine().text, "Zoom 1.24\u00d7")
      h.eq("visible", zoomLine().visible, true)
      h.eq("the Camera tab's groups carry none", C().settingsView.groups.map(function(g) { return g.live }).join(""), "")
      h.fits(A(), "Effect tab with the zoom readout")
    })
    h.grabStep(function() { return A().popup }, "e2b-effect-zoom.png")
    h.step("zoom readout: it follows the daemon's next state line", function() {
      h.feed([stateLine(zoomState({ state: "active", consumers: 1, stage_values: zoomZ(1.6) }))])
    }, function() { return zoomLine() && zoomLine().text === "Zoom 1.60\u00d7" }, 3000)
    h.step("zoom readout: a state line without the key leaves it", function() {
      h.feed([stateLine(zoomState({ state: "active", consumers: 2 }))])
    }, function() { return S().record.consumers === 2 })
    h.step("zoom readout: still shown", function() {
      h.eq("text", zoomLine().text, "Zoom 1.60\u00d7")
    })
    h.step("zoom readout: the camera goes idle, nothing shown", function() {
      h.feed([stateLine(zoomState({ state: "idle", consumers: 0 }))])
    }, function() { return S().record.state === "idle" })
    h.step("zoom readout: gone while idle", function() {
      h.eq("hidden", zoomLine().visible, false)
      h.eq("empty", zoomLine().text, "")
    })
    h.step("zoom readout: active again, none reported yet (an empty list), nothing shown", function() {
      h.feed([stateLine(zoomState({ state: "active", consumers: 1, stage_values: [] }))])
    }, function() { return S().record.state === "active" })
    h.step("zoom readout: hidden", function() { h.eq("hidden", zoomLine().visible, false) })
    h.step("zoom readout: an older daemon's snapshot has no key, nothing shown", function() {
      h.feed([snapshotLine(zoomState({ state: "active", consumers: 1 }))])
    }, function() { return !!S().record.settings && S().record.settings.groups.length === 7 && h.writerIdle() })
    h.wait(200)
    h.step("zoom readout: hidden without the key", function() { h.eq("hidden", zoomLine().visible, false) })
    h.step("zoom readout: auto-frame switched off, a value is not shown", function() {
      h.writeFile("settings-state", brioState().concat(globalRows("none"), autoFrameRows(false)))
      h.feed([snapshotLine(zoomState({ state: "active", consumers: 1, stage_values: zoomZ(1.3) }))])
    }, function() { return !!S().record.settings && h.model.findSetting(S().record, "effect.auto_frame.enabled").value === false && h.writerIdle() })
    h.wait(200)
    h.step("zoom readout: hidden while off", function() { h.eq("hidden", zoomLine().visible, false) })
    h.step("global settings: no global setting published (no module): no choices, a hint", function() {
      h.writeFile("settings-state", brioState())
      h.feed([snapshotLine(rev7({ interface_revision: 9, effect: "blur", blur_strength: 0.5, denoise: true }))])
    }, function() { return S().record.settings.groups.length === 4 && h.writerIdle() })
    h.wait(300)
    h.step("global settings: nothing to offer", function() {
      h.eq("no generic section", h.find(A(), "effectSettingsArea").visible, false)
      h.eq("no choices", h.find(A(), "effectChoices").visible, false)
      h.eq("the hint", h.find(A(), "effectHint").text, h.model.NO_BACKGROUND_TEXT)
      h.eq("stops", kinds(), "switch,info,tabs,preview")
    })
    h.grabStep(function() { return A().popup }, "e3-effect-no-module.png")
    h.step("global settings: back to the Camera tab", function() { h.tab(A(), "camera") }, function() { return h.find(A(), "settingsArea").visible })
    h.wait(300)

    // the microphone (revision 13): the Mic tab draws the groups of surface
    // "mic" generically, below the microphone's own switch and state; the
    // bar shows a glyph while apps record from it
    var micDevice = "alsa_input.usb-C-Media-00.mono"
    // a real node name, well past 32 characters (the cap was raised to 128)
    var micLongDevice = "alsa_input.usb-K66_K66_20190805V001-00.analog-stereo"
    var micRows = function() {
      var m = function(group, groupLabel, id, type, label, v, d, o) {
        var x = { scope: "global", surface: "mic" }
        for (var k in o) x[k] = o[k]
        return stateRow(group, groupLabel, id, type, label, v, d, x)
      }
      var voiceOff = { master: "mic.voice.enabled", when: "false", reason: "Studio voice already removes noise and echo" }
      return [
        m("input", "Microphone", "mic.input.enabled", "bool", "Noise and echo processing", "true", "true", {}),
        m("input", "Microphone", "mic.input.device", "enum", "Input device", "default", "default",
          { options: "default:System default," + micDevice + ":USB PnP Sound Device," + micLongDevice + ":K66" }),
        m("input", "Microphone", "mic.input.hardware_gain_db", "int", "Hardware gain", 6, 6, { min: -12, max: 36, step: 1, unit: "dB" }),
        // revision 28: one switch, on while the Omarchy Broadcast Mic is
        // the default made here (the two actions are no longer published)
        m("input", "Microphone", "mic.input.use_as_default", "bool", "Use as default microphone", "false", "false", {}),
        m("noise", "Noise removal", "mic.noise.enabled", "bool", "Noise removal", "true", "false", voiceOff),
        // as the daemon's audio module publishes it: the strength follows
        // noise removal (enabled_when mic.noise.enabled eq true)
        m("noise", "Noise removal", "mic.noise.strength", "int", "Strength", 100, 100,
          { min: 0, max: 100, step: 1, unit: "%", master: "mic.noise.enabled", when: "true", reason: "Turn on noise removal to change this" }),
        m("voice", "Studio voice", "mic.voice.enabled", "bool", "Studio voice (adds noticeable delay)", "false", "false", {}),
        m("voice", "Studio voice", "mic.voice.profile", "enum", "Mic profile", "passthrough", "passthrough",
          { options: "passthrough:None,bright:Bright,warm:Warm", master: "mic.voice.enabled", when: "true", reason: "Turn on studio voice to change this" })
      ]
    }
    var micState = function(o) {
      var m = { state: "active", consumers: 1, provider: "mic-denoise: Example Denoiser (GPU)", latency_ms: 20, error: "" }
      for (var k in o) m[k] = o[k]
      return m
    }
    var micLine = function(o) {
      var m = micState(o)
      m.v = 1
      m.type = "mic"
      return JSON.stringify(m)
    }
    var rev13 = function(o) {
      var m = rev7({ interface_revision: 13, effect: "none", blur_strength: 0.5, denoise: false, mic: micState({}) })
      for (var k in o) m[k] = o[k]
      return m
    }
    var micArgs = function() { return h.newLogArgs().filter(function(a) { return a[0] === "mic" }) }
    h.step("mic: a revision-13 daemon publishes the microphone's groups after the others", function() {
      h.writeFile("settings-state", brioState().concat(micRows()))
      h.feed([snapshotLine(rev13({}))])
    }, function() { return !!S().record.settings && S().record.settings.groups.length === 7 && !!S().record.mic && h.writerIdle() })
    h.step("mic: the Mic tab", function() { h.tab(A(), "mic") }, function() { return h.find(A(), "micSettingsArea").visible })
    h.wait(300)
    h.step("mic: the switch, the state, then the generic rows", function() {
      h.eq("the Mic tab shown", h.find(A(), "micTab").visible, true)
      h.eq("the Camera tab hidden", h.find(A(), "cameraTab").visible, false)
      h.eq("the Mic view's groups", C().micSettings.groups.map(function(g) { return g.id }).join(","), "input,noise,voice")
      h.eq("none in the Effect tab's", C().effectSettings.groups.length, 0)
      h.eq("none in the Camera tab's", C().settingsView.groups.map(function(g) { return g.id }).join(","), "image,white_balance,exposure,focus")
      h.eq("no hint", h.find(A(), "micHint").visible, false)
      h.eq("the switch is on", h.find(A(), "micSwitch").checked, true)
      h.eq("its state in one line", h.find(A(), "micState").text, "Processing, 1 app recording, adds 20 ms")
      h.eq("no explainer while on", h.find(A(), "micExplainer").visible, false)
      h.eq("no error", h.find(A(), "micError").visible, false)
      h.eq("processing switch", !!h.find(A(), "settingSwitch-mic.input.enabled"), true)
      h.eq("the device is a dropdown of node names", !!h.find(A(), "settingDropdown-mic.input.device"), true)
      h.eq("the device's choices", h.model.findSetting(S().record, "mic.input.device").options.map(function(o) { return o.value }).join(","),
           "default," + micDevice + "," + micLongDevice)
      h.eq("Use as default microphone: one switch, drawn generically", h.find(A(), "settingLabel-mic.input.use_as_default").text
           + "/" + !!h.find(A(), "settingSwitch-mic.input.use_as_default"), "Use as default microphone/true")
      h.eq("no default-microphone buttons", h.find(A(), "settingAction-mic.input.make_default"), null)
      h.eq("studio voice says what it costs", h.find(A(), "settingLabel-mic.voice.enabled").text, "Studio voice (adds noticeable delay)")
      h.eq("the profile hidden while studio voice is off", row("mic.voice.profile"), null)
      h.eq("no modules note", h.find(A(), "mic-settingsNote").visible, false)
      h.eq("stops", kinds(), "switch,info,tabs,mic-host,setting0,setting1,setting2,setting3,setting4,setting5,setting6")
      h.eq("no preview on the Mic tab (narrow)", h.find(A(), "previewStrip").visible || h.find(A(), "previewBlock").visible, false)
      h.eq("the bar's mic glyph", A().micButton.visible + "/" + A().micButton.text, "true/" + String.fromCodePoint(0xF036C))
      h.eq("its tooltip", A().micButton.tooltipText, "Omarchy Broadcast Mic: processing · 1 app recording")
      h.check("beside the camera's", A().micButton.x >= A().iconButton.x + A().iconButton.width - 0.5, A().micButton.x)
      h.fits(A(), "Mic tab")
    })
    h.grabStep(function() { return A().popup }, "m1-mic.png")
    // revision 25: the hardware gain, a dB slider over the device's own range
    h.step("mic: the hardware gain sits between the device and the default button, a slider reading 6 dB", function() {
      var ids = C().micSettings.groups[0].rows.map(function(r) { return r.id }).join(",")
      h.eq("order", ids, "mic.input.enabled,mic.input.device,mic.input.hardware_gain_db,mic.input.use_as_default")
      var g = h.model.findSetting(S().record, "mic.input.hardware_gain_db")
      h.eq("range kept, negative min", g.min + "," + g.max + "," + g.unit, "-12,36,dB")
      h.eq("a slider", !!h.find(A(), "settingSlider-mic.input.hardware_gain_db"), true)
      h.eq("value text", h.find(A(), "settingValue-mic.input.hardware_gain_db").text, "6 dB")
      h.markLog()
      C().setCursor("setting", stopOf("mic.input.hardware_gain_db"))
      h.eq("the cursor is on the slider row", highlights("mic.input.hardware_gain_db"), "row")
      h.key(Qt.Key_Left)
    }, function() { return setArgs().length === 1 && value("mic.input.hardware_gain_db") === 4 && !S().commandBusy }, 3000)
    h.step("mic: Left stepped by 2 dB and wrote as a global setting", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([gwrite("mic.input.hardware_gain_db", 4)]))
      h.eq("value text", h.find(A(), "settingValue-mic.input.hardware_gain_db").text, "4 dB")
      h.markLog()
      h.check("a negative gain, written after --", S().commitSetting("mic.input.hardware_gain_db", -3))
    }, function() { return setArgs().length === 1 && value("mic.input.hardware_gain_db") === -3 && !S().commandBusy }, 3000)
    h.step("mic: a negative gain reads -3 dB", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([gwrite("mic.input.hardware_gain_db", -3)]))
      h.eq("value text", h.find(A(), "settingValue-mic.input.hardware_gain_db").text, "-3 dB")
      h.markLog()
      h.check("near the bottom", S().commitSetting("mic.input.hardware_gain_db", -11))
    }, function() { return setArgs().length === 1 && value("mic.input.hardware_gain_db") === -11 && !S().commandBusy }, 3000)
    h.step("mic: Left near the bottom stays in range", function() {
      h.markLog()
      C().setCursor("setting", stopOf("mic.input.hardware_gain_db"))
      h.key(Qt.Key_Left)
    }, function() { return setArgs().length === 1 && value("mic.input.hardware_gain_db") === -12 && !S().commandBusy }, 3000)
    h.step("mic: clamped at -12", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([gwrite("mic.input.hardware_gain_db", -12)]))
      h.eq("value text", h.find(A(), "settingValue-mic.input.hardware_gain_db").text, "-12 dB")
      h.markLog()
      h.key(Qt.Key_Right)
    }, function() { return setArgs().length === 1 && value("mic.input.hardware_gain_db") === -10 && !S().commandBusy }, 3000)
    h.step("mic: Right steps up from the negative end", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([gwrite("mic.input.hardware_gain_db", -10)]))
      C().cursorActive = false
    })
    h.step("mic: studio voice on, by the keyboard; noise removal greys with the daemon's reason", function() {
      h.markLog()
      C().setCursor("setting", stopOf("mic.voice.enabled"))
      h.key(Qt.Key_Return)
    }, function() { return setArgs().length >= 1 && value("mic.voice.enabled") === true && !S().commandBusy }, 3000)
    h.step("mic: the write names no camera; the conflict hides noise removal", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([gwrite("mic.voice.enabled", true)]))
      h.eq("noise removal disabled", h.model.findSetting(S().record, "mic.noise.enabled").enabled, false)
      h.eq("and hidden (its rule fails)", row("mic.noise.enabled"), null)
      h.eq("the profile open, under studio voice", h.model.findSetting(S().record, "mic.voice.profile").enabled + "/" + row("mic.voice.profile").row.depth, "true/1")
      h.markLog()
      h.check("the device, written as a node name", S().commitSetting("mic.input.device", micDevice))
    }, function() { return setArgs().length >= 1 && value("mic.input.device") === micDevice && !S().commandBusy }, 3000)
    h.grabStep(function() { return A().popup }, "m2-mic-studio-voice.png")
    h.step("mic: the device write; Use as default microphone", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([gwrite("mic.input.device", micDevice)]))
      h.eq("the box shows the daemon's word", h.find(A(), "settingDropdown-mic.input.device").value, micDevice)
      h.markLog()
      clickAt("mic.input.use_as_default", row("mic.input.use_as_default"))
    }, function() { return setArgs().length >= 1 && value("mic.input.use_as_default") === true && !S().commandBusy }, 3000)
    h.step("mic: the switch's argv; the microphone off by the keyboard", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([gwrite("mic.input.use_as_default", true)]))
      h.eq("on", h.find(A(), "settingSwitch-mic.input.use_as_default").checked, true)
      h.markLog()
      C().setCursor("mic-host", -1)
      h.eq("the switch has the cursor", h.find(A(), "micSwitch").hasCursor, true)
      h.key(Qt.Key_Return)
    }, function() { return micArgs().length >= 1 && !!S().record.mic && S().record.mic.state === "off" && !S().commandBusy }, 3000)
    h.step("mic: off", function() {
      h.eq("argv", JSON.stringify(micArgs()), JSON.stringify([["mic", "off"]]))
      h.eq("the switch follows the daemon", h.find(A(), "micSwitch").checked, false)
      h.eq("off: what it is, one sentence", h.find(A(), "micExplainer").text, h.model.MIC_EXPLAINER_TEXT)
      h.eq("and nothing else", h.find(A(), "micState").visible || h.find(A(), "micSettingsArea").visible, false)
      h.eq("stops: only its switch", kinds(), "switch,info,tabs,mic-host")
      h.eq("no bar glyph", A().micButton.visible, false)
      h.eq("the camera's icon takes the widget back", A().iconButton.width, A().width)
      h.eq("the camera's switch never waited", S().toggleBusy, false)
      h.markLog()
      h.check("on again", C().toggleMic())
    }, function() { return micArgs().length >= 1 && S().record.mic.state === "passthrough" && !S().commandBusy }, 3000)
    h.step("mic: on, not processed; an app starts recording", function() {
      h.eq("argv", JSON.stringify(micArgs()), JSON.stringify([["mic", "on"]]))
      h.eq("the switch", h.find(A(), "micSwitch").checked, true)
      h.eq("state line", h.find(A(), "micState").text, "On, not processed, no app recording")
      h.eq("nobody records: no glyph", A().micButton.visible, false)
      h.feed([micLine({ consumers: 2, state: "error", error: "The audio worker stopped; the microphone passes through" })])
    }, function() { return S().record.mic.consumers === 2 })
    h.wait(200)
    h.step("mic: the glyph while apps record, the error in the tab", function() {
      h.eq("the glyph", A().micButton.visible, true)
      h.eq("urgent on an error", A().micButton.activeColor + "", A().urgentColor + "")
      h.eq("tooltip", A().micButton.tooltipText,
           "Omarchy Broadcast Mic: error · 2 apps recording · error: The audio worker stopped; the microphone passes through")
      h.eq("the error shown", h.find(A(), "micError").text, "The audio worker stopped; the microphone passes through")
      h.markLog()
      A().micButton.triggerPress(Qt.MiddleButton)
      h.eq("its middle click runs nothing", h.newLogArgs().length, 0)
      h.eq("and leaves the panel open", A().opened, true)
      A().micButton.triggerPress(Qt.LeftButton)
      h.eq("its left click closes the panel", A().opened, false)
      A().open()
    }, function() { return A().opened && h.content(A()) !== null })
    h.grabStep(function() { return A().popup }, "m3-mic-error.png")
    h.step("mic: error shows no delay and no module; a long node name is written as any other", function() {
      h.eq("no added delay in an error", h.find(A(), "micState").text, "Error, 2 apps recording")
      h.markLog()
      h.check("the long device, written as a node name", S().commitSetting("mic.input.device", micLongDevice))
    }, function() { return setArgs().length >= 1 && value("mic.input.device") === micLongDevice && !S().commandBusy }, 3000)
    h.step("mic: the long device's argv", function() {
      h.eq("argv", JSON.stringify(setArgs()), JSON.stringify([gwrite("mic.input.device", micLongDevice)]))
      h.eq("the box shows it", h.find(A(), "settingDropdown-mic.input.device").value, micLongDevice)
      h.tab(A(), "camera")
    }, function() { return h.find(A(), "cameraTab").visible })
    var storedBefore = ""
    h.step("mic: a left click on the glyph opens the panel on the Mic tab, for this opening only", function() {
      storedBefore = A().storedTab
      A().close()
      A().micButton.triggerPress(Qt.LeftButton)
    }, function() { return A().opened && h.content(A()) !== null && h.find(A(), "micTab").visible })
    h.step("mic: the stored tab is untouched; a second click closes", function() {
      h.eq("the request", A().requestedTab, "mic")
      h.eq("the stored tab", A().storedTab, storedBefore)
      A().micButton.triggerPress(Qt.LeftButton)
      h.eq("closed", A().opened, false)
      h.eq("the request is gone", A().requestedTab, "")
      A().open()
    }, function() { return A().opened && h.content(A()) !== null && h.find(A(), "cameraTab").visible })
    h.step("mic: back to the Mic tab", function() { h.tab(A(), "mic") }, function() { return h.find(A(), "micSettingsArea").visible })
    h.step("mic: no audio module installed: only the daemon's group, and the note", function() {
      h.writeFile("settings-state", brioState().concat(micRows().slice(0, 4)))
      h.feed([snapshotLine(rev13({ mic: micState({ state: "passthrough", consumers: 0, provider: "", latency_ms: 0 }) }))])
    }, function() { return !!S().record.settings && S().record.settings.groups.length === 5 && h.writerIdle() })
    h.wait(300)
    h.step("mic: the note", function() {
      h.eq("the note", h.find(A(), "mic-settingsNote").text, h.model.MIC_NO_MODULES_TEXT)
      h.eq("the daemon's group still drawn", C().micSettings.groups.map(function(g) { return g.id }).join(","), "input")
      h.fits(A(), "Mic tab without modules")
    })
    h.step("mic: a daemon below revision 13", function() {
      h.writeFile("settings-state", brioState())
      h.feed([snapshotLine(rev7({ interface_revision: 12, mic: null }))])
    }, function() { return S().record.interfaceRevision === 12 && h.writerIdle() })
    h.wait(300)
    h.step("mic: the tab says the daemon needs updating, and offers nothing", function() {
      h.eq("the Mic tab still there", h.find(A(), "micTab").visible, true)
      h.eq("the hint", h.find(A(), "micHint").text, h.model.DAEMON_NO_MIC)
      h.eq("no switch", h.find(A(), "micHostRow").visible, false)
      h.eq("no state", h.find(A(), "micStatusBlock").visible, false)
      h.eq("no settings", h.find(A(), "micSettingsArea").visible, false)
      h.eq("stops", kinds(), "switch,info,tabs")
      h.check("the switch runs nothing", !C().toggleMic() && !S().setMicHost(true))
      h.eq("no bar glyph", A().micButton.visible, false)
      h.fits(A(), "Mic tab, old daemon")
    })
    h.grabStep(function() { return A().popup }, "m4-mic-old-daemon.png")
    h.step("mic: back to the Camera tab", function() {
      h.tab(A(), "camera")
      h.feed([snapshotLine(rev7({}))])
    }, function() { return h.find(A(), "settingsArea").visible && S().record.interfaceRevision === 7 && h.writerIdle() })
    h.wait(300)

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


  // ---- the camera's health (mock, interface revision 20) -----------------------
  //
  // The snapshot's `camera_health` and the watch's `camera_health` lines, in
  // the Camera tab for the active camera only: the delivered rate, the
  // warnings, a suggestion's button (`settings set`, as a switch writes) and
  // Use recommended settings (`recommended apply`, whose result shows only
  // when the next camera_health line arrives: the fake appends it).
  function healthObj(o) {
    var m = { camera: brioId, delivered_fps: 19.5, nominal_fps: 30, corrupt_frames: 12,
              warnings: ["<b>Shared</b> USB hub: the camera may drop frames"],
              suggestions: [{ setting: "effect.video.denoise", value: "on", reason: "The image is noisy in this light" }],
              has_recommendation: true,
              recommended: [{ setting: "camera.image.sharpness", label: "Sharpness", value: "150", current: "128" },
                            { setting: "camera.exposure.power_line_frequency", label: "Anti-flicker", value: "50 Hz", current: "60 Hz" }] }
    for (var k in o) m[k] = o[k]
    return m
  }
  function healthLine(o) {
    var m = healthObj(o)
    m.v = 1
    m.type = "camera_health"
    return JSON.stringify(m)
  }
  function healthScenario() {
    var A = function() { return h.widgetA }
    var S = function() { return h.widgetA.service }
    var C = function() { return h.content(A()) }
    var rev20 = function(o) {
      var m = { interface_revision: 20, settings_schema: 1, settings_revision: 5, loopback_consumers: 0, pipewire_consumers: 0,
                preview_consumers: 0, pipewire_output: "ready", camera_health: healthObj({}) }
      for (var k in o) m[k] = o[k]
      return m
    }
    var denoise = stateRow("video", "Video", "effect.video.denoise", "bool", "Noise removal", "false", "false", { scope: "global" })
    var kinds = function() { return C().stops.map(function(st) { return st.kind + (st.index >= 0 ? st.index : "") }).join(",") }
    var visible = function(name) { var it = h.find(A(), name); return !!it && it.visible }
    var args = function(verb) { return h.newLogArgs().filter(function(a) { return a[0] === verb }) }

    h.step("health: a revision-20 daemon reports the MX Brio's health", function() {
      h.writeFile("settings-state", brioState().concat([denoise]))
      h.writeFile("settings-camera", [brioId])
      h.writeFile("settings-rev", ["5"])
      h.writeFile("settings-serial", ["2"])
      h.writeFile("settings-per-line", ["4"])
      h.writeFile("settings-mode", ["list"])
      h.writeFile("camera-health", [healthLine({})])
      h.removeFile("camera-health-applied")
      h.removeFile("delay")
      h.removeFile("stderr")
      h.writeFile("exit", ["0"])
      h.feed([snapshotLine(rev20({}))])
    }, function() { return !!S().record.health && !!S().record.settings && S().record.settings.groups.length === 5 && h.writerIdle() })
    h.step("health: the Camera tab", function() { A().open(); h.tab(A(), "camera") }, function() { return C() !== null && h.find(A(), "cameraTab").visible })
    h.wait(300)
    h.step("health: the delivered rate, the warning, the suggestion and the recommended settings", function() {
      h.eq("the block", visible("healthBlock"), true)
      h.eq("the rate", h.find(A(), "healthDelivers").text, "Delivers 19.5 of 30 fps")
      h.check("muted", String(h.find(A(), "healthDelivers").color) === String(C().dim), String(h.find(A(), "healthDelivers").color))
      var w = h.find(A(), "healthWarning-0")
      h.eq("the warning, as text, behind the caution sign", w.text, h.model.GLYPH_WARNING + " bShared/b USB hub: the camera may drop frames")
      h.eq("plain text", w.textFormat, Text.PlainText)
      h.check("not urgent", String(w.color) !== String(barA.urgent), String(w.color))
      h.eq("one warning", h.find(A(), "healthWarning-1"), null)
      h.eq("the suggestion's label", h.find(A(), "healthSuggestionLabel-0").text, "Noise removal")
      h.eq("its reason", h.find(A(), "healthSuggestionReason-0").text, "The image is noisy in this light")
      h.eq("its button", h.find(A(), "healthSuggestionButton-0").text, "Turn on")
      h.check("the button on the right", h.find(A(), "healthSuggestionButton-0").x > h.find(A(), "healthSuggestionLabel-0").x)
      h.eq("a rule above the health", visible("healthSeparator"), true)
      h.check("the suggestion's label wraps, never elides", h.find(A(), "healthSuggestionLabel-0").wrapMode === Text.Wrap
              && h.find(A(), "healthSuggestionLabel-0").elide === Text.ElideNone)
      h.eq("one suggestion: no line to open more", visible("healthSuggestionsMore"), false)
      h.eq("the recommended block", visible("recommendedBlock"), true)
      h.eq("its title, as the panel's section headers", h.find(A(), "recommendedTitle").text, "RECOMMENDED FOR THIS CAMERA")
      h.eq("the changes folded to one line", h.find(A(), "recommendedSummary").text, "2 changes: Sharpness, Anti-flicker")
      h.eq("no change listed while folded", h.find(A(), "recommendedChange-0"), null)
      h.eq("the button", h.find(A(), "recommendedButton").text, "Use recommended settings")
      var title = h.find(A(), "recommendedTitle"), button = h.find(A(), "recommendedButton")
      var tp = title.mapToItem(C(), 0, 0), bp = button.mapToItem(C(), 0, 0)
      h.check("the button on its title's line, at the right",
              bp.x > tp.x + title.implicitWidth && bp.y < tp.y + title.height && tp.y < bp.y + button.height
              && Math.abs((bp.x + button.width) - (h.find(A(), "settingsReset").mapToItem(C(), 0, 0).x + h.find(A(), "settingsReset").width)) < 1,
              JSON.stringify([tp, bp]))
      h.check("above the settings' groups", bp.y < h.find(A(), "settingsGroupHeader-image").mapToItem(C(), 0, 0).y)
      h.eq("stops", kinds(), "switch,info,tabs,preview,camera,suggestion0,recommended,recommended-changes,group0,"
           + "setting0,setting1,setting2,setting3,setting4,setting5,group1,group2,group3,reset")
      h.eq("the Camera tab carries the caution sign", h.find(A(), "tab-camera").iconText, h.model.GLYPH_WARNING)
      h.eq("and says so", h.find(A(), "tab-camera").Accessible.name, "Camera, with a warning")
      h.eq("the other tabs do not", h.find(A(), "tab-effect").iconText + h.find(A(), "tab-mic").iconText, "")
      h.eq("the chips keep one height", h.find(A(), "tab-camera").height, h.find(A(), "tab-effect").height)
      h.eq("nothing written by showing it", args("settings").length + args("recommended").length, 0)
      // Three cameras, the health and two changes on a 1080 screen: the
      // card stays within its cap; the body is the one scroller.
      var flick = h.find(A(), "panelFlick")
      h.check("the card within the 860 cap", A().popup.contentHeight <= 860, A().popup.contentHeight)
      h.eq("no scroller in the settings", h.find(A(), "settingsFlick"), null)
      h.eq("Reset to defaults drawn, at the bottom", visible("settingsReset"), true)
      h.note("health: body " + Math.round(flick.contentHeight) + " in " + Math.round(flick.height))
    })
    h.grabStep(function() { return A().popup }, "h1-camera-health.png")

    h.step("health: open the recommended changes", function() {
      var line = h.find(A(), "recommendedChangesLine")
      keys.mouseClick(line, line.width / 2, line.height / 2)
    }, function() { return h.find(A(), "recommendedChange-1") !== null })
    h.wait(250)
    h.step("health: the changes, listed", function() {
      h.eq("the changes", h.find(A(), "recommendedChange-0").text + " | " + h.find(A(), "recommendedChange-1").text,
           "Sharpness: 128 → 150 | Anti-flicker: 60 Hz → 50 Hz")
      // Opened by hand, the list may take the groups' room down to their
      // minimum (past it the panel scrolls, the designed fallback); the
      // groups still show and Reset stays reachable.
      h.eq("the settings still drawn", visible("settingsReset") && visible("settingsView"), true)
    })
    h.grabStep(function() { return A().popup }, "h2-camera-health-changes.png")
    h.step("health: Enter on the line folds them again", function() {
      C().setCursor("recommended-changes", -1)
      h.key(Qt.Key_Return)
    }, function() { return h.find(A(), "recommendedChange-0") === null })
    h.step("health: another tab shows the camera's warning on its button", function() { h.tab(A(), "mic") },
           function() { return !h.find(A(), "cameraTab").visible })
    h.grabStep(function() { return A().popup }, "h3-mic-tab-warning.png")
    h.step("health: back to the Camera tab", function() { h.tab(A(), "camera") }, function() { return h.find(A(), "cameraTab").visible })

    h.step("health: Turn on writes the setting, as its switch would", function() {
      h.markLog()
      h.find(A(), "healthSuggestionButton-0").clicked()
    }, function() { return args("settings").length >= 1 && !S().commandBusy }, 3000)
    h.step("health: the write", function() {
      h.eq("argv", JSON.stringify(args("settings")), JSON.stringify([["settings", "set", "--", "effect.video.denoise", "true"]]))
      h.eq("no error", S().commandError, "")
      // the daemon's next value drops the suggestion
      h.feed([healthLine({ suggestions: [] })])
    }, function() { return S().record.health.suggestions.length === 0 })
    h.wait(250)
    h.step("health: the suggestion is gone", function() {
      h.eq("no row", h.find(A(), "healthSuggestion-0"), null)
      h.eq("the rate and the warning stay", visible("healthDelivers") && visible("healthWarning-0"), true)
      h.eq("stops", kinds().indexOf("suggestion"), -1)
    })

    h.step("health: a refused apply shows the error and changes nothing", function() {
      h.writeFile("exit", ["1"])
      h.writeFile("stderr", ["omarchy-broadcast: this camera has no recommended settings"])
      h.writeFile("camera-health-applied", [healthLine({ suggestions: [], recommended: [] })])
    }, function() { return h.writerIdle() })
    h.step("health: click Use recommended settings", function() {
      h.markLog()
      S().commandError = ""
      h.find(A(), "recommendedButton").clicked()
    }, function() { return S().commandError !== "" && !S().commandBusy }, 3000)
    h.wait(250)
    h.step("health: refused", function() {
      h.eq("argv", JSON.stringify(args("recommended")), JSON.stringify([["recommended", "apply"]]))
      h.check("the error", S().commandError.indexOf("no recommended settings") >= 0, S().commandError)
      h.eq("the changes still listed", visible("recommendedBlock") && S().record.health.recommended.length === 2, true)
      h.writeFile("exit", ["0"])
      h.removeFile("stderr")
    }, function() { return h.writerIdle() })

    h.step("health: Enter on Use recommended settings applies them", function() {
      h.markLog()
      C().setCursor("recommended", -1)
      h.eq("the button has the cursor", h.find(A(), "recommendedButton").hasCursor, true)
      h.key(Qt.Key_Return)
    }, function() { return args("recommended").length >= 1 && S().record.health.recommended.length === 0 }, 3000)
    h.wait(250)
    h.step("health: applied; the daemon's next value shows it", function() {
      h.eq("argv", JSON.stringify(args("recommended")), JSON.stringify([["recommended", "apply"]]))
      h.eq("no error", S().commandError, "")
      h.eq("the recommended block is gone", visible("recommendedBlock"), false)
      h.eq("stops", kinds().indexOf("recommended"), -1)
    })

    h.step("health: another camera's health shows nothing", function() {
      h.feed([healthLine({ camera: fhdId })])
    }, function() { return S().record.health.camera === fhdId })
    h.wait(250)
    h.step("health: nothing for another camera", function() {
      h.eq("no block", visible("healthBlock"), false)
      h.eq("no recommended settings", visible("recommendedBlock"), false)
    })
    // interface revision 26: the camera's status lines
    h.step("health: a revision-26 daemon reports a closed shutter and a Show Mode line", function() {
      var o = { shutter: "closed", show_mode: "desk_view", status: ["Shutter closed", "Show Mode: desk view"] }
      h.feed([snapshotLine(rev20({ interface_revision: 26, camera_health: healthObj(o) }))])
    }, function() { return S().record.interfaceRevision === 26 && S().record.health.status.length === 2 })
    h.wait(250)
    h.step("health: both status lines, the first strong, before the rate", function() {
      var a = h.find(A(), "healthStatus-0"), b = h.find(A(), "healthStatus-1")
      h.eq("first line, behind the caution sign", a.text, h.model.GLYPH_WARNING + " Shutter closed")
      h.eq("second line", b.text, "Show Mode: desk view")
      h.eq("first is bold", a.font.bold, true)
      h.eq("second is not", b.font.bold, false)
      h.check("first in the foreground colour", String(a.color) === String(C().foreground), String(a.color))
      h.check("second muted", String(b.color) === String(C().dim), String(b.color))
      h.eq("a strong line's accessible name is a warning", a.Accessible.name, "Warning: Shutter closed")
      h.eq("a plain line's accessible name is its text", b.Accessible.name, "Show Mode: desk view")
      h.eq("plain text", a.textFormat, Text.PlainText)
      h.eq("no third", h.find(A(), "healthStatus-2"), null)
      h.check("above the rate", a.mapToItem(C(), 0, 0).y < h.find(A(), "healthDelivers").mapToItem(C(), 0, 0).y)
      h.eq("the status lines are no cursor stops", kinds(),
           "switch,info,tabs,preview,camera,recommended,recommended-changes,group0,setting0,setting1,setting2,setting3,setting4,setting5,group1,group2,group3,reset")
    })
    // a closed shutter while a session runs: the tab chip and the bar say so
    h.step("health: a session runs with the shutter closed", function() {
      var o = { shutter: "closed", show_mode: "desk_view", status: ["Shutter closed", "Show Mode: desk view"] }
      h.feed([snapshotLine(rev20({ state: "active", consumers: 1, interface_revision: 26, camera_health: healthObj(o) }))])
    }, function() { return S().record.state === "active" && S().record.health.shutter === "closed" })
    h.wait(250)
    h.step("health: the Camera tab and the bar show the closed shutter", function() {
      h.eq("the Camera tab carries the caution sign", h.find(A(), "tab-camera").iconText, h.model.GLYPH_WARNING)
      h.eq("and names the shutter and the warning", h.find(A(), "tab-camera").Accessible.name, "Camera, shutter closed, with a warning")
      h.eq("the bar glyph is crossed-out webcam", A().iconButton.text, h.model.GLYPH_WEBCAM_OFF)
      h.check("the tooltip says so", A().iconButton.tooltipText.indexOf("camera shutter closed") >= 0, A().iconButton.tooltipText)
      h.check("the accessible name says so", A().iconButton.Accessible.name.indexOf("camera shutter closed") >= 0)
    })
    h.step("health: the shutter opens", function() {
      var o = { shutter: "open", show_mode: "desk_view", status: ["Show Mode: desk view"], warnings: [] }
      h.feed([snapshotLine(rev20({ state: "active", consumers: 1, interface_revision: 26, camera_health: healthObj(o) }))])
    }, function() { return S().record.health.shutter === "open" })
    h.wait(250)
    h.step("health: the tab and the bar clear", function() {
      h.eq("no caution sign", h.find(A(), "tab-camera").iconText, "")
      h.eq("plain name", h.find(A(), "tab-camera").Accessible.name, "Camera")
      h.eq("the active webcam glyph", A().iconButton.text, h.model.GLYPH_WEBCAM)
      h.check("no phrase", A().iconButton.tooltipText.indexOf("shutter") < 0, A().iconButton.tooltipText)
    })
    h.step("health: closed again, then no session runs", function() {
      var o = { shutter: "closed", show_mode: "desk_view", status: ["Shutter closed", "Show Mode: desk view"], warnings: [] }
      h.feed([snapshotLine(rev20({ state: "idle", consumers: 0, interface_revision: 26, camera_health: healthObj(o) }))])
    }, function() { return S().record.state === "idle" && S().record.health.shutter === "closed" })
    h.wait(250)
    h.step("health: idle shows neither", function() {
      h.eq("no caution sign", h.find(A(), "tab-camera").iconText, "")
      h.eq("plain name", h.find(A(), "tab-camera").Accessible.name, "Camera")
      h.eq("the idle glyph", A().iconButton.text, h.model.GLYPH_WEBCAM)
      h.check("no phrase", A().iconButton.tooltipText.indexOf("shutter") < 0, A().iconButton.tooltipText)
    })
    h.step("health: the same report at revision 25 shows no status line", function() {
      var o = { shutter: "closed", show_mode: "desk_view", status: ["Shutter closed", "Show Mode: desk view"] }
      h.feed([snapshotLine(rev20({ interface_revision: 25, camera_health: healthObj(o) }))])
    }, function() { return S().record.interfaceRevision === 25 })
    h.wait(250)
    h.step("health: none drawn below revision 26", function() {
      h.eq("no first line", h.find(A(), "healthStatus-0"), null)
      h.eq("the rest of the health still drawn", visible("healthBlock"), true)
    })
    h.step("health: a daemon below revision 20 (null)", function() {
      h.feed([snapshotLine(rev20({ interface_revision: 19, camera_health: null }))])
    }, function() { return S().record.interfaceRevision === 19 && S().record.health === null })
    h.wait(250)
    h.step("health: nothing at all", function() {
      h.eq("no block", visible("healthBlock"), false)
      h.eq("no recommended settings", visible("recommendedBlock"), false)
      h.eq("the settings still drawn", visible("settingsArea"), true)
    })
    h.step("health: close", function() {
      A().close()
      h.removeFile("settings-mode")
      h.removeFile("settings-state")
      h.removeFile("settings-camera")
      h.removeFile("settings-rev")
      h.removeFile("settings-serial")
      h.removeFile("settings-per-line")
      h.removeFile("camera-health")
      h.removeFile("camera-health-applied")
      h.feed([snapshotLine({})])
    }, function() { return S().record.interfaceRevision === 4 && h.writerIdle() })
  }

  // ---- the setup dialog (mock): the overlay, its reads and writes ------------------

  function setupModulesLines(maxineOn) {
    var mods = [
      { id: "br.com.dias.maxine-vfx", name: "NVIDIA Maxine video effects", version: "0.25.0", licence: "MIT", description: "", kind: "video-stage",
        library: "/usr/lib/x.so", manifest: "/usr/lib/x.toml", enabled: maxineOn, status: maxineOn ? "available" : "disabled",
        reason: maxineOn ? "" : "Disabled", overridden_by: "",
        stages: [{ id: "background", slot: "matte", rank: 300, device: "nvidia-gpu", available: true, reason: "", selected: true },
                 { id: "relight", slot: "post-matte", rank: 300, device: "nvidia-gpu", available: false, reason: "Not installed", selected: false }],
        stages_truncated: false },
      { id: "org.example.hello", name: "Hello <b>tint</b>", version: "0.1.0", licence: "MIT", description: "", kind: "video-stage",
        library: "/l.so", manifest: "/m.toml", enabled: false, status: "disabled",
        reason: "Disabled after crashing the daemon twice in a row", overridden_by: "config.d/90-local.toml",
        stages: [{ id: "hello", slot: "post-composite", rank: 100, device: "cpu", available: false, reason: "Disabled", selected: false }],
        stages_truncated: false }
    ]
    var out = [JSON.stringify({ v: 1, type: "modules", serial: 1, profile: "quality", count: mods.length, profile_overridden_by: "" })]
    for (var i = 0; i < mods.length; i++)
      out.push(JSON.stringify({ v: 1, type: "module", serial: 1, index: i, count: mods.length, module: mods[i] }))
    return out
  }
  function setupOrderLine(ids) {
    var stages = []
    for (var i = 0; i < ids.length; i++) stages.push({ id: ids[i], slot: "pre-matte", up: i > 0, down: i < ids.length - 1 })
    return JSON.stringify({ v: 1, type: "order", order: ids, order_truncated: false, stages: stages, overridden_by: "" })
  }
  // One config row: id and value first (the fake's `config set` rewrites
  // the value that follows the id).
  function cfg(id, type, value, o) {
    var m = { id: id, value: value, label: id, description: "", type: type, editable: true, source: "", overridden_by: "",
              apply: "live", enabled: true, disabled_reason: "" }
    for (var k in o) m[k] = o[k]
    return m
  }
  // The 16 options of output.mode as a revision-12 daemon computes them (the
  // selected camera's 16:9 sizes, each at four rates; 60 fps generated).
  function outputModeOptions() {
    var sizes = ["3840x2160", "2560x1440", "1920x1080", "1280x720"]
    var rates = [15, 24, 30, 60]
    var out = []
    for (var i = 0; i < sizes.length; i++)
      for (var j = 0; j < rates.length; j++)
        out.push({ value: sizes[i] + "@" + rates[j], label: sizes[i] + " \u00b7 " + rates[j] + " fps" + (rates[j] === 60 ? " (generated)" : "") })
    return out
  }
  // `editableMode`: the output.mode row of interface revision 12, an editable
  // enum; else the read-only text of an older daemon.
  function setupConfigLines(editableMode) {
    var modeRow = editableMode === true
      ? cfg("output.mode", "enum", "1920x1080@30", { label: "Output size and rate", "default": "1920x1080@30", apply: "reload",
            description: "Size and frame rate of the virtual camera", options: outputModeOptions() })
      : cfg("output.mode", "string", "1920x1080@30", { label: "Mode", editable: false, description: "The output size and rate" })
    var groups = [
      { id: "output", label: "Output", settings: [
        cfg("output.format", "enum", "nv12", { label: "Format", "default": "nv12", apply: "reload", description: "The pixel format apps receive",
            options: [{ value: "nv12", label: "NV12" }, { value: "yuyv", label: "YUYV" }] }),
        modeRow] },
      { id: "lifecycle", label: "Lifecycle", settings: [
        cfg("lifecycle.idle_grace_s", "int", 5, { label: "Idle grace", "default": 5, min: 0, max: 60, step: 1, unit: "s" }),
        cfg("lifecycle.start_debounce_ms", "int", 200, { label: "Start debounce", min: 0, max: 5000, step: 10, unit: "ms",
            source: "config.d/90-local.toml", overridden_by: "config.d/90-local.toml", enabled: false,
            disabled_reason: "Overridden by config.d/90-local.toml" })] },
      { id: "pipewire", label: "PipeWire", settings: [
        cfg("pipewire.enabled", "bool", false, { label: "PipeWire output", "default": false, apply: "reload", source: "config.d/50-panel.toml" })] },
      { id: "effect", label: "Effect", settings: [
        cfg("effect.maxine_root", "path", "/opt/maxine", { label: "Maxine root", editable: false, apply: "restart" })] },
      { id: "modules", label: "Modules", settings: [
        cfg("modules.profile", "enum", "quality", { label: "Backend profile", apply: "reload",
            options: [{ value: "quality", label: "Quality" }, { value: "battery", label: "Battery" }] }),
        cfg("modules.pin.background", "enum", "", { label: "Background", apply: "reload",
            options: [{ value: "", label: "Automatic" }, { value: "br.com.dias.maxine-vfx", label: "NVIDIA Maxine video effects" },
                      { value: "org.example.long", label: "A backend module with a name far too long to share a line of chips with any other" }] }),
        cfg("modules.dirs", "list", ["/usr/lib/omarchy-broadcast/modules.d"], { label: "Module directories", editable: false })] }
    ]
    var raw = []
    for (var g = 0; g < groups.length; g++) {
      var per = 2
      var parts = Math.max(1, Math.ceil(groups[g].settings.length / per))
      for (var p = 0; p < parts; p++)
        raw.push({ v: 1, type: "config_group", schema: 1, serial: 4, part: p + 1, parts: parts,
                   group: { id: groups[g].id, label: groups[g].label, settings: groups[g].settings.slice(p * per, (p + 1) * per) } })
    }
    for (var i = 0; i < raw.length; i++) { raw[i].index = i; raw[i].count = raw.length }
    return raw.map(function(o) { return JSON.stringify(o) })
  }
  function setupFilesLine() {
    return JSON.stringify({ v: 1, type: "config_files", serial: 4, dir: "/home/u/.config/omarchy-broadcast", files: [
      { path: "config.toml", status: "loaded", managed: false, reason: "" },
      { path: "config.d/50-panel.toml", status: "loaded", managed: true, reason: "" },
      { path: "config.d/90-local.toml", status: "error", managed: false, reason: "line 3: unknown field `foo`" }], files_truncated: false })
  }

  function setupScenario() {
    var A = function() { return h.widgetA }
    var B = function() { return h.widgetB }
    var S = function() { return h.widgetA.service }
    var D = function() { return h.dialog }
    var find = function(name) { return h.findByName(D(), name) }
    var rev = function(n) { return { interface_revision: n, config_serial: 1, modules_serial: 1, error: "" } }
    var reads = function() {
      return h.newLogArgs().filter(function(a) { return a[a.length - 1] === "--json" && a[0] !== "watch" && a[0] !== "preview" })
                           .map(function(a) { return a.join(" ") })
    }
    var writes = function() {
      return h.newLogArgs().filter(function(a) { return (a[0] === "modules" || a[0] === "order" || a[0] === "config") && a[a.length - 1] !== "--json" })
    }
    var loaded = function(kinds) { return kinds.every(function(k) { return S().setup[k] !== null }) && !S().readArmed && S().readQueue.length === 0 }
    var shot = function(file) { h.grabStep(function() { return find("setupCard") }, file) }

    h.step("setup: seed the fake with a revision-10 daemon; two monitors again", function() {
      // The overlay is loaded from the widgets' directory, as the shell does.
      if (!h.widgetB) h.widgetB = h.makeWidget(barB, { cliPath: shellRoot.cli })
      h.writeFile("modules-list", setupModulesLines(true))
      h.writeFile("order-show", [setupOrderLine(["enhance", "denoise", "background"])])
      h.writeFile("config-show", setupConfigLines())
      h.writeFile("config-files", [setupFilesLine()])
      h.writeFile("setup-serial", ["1"])
      h.removeFile("delay")
      h.removeFile("stderr")
      h.writeFile("exit", ["0"])
      h.feed([snapshotLine(rev(10))])
    }, function() { return S().record.interfaceRevision === 10 && S().attachedCount === 2 && h.writerIdle() })
    // As the shell's panel loader (shell.qml, panelEntry.panelLoader): an
    // asynchronous Loader of the entry point whose onLoaded hands the item
    // what it declares, in the shell's order, before registering it. An
    // assignment that throws (a readonly property of one of these names)
    // stops it there, as in the shell: never registered, so never opened.
    h.step("setup: the shell's loader makes the overlay", function() {
      fakeShell.toggles = []
      fakeShell.hides = []
      h.notes.loaderError = ""
      var loader = Qt.createQmlObject('import QtQuick; Loader { asynchronous: true; width: 900; height: 760 }',
                                      window.contentItem, "setupLoader")
      h.notes.loader = loader
      loader.loaded.connect(function() {
        var item = loader.item
        if (!item) return
        try {
          if ("omarchyPath" in item) item.omarchyPath = "/usr/share/omarchy"
          if ("shell" in item) item.shell = fakeShell
          if ("manifest" in item) item.manifest = { id: shellRoot.moduleName }
          if ("barWidgetRegistry" in item) item.barWidgetRegistry = null
          if ("pluginRegistry" in item) item.pluginRegistry = null
          // This plugin has no service entry: the shell's serviceFor gives null.
          if ("service" in item) item.service = null
          h.dialog = item
        } catch (e) {
          h.notes.loaderError = String(e)
        }
      })
      loader.source = "file://" + shellRoot.pluginPath + "/SetupDialog.qml"
    }, function() { return !!h.dialog || h.notes.loaderError !== "" || h.notes.loader.status === Loader.Error })
    h.step("setup: loaded, shown nothing, held nothing", function() {
      h.eq("the loader's injections went through and it registered", h.notes.loaderError, "")
      h.check("registered", !!h.dialog, h.notes.loader.status === Loader.Error
              ? Qt.createComponent("file://" + shellRoot.pluginPath + "/SetupDialog.qml").errorString() : h.notes.loader.status)
      if (!h.dialog) return
      h.eq("the shell's manifest", D().manifest.id, shellRoot.moduleName)
      h.eq("not shown", D().shown, false)
      h.eq("not open", D().opened, false)
      h.eq("no reads", S().setupHeld, false)
      h.check("one service: the widgets' singleton", D().daemonService === S())
      A().open()
    }, function() { return A().opened })
    h.step("setup: an open panel makes the plugin open, for the shell", function() {
      h.eq("panel open: the overlay reports open", D().opened, true)
      h.eq("Daemon.panelOpen", S().panelOpen, true)
      // a shell without a toggle: nothing to open, and the panel stays
      barA.shell = noToggleShell
      h.eq("no toggle: no setup", A().openSetup(), false)
      h.eq("the panel stays open", A().opened, true)
      barA.shell = fakeShell
      h.markLog()
      A().iconButton.triggerPress(Qt.RightButton)
    }, function() { return D().shown && loaded(["modules", "order", "config", "files"]) }, 8000)
    h.step("setup: the right click closed the panel and opened the dialog through the shell's toggle", function() {
      h.eq("panel closed", A().opened, false)
      h.eq("one toggle", fakeShell.toggles.length, 1)
      h.eq("for the plugin", fakeShell.toggles[0].id, shellRoot.moduleName)
      h.eq("payload, no program in it", fakeShell.toggles[0].payload, JSON.stringify({ view: "setup" }))
      h.eq("held", S().setupHeld, true)
      h.eq("the four reads, in order", JSON.stringify(reads()),
           JSON.stringify(["modules list --json", "order show --json", "config show --json", "config files --json"]))
      h.eq("no write", writes().length, 0)
      h.eq("the dialog did not attach itself (the widgets run the watch)", D().attached, false)
      h.eq("watch still one", S().watchStarts >= 1 && S().attachedCount === 2, true)
      h.eq("title", find("setupTitle").text, h.model.SETUP_TITLE)
      h.eq("Modules shown first", D().section, "modules")
      h.eq("Modules selected in the list", find("setupSection-modules").current, true)
      h.check("the keyboard is the dialog's", D().keyCatcher.activeFocus)
    })
    h.wait(300)
    h.step("setup: Modules", function() {
      h.eq("two rows", find("modulesSection").visible && D().modulesView.rows.length, 2)
      h.eq("titles", D().modulesView.rows.map(function(r) { return r.title }).join("|"), "NVIDIA Maxine video effects 0.25.0|Hello btint/b 0.1.0")
      h.eq("the crash-ledger reason", D().modulesView.rows[1].reason, "Disabled after crashing the daemon twice in a row")
      h.eq("overridden: greyed, no switch", D().modulesView.rows[1].switchable, false)
      h.eq("its note", D().modulesView.rows[1].note, "Overridden by config.d/90-local.toml")
      h.check("its switch faded", find("moduleSwitch-1").opacity < 1)
      h.eq("switch on", find("moduleSwitch-0").checked, true)
      h.eq("stops: the list, then the one switch that can flip", D().stops.map(function(x) { return x.kind + x.index }).join(","),
           "section0,section1,section2,section3,section4,module0")
    })
    shot("setup-modules.png")
    h.step("setup: Down shows the cursor, Right enters, Enter disables the module", function() {
      h.markLog()
      h.key(Qt.Key_Down)
      h.eq("cursor on the section shown", D().currentStop.kind + D().currentStop.index, "section0")
      h.eq("one highlight", find("setupSection-modules").hasCursor, true)
      h.key(Qt.Key_Right)
      h.eq("into the section", D().currentStop.kind + D().currentStop.index, "module0")
      h.eq("the row has the cursor", find("moduleRow-0").hasCursor, true)
      h.key(Qt.Key_Return)
      h.check("busy", S().setupBusy)
      h.eq("Saving… on the title line", find("setupSaving").text, h.model.SETUP_SAVING)
      h.eq("a setup write does not hold the middle click (Q5)", S().toggleBusy, false)
      h.eq("nor the panel's switch", h.model.middleClickAction(S().record, S().toggleBusy), "toggle")
      h.check("a second write is refused while it runs", !S().setModuleEnabled("br.com.dias.maxine-vfx", true))
      h.writeFile("modules-list", setupModulesLines(false))
    }, function() { return writes().length >= 1 && !S().setupBusy && S().setup.modules && S().setup.modules.ok
                           && S().setup.modules.modules[0].enabled === false }, 8000)
    h.step("setup: the write and the re-read", function() {
      h.eq("argv", JSON.stringify(writes()), JSON.stringify([["modules", "disable", "br.com.dias.maxine-vfx"]]))
      h.eq("switch off, from the daemon's list", find("moduleSwitch-0").checked, false)
      h.eq("its status", D().modulesView.rows[0].statusText, "Disabled")
      h.eq("a bare Disabled, not Disabled: Disabled", D().modulesView.rows[0].statusLine, "Disabled")
      h.eq("a real reason keeps its status", D().modulesView.rows[1].statusLine, "Disabled: Disabled after crashing the daemon twice in a row")
      h.check("read again after modules_changed", reads().indexOf("modules list --json") >= 0, JSON.stringify(reads()))
      h.eq("no error", D().statusText, "")
      h.eq("the panel's error untouched", S().commandError, "")
    })
    // Order: the daemon's moves only
    h.step("setup: 2 shows Order", function() { h.key("2") }, function() { return D().section === "order" })
    h.wait(250)
    h.step("setup: Order", function() {
      h.eq("rows", D().orderView.rows.map(function(r) { return r.position + r.id }).join(","), "1enhance,2denoise,3background")
      h.eq("first cannot go up", find("stageUp-0").enabled, false)
      h.eq("last cannot go down", find("stageDown-2").enabled, false)
      h.eq("reset offered", find("resetOrder").visible, true)
      h.eq("Move up names its stage", find("stageUp-1").Accessible.name, "Move denoise up")
      h.eq("Move down names its stage", find("stageDown-1").Accessible.name, "Move denoise down")
      h.eq("the cursor moved to the section entry", D().currentStop.kind + D().currentStop.index, "section1")
      h.markLog()
      D().setCursor("stage", 1)
      h.eq("lands on Move up", D().stageButton, 0)
      h.eq("Move up has the cursor", find("stageUp-1").hasCursor, true)
      h.key(Qt.Key_Return)
    }, function() { return writes().length >= 1 && !S().setupBusy && S().setup.order && S().setup.order.order[0] === "denoise" }, 8000)
    h.step("setup: a move is the whole new order", function() {
      h.eq("argv", JSON.stringify(writes()), JSON.stringify([["order", "set", "denoise,enhance,background"]]))
      h.eq("re-read", D().orderView.rows.map(function(r) { return r.id }).join(","), "denoise,enhance,background")
      h.eq("the cursor followed the stage", D().currentStop.kind + D().currentStop.index, "stage0")
      h.markLog()
      keys.keyClick(Qt.Key_Down, Qt.ControlModifier)
    }, function() { return writes().length >= 1 && !S().setupBusy && S().setup.order.order[1] === "denoise" }, 8000)
    h.step("setup: Ctrl+Down moves it down", function() {
      h.eq("argv", JSON.stringify(writes()), JSON.stringify([["order", "set", "enhance,denoise,background"]]))
      h.markLog()
      var b = find("resetOrder")
      keys.mouseClick(b, b.width / 2, b.height / 2)
    }, function() { return writes().length >= 1 && !S().setupBusy }, 8000)
    h.step("setup: Reset order", function() {
      h.eq("argv", JSON.stringify(writes()), JSON.stringify([["order", "reset"]]))
    })
    shot("setup-order.png")
    // Backends: the profile and the pins, written with config set
    h.step("setup: 3 shows Backends", function() { h.key("3") }, function() { return D().section === "backends" })
    h.wait(250)
    h.step("setup: Backends", function() {
      // A few short choices are buttons; the pin's long module name makes it a dropdown (Model.fitsSegmented)
      h.eq("rows", D().backendsView.groups.map(function(g) { return g.rows.map(function(r) { return r.id + ":" + r.widget }).join(",") }).join("|"),
           "modules.profile:choices,modules.pin.background:dropdown")
      h.eq("Quality selected", find("configChoice-modules.profile-0").selected, true)
      var flow = find("configChoices-modules.profile")
      var profileRow = find("configRow-modules.profile")
      h.check("on their own line under the label", flow.y > 0, flow.y)
      h.check("across the whole row", flow.width > profileRow.width * 0.8, flow.width + " of " + profileRow.width)
      h.check("each chip within the row", find("configChoice-modules.profile-1").width <= flow.width + 0.5)
      h.eq("a chip that fits has no tooltip", find("configChoice-modules.profile-1").tooltipText, "")
      h.eq("a row of choices reads as a combo box", profileRow.Accessible.role, Accessible.ComboBox)
      h.eq("a chip as a radio button", find("configChoice-modules.profile-1").Accessible.role, Accessible.RadioButton)
      var pinRow = find("configRow-modules.pin.background")
      var dd = find("configDropdown-modules.pin.background")
      h.eq("the pin has no chips", find("configChoices-modules.pin.background").visible, false)
      h.eq("the pin's box shows Automatic", dd.value + "/" + dd.currentLabel(), "/Automatic")
      h.eq("its three choices", dd.options.length, 3)
      h.eq("a dropdown row reads as a combo box", pinRow.Accessible.role, Accessible.ComboBox)
      var ddBox = dd.mapToItem(pinRow, 0, 0)
      h.check("on the label's line, at the right", ddBox.x > pinRow.width * 0.3 && ddBox.x + dd.width <= pinRow.width + 0.5, ddBox.x + "+" + dd.width + " in " + pinRow.width)
      h.markLog()
      D().setCursor("config", 0)
      h.eq("lands on the current choice", D().choiceCursor, 0)
      h.key(Qt.Key_Right)
      h.eq("Battery has the cursor", find("configChoice-modules.profile-1").hasCursor, true)
      h.key(Qt.Key_Space)
    }, function() { return writes().length >= 1 && !S().setupBusy && h.model.findConfigRow(S().setup.config, "modules.profile").value === "battery" }, 8000)
    // a narrow screen: the dropdown stays inside its row
    h.step("setup: Backends on a narrow screen", function() { h.notes.loader.width = 470 })
    h.wait(250)
    h.step("setup: a dropdown stays within the row on a narrow screen", function() {
      var pinRow = find("configRow-modules.pin.background")
      var dd = find("configDropdown-modules.pin.background")
      var at = dd.mapToItem(pinRow, 0, 0)
      h.check("inside the row", at.x >= 0 && at.x + dd.width <= pinRow.width + 0.5, at.x + "+" + dd.width + " in " + pinRow.width)
      h.check("not collapsed", dd.width >= 100, dd.width)
      h.notes.loader.width = 900
    })
    h.wait(250)
    h.step("setup: the profile write", function() {
      h.eq("argv", JSON.stringify(writes()), JSON.stringify([["config", "set", "--", "modules.profile", "battery"]]))
      h.eq("Battery selected", find("configChoice-modules.profile-1").selected, true)
      h.eq("its apply note", D().backendsView.groups[0].rows[0].applyText, "Applies at next camera start")
      h.markLog()
      D().setCursor("config", 1)
      h.eq("the dropdown draws the one highlight", find("configDropdown-modules.pin.background").hasCursor + "/" + find("configRow-modules.pin.background").hasCursor, "true/false")
      // the mouse away from where the list opens (its rows follow the mouse)
      keys.mouseMove(find("setupTitle"), 1, 1)
      h.key(Qt.Key_Return)
    }, function() { return find("configDropdown-modules.pin.background").popupOpen })
    h.step("setup: the pin's list is open; Down, Enter", function() {
      h.eq("nothing written by opening it", writes().length, 0)
      h.key(Qt.Key_Down)
      h.key(Qt.Key_Return)
    }, function() { return writes().length >= 1 && !S().setupBusy && !find("configDropdown-modules.pin.background").popupOpen }, 8000)
    h.step("setup: a pin is a config write of the module's id", function() {
      h.eq("argv", JSON.stringify(writes()), JSON.stringify([["config", "set", "--", "modules.pin.background", "br.com.dias.maxine-vfx"]]))
      h.eq("the box shows the daemon's word", find("configDropdown-modules.pin.background").value, "br.com.dias.maxine-vfx")
      h.eq("its apply note", D().backendsView.groups[0].rows[1].applyText, "Applies at next camera start")
      h.check("the keyboard is the dialog's again", D().keyCatcher.activeFocus)
    })
    shot("setup-backends.png")
    // Daemon: rows by type
    h.step("setup: 4 shows Daemon", function() { h.key("4") }, function() { return D().section === "daemon" })
    h.wait(250)
    h.step("setup: Daemon", function() {
      h.eq("groups", D().daemonView.groups.map(function(g) { return g.id }).join(","), "output,lifecycle,pipewire,effect")
      h.eq("an overridden row is greyed, with its file", find("configNote-lifecycle.start_debounce_ms").text, "Overridden by config.d/90-local.toml")
      h.eq("shown as a value", find("configValue-lifecycle.start_debounce_ms").visible, true)
      h.eq("read-only rows show their value", find("configValue-output.mode").text, "1920x1080@30")
      h.eq("a path", find("configValue-effect.maxine_root").text, "/opt/maxine")
      h.eq("the stops: interactive rows only", D().stops.filter(function(x) { return x.kind === "config" }).length, 3)
      h.markLog()
      D().setCursor("config", 1)
      h.eq("the stepper row has the cursor", find("configRow-lifecycle.idle_grace_s").hasCursor, true)
      h.eq("a number reads as a spin box", find("configRow-lifecycle.idle_grace_s").Accessible.role, Accessible.SpinBox)
      h.eq("Less names its row", find("configLess-lifecycle.idle_grace_s").Accessible.name, "Less " + h.model.findConfigRow(S().setup.config, "lifecycle.idle_grace_s").label)
      h.eq("More names its row", find("configMore-lifecycle.idle_grace_s").Accessible.name, "More " + h.model.findConfigRow(S().setup.config, "lifecycle.idle_grace_s").label)
      var sw = find("configRow-pipewire.enabled")
      h.eq("a switch reads as a check box", sw.Accessible.role, Accessible.CheckBox)
      h.eq("checkable", sw.Accessible.checkable, true)
      h.eq("unchecked", sw.Accessible.checked, false)
      h.key(Qt.Key_Right)
    }, function() { return writes().length >= 1 && !S().setupBusy && h.model.findConfigRow(S().setup.config, "lifecycle.idle_grace_s").value === 8 }, 8000)
    h.step("setup: a number steps by a twentieth of its range", function() {
      h.eq("argv", JSON.stringify(writes()), JSON.stringify([["config", "set", "--", "lifecycle.idle_grace_s", "8"]]))
      h.eq("shown", find("configStepValue-lifecycle.idle_grace_s").text, "8 s")
      h.markLog()
      var r = find("configRow-pipewire.enabled")
      keys.mouseClick(r, r.width / 2, r.height / 2)
    }, function() { return writes().length >= 1 && !S().setupBusy && h.model.findConfigRow(S().setup.config, "pipewire.enabled").value === true }, 8000)
    h.step("setup: a switch row owns its click", function() {
      h.eq("argv", JSON.stringify(writes()), JSON.stringify([["config", "set", "--", "pipewire.enabled", "true"]]))
      h.eq("switch on", find("configSwitch-pipewire.enabled").checked, true)
      h.eq("apply note", D().daemonView.groups[2].rows[0].applyText, "Applies at next camera start")
    })
    shot("setup-daemon.png")
    // a refused write: the daemon's reason in the dialog, not the panel
    h.step("setup: a refused write", function() {
      h.writeFile("exit", ["1"])
      h.writeFile("stderr", ["omarchy-broadcast: Overridden by config.d/90-local.toml"])
    }, function() { return h.writerIdle() })
    h.step("setup: refused", function() {
      h.markLog()
      D().setCursor("config", 0)
      h.key(Qt.Key_Right)
      h.key(Qt.Key_Return)
    }, function() { return writes().length >= 1 && !S().setupBusy && D().statusText !== "" }, 8000)
    h.wait(400)
    h.step("setup: the reason shows on the dialog's status line", function() {
      h.eq("status", find("setupStatus").text, "The daemon refused the request: Overridden by config.d/90-local.toml")
      h.check("under the title, wrapped", find("setupStatus").y > find("setupTitle").y && find("setupStatus").wrapMode === Text.Wrap)
      h.eq("at most two lines", find("setupStatus").maximumLineCount, 2)
      h.eq("Saving… gone", find("setupSaving").text, "")
      h.eq("a refused write is read again once, all four reads", JSON.stringify(reads()),
           JSON.stringify(["modules list --json", "order show --json", "config show --json", "config files --json"]))
      h.eq("the panel's error untouched", S().commandError, "")
      h.writeFile("exit", ["0"])
      h.removeFile("stderr")
    }, function() { return h.writerIdle() })
    // Interface revision 12: output.mode is an editable enum of up to 16 options
    // the daemon computes: too many for buttons, so a dropdown
    h.step("setup: a revision-12 daemon publishes output.mode as an enum", function() {
      h.writeFile("config-show", setupConfigLines(true))
      h.feed(['{"v":1,"type":"config_changed","serial":50}'])
    }, function() {
      var r = h.model.findConfigRow(S().setup.config, "output.mode")
      return !!r && r.type === "enum" && !S().readArmed && S().readQueue.length === 0 && h.writerIdle()
    }, 8000)
    h.wait(250)
    h.step("setup: output.mode is a dropdown with its 16 options", function() {
      var row = D().daemonView.groups[0].rows[1]
      h.eq("the row", row.id + ":" + row.widget + ":" + row.options.length, "output.mode:dropdown:16")
      var dd = find("configDropdown-output.mode")
      h.eq("the box is shown", dd.visible, true)
      h.eq("no text value, no buttons", find("configValue-output.mode").visible + "/" + find("configChoices-output.mode").visible, "false/false")
      h.eq("its value and label", dd.value + "/" + dd.currentLabel(), "1920x1080@30/1920x1080 \u00b7 30 fps")
      h.eq("a generated rate keeps its words", dd.options[15].label, "1280x720 \u00b7 60 fps (generated)")
      h.eq("a combo box", find("configRow-output.mode").Accessible.role, Accessible.ComboBox)
      h.eq("its apply text", row.applyText, "Applies at next camera start")
      h.eq("the stops: the dropdown is one", D().stops.filter(function(x) { return x.kind === "config" }).length, 4)
      h.markLog()
      D().setCursor("config", 1)
      h.eq("the box draws the one highlight", dd.hasCursor + "/" + find("configRow-output.mode").hasCursor, "true/false")
      h.key(Qt.Key_Right)
      h.eq("Left/Right do not write", writes().length, 0)
      keys.mouseMove(find("setupTitle"), 1, 1)
      h.key(Qt.Key_Return)
    }, function() { return find("configDropdown-output.mode").popupOpen })
    h.step("setup: the output list is open; Down, Enter writes the mode", function() {
      h.eq("nothing written by opening it", writes().length, 0)
      h.key(Qt.Key_Down)
      h.key(Qt.Key_Return)
    }, function() { return writes().length >= 1 && !S().setupBusy && !find("configDropdown-output.mode").popupOpen }, 8000)
    h.step("setup: the dropdown wrote output.mode by config set", function() {
      h.eq("argv", JSON.stringify(writes()), JSON.stringify([["config", "set", "--", "output.mode", "1920x1080@60"]]))
      h.eq("the daemon's word shows", find("configDropdown-output.mode").value, "1920x1080@60")
      h.check("the keyboard is the dialog's again", D().keyCatcher.activeFocus)
      h.markLog()
      // the same value again writes nothing
      D().chooseConfigValue(D().daemonView.groups[0].rows[1], "1920x1080@60")
      h.eq("the current option is not written again", writes().length, 0)
      // a value that is not an option is refused before any command runs
      h.eq("an unknown value is refused", D().chooseConfigValue(D().daemonView.groups[0].rows[1], "800x600@30"), false)
      h.eq("nothing written", writes().length, 0)
    })
    shot("setup-output-mode.png")
    // back to the revision-10 daemon's read-only text, as the steps after expect
    h.step("setup: output.mode read-only again", function() {
      h.writeFile("config-show", setupConfigLines())
      h.feed(['{"v":1,"type":"config_changed","serial":51}'])
    }, function() {
      var r = h.model.findConfigRow(S().setup.config, "output.mode")
      return !!r && r.type === "string" && !S().readArmed && S().readQueue.length === 0 && h.writerIdle()
    }, 8000)
    h.wait(250)
    h.step("setup: an older daemon's output.mode is text", function() {
      h.eq("shown as a value", find("configValue-output.mode").visible, true)
      h.eq("no dropdown", find("configDropdown-output.mode").visible, false)
      h.eq("the stops again", D().stops.filter(function(x) { return x.kind === "config" }).length, 3)
    })
    // Diagnostics, read-only
    h.step("setup: 5 shows Diagnostics", function() { h.key("5") }, function() { return D().section === "diagnostics" })
    h.wait(250)
    h.step("setup: Diagnostics", function() {
      var d = D().diagnostics
      h.eq("revision", d.rows[0].value, "revision 10")
      h.eq("files in load order", d.files.map(function(f) { return f.path + ":" + f.statusText }).join(","),
           "config.toml:Loaded,config.d/50-panel.toml:Loaded,config.d/90-local.toml:Error")
      h.eq("the managed one", d.files[1].note, h.model.MANAGED_FILE_TEXT)
      h.eq("the error", d.files[2].reason, "line 3: unknown field `foo`")
      h.eq("problems", d.problems.map(function(p) { return p.title }).join("|"), "NVIDIA Maxine video effects|Hello btint/b")
      h.eq("a command to copy", find("diagnosticCommand").text, "omarchy-broadcast modules")
      h.eq("read-only", find("diagnosticCommand").readOnly, true)
      h.eq("no stops but the list", D().stops.length, 5)
      h.check("its sub-headings are section headers, uppercased", !!h.findByText(find("diagnosticsSection"), "MODULE PROBLEMS"))
      // a short screen, so the section does not fit
      h.notes.loader.height = 420
    })
    h.wait(250)
    h.step("setup: Diagnostics scrolls with the keys", function() {
      var f = find("setupFlick")
      h.check("does not fit", f.contentHeight > f.height + 0.5, f.contentHeight + " in " + f.height)
      h.eq("at the top", f.contentY, 0)
      h.key(Qt.Key_Down)
      h.check("Down scrolls", f.contentY > 0, f.contentY)
      var y = f.contentY
      h.key(Qt.Key_Up)
      h.check("Up scrolls back", f.contentY < y, f.contentY)
      h.key(Qt.Key_PageDown)
      h.check("PageDown scrolls a page", f.contentY > y, f.contentY)
      for (var i = 0; i < 6; i++) h.key(Qt.Key_PageDown)
      h.eq("never past the end", f.contentY, Math.max(0, f.contentHeight - f.height))
      h.key(Qt.Key_PageUp)
      h.check("PageUp scrolls back", f.contentY < Math.max(0, f.contentHeight - f.height), f.contentY)
      for (var j = 0; j < 6; j++) h.key(Qt.Key_PageUp)
      h.eq("never past the top", f.contentY, 0)
      h.key("1")
      h.notes.loader.height = 760
    })
    h.wait(250)
    h.step("setup: PageDown scrolls a section with stops too; Up/Down still walk them", function() {
      h.key("4")
      h.key(Qt.Key_Down)
      h.eq("the cursor, not a scroll", D().cursorActive, true)
      h.key("5")
      D().cursorActive = false
    })
    h.step("setup: selecting a command copies it", function() {
      var edit = find("diagnosticCommand")
      h.notes.copies = D().copies
      edit.select(0, "omarchy-broadcast".length)
    }, function() { return D().copies === h.notes.copies + 1 }, 3000)
    h.step("setup: copied", function() {
      var edit = find("diagnosticCommand")
      h.eq("what was copied", D().copiedText, "omarchy-broadcast")
      h.eq("said so", find("diagnosticCopied").text, "Copied: omarchy-broadcast")
      h.eq("the selection stays drawn", edit.persistentSelection, true)
      var probe = Qt.createQmlObject('import QtQuick; TextEdit { visible: false }', window.contentItem, "pasteProbe")
      probe.paste()
      h.eq("on the clipboard", probe.text, "omarchy-broadcast")
      probe.destroy()
      h.check("the keyboard is still the dialog's", D().keyCatcher.activeFocus)
      edit.deselect()
    })
    // a long warning (revision 12 sets several clauses) is drawn under its label, in full
    h.step("setup: Diagnostics with a long daemon warning", function() {
      var m = rev(10)
      m.warning = longWarning()
      h.feed([snapshotLine(m)])
    }, function() { return S().record.warning.indexOf("start it again") >= 0 })
    h.wait(250)
    h.step("setup: the warning wraps under its label", function() {
      var row = find("diagnosticRow-Daemon warning")
      var v = h.findByName(row, "infoValue")
      h.check("a row for it", !!row && !!v, "none")
      h.eq("the whole text", v.text, S().record.warning)
      h.check("wrapped onto several lines, none elided", v.lineCount > 2 && !v.truncated, v.lineCount + " lines")
      h.check("under the label, as wide as the row", v.y > 0 && Math.abs(v.width - row.width) < 0.5, v.y + ", " + v.width + " of " + row.width)
      h.check("the row is tall enough for it", row.height >= v.y + v.contentHeight - 0.5, row.height + " for " + (v.y + v.contentHeight))
      h.eq("a short value stays on its line", h.findByName(find("diagnosticRow-D-Bus API"), "infoValue").y, 0)
      var m = rev(10)
      h.feed([snapshotLine(m)])
    }, function() { return S().record.warning === "" })
    h.wait(250)
    shot("setup-diagnostics.png")
    // Escape closes through the shell; the reads stop
    h.step("setup: Escape", function() {
      h.markLog()
      h.key(Qt.Key_Escape)
    }, function() { return !D().shown })
    h.step("setup: closed through the shell's hide", function() {
      h.eq("hide called", fakeShell.hides.length, 1)
      h.eq("released", S().setupHeld, false)
      h.eq("data dropped", S().setup.modules, null)
      h.eq("not open", D().opened, false)
      h.notes.reads = S().setupReadRuns
      h.feed(['{"v":1,"type":"config_changed","serial":40}'])
    }, function() { return S().record.configSerial === 40 })
    h.wait(300)
    h.step("setup: no read while closed", function() { h.eq("reads", S().setupReadRuns, h.notes.reads) })
    // the panel hotkey: routed to the overlay, forwarded to a panel
    h.step("setup: the hotkey (empty payload) opens a bar panel", function() {
      fakeShell.toggle(shellRoot.moduleName, "")
      h.eq("a panel opened", A().opened || B().opened, true)
      h.eq("one only", A().opened && B().opened, false)
      h.eq("the dialog stays hidden", D().shown, false)
      h.eq("the plugin reports open", D().opened, true)
      fakeShell.toggle(shellRoot.moduleName, "")
      h.eq("the hotkey again closes it", A().opened || B().opened, false)
      fakeShell.toggle(shellRoot.moduleName, "{}")
      h.eq("the shell's togglePanelAt payload too", A().opened || B().opened, true)
      fakeShell.hide(shellRoot.moduleName)
      h.eq("hide closes it", A().opened || B().opened, false)
      h.eq("no reads", S().setupHeld, false)
    })
    // a revision-9 daemon: Modules and Order, no configuration
    h.step("setup: revision 9", function() {
      h.feed([snapshotLine(rev(9))])
    }, function() { return S().record.interfaceRevision === 9 })
    h.step("setup: reopened from the other monitor", function() {
      h.markLog()
      B().iconButton.triggerPress(Qt.RightButton)
    }, function() { return D().shown && loaded(["modules", "order"]) && !S().readArmed }, 8000)
    h.wait(300)
    h.step("setup: only the modules reads", function() {
      h.eq("reads", JSON.stringify(reads()), JSON.stringify(["modules list --json", "order show --json"]))
      h.eq("Modules work", D().modulesView.hint, "")
      h.eq("no configuration read kept from revision 10", S().setup.config, null)
      h.key("3")
      h.eq("Backends needs a newer daemon", find("setupHint").text, h.model.SETUP_OLD_CONFIG)
      h.key("4")
      h.eq("Daemon too", find("setupHint").text, h.model.SETUP_OLD_CONFIG)
      h.eq("no config stops", D().stops.length, 5)
      h.check("a config write is refused", !S().setConfig("pipewire.enabled", false))
    })
    shot("setup-revision-9.png")
    h.step("setup: revision 8", function() {
      h.markLog()
      h.feed([snapshotLine(rev(8))])
    }, function() { return S().record.interfaceRevision === 8 })
    h.wait(400)
    h.step("setup: the daemon needs updating", function() {
      h.eq("the modules reads of revision 9 are dropped", S().setup.modules, null)
      h.eq("and the order", S().setup.order, null)
      h.key("1")
      h.eq("hint", find("setupHint").text, h.model.SETUP_OLD_DAEMON)
      h.eq("no reads", reads().length, 0)
      h.eq("no module stops", D().stops.length, 5)
    })
    h.step("setup: the daemon goes away", function() {
      h.feed(['{"v":1,"type":"error","code":"daemon-not-running","error":"gone"}'])
    }, function() { return S().record.link === "not-running" })
    h.wait(250)
    h.step("setup: says so, with the start command", function() {
      h.eq("hint", find("setupHint").text, "omarchy-broadcastd is not running")
      h.key("5")
      h.eq("Diagnostics still shows", D().diagnostics.rows[1].value, "omarchy-broadcastd is not running")
    })
    shot("setup-unavailable.png")
    h.step("setup: close and clean up", function() {
      D().close()
      h.removeFile("modules-list")
      h.removeFile("order-show")
      h.removeFile("config-show")
      h.removeFile("config-files")
      h.removeFile("setup-serial")
      h.feed([snapshotLine({})])
    }, function() { return S().record.link === "ok" && S().record.interfaceRevision === 4 && h.writerIdle() })
    h.step("setup: the overlay goes", function() {
      h.eq("released", S().setupHeld, false)
      h.dialog = null
      h.notes.loader.destroy()
      h.notes.loader = null
    })
    // An overlay whose singleton no widget attached to (the plugin copy, at
    // another URL than the widgets): it runs the watch itself while shown,
    // with the CLI the resolver finds on PATH (the payload names none).
    h.step("setup: an overlay of a singleton with no widget", function() {
      var comp = Qt.createComponent("file://" + shellRoot.pluginCopy + "/SetupDialog.qml")
      h.notes.lone = comp.createObject(window.contentItem, { width: 900, height: 760 })
      h.check("another singleton", h.notes.lone.daemonService !== S())
      h.eq("no reader", h.notes.lone.daemonService.attachedCount, 0)
      // A payload that names a program is ignored: the dialog never runs one
      // a summoning process names.
      h.notes.lone.open('{"view":"setup","cliPath":"/tmp/x"}')
    }, function() { return h.notes.lone.shown && h.notes.lone.daemonService.record.link === "ok" }, 8000)
    h.step("setup: it attached and resolved the CLI from PATH", function() {
      var ls = h.notes.lone.daemonService
      h.eq("attached", h.notes.lone.attached, true)
      h.eq("one reader", ls.attachedCount, 1)
      h.eq("the resolver's CLI, the fake on PATH", ls.cliPath, shellRoot.cli)
      h.check("the payload's cliPath was not taken", ls.cliPath !== "/tmp/x")
      h.eq("the dialog is shown", h.notes.lone.shown, true)
      h.notes.lone.close()
      h.eq("detached on close", ls.attachedCount, 0)
      h.notes.lone.destroy()
      h.notes.lone = null
    })
    h.wait(800)
    h.countStep(1, "after the lone overlay closed")
    h.step("setup: back to one widget, as the checks after these expect", function() {
      B().destroy()
      h.widgetB = null
    }, function() { return S().attachedCount === 1 })
  }

  // ---- the background gallery (mock, interface revision 15) ---------------------
  //
  // The fake CLI's `media` commands, and bin/omarchy-menu-images and
  // bin/omarchy-file-select (tests/fake-*): fakes that print the path the
  // harness puts in gallery-pick / file-pick, or exit with gallery-exit /
  // file-exit, and log their argv to the same log as the CLI.
  readonly property string mediaBundled: "/usr/share/omarchy-broadcast/media/backgrounds"
  readonly property string mediaUser: "/home/u/Pictures/omarchy-broadcast"
  // The videos folder: the daemon's `video_dir` (revision 19); videos live here.
  readonly property string mediaVideo: "/home/u/Videos/omarchy-broadcast"
  // A video background's poster: the JPEG run-harness.sh puts where the
  // daemon keeps them.
  function mediaPosterPath() { return shellRoot.fakeDir + "/cache/omarchy-broadcast/posters/loop.jpg" }
  // `media list background --json`: the header, then one line per item.
  // `user`: true for the user's two (office.png in the pictures folder, the video loop.webm in the videos folder), else
  // a list of their names ("office", "loop"; false: none).
  function mediaListLines(user) {
    var items = [
      { path: mediaBundled + "/aurora.webp", label: "Aurora", bundled: true, media_type: "image", width: 3840, height: 2160, duration_ms: 0, poster: "" },
      { path: mediaBundled + "/dunes.webp", label: "Dunes", bundled: true, media_type: "image", width: 3840, height: 2160, duration_ms: 0, poster: "" }
    ]
    var own = user === true ? ["office", "loop"] : (Array.isArray(user) ? user : [])
    if (own.indexOf("office") >= 0)
      items.push({ path: mediaUser + "/office.png", label: "office <b>\u202e", bundled: false, media_type: "image",
                   width: 1920, height: 1080, duration_ms: 0, poster: "" })
    if (own.indexOf("loop") >= 0)
      items.push({ path: mediaVideo + "/loop.webm", label: "loop", bundled: false, media_type: "video",
                   width: 1920, height: 1080, duration_ms: 12400, poster: mediaPosterPath() })
    var out = [JSON.stringify({ v: 1, type: "media", kind: "background", serial: 1, bundled_dir: mediaBundled, user_dir: mediaUser,
                                video_dir: mediaVideo, items: items.length, items_truncated: false })]
    for (var i = 0; i < items.length; i++) {
      var it = { v: 1, type: "media_item", kind: "background" }
      for (var k in items[i]) it[k] = items[i][k]
      out.push(JSON.stringify(it))
    }
    return out
  }

  // A MediaThumbnail's placeholder glyph and video badge both inside it and
  // not overlapping each other.
  function thumbFits(thumb, what) {
    var glyph = h.findByName(thumb, thumb.objectName + "Placeholder")
    var badge = h.findByName(thumb, thumb.objectName + "VideoBadge")
    var g = glyph.mapToItem(thumb, 0, 0)
    var b = badge.mapToItem(thumb, 0, 0)
    var gw = glyph.contentWidth, gh = glyph.contentHeight
    var gx = g.x + (glyph.width - gw) / 2, gy = g.y + (glyph.height - gh) / 2
    h.check(what + " badge inside the frame", b.x >= 0 && b.y >= 0 && b.x + badge.width <= thumb.width && b.y + badge.height <= thumb.height,
            JSON.stringify([b.x, b.y, badge.width, badge.height, thumb.width, thumb.height]))
    h.check(what + " glyph inside the frame", gx >= 0 && gy >= 0 && gx + gw <= thumb.width && gy + gh <= thumb.height,
            JSON.stringify([gx, gy, gw, gh, thumb.width, thumb.height]))
    var apart = b.x >= gx + gw || gx >= b.x + badge.width || b.y >= gy + gh || gy >= b.y + badge.height
    h.check(what + " glyph and badge apart", apart, JSON.stringify({ glyph: [gx, gy, gw, gh], badge: [b.x, b.y, badge.width, badge.height] }))
  }

  function mediaScenario() {
    var A = function() { return h.widgetA }
    var S = function() { return h.widgetA.service }
    var C = function() { return h.content(A()) }
    var D = function() { return h.notes.mediaDialog }
    var dfind = function(name) { return h.findByName(D(), name) }
    var binDir = shellRoot.cli.slice(0, shellRoot.cli.lastIndexOf("/"))
    // the thumbnail: a real JPEG (one of the preview's frames)
    var current = shellRoot.fakeDir + "/frames/0.jpg"
    var rev = function(n) {
      return { interface_revision: n, settings_schema: 1, settings_revision: 5, loopback_consumers: 0, pipewire_consumers: 0,
               preview_consumers: 0, pipewire_output: "ready", config_serial: 1, modules_serial: 1, background_image: current }
    }
    var rows = function() {
      var g = function(id, type, label, v, d, o) {
        var x = { scope: "global" }
        for (var k in o) x[k] = o[k]
        return stateRow("background", "Background effect", id, type, label, v, d, x)
      }
      return [g("effect.background.mode", "enum", "Effect", "replace", "none", { options: "none:Off,blur:Blur,replace:Replace" })]
    }
    var args = function() { return h.newLogArgs().map(function(a) { return a.join(" ") }) }
    var has = function(text) { return args().indexOf(text) >= 0 }
    var kinds = function() { return C().stops.map(function(st) { return st.kind }).join(",") }
    var idle = function() { return !S().mediaBusy && !S().commandBusy }

    h.step("media: a revision-15 daemon offering the replacement background", function() {
      h.writeFile("settings-state", brioState().concat(rows()))
      h.writeFile("settings-camera", [brioId])
      h.writeFile("settings-rev", ["5"])
      h.writeFile("settings-serial", ["2"])
      h.writeFile("settings-mode", ["list"])
      h.writeFile("media-list", mediaListLines(true))
      h.removeFile("delay")
      h.removeFile("stderr")
      h.writeFile("exit", ["0"])
      h.removeFile("gallery-pick")
      h.removeFile("gallery-exit")
      h.removeFile("file-pick")
      h.removeFile("file-exit")
      h.feed([snapshotLine(rev(15))])
    }, function() {
      return S().record.interfaceRevision === 15 && !!S().record.settings && h.model.backgroundRowShown(S().record) && h.writerIdle()
    })
    h.step("media: open the panel's Effect tab", function() {
      A().open()
      h.tab(A(), "effect")
    }, function() { return A().opened && S().mediaTools.known && S().mediaTools.gallery !== "" })
    h.wait(400)
    h.step("media: the Background row: thumbnail, name, Gallery… and Add…", function() {
      h.eq("the tools are the harness's fakes", S().mediaTools.gallery + " " + S().mediaTools.chooser,
           binDir + "/omarchy-menu-images " + binDir + "/omarchy-file-select")
      h.eq("the row is shown", h.find(A(), "backgroundLine").visible, true)
      h.eq("the image's name", h.find(A(), "backgroundLabel").text, "0")
      h.eq("the thumbnail's source is the file's URL", String(h.find(A(), "backgroundImage").source), "file://" + current)
      h.eq("Gallery…", h.find(A(), "backgroundButton-0").text, "Gallery…")
      h.eq("Add…", h.find(A(), "backgroundButton-1").text, "Add…")
      h.eq("both offered", h.find(A(), "backgroundButton-0").opacity === 1 && h.find(A(), "backgroundButton-1").opacity === 1, true)
      h.eq("no hint", h.find(A(), "backgroundHint").visible, false)
      h.eq("the image loaded: no placeholder glyph", h.find(A(), "backgroundPlaceholder").visible, false)
      h.eq("no read-only image row", C().effectRows.length, 0)
      h.check("a stop after the effect row", kinds().indexOf("effect,background") >= 0, kinds())
    }, function() { return h.find(A(), "backgroundImage").status === Image.Ready }, 4000)
    h.grabStep(function() { return A().popup }, "m1-effect-background-row.png")

    h.step("media: Gallery… picks a bundled image (the picker open a second)", function() {
      h.writeFile("gallery-pick", [mediaBundled + "/aurora.webp"])
      h.writeFile("gallery-delay", ["1"])
    }, function() { return h.writerIdle() })
    h.step("media: Enter on Gallery…", function() {
      h.markLog()
      C().setCursor("background", -1)
      h.eq("the row has the cursor on Gallery…", h.find(A(), "backgroundButton-0").hasCursor, true)
      h.key(Qt.Key_Return)
    }, function() { return S().mediaBusy && S().mediaFlow.step === "pick" && args().some(function(a) { return a.indexOf("omarchy-menu-images --show-labels") === 0 }) }, 6000)
    h.step("media: the panel is closed while the picker runs", function() {
      h.eq("closed", A().opened, false)
      h.check("the flow remembers the widget it came from", S().mediaOpener === A())
    })
    h.step("media: the picker answers", function() {}, function() {
      return has("effect replace --image " + mediaBundled + "/aurora.webp") && idle() && A().opened
    }, 6000)
    h.step("media: listed, picked, selected, and the panel back", function() {
      h.eq("the panel opened again on its widget", A().opened, true)
      h.eq("the opener forgotten", S().mediaOpener, null)
      h.eq("the four commands, in order", JSON.stringify(args()), JSON.stringify([
        "media list background --json",
        "omarchy-menu-images --print-rows --show-labels " + mediaBundled + " " + mediaUser + " " + mediaVideo,
        "omarchy-menu-images --show-labels --selected " + current + " " + mediaBundled + " " + mediaUser + " " + mediaVideo,
        "effect replace --image " + mediaBundled + "/aurora.webp"]))
      h.eq("no error", S().commandError, "")
      h.removeFile("gallery-delay")
    }, function() { return h.writerIdle() })

    // a file the picker lists but the daemon skipped (a GIF in the user's
    // folder): refused, said on the panel's failure line once it is back
    h.step("media: the picker returns a file the gallery did not list", function() {
      h.writeFile("gallery-pick", [mediaUser + "/clip.gif"])
    }, function() { return h.writerIdle() })
    h.step("media: Gallery… from the open panel", function() {
      h.markLog()
      h.notes.steps = S().mediaSteps
      h.check("started", C().activateBackground(0))
    }, function() { return S().mediaSteps === h.notes.steps + 3 && idle() && A().opened }, 6000)
    h.wait(300)
    h.step("media: refused, and the panel shows why", function() {
      h.eq("no selection", args().filter(function(a) { return a.indexOf("effect") === 0 }).length, 0)
      h.eq("the failure line", S().commandError, h.model.GALLERY_REFUSED_TEXT)
      h.eq("seen in the reopened panel", h.find(A(), "commandError").text, "That file is not in the gallery; nothing was changed")
      h.eq("shown", h.find(A(), "commandErrorBlock").visible, true)
    })
    h.grabStep(function() { return A().popup }, "m1b-effect-gallery-refused.png")
    h.step("media: a cancel from the open panel", function() {
      h.removeFile("gallery-pick")
    }, function() { return h.writerIdle() })
    h.step("media: Gallery…, then closed without a choice", function() {
      h.notes.steps = S().mediaSteps
      h.check("started", C().activateBackground(0))
    }, function() { return S().mediaSteps === h.notes.steps + 3 && idle() && A().opened }, 6000)
    h.step("media: the panel is back after a cancel too", function() {
      h.eq("open", A().opened, true)
      A().close()
    }, function() { return !A().opened })

    // an empty gallery: neither the rows nor the picker is asked for (it
    // would show the desktop theme's backgrounds), and the panel says so
    h.step("media: an empty gallery", function() {
      h.writeFile("media-list", [JSON.stringify({ v: 1, type: "media", kind: "background", serial: 1, bundled_dir: mediaBundled,
                                                  user_dir: mediaUser, video_dir: mediaVideo, items: 0, items_truncated: false })])
      h.writeFile("gallery-pick", [mediaBundled + "/dunes.webp"])
    }, function() { return h.writerIdle() })
    h.step("media: Gallery… with nothing to choose from", function() {
      h.markLog()
      h.notes.steps = S().mediaSteps
      A().open()
      h.tab(A(), "effect")
      h.check("started", C().activateBackground(0))
    }, function() { return S().mediaSteps >= h.notes.steps + 1 && idle() && A().opened }, 6000)
    h.wait(300)
    h.step("media: listed, no picker, and the panel says why", function() {
      h.eq("only the list ran", JSON.stringify(args()), JSON.stringify(["media list background --json"]))
      h.eq("the failure line", S().commandError, "No backgrounds yet. Add one with Add…")
      h.eq("the fake picker was not invoked", h.logLines().slice(h.logMark).some(function(l) { return l.indexOf("[omarchy-menu-images]") >= 0 }), false)
      A().close()
    }, function() { return !A().opened })

    // items listed but the picker builds no row for them (its thumbnailer
    // failed: it prints an empty line): the picker is not run either
    h.step("media: items listed, the picker has no rows", function() {
      h.writeFile("media-list", mediaListLines(true))
      h.writeFile("gallery-rows", [""])
    }, function() { return h.writerIdle() })
    h.step("media: Gallery… with rows empty", function() {
      h.markLog()
      h.notes.steps = S().mediaSteps
      A().open()
      h.tab(A(), "effect")
      h.check("started", C().activateBackground(0))
    }, function() { return S().mediaSteps >= h.notes.steps + 2 && idle() && A().opened }, 6000)
    h.wait(300)
    h.step("media: listed, rows asked, no picker, and the panel says why", function() {
      h.eq("the list and the rows only", JSON.stringify(args()), JSON.stringify([
        "media list background --json",
        "omarchy-menu-images --print-rows --show-labels " + mediaBundled + " " + mediaUser + " " + mediaVideo]))
      h.eq("the failure line", S().commandError, "The picker cannot show any of the gallery's backgrounds. Add another with Add…")
      h.eq("the picker did not open", h.logLines().slice(h.logMark).filter(function(l) {
        return l.indexOf("[omarchy-menu-images]") >= 0 && l.indexOf("[--print-rows]") < 0 }).length, 0)
      A().close()
    }, function() { return !A().opened })
    h.step("media: the gallery back as it was", function() {
      h.removeFile("gallery-rows")
      h.removeFile("gallery-pick")
    }, function() { return h.writerIdle() })

    // the watchdog: a picker that never answers is stopped, and the buttons
    // say why they are faded meanwhile
    h.step("media: a picker that does not answer", function() {
      h.writeFile("gallery-pick", [mediaBundled + "/dunes.webp"])
      h.writeFile("gallery-delay", ["8"])
      S().mediaWatchdogMs = 1500
    }, function() { return h.writerIdle() })
    h.step("media: Gallery…, and the panel opened meanwhile", function() {
      h.markLog()
      h.check("started", S().openGallery())
    }, function() { return S().mediaBusy && S().mediaFlow.step === "pick" }, 6000)
    h.step("media: the panel opened by hand while it waits", function() {
      A().open()
      h.tab(A(), "effect")
    }, function() { return A().opened })
    h.wait(200)
    h.step("media: faded, and the hint says why", function() {
      h.eq("the hint", h.find(A(), "backgroundHint").text, h.model.GALLERY_WAITING_TEXT)
      h.eq("Gallery… faded", h.find(A(), "backgroundButton-0").opacity < 1, true)
      h.eq("Add… faded", h.find(A(), "backgroundButton-1").opacity < 1, true)
      h.check("a press does nothing", !C().activateBackground(1))
    })
    h.grabStep(function() { return A().popup }, "m1c-effect-waiting.png")
    h.step("media: the watchdog stops the picker", function() {}, function() { return !S().mediaBusy && idle() }, 6000)
    h.step("media: nothing selected, said on the failure line", function() {
      h.eq("no selection", args().filter(function(a) { return a.indexOf("effect") === 0 }).length, 0)
      h.eq("the failure line", S().commandError, h.model.MEDIA_TIMEOUT_TEXT)
      h.eq("the hint is gone", h.find(A(), "backgroundHint").visible, false)
      h.eq("the buttons are back", h.find(A(), "backgroundButton-0").opacity, 1)
      S().mediaWatchdogMs = h.model.MEDIA_WATCHDOG_MS
      h.removeFile("gallery-delay")
      h.removeFile("gallery-pick")
      A().close()
    }, function() { return h.writerIdle() && !A().opened })

    // no image to show: the placeholder glyph
    h.step("media: an image that does not load", function() {
      var r = rev(15)
      r.background_image = shellRoot.fakeDir + "/frames/missing.jpg"
      h.feed([snapshotLine(r)])
    }, function() { return S().record.backgroundImagePath.indexOf("missing.jpg") > 0 })
    h.step("media: open the panel", function() {
      A().open()
      h.tab(A(), "effect")
    }, function() { return A().opened && h.find(A(), "backgroundImage").status === Image.Error }, 4000)
    h.step("media: a faint image glyph in its place", function() {
      h.eq("the placeholder", h.find(A(), "backgroundPlaceholder").visible, true)
      h.eq("the shell's image glyph", h.find(A(), "backgroundPlaceholder").text, h.model.GLYPH_IMAGE)
      h.eq("still named", h.find(A(), "backgroundLabel").text, "missing")
      A().close()
      h.feed([snapshotLine(rev(15))])
    }, function() { return !A().opened && S().record.backgroundImagePath === current })

    h.step("media: the picker closed without a choice", function() {
      h.removeFile("gallery-pick")
    }, function() { return h.writerIdle() })
    h.step("media: Gallery… again", function() {
      h.markLog()
      h.notes.steps = S().mediaSteps
      h.check("started", S().openGallery())
    }, function() { return S().mediaSteps === h.notes.steps + 3 && idle() }, 6000)
    h.wait(300)
    h.step("media: a cancel runs nothing more", function() {
      h.eq("listed, rows and picked only", args().length, 3)
      h.eq("no selection", args().filter(function(a) { return a.indexOf("effect") === 0 }).length, 0)
      h.eq("no error", S().commandError, "")
    })

    h.step("media: the picker returns a file outside the gallery", function() {
      h.writeFile("gallery-pick", [mediaUser + "/../../../../.ssh/id_rsa"])
    }, function() { return h.writerIdle() })
    h.step("media: Gallery… once more", function() {
      h.markLog()
      h.notes.steps = S().mediaSteps
      S().openGallery()
    }, function() { return S().mediaSteps === h.notes.steps + 3 && idle() }, 6000)
    h.wait(300)
    h.step("media: refused, said on the failure line", function() {
      h.eq("no selection", args().filter(function(a) { return a.indexOf("effect") === 0 }).length, 0)
      h.eq("the failure line", S().commandError, h.model.GALLERY_REFUSED_TEXT)
      h.removeFile("gallery-pick")
    })

    h.step("media: Add… picks a file", function() {
      h.writeFile("file-pick", ["/home/u/Pictures/beach day.jpg"])
      h.writeFile("file-exit", ["0"])
    }, function() { return h.writerIdle() })
    h.step("media: Add…", function() {
      h.markLog()
      h.check("started", S().addBackground())
    }, function() { return has("media import background /home/u/Pictures/beach day.jpg --select") && idle() }, 6000)
    h.step("media: chosen, then imported and selected", function() {
      h.eq("the two commands", JSON.stringify(args()), JSON.stringify([
        "omarchy-file-select --title Add a background --extensions png jpg jpeg webp gif apng mp4 m4v mov mkv webm",
        "media import background /home/u/Pictures/beach day.jpg --select"]))
      h.eq("no error", S().commandError, "")
      h.writeFile("file-exit", ["1"])
    }, function() { return h.writerIdle() })
    h.step("media: Add…, nothing picked", function() {
      h.markLog()
      h.notes.steps = S().mediaSteps
      S().addBackground()
    }, function() { return S().mediaSteps === h.notes.steps + 1 && idle() }, 6000)
    h.wait(300)
    h.step("media: exit 1 is no error and imports nothing", function() {
      h.eq("the chooser only", args().length, 1)
      h.eq("no error", S().commandError, "")
      h.writeFile("file-exit", ["2"])
    }, function() { return h.writerIdle() })
    h.step("media: Add…, the chooser fails", function() {
      h.markLog()
      h.notes.steps = S().mediaSteps
      S().addBackground()
    }, function() { return S().mediaSteps === h.notes.steps + 1 && idle() }, 6000)
    h.wait(300)
    h.step("media: exit 2 is said on the failure line", function() {
      h.eq("the chooser only", args().length, 1)
      h.eq("the failure line", S().commandError, "The file chooser could not open")
      h.removeFile("file-pick")
      h.removeFile("file-exit")
      A().open()
      h.tab(A(), "effect")
    }, function() { return A().opened && h.writerIdle() })
    h.wait(300)
    h.grabStep(function() { return A().popup }, "m2-effect-chooser-failed.png")

    // a slow import (an animated GIF the daemon converts): a step of the
    // flow, beside the command queue, with the panel back and saying so
    h.step("media: Add… picks an animated GIF that takes a while", function() {
      A().close()
      h.writeFile("file-pick", ["/home/u/Pictures/party.gif"])
      h.writeFile("file-exit", ["0"])
      h.writeFile("import-delay", ["3"])
    }, function() { return h.writerIdle() && !A().opened })
    h.step("media: Add…, and the import runs", function() {
      h.markLog()
      A().open()
      h.tab(A(), "effect")
      h.check("started", C().activateBackground(1))
    }, function() { return S().mediaImporting && A().opened && has("media import background /home/u/Pictures/party.gif --select") }, 6000)
    h.wait(200)
    h.step("media: the panel is back while it imports, and says so", function() {
      h.eq("reopened at the import's start", A().opened, true)
      h.eq("the hint", h.find(A(), "backgroundHint").text, "Adding the background…")
      h.eq("the earlier failure cleared", S().commandError, "")
      h.eq("Gallery… faded", h.find(A(), "backgroundButton-0").opacity < 1, true)
      h.eq("Add… faded", h.find(A(), "backgroundButton-1").opacity < 1, true)
      h.check("a press does nothing", !C().activateBackground(0))
      h.eq("no command queued: an on/off would not wait behind it", S().commandBusy || S().toggleBusy, false)
    })
    h.grabStep(function() { return A().popup }, "m2b-effect-importing.png")
    h.step("media: the import ends", function() {}, function() { return idle() }, 8000)
    h.step("media: imported, no error, the hint gone", function() {
      h.eq("the two commands", JSON.stringify(args()), JSON.stringify([
        "omarchy-file-select --title Add a background --extensions png jpg jpeg webp gif apng mp4 m4v mov mkv webm",
        "media import background /home/u/Pictures/party.gif --select"]))
      h.eq("no error", S().commandError, "")
      h.eq("the hint is gone", h.find(A(), "backgroundHint").visible, false)
      h.eq("the buttons are back", h.find(A(), "backgroundButton-1").opacity, 1)
      h.writeFile("import-delay", ["8"])
      S().mediaWatchdogMs = 1500
    }, function() { return h.writerIdle() })
    // an import that never ends: the watchdog stops it
    h.step("media: Add…, an import that does not end", function() {
      h.check("started", C().activateBackground(1))
    }, function() { return S().mediaImporting }, 6000)
    h.step("media: the watchdog stops the import", function() {}, function() { return idle() }, 8000)
    h.step("media: said on the failure line", function() {
      h.eq("the failure line", S().commandError, h.model.MEDIA_IMPORT_TIMEOUT_TEXT)
      h.eq("seen in the panel", h.find(A(), "commandError").text, h.model.MEDIA_IMPORT_TIMEOUT_TEXT)
      S().mediaWatchdogMs = h.model.MEDIA_WATCHDOG_MS
      h.removeFile("import-delay")
      h.writeFile("stderr", ["omarchy-broadcast: animated images need ffmpeg"])
      h.writeFile("exit", ["1"])
    }, function() { return h.writerIdle() })
    // the daemon refuses it (no ffmpeg): its reason on the failure line
    h.step("media: Add…, the daemon refuses the file", function() {
      h.notes.steps = S().mediaSteps
      h.check("started", C().activateBackground(1))
    }, function() { return S().mediaSteps === h.notes.steps + 2 && idle() }, 6000)
    h.step("media: the daemon's reason", function() {
      h.eq("the failure line", S().commandError, "The daemon refused the request: animated images need ffmpeg")
      h.removeFile("stderr")
      h.writeFile("exit", ["0"])
      h.removeFile("file-pick")
      h.removeFile("file-exit")
    }, function() { return h.writerIdle() })

    // a video background: its poster (from the gallery just read) and the badge
    h.step("media: Gallery… picks the video", function() {
      h.writeFile("gallery-pick", [mediaVideo + "/loop.webm"])
    }, function() { return h.writerIdle() })
    h.step("media: Gallery…, the video selected", function() {
      h.markLog()
      h.check("started", C().activateBackground(0))
    }, function() { return has("effect replace --image " + mediaVideo + "/loop.webm") && idle() && A().opened }, 6000)
    h.step("media: the daemon reports the video in force", function() {
      h.removeFile("gallery-pick")
      var r = rev(15)
      r.background_image = mediaVideo + "/loop.webm"
      h.feed([snapshotLine(r)])
    }, function() { return S().record.backgroundImagePath === mediaVideo + "/loop.webm" && h.find(A(), "backgroundImage").status === Image.Ready }, 4000)
    h.step("media: the poster, badged", function() {
      h.eq("the gallery read is kept", S().backgroundMedia.items.length, 4)
      h.eq("the poster's URL", String(h.find(A(), "backgroundImage").source), "file://" + mediaPosterPath())
      h.eq("the badge", h.find(A(), "backgroundVideoBadge").visible, true)
      h.eq("no placeholder", h.find(A(), "backgroundPlaceholder").visible, false)
      h.eq("its name", h.find(A(), "backgroundLabel").text, "loop")
    })
    h.grabStep(function() { return A().popup }, "m2c-effect-video-background.png")
    h.step("media: a video the gallery does not list", function() {
      var r = rev(15)
      r.background_image = "/home/u/Videos/talk.mp4"
      h.feed([snapshotLine(r)])
    }, function() { return S().record.backgroundImagePath === "/home/u/Videos/talk.mp4" })
    h.wait(200)
    h.step("media: the poster-less video's thumbnail: glyph and badge apart", function() {
      thumbFits(h.find(A(), "background"), "the panel's")
      h.eq("its accessible name says video", h.find(A(), "background").Accessible.name, "Background image: talk, video")
    })
    h.grabStep(function() { return h.find(A(), "background") }, "m2d-panel-video-no-poster.png")
    h.step("media: badged by its name, the placeholder glyph", function() {
      h.eq("nothing loaded", String(h.find(A(), "backgroundImage").source), "")
      h.eq("the placeholder", h.find(A(), "backgroundPlaceholder").visible, true)
      h.eq("the badge", h.find(A(), "backgroundVideoBadge").visible, true)
      h.eq("the shell's video-file glyph", h.find(A(), "backgroundVideoBadge").children[0].text, h.model.GLYPH_FILE_VIDEO)
      h.feed([snapshotLine(rev(15))])
    }, function() { return S().record.backgroundImagePath === current })
    h.step("media: a still again: no badge", function() {}, function() { return h.find(A(), "backgroundImage").status === Image.Ready })
    h.step("media: the badge is gone", function() {
      h.eq("no badge", h.find(A(), "backgroundVideoBadge").visible, false)
    })

    // the setup dialog's Backgrounds section
    h.step("media: the setup dialog", function() {
      A().close()
      h.writeFile("media-list-removed", mediaListLines(["loop"]))
      var comp = Qt.createComponent("file://" + shellRoot.pluginPath + "/SetupDialog.qml")
      h.notes.mediaDialog = comp.createObject(window.contentItem, { width: 900, height: 760 })
      D().shell = fakeShell
      D().manifest = { id: shellRoot.moduleName }
      h.check("the widgets' singleton", D().daemonService === S())
      h.markLog()
      D().open(h.model.setupPayloadJson())
    }, function() { return D().shown && S().setup.media !== null && !S().readArmed && S().readQueue.length === 0 && h.writerIdle() }, 8000)
    h.step("media: Backgrounds, the fifth of six sections", function() {
      h.eq("the sections", D().sectionWords.join(","), "modules,order,backends,daemon,backgrounds,diagnostics")
      h.check("the gallery was read", has("media list background --json"), JSON.stringify(args()))
      h.key("5")
      h.eq("shown", D().section, "backgrounds")
      h.eq("the section", dfind("backgroundsSection").visible, true)
      h.eq("the bundled count", dfind("backgroundsBundled").text, "2 bundled backgrounds")
      h.eq("the folders' note", dfind("backgroundsFolder").text, "Your own backgrounds are kept in these folders; files you copy there appear here:")
      h.eq("the pictures folder, on its own line", dfind("backgroundsFolderPath").text, mediaUser)
      h.eq("the videos folder, on its own line", dfind("backgroundsVideoFolderPath").text, mediaVideo)
      h.eq("broken anywhere", dfind("backgroundsVideoFolderPath").wrapMode, Text.WrapAnywhere)
      h.check("the videos path under the pictures path", dfind("backgroundsVideoFolderPath").y > dfind("backgroundsFolderPath").y)
      h.eq("two of the user's own", D().mediaView.rows.length, 2)
      h.eq("its name, sanitised", dfind("mediaLabel-0").text, "office b")
      h.eq("Remove", dfind("mediaRemove-0").text, "Remove")
      h.eq("the still's size", dfind("mediaSize-0").text, "1920×1080")
      h.eq("the video's name", dfind("mediaLabel-1").text, "loop")
      h.eq("the video's size and length", dfind("mediaSize-1").text, "1920×1080, video, 0:12")
      h.eq("the still: no badge", dfind("mediaThumb-0VideoBadge").visible, false)
      h.eq("the video: badged", dfind("mediaThumb-1VideoBadge").visible, true)
      h.eq("its poster", String(dfind("mediaThumb-1Image").source), "file://" + mediaPosterPath())
      h.eq("Remove for the video too", dfind("mediaRemove-1").text, "Remove")
    }, function() { return !!dfind("mediaThumb-1Image") && dfind("mediaThumb-1Image").status === Image.Ready
                           && dfind("mediaThumb-0Image").status !== Image.Loading }, 4000)
    h.grabStep(function() { return dfind("setupCard") }, "m3-setup-backgrounds.png")
    // a video without a poster yet, at the dialog's thumbnail size: the
    // row's own thumbnail with its poster taken away
    h.step("media: the dialog's poster-less video thumbnail", function() {
      h.eq("its accessible name says video", dfind("mediaThumb-1").Accessible.name, "loop, video")
      h.eq("the still's does not", dfind("mediaThumb-0").Accessible.name, "office b")
      h.notes.thumbSource = dfind("mediaThumb-1").source
      dfind("mediaThumb-1").source = ""
    }, function() { return dfind("mediaThumb-1Image").status === Image.Null })
    h.step("media: glyph and badge apart in the dialog's row", function() {
      h.eq("the placeholder", dfind("mediaThumb-1Placeholder").visible, true)
      thumbFits(dfind("mediaThumb-1"), "the dialog's")
    })
    h.grabStep(function() { return dfind("mediaThumb-1") }, "m3b-setup-video-no-poster.png")
    h.step("media: the row's poster back", function() {
      dfind("mediaThumb-1").source = Qt.binding(function() { return D().shown && D().section === "backgrounds" ? D().mediaView.rows[1].source : "" })
    }, function() { return dfind("mediaThumb-1Image").status === Image.Ready })
    // a video the CPU path cannot play (revision 19): the daemon's convert
    // command, shown under its row with a Copy button of its own
    h.step("media: a video that is not CPU-ready, from a revision-19 daemon", function() {
      h.notes.convert = "ffmpeg -i '" + mediaVideo + "/loop.webm' -c:v libvpx-vp9 -an '" + mediaVideo + "/loop-vp9.webm'"
      var lines = mediaListLines(true).map(function(l) {
        var o = JSON.parse(l)
        if (o.type === "media_item" && o.media_type === "video") { o.cpu_ready = false; o.convert_command = h.notes.convert }
        return JSON.stringify(o)
      })
      h.writeFile("media-list", lines)
      h.feed([snapshotLine(rev(19))])
    }, function() { return S().record.interfaceRevision === 19 && h.writerIdle() })
    h.step("media: the dialog reads again", function() { S().refreshSetup() },
           function() { return !S().readArmed && S().readQueue.length === 0 && D().mediaView.rows.length === 2 && D().mediaView.rows[1].convertCommand !== "" }, 6000)
    h.wait(300)
    h.step("media: the note, the command and Copy under the video's row", function() {
      h.eq("the note", dfind("mediaConvertNote-1").text, "Without an NVIDIA GPU this video shows as a still. To play it without one, convert it in a terminal; the copy lands in your videos folder:")
      h.eq("the command", dfind("mediaConvertCommand-1").text, h.notes.convert)
      h.eq("monospace", dfind("mediaConvertCommand-1").font.family, "monospace")
      h.eq("breaks anywhere", dfind("mediaConvertCommand-1").wrapMode, TextEdit.WrapAnywhere)
      h.eq("Copy", dfind("mediaCopy-1").text, "Copy")
      h.eq("shown", dfind("mediaConvert-1").visible, true)
      h.eq("none under the still", dfind("mediaConvert-0").visible, false)
      h.check("under its row", dfind("mediaConvert-1").mapToItem(dfind("mediaEntry-1"), 0, 0).y >= dfind("mediaRow-1").height)
      h.check("inside the card", dfind("mediaCopy-1").mapToItem(dfind("setupCard"), 0, 0).x + dfind("mediaCopy-1").width <= dfind("setupCard").width)
      h.eq("not copied yet", dfind("mediaCopied-1").text, "")
    })
    h.grabStep(function() { return dfind("setupCard") }, "m3c-setup-convert-command.png")
    h.step("media: Down from Remove lands on Copy, Enter copies the command", function() {
      D().setCursor("media-remove", 1)
      h.key(Qt.Key_Down)
      h.eq("on the Copy stop", D().hasCursor("media-copy", 1), true)
      h.eq("the Copy button has the cursor", dfind("mediaCopy-1").hasCursor, true)
      h.notes.copies = D().copies
      h.key(Qt.Key_Return)
      h.eq("one copy", D().copies, h.notes.copies + 1)
      h.eq("what was copied", D().copiedText, h.notes.convert)
      h.eq("said so", dfind("mediaCopied-1").text, "Copied")
      h.eq("nothing else ran", args().filter(function(a) { return a.indexOf("media remove") === 0 }).length, 0)
    })
    h.wait(500)
    h.step("media: no second copy from the selection", function() {
      h.eq("still one", D().copies, h.notes.copies + 1)
    })
    h.step("media: a mouse click on Copy copies it too", function() {
      D().copiedText = ""
      h.notes.copies = D().copies
      dfind("mediaCopy-1").clicked()
    }, function() { return D().copies === h.notes.copies + 1 && D().copiedText === h.notes.convert }, 3000)
    h.step("media: back to the revision-15 gallery", function() {
      h.writeFile("media-list", mediaListLines(true))
      h.feed([snapshotLine(rev(15))])
    }, function() { return S().record.interfaceRevision === 15 && h.writerIdle() })
    h.step("media: the dialog reads again, without the command", function() { S().refreshSetup() },
           function() { return !S().readArmed && S().readQueue.length === 0 && D().mediaView.rows.length === 2 && D().mediaView.rows[1].convertCommand === "" }, 6000)
    h.step("media: no convert block", function() {
      h.eq("hidden", dfind("mediaConvert-1").visible, false)
      h.eq("no note", dfind("mediaConvertNote-1").text, "")
    })

    h.step("media: Remove pressed once, then the mouse moves off it", function() {
      D().setCursor("media-remove", 0)
      h.key(Qt.Key_Return)
      h.eq("asks for the second press", dfind("mediaRemove-0").text, "Confirm remove")
      // what hovering a section entry does
      D().setCursor("section", 0)
      h.eq("forgotten on hover", D().confirmRemove, "")
      h.eq("the button says Remove again", dfind("mediaRemove-0").text, "Remove")
      D().setCursor("media-remove", 0)
      h.key(Qt.Key_Return)
      h.eq("asks again", dfind("mediaRemove-0").text, "Confirm remove")
      h.key(Qt.Key_Left)
      h.eq("Left back to the list forgets it", D().confirmRemove, "")
      h.eq("on the list", D().currentStop.kind, "section")
      h.eq("Remove again", dfind("mediaRemove-0").text, "Remove")
    })
    h.step("media: Remove, pressed once, asks again", function() {
      h.markLog()
      D().setCursor("media-remove", 0)
      h.key(Qt.Key_Return)
      h.eq("asks for the second press", dfind("mediaRemove-0").text, "Confirm remove")
      h.eq("nothing removed yet", args().filter(function(a) { return a.indexOf("media remove") === 0 }).length, 0)
      h.key(Qt.Key_Return)
    }, function() { return args().some(function(a) { return a.indexOf("media remove") === 0 }) }, 6000)
    h.step("media: removed, and the section read again", function() {
      h.eq("the remove", JSON.stringify(args().filter(function(a) { return a.indexOf("media remove") === 0 })),
           JSON.stringify(["media remove " + mediaUser + "/office.png"]))
      h.eq("the video left", dfind("mediaLabel-0").text, "loop")
      h.writeFile("media-list-removed", mediaListLines(false))
    }, function() { return !S().setupBusy && !S().readArmed && D().mediaView.rows.length === 1 && h.writerIdle() }, 6000)
    h.step("media: the video removed the same way", function() {
      h.markLog()
      D().setCursor("media-remove", 0)
      h.key(Qt.Key_Return)
      h.eq("asks for the second press", dfind("mediaRemove-0").text, "Confirm remove")
      h.key(Qt.Key_Return)
    }, function() { return args().some(function(a) { return a.indexOf("media remove") === 0 }) }, 6000)
    h.step("media: the video removed, and the section read again", function() {
      h.eq("the remove", JSON.stringify(args().filter(function(a) { return a.indexOf("media remove") === 0 })),
           JSON.stringify(["media remove " + mediaVideo + "/loop.webm"]))
    }, function() { return !S().setupBusy && !S().readArmed && D().mediaView.rows.length === 0 }, 6000)
    h.step("media: none of the user's own left", function() {
      h.eq("no hint block", dfind("setupHintBlock").visible, false)
      h.eq("still the bundled count", dfind("backgroundsBundled").text, "2 bundled backgrounds")
      h.eq("the empty note", dfind("backgroundsEmpty").text, h.model.MEDIA_EMPTY_TEXT)
      h.check("under the bundled count", dfind("backgroundsEmpty").y > dfind("backgroundsBundled").y)
      h.eq("no dialog error", S().setupError, "")
    })

    awayCases(D, dfind, rev, args, has, idle)
    batterySaverCases(D, dfind, rev, has, idle)

    // a revision-14 daemon: no Background row, no section, the old row back
    h.step("media: revision 14", function() {
      h.feed([snapshotLine(rev(14))])
    }, function() { return S().record.interfaceRevision === 14 && !!S().record.settings })
    h.wait(300)
    h.step("media: the dialog hides Backgrounds", function() {
      h.eq("the sections", D().sectionWords.join(","), "modules,order,backends,daemon,diagnostics")
      h.eq("back to the first", D().section, "modules")
      h.eq("the gallery read dropped", S().setup.media, null)
      D().close()
      D().destroy()
      h.notes.mediaDialog = null
      A().open()
      h.tab(A(), "effect")
    }, function() { return A().opened })
    h.wait(400)
    h.step("media: the panel shows the read-only image row instead", function() {
      h.eq("no Background row", h.find(A(), "backgroundLine").visible, false)
      h.eq("the read-only row", JSON.stringify(C().effectRows.map(function(r) { return r.label })), JSON.stringify(["Background image"]))
      h.check("no background stop", kinds().indexOf("background") < 0, kinds())
      h.check("Gallery… refused", !S().openGallery())
      h.check("Add… refused", !S().addBackground())
    })
    h.step("media: clean up", function() {
      A().close()
      h.removeFile("settings-mode")
      h.removeFile("settings-state")
      h.removeFile("media-list")
      h.removeFile("media-list-removed")
      h.removeFile("gallery-delay")
      h.feed([snapshotLine({})])
    }, function() { return S().record.link === "ok" && S().record.interfaceRevision === 4 && h.writerIdle() })
  }

  // ---- the away image (mock, interface revision 17) ------------------------------
  //
  // Inside the media scenario, with its dialog open: the away gallery's two
  // directories (the bundled one holds the preview's real JPEGs, so the
  // thumbnail loads), the configuration rows of a revision-17 daemon
  // (`output.placeholder`, an editable `effect.fallback_image`), and those
  // of a revision-16 one (the read-only row).
  function awayBundledDir() { return shellRoot.fakeDir + "/frames" }
  readonly property string awayUserDir: "/home/u/Pictures/omarchy-broadcast/away"
  function awayListLines() {
    var items = [
      { path: awayBundledDir() + "/0.jpg", label: "Be right back", bundled: true, media_type: "image", width: 480, height: 270, duration_ms: 0, poster: "" },
      { path: awayUserDir + "/me.png", label: "me", bundled: false, media_type: "image", width: 1280, height: 720, duration_ms: 0, poster: "" }
    ]
    var out = [JSON.stringify({ v: 1, type: "media", kind: "away", serial: 1, bundled_dir: awayBundledDir(), user_dir: awayUserDir,
                                items: items.length, items_truncated: false })]
    for (var i = 0; i < items.length; i++) {
      var it = { v: 1, type: "media_item", kind: "away" }
      for (var k in items[i]) it[k] = items[i][k]
      out.push(JSON.stringify(it))
    }
    return out
  }
  // The rows that hide the camera when an effect cannot run. Below revision
  // 21 (`privacy` undefined) the one `effect.on_failure` enum; from it the
  // switch `effect.privacy` and its enum `effect.privacy_mode`, which the
  // daemon greys with a reason while the switch is off and offers
  // "Away image" only with an image set (or while it is the value in force).
  // `privacy`: { on, mode }.
  function failureRows(privacy, image) {
    if (privacy === undefined)
      return [cfg("effect.on_failure", "enum", "black", { label: "When an effect can't run", "default": "black",
                  options: [{ value: "black", label: "Hide the camera: black" }, { value: "none", label: "Show the camera" }] })]
    var modes = [{ value: "black", label: "Black" }]
    if (image !== "" || privacy.mode === "away") modes.push({ value: "away", label: "Away image" })
    modes.push({ value: "freeze", label: "Last frame" })
    var mode = cfg("effect.privacy_mode", "enum", privacy.mode, { label: "Show instead of the camera", "default": "black", options: modes })
    if (!privacy.on) { mode.enabled = false; mode.disabled_reason = "Turn on \"Hide the camera when an effect can't run\" to change this" }
    return [cfg("effect.privacy", "bool", privacy.on, { label: "Hide the camera when an effect can't run", "default": false }), mode]
  }
  // `editable`: revision 17's rows; else revision 16's (no placeholder row,
  // the image read-only). `o`: more fields of the image's row. `privacy`:
  // revision 21's rows (failureRows), else the old row.
  function awayConfigLines(editable, image, o, privacy) {
    var imageRow = editable
      ? cfg("effect.fallback_image", "path", image, { label: "Away image", description: "The image that stands in for the camera" })
      : cfg("effect.fallback_image", "path", image, { label: "Fallback image", editable: false, description: "Set it in the configuration file." })
    for (var k in o) imageRow[k] = o[k]
    var output = [cfg("output.format", "enum", "nv12", { label: "Format", options: [{ value: "nv12", label: "NV12" }, { value: "yuyv", label: "YUYV" }] })]
    if (editable) output.push(cfg("output.placeholder", "enum", "black", { label: "When there is no camera picture", "default": "black",
                                   options: [{ value: "black", label: "Black" }, { value: "image", label: "Away image" }] }))
    var groups = [
      { id: "output", label: "Output", settings: output },
      { id: "effect", label: "Effect", settings: failureRows(privacy, image).concat([imageRow]) }
    ]
    var raw = []
    for (var g = 0; g < groups.length; g++)
      raw.push({ v: 1, type: "config_group", schema: 1, serial: 9, part: 1, parts: 1, group: groups[g] })
    for (var i = 0; i < raw.length; i++) { raw[i].index = i; raw[i].count = raw.length }
    return raw.map(function(x) { return JSON.stringify(x) })
  }

  function awayCases(D, dfind, rev, args, has, idle) {
    var A = function() { return h.widgetA }
    var S = function() { return h.widgetA.service }
    var C = function() { return h.content(A()) }
    var row = function() { return h.model.findConfigRow(S().setup.config, h.model.AWAY_IMAGE_KEY) }
    var stopOf = function(id) {
      var groups = D().daemonView.groups
      for (var g = 0; g < groups.length; g++)
        for (var r = 0; r < groups[g].rows.length; r++) if (groups[g].rows[r].id === id) return groups[g].rows[r].stop
      return -2
    }
    var settled = function() { return idle() && !S().setupBusy && !S().readArmed && S().readQueue.length === 0 && h.writerIdle() }
    var brb = awayBundledDir() + "/0.jpg"

    h.step("away: a revision-17 daemon, no away image yet", function() {
      h.writeFile("config-show", awayConfigLines(true, ""))
      h.writeFile("media-list-away", awayListLines())
      h.writeFile("setup-serial", ["1"])
      h.removeFile("gallery-pick")
      h.removeFile("file-pick")
      h.removeFile("file-exit")
      h.feed([snapshotLine(rev(17))])
    }, function() { return S().record.interfaceRevision === 17 && row() !== null && settled() }, 8000)
    h.step("away: the Daemon section draws the image's row as a picker", function() {
      h.key("4")
      h.eq("shown", D().section, "daemon")
      h.eq("the row", dfind("awayLine").visible, true)
      h.eq("its widget", h.model.configViewRow(D().daemonView, stopOf("effect.fallback_image")).widget, "away")
      h.eq("no image", dfind("awayName").text, h.model.AWAY_NONE_TEXT)
      h.eq("the glyph", dfind("awayPlaceholder").visible, true)
      h.eq("Choose…", dfind("awayButton-0").text, "Choose…")
      h.eq("Add…", dfind("awayButton-1").text, "Add…")
      h.eq("Clear", dfind("awayButton-2").text, "Clear")
      h.eq("Clear faded: nothing to clear", dfind("awayButton-2").opacity < 1, true)
      h.eq("Choose… offered", dfind("awayButton-0").opacity, 1)
      h.eq("no text value", dfind("configValue-effect.fallback_image").visible, false)
      h.eq("the placeholder switch: the generic chips", dfind("configChoices-output.placeholder").visible, true)
      h.eq("its two choices", dfind("configChoice-output.placeholder-1").text, "Away image")
      h.eq("the picker the next stop after the switch", stopOf("effect.fallback_image"), stopOf("output.placeholder") + 1)
      h.eq("in the Output group", D().daemonView.groups[0].rows.map(function(r) { return r.id }).join(","),
           "output.format,output.placeholder,effect.fallback_image")
      var chips = dfind("configChoices-output.placeholder")
      var line = dfind("awayLine")
      var gap = line.mapToItem(null, 0, 0).y - chips.mapToItem(null, 0, chips.height).y
      h.check("drawn directly under the chips (" + gap + " px)", gap >= 0 && gap < 80)
      h.eq("no note: the switch is on Black", dfind("awayNote").visible, false)
    })
    h.step("away: Left/Right skip the faded Clear", function() {
      D().setCursor("config", stopOf("effect.fallback_image"))
      h.eq("landed on Choose…", D().awayCursor, 0)
      h.key(Qt.Key_Right)
      h.eq("Add…", D().awayCursor, 1)
      h.key(Qt.Key_Right)
      h.eq("still Add…: Clear is faded", D().awayCursor, 1)
      h.eq("the cursor drawn on Add…", dfind("awayButton-1").hasCursor, true)
      h.eq("not on Clear", dfind("awayButton-2").hasCursor, false)
      h.key(Qt.Key_Left)
      h.eq("back to Choose…", D().awayCursor, 0)
    })
    h.grabStep(function() { return dfind("setupCard") }, "a1-setup-away-row.png")

    h.step("away: Choose… picks a bundled away image (the picker open a second)", function() {
      h.writeFile("gallery-pick", [brb])
      h.writeFile("gallery-delay", ["1"])
    }, function() { return h.writerIdle() })
    h.step("away: Enter on Choose…", function() {
      h.markLog()
      D().setCursor("config", stopOf("effect.fallback_image"))
      h.eq("the cursor on Choose…", dfind("awayButton-0").hasCursor, true)
      h.key(Qt.Key_Return)
    }, function() { return S().mediaBusy && S().mediaFlow.step === "pick" }, 6000)
    h.step("away: the dialog is hidden while the picker runs", function() {
      h.eq("suspended", D().suspended, true)
      h.eq("still open for the shell", D().opened, true)
      h.eq("the flow's gallery", S().mediaFlow.gallery, "away")
    })
    h.step("away: the picker answers", function() {}, function() {
      return has("config set -- effect.fallback_image " + brb) && settled() && row().rawPath === brb
    }, 8000)
    h.step("away: listed, picked, set, and the dialog back", function() {
      h.eq("the four commands, in order", JSON.stringify(args().filter(function(a) { return a.indexOf("--json") < 0 || a === "media list away --json" })), JSON.stringify([
        "media list away --json",
        "omarchy-menu-images --print-rows --show-labels " + awayBundledDir() + " " + awayUserDir,
        "omarchy-menu-images --show-labels " + awayBundledDir() + " " + awayUserDir,
        "config set -- effect.fallback_image " + brb]))
      h.eq("shown again", D().suspended, false)
      h.eq("no dialog error", S().setupError, "")
      h.eq("no panel error", S().commandError, "")
      h.eq("the image's name", dfind("awayName").text, "0")
      h.eq("Clear offered", dfind("awayButton-2").opacity, 1)
      h.removeFile("gallery-delay")
    }, function() { return dfind("awayImage").status === Image.Ready }, 4000)
    h.step("away: the thumbnail", function() {
      h.eq("its source", String(dfind("awayImage").source), "file://" + brb)
      h.eq("no glyph", dfind("awayPlaceholder").visible, false)
    })
    h.grabStep(function() { return dfind("setupCard") }, "a2-setup-away-chosen.png")

    h.step("away: the picker returns a file the gallery did not list", function() {
      h.writeFile("gallery-pick", [awayUserDir + "/clip.gif"])
    }, function() { return h.writerIdle() })
    h.step("away: Choose…", function() {
      h.markLog()
      h.notes.steps = S().mediaSteps
      h.check("started", D().activateAway(0))
    }, function() { return S().mediaSteps === h.notes.steps + 3 && settled() }, 6000)
    h.step("away: refused, said on the dialog's status line", function() {
      h.eq("nothing set", args().filter(function(a) { return a.indexOf("config set") === 0 }).length, 0)
      h.eq("the dialog's error", S().setupError, h.model.GALLERY_REFUSED_TEXT)
      h.eq("not the panel's", S().commandError, "")
      h.eq("shown", D().statusText, h.model.GALLERY_REFUSED_TEXT)
      h.eq("still the image", row().rawPath, brb)
      h.removeFile("gallery-pick")
    })

    h.step("away: Add… picks a file", function() {
      h.writeFile("file-pick", ["/home/u/Pictures/me at desk.png"])
      h.writeFile("file-exit", ["0"])
    }, function() { return h.writerIdle() })
    h.step("away: Add…", function() {
      h.markLog()
      h.check("started", S().addAwayImage())
    }, function() { return has("media import away /home/u/Pictures/me at desk.png --select") && settled()
                            && row().rawPath === shellRoot.fakeDir + "/away-user/me at desk.png" }, 8000)
    h.step("away: chosen, imported and set", function() {
      h.eq("the two commands", JSON.stringify(args().filter(function(a) { return a.indexOf("--json") < 0 })), JSON.stringify([
        "omarchy-file-select --title Add an away image --extensions png jpg jpeg webp",
        "media import away /home/u/Pictures/me at desk.png --select"]))
      h.eq("no error", S().setupError, "")
      h.eq("the stored file's name", dfind("awayName").text, "me at desk")
      h.removeFile("file-pick")
      h.removeFile("file-exit")
    })

    h.step("away: Clear", function() {
      h.markLog()
      h.check("cleared", D().activateAway(2))
    }, function() { return args().indexOf("config set -- effect.fallback_image ") >= 0 && settled() && row().value === "" }, 6000)
    h.step("away: no away image again", function() {
      h.eq("the empty value", JSON.stringify(h.newLogArgs().filter(function(a) { return a[0] === "config" && a[1] === "set" })),
           JSON.stringify([["config", "set", "--", "effect.fallback_image", ""]]))
      h.eq("no image", dfind("awayName").text, h.model.AWAY_NONE_TEXT)
      h.check("Clear refused now", !S().clearAwayImage())
    })
    h.step("away: Away image when there is no camera picture", function() {
      h.markLog()
      D().setCursor("config", stopOf("output.placeholder"))
      h.check("chosen", D().chooseConfig(h.model.configViewRow(D().daemonView, stopOf("output.placeholder")), 1))
    }, function() { return has("config set -- output.placeholder image") && settled()
                            && h.model.findConfigRow(S().setup.config, "output.placeholder").value === "image" }, 6000)
    h.step("away: no image while the switch shows it: the note says black", function() {
      h.eq("shown", dfind("awayNote").visible, true)
      h.eq("its words", dfind("awayNote").text, h.model.AWAY_UNSET_TEXT)
    })
    h.grabStep(function() { return dfind("setupCard") }, "a1b-setup-away-unset.png")

    // the panel's Away image row: Setup… opens the dialog at the picker
    h.step("away: the panel's Away image row, under More", function() {
      D().close()
      h.dialog = D()
      fakeShell.toggles = []
      A().open()
      h.tab(A(), "effect")
    }, function() { return A().opened && !D().shown })
    h.step("away: More folded by default: one line, the row hidden", function() {
      h.eq("More shown", h.find(A(), "moreLine").visible, true)
      h.eq("the row hidden", h.find(A(), "awayLine").visible, false)
      h.check("More is a stop, the row is not", C().stops.map(function(st) { return st.kind }).join(",").indexOf("more") >= 0
              && C().stops.map(function(st) { return st.kind }).indexOf("away") < 0)
      C().setCursor("more", -1)
      h.key(Qt.Key_Return)
    }, function() { return C().moreOpen })
    h.wait(300)
    h.step("away: shown under the Background row, a stop of its own", function() {
      h.eq("the row", h.find(A(), "awayLine").visible, true)
      h.eq("its label", h.find(A(), "awayLabel").text, "Away image")
      h.eq("the button", h.find(A(), "awayButton").visible, true)
      h.eq("its text", h.find(A(), "awayButton").text, "Setup…")
      h.eq("its tooltip", h.find(A(), "awayButton").tooltipText, "The image shown instead of the camera: choose it in the setup")
      h.check("the button on the right", h.find(A(), "awayButton").x > h.find(A(), "awayLabel").x)
      h.check("after the Background row", h.find(A(), "awayLine").mapToItem(C(), 0, 0).y > h.find(A(), "backgroundLine").mapToItem(C(), 0, 0).y)
      h.check("under More", h.find(A(), "awayLine").mapToItem(C(), 0, 0).y > h.find(A(), "moreLine").mapToItem(C(), 0, 0).y)
    })
    h.grabStep(function() { return A().popup }, "a2b-panel-away-row.png")
    h.step("away: Enter on Setup…", function() {
      h.check("a stop after More", C().stops.map(function(st) { return st.kind }).join(",").indexOf("more,away") >= 0)
      C().setCursor("away", -1)
      h.key(Qt.Key_Return)
    }, function() { return D().shown && !A().opened && D().currentStop !== null && D().currentStop.kind === "config" && settled() }, 8000)
    h.step("away: the dialog opens at the away image's row", function() {
      h.eq("one toggle, with the row's key", JSON.parse(fakeShell.toggles[0].payload).focus, "effect.fallback_image")
      h.eq("the Daemon section", D().section, "daemon")
      h.eq("the cursor on the row", D().currentStop.index, stopOf("effect.fallback_image"))
      h.eq("on Choose…", dfind("awayButton-0").hasCursor, true)
      h.eq("the focus asked for is done", D().pendingFocus, "")
      h.dialog = null
    })
    h.grabStep(function() { return dfind("setupCard") }, "a3-setup-away-focus.png")

    // revision 21: effect.on_failure is replaced by a switch and its mode
    h.step("privacy: a revision-21 daemon, privacy off", function() {
      h.writeFile("config-show", awayConfigLines(true, "", undefined, { on: false, mode: "black" }))
      h.feed([snapshotLine(rev(21))])
    }, function() { return S().record.interfaceRevision === 21 && h.model.findConfigRow(S().setup.config, "effect.privacy") !== null && settled() }, 8000)
    h.step("privacy: the switch, then its greyed mode as text with the reason", function() {
      h.key("4")
      h.eq("the Daemon section", D().section, "daemon")
      h.eq("the rows in the Effect group", D().daemonView.groups[1].rows.map(function(r) { return r.id }).join(","),
           "effect.privacy,effect.privacy_mode")
      h.eq("no on_failure row", stopOf("effect.on_failure"), -2)
      h.eq("the label", dfind("configSwitch-effect.privacy").visible, true)
      h.eq("the switch is off", dfind("configSwitch-effect.privacy").checked, false)
      h.eq("the mode is text", dfind("configValue-effect.privacy_mode").visible, true)
      h.eq("its value", dfind("configValue-effect.privacy_mode").text, "Black")
      h.eq("no chips", dfind("configChoices-effect.privacy_mode").visible, false)
      h.eq("the reason", dfind("configNote-effect.privacy_mode").text, "Turn on \"Hide the camera when an effect can't run\" to change this")
      h.eq("no keyboard stop", stopOf("effect.privacy_mode"), -1)
      h.check("the mode under the switch", dfind("configValue-effect.privacy_mode").mapToItem(null, 0, 0).y
              > dfind("configSwitch-effect.privacy").mapToItem(null, 0, 0).y)
    })
    h.grabStep(function() { return dfind("setupCard") }, "a4-setup-privacy-off.png")
    h.step("privacy: Enter on the switch writes the new key", function() {
      h.markLog()
      D().setCursor("config", stopOf("effect.privacy"))
      h.key(Qt.Key_Return)
    }, function() { return has("config set -- effect.privacy true") && settled()
                            && h.model.findConfigRow(S().setup.config, "effect.privacy").value === true }, 6000)
    h.step("privacy: the mode is live, as chips, without Away image (no image)", function() {
      h.eq("the daemon's one write", JSON.stringify(h.newLogArgs().filter(function(a) { return a[0] === "config" && a[1] === "set" })),
           JSON.stringify([["config", "set", "--", "effect.privacy", "true"]]))
      h.eq("the switch is on", dfind("configSwitch-effect.privacy").checked, true)
      h.eq("chips", dfind("configChoices-effect.privacy_mode").visible, true)
      h.eq("Black", dfind("configChoice-effect.privacy_mode-0").text, "Black")
      h.eq("Last frame", dfind("configChoice-effect.privacy_mode-1").text, "Last frame")
      h.eq("no third chip: no image, no Away image", dfind("configChoice-effect.privacy_mode-2"), null)
      h.eq("no reason", dfind("configNote-effect.privacy_mode").text, "")
      h.eq("a stop", stopOf("effect.privacy_mode"), stopOf("effect.privacy") + 1)
      h.eq("no note: nothing shows the image", dfind("awayNote").visible, false)
    })
    h.grabStep(function() { return dfind("setupCard") }, "a5-setup-privacy-on.png")
    h.step("privacy: Last frame writes the mode", function() {
      h.markLog()
      D().setCursor("config", stopOf("effect.privacy_mode"))
      h.check("chosen", D().chooseConfig(h.model.configViewRow(D().daemonView, stopOf("effect.privacy_mode")), 1))
    }, function() { return has("config set -- effect.privacy_mode freeze") && settled()
                            && h.model.findConfigRow(S().setup.config, "effect.privacy_mode").value === "freeze" }, 6000)
    h.step("privacy: the choice is marked", function() {
      h.eq("Last frame selected", dfind("configChoice-effect.privacy_mode-1").selected, true)
      h.eq("no dialog error", S().setupError, "")
    })
    h.step("privacy: switched off again, the mode greys", function() {
      h.markLog()
      D().setCursor("config", stopOf("effect.privacy"))
      h.key(Qt.Key_Return)
    }, function() { return has("config set -- effect.privacy false") && settled()
                            && h.model.findConfigRow(S().setup.config, "effect.privacy_mode").enabled === false }, 6000)
    h.step("privacy: greyed with its reason, its value still read", function() {
      h.eq("text", dfind("configValue-effect.privacy_mode").text, "Last frame")
      h.eq("the reason", dfind("configNote-effect.privacy_mode").text, "Turn on \"Hide the camera when an effect can't run\" to change this")
      h.eq("no stop", stopOf("effect.privacy_mode"), -1)
    })

    // revision 16: the old read-only row, no button
    h.step("away: revision 16", function() {
      h.writeFile("config-show", awayConfigLines(false, "/home/u/Pictures/away.png"))
      h.feed([snapshotLine(rev(16))])
    }, function() { return S().record.interfaceRevision === 16 && row() !== null && row().label === "Fallback image" && settled() }, 8000)
    h.step("away: the read-only image row stays", function() {
      h.eq("no picker", dfind("awayLine"), null)
      h.eq("the text value", dfind("configValue-effect.fallback_image").visible, true)
      h.eq("its path", dfind("configValue-effect.fallback_image").text, "/home/u/Pictures/away.png")
      h.eq("no stop", stopOf("effect.fallback_image"), -1)
      h.eq("no placeholder row", stopOf("output.placeholder"), -2)
      h.check("Choose… refused", !S().chooseAwayImage())
      h.check("Add… refused", !S().addAwayImage())
      h.check("Clear refused", !S().clearAwayImage())
      D().close()
      A().open()
      h.tab(A(), "effect")
    }, function() { return A().opened })
    h.wait(300)
    h.step("away: no button in the panel", function() {
      h.eq("hidden", h.find(A(), "awayLine").visible, false)
      h.check("no stop", C().stops.map(function(st) { return st.kind }).indexOf("away") < 0)
      h.check("pressing does nothing", !C().openAwayImage())
      A().close()
      h.markLog()
      D().open(h.model.setupPayloadJson())
    }, function() { return D().shown && settled() }, 8000)
    h.step("away: back to Backgrounds, as the steps after these expect", function() {
      h.key("5")
      h.eq("shown", D().section, "backgrounds")
      h.removeFile("config-show")
      h.removeFile("media-list-away")
      h.removeFile("setup-serial")
      h.feed([snapshotLine(rev(15))])
    }, function() { return S().record.interfaceRevision === 15 && settled() }, 8000)
  }

  // ---- the battery saver (mock, interface revision 22) ---------------------------
  //
  // After the away image's cases, with the dialog open at revision 15: the
  // configuration rows of a revision-22 daemon (`video.memory` and
  // `video.battery_saver`, whose mode is a dropdown of four options and
  // whose description ends with "Now: ..."), the panel's switch on the Effect
  // tab (revision gate, writes, the remembered mode, greyed while the
  // memory is not automatic) and the daemon's notice in the panel and in the
  // dialog, and the Mode dropdown under the switch (three modes at revision
  // 22, four with `auto` at 23, a mode it cannot offer shown read-only).
  // Ends as it began.
  readonly property string batteryNow: "Now: on battery, the camera runs without the NVIDIA GPU"
  // `auto`: the row of a revision-23 daemon, whose options include `auto`.
  function batteryConfigLines(mode, auto) {
    var modes = [{ value: "off", label: "Off" }, { value: "on_battery", label: "On battery" },
                 { value: "power_profile", label: "Follow the power profile" }, { value: "always", label: "Always" }]
    if (auto === true) modes.splice(1, 0, { value: "auto", label: "On battery or power-saver" })
    var memory = cfg("video.memory", "enum", "auto", { label: "Video processing", "default": "auto", apply: "reload",
                     options: [{ value: "auto", label: "Automatic" }, { value: "gpu", label: "GPU memory" }, { value: "host", label: "System memory" }] })
    var saver = cfg("video.battery_saver", "enum", mode, { label: "Battery saver", "default": "on_battery", apply: "reload",
                    description: "Run the camera without the NVIDIA GPU to save power. " + batteryNow, options: modes, notice: "" })
    var raw = [{ v: 1, type: "config_group", schema: 1, serial: 11, part: 1, parts: 1, index: 0, count: 1,
                 group: { id: "video", label: "Video processing", settings: [memory, saver] } }]
    return raw.map(function(x) { return JSON.stringify(x) })
  }

  function batterySaverCases(D, dfind, rev, has, idle) {
    var A = function() { return h.widgetA }
    var S = function() { return h.widgetA.service }
    var C = function() { return h.content(A()) }
    var row = function() { return h.model.findConfigRow(S().setup.config, "video.battery_saver") }
    var kinds = function() { return C().stops.map(function(st) { return st.kind }) }
    var settled = function() { return idle() && !S().setupBusy && !S().readArmed && S().readQueue.length === 0 && h.writerIdle() }
    var writesOf = function(key) {
      return JSON.stringify(h.newLogArgs().filter(function(a) { return a[0] === "config" && a[1] === "set" && a[3] === key })
                                           .map(function(a) { return a[4] }))
    }

    // below revision 22 the row is not offered, though the daemon's file has it
    h.step("battery: a revision-21 daemon, the panel on the Effect tab", function() {
      D().close()
      h.dialog = D()
      h.writeFile("config-show", batteryConfigLines("power_profile"))
      h.feed([snapshotLine(rev(21))])
    }, function() { return S().record.interfaceRevision === 21 && !D().shown })
    h.step("battery: open the panel", function() {
      A().open()
      h.tab(A(), "effect")
    }, function() { return A().opened })
    h.wait(500)
    h.step("battery: no switch, no stop, nothing read for it", function() {
      h.eq("hidden", h.find(A(), "batteryBlock").visible, false)
      h.check("no stop", kinds().indexOf("battery") < 0, kinds())
      h.eq("the panel holds the configuration", S().configHolders.length, 1)
      h.eq("but reads nothing", S().setup.config, null)
      h.check("refused", !C().toggleBatterySaver())
    })

    // revision 22: the panel reads the configuration on its own
    h.step("battery: a revision-22 daemon, in Follow the power profile", function() {
      h.markLog()
      h.feed([snapshotLine(rev(22))])
    }, function() { return S().record.interfaceRevision === 22 && row() !== null && settled() }, 8000)
    h.step("battery: only the configuration was read, by the panel", function() {
      h.eq("the read", JSON.stringify(h.newLogArgs().filter(function(a) { return a[a.length - 1] === "--json" && a[0] !== "watch" && a[0] !== "preview" }).map(function(a) { return a.join(" ") })),
           JSON.stringify(["config show --json"]))
      h.eq("no modules read", S().setup.modules, null)
    })
    h.wait(300)
    h.step("battery: the switch under the Away image row, on, with what is in force", function() {
      h.eq("shown", h.find(A(), "batteryBlock").visible, true)
      h.eq("its label", h.find(A(), "batteryLabel").text, "Battery saver")
      h.eq("on", h.find(A(), "batterySwitch").checked, true)
      h.eq("interactive", h.find(A(), "batterySwitch").interactive, true)
      h.eq("the daemon's Now, on hover and for the screen reader", h.find(A(), "batterySwitch").Accessible.description, shellRoot.batteryNow)
      h.eq("no Now line", h.find(A(), "batteryNow"), null)
      h.eq("no reason", h.find(A(), "batteryReason").visible, false)
      h.eq("no notice", h.find(A(), "batteryNotice").visible, false)
      h.eq("no error", h.find(A(), "batteryError").visible, false)
      h.check("a stop", kinds().indexOf("battery") >= 0, kinds())
      h.check("under More, after the Background row", h.find(A(), "batteryBlock").mapToItem(C(), 0, 0).y > h.find(A(), "moreLine").mapToItem(C(), 0, 0).y
              && h.find(A(), "moreLine").mapToItem(C(), 0, 0).y > h.find(A(), "backgroundLine").mapToItem(C(), 0, 0).y)
      h.eq("the saved mode is the default", A().storedBatteryMode, "on_battery")
    })
    h.grabStep(function() { return A().popup }, "b1-panel-battery-saver-on.png")

    // off: writes off, and remembers the mode that was in force
    h.step("battery: the switch turned off", function() {
      h.markLog()
      h.find(A(), "batterySwitch").toggled()
    }, function() { return has("config set -- video.battery_saver off") && settled() && row().value === "off" }, 8000)
    h.step("battery: off written once, Follow the power profile remembered in the settings", function() {
      h.eq("one write", writesOf("video.battery_saver"), JSON.stringify(["off"]))
      h.eq("off", h.find(A(), "batterySwitch").checked, false)
      h.eq("stored", A().settings.batterySaverMode, "power_profile")
      h.eq("the widget holds it", A().storedBatteryMode, "power_profile")
      h.eq("the shell was written", JSON.stringify(fakeShell.calls[fakeShell.calls.length - 1].entry.batterySaverMode), JSON.stringify("power_profile"))
    })
    h.grabStep(function() { return A().popup }, "b2-panel-battery-saver-off.png")
    h.step("battery: turned on again, it writes the remembered mode", function() {
      h.markLog()
      C().setCursor("battery", -1)
      h.key(Qt.Key_Return)
    }, function() { return has("config set -- video.battery_saver power_profile") && settled() && row().value === "power_profile" }, 8000)
    h.step("battery: on, the mode as it was", function() {
      h.eq("on", h.find(A(), "batterySwitch").checked, true)
      h.eq("one write", writesOf("video.battery_saver"), JSON.stringify(["power_profile"]))
    })

    // the Mode dropdown: three modes at revision 22, the daemon's mode while on
    var dd = function() { return h.find(A(), "batteryModeDropdown") }
    var calls = 0
    h.step("battery: one row: the label, the mode, the switch; three modes at revision 22", function() {
      var rowItem = h.find(A(), "batteryRow")
      var mid = function(it) { return it.mapToItem(C(), 0, it.height / 2).y }
      h.check("the dropdown on the switch's row", Math.abs(mid(dd()) - mid(h.find(A(), "batterySwitch"))) < 2
              && Math.abs(mid(dd()) - mid(rowItem)) < 2, mid(dd()) + " vs " + mid(h.find(A(), "batterySwitch")))
      h.check("between the label and the switch", dd().mapToItem(C(), 0, 0).x > h.find(A(), "batteryLabel").mapToItem(C(), 0, 0).x
              && dd().mapToItem(C(), dd().width, 0).x < h.find(A(), "batterySwitch").mapToItem(C(), 0, 0).x)
      h.eq("three", JSON.stringify(dd().options.map(function(o) { return o.value })), JSON.stringify(["on_battery", "power_profile", "always"]))
      h.eq("the plugin's labels", JSON.stringify(dd().options.map(function(o) { return o.label })), JSON.stringify(["On battery", "Follow the power profile", "Always"]))
      h.eq("the daemon's mode", dd().value, "power_profile")
      h.eq("live", dd().enabled, true)
      h.eq("a stop right after the switch", kinds()[kinds().indexOf("battery") + 1], "battery-mode")
    })
    h.step("battery: Enter on the Mode stop opens the list (Left/Right do nothing)", function() {
      h.markLog()
      calls = fakeShell.calls.length
      C().setCursor("battery-mode", -1)
      h.key(Qt.Key_Right)
      h.key(Qt.Key_Left)
      h.eq("the box draws the cursor", dd().hasCursor, true)
      keys.mouseMove(h.find(A(), "batteryLabel"), 1, 1)
      h.key(Qt.Key_Return)
    }, function() { return dd().popupOpen }, 3000)
    h.step("battery: Down, Enter: Always, while on", function() {
      h.eq("nothing written by opening it", writesOf("video.battery_saver"), "[]")
      h.key(Qt.Key_Down)
      h.key(Qt.Key_Return)
    }, function() { return has("config set -- video.battery_saver always") && settled() && row().value === "always" && !dd().popupOpen }, 8000)
    h.step("battery: one write, the mode stored, the keyboard the panel's again", function() {
      h.eq("one write", writesOf("video.battery_saver"), JSON.stringify(["always"]))
      h.eq("stored", A().settings.batterySaverMode, "always")
      h.eq("one settings write", fakeShell.calls.length, calls + 1)
      h.eq("the box shows the daemon's word", dd().value, "always")
      h.eq("still on", h.find(A(), "batterySwitch").checked, true)
      h.check("the keyboard is the panel's again", h.catcher(A()).activeFocus)
    })
    h.step("battery: the Mode dropdown is a combo box named for the setting", function() {
      h.eq("role", dd().Accessible.role, Accessible.ComboBox)
      h.eq("name", dd().Accessible.name, "Battery saver mode")
    })

    // Enter opens the list, Escape closes it: nothing chosen, nothing written
    h.step("battery: Enter opens the Mode list again", function() {
      h.markLog()
      calls = fakeShell.calls.length
      C().setCursor("battery-mode", -1)
      h.key(Qt.Key_Return)
    }, function() { return dd().popupOpen }, 3000)
    h.step("battery: Escape closes it", function() {
      h.key(Qt.Key_Down)
      h.key(Qt.Key_Escape)
    }, function() { return !dd().popupOpen }, 3000)
    h.wait(300)
    h.step("battery: closed with no choice: no write, the keyboard the panel's again", function() {
      h.eq("no write", writesOf("video.battery_saver"), "[]")
      h.eq("no settings write", fakeShell.calls.length, calls)
      h.eq("the mode as it was", dd().value, "always")
      h.eq("the panel still open", A().opened, true)
      h.check("the keyboard is the panel's again", h.catcher(A()).activeFocus)
    })

    // a setup write running: the dropdown takes no choice, none is dropped silently
    h.step("battery: a slow CLI", function() { h.writeFile("delay", ["0.8"]) }, function() { return settled() })
    h.step("battery: while the switch's write runs, the dropdown takes no choice", function() {
      h.markLog()
      calls = fakeShell.calls.length
      h.find(A(), "batterySwitch").toggled()
      h.check("busy", S().setupBusy)
      h.eq("not interactive while busy", dd().enabled, false)
      h.check("a choice is refused", !C().chooseBatteryMode("on_battery"))
      dd().changed("on_battery")
      h.check("the list does not open", !C().openBatteryModes())
    }, function() { return has("config set -- video.battery_saver off") && settled() && row().value === "off" }, 8000)
    h.step("battery: only the switch's write, the remembered mode unchanged", function() {
      h.removeFile("delay")
      h.eq("one write", writesOf("video.battery_saver"), JSON.stringify(["off"]))
      h.eq("still remembered", A().settings.batterySaverMode, "always")
      h.eq("shown", dd().value, "always")
      h.eq("interactive again", dd().enabled, true)
    })
    h.step("battery: turned on again, Always", function() {
      h.markLog()
      h.find(A(), "batterySwitch").toggled()
    }, function() { return has("config set -- video.battery_saver always") && settled() && row().value === "always" }, 8000)

    // revision 23: four modes, auto first
    h.step("battery: a revision-23 daemon whose row offers auto", function() {
      h.writeFile("config-show", batteryConfigLines("always", true))
      h.writeFile("setup-serial", ["900"])
      h.feed([snapshotLine(rev(23)), '{"v":1,"type":"config_changed","serial":900}'])
    }, function() { return S().record.interfaceRevision === 23 && settled() && row() !== null && h.model.configOptionIndex(row().options, "auto") >= 0 }, 8000)
    h.wait(300)
    h.step("battery: four modes, the one in force shown", function() {
      h.eq("four", JSON.stringify(dd().options.map(function(o) { return o.value })), JSON.stringify(["auto", "on_battery", "power_profile", "always"]))
      h.eq("auto's label", dd().options[0].label, "On battery or power saver")
      h.eq("the daemon's mode", dd().value, "always")
    })
    h.grabStep(function() { return A().popup }, "b1b-panel-battery-saver-mode.png")
    h.step("battery: turned off, at revision 23", function() {
      h.markLog()
      h.find(A(), "batterySwitch").toggled()
    }, function() { return has("config set -- video.battery_saver off") && settled() && row().value === "off" }, 8000)
    h.step("battery: off, the dropdown shows the remembered mode; choose auto", function() {
      h.eq("the remembered mode", dd().value, "always")
      h.eq("live while off", dd().enabled, true)
      calls = fakeShell.calls.length
      h.markLog()
      dd().changed("auto")
    })
    h.wait(400)
    h.step("battery: no daemon write while off, auto stored and shown", function() {
      h.eq("no write", writesOf("video.battery_saver"), "[]")
      h.eq("stored", A().settings.batterySaverMode, "auto")
      h.eq("the widget reads it as auto", A().storedBatteryMode, "auto")
      h.eq("one settings write", fakeShell.calls.length, calls + 1)
      h.eq("shown", dd().value, "auto")
      h.eq("still off", h.find(A(), "batterySwitch").checked, false)
    })
    h.step("battery: turned on, it writes the mode chosen", function() {
      h.markLog()
      h.find(A(), "batterySwitch").toggled()
    }, function() { return has("config set -- video.battery_saver auto") && settled() && row().value === "auto" }, 8000)
    h.step("battery: auto written once", function() {
      h.eq("one write", writesOf("video.battery_saver"), JSON.stringify(["auto"]))
      h.eq("shown", dd().value, "auto")
    })

    // auto seen from a revision-22 view: read-only, the daemon's label
    h.step("battery: the daemon at revision 22 again, its mode auto", function() {
      h.writeFile("setup-serial", ["910"])
      h.feed([snapshotLine(rev(22)), '{"v":1,"type":"config_changed","serial":910}'])
    }, function() { return S().record.interfaceRevision === 22 && settled() && row().value === "auto" }, 8000)
    h.wait(300)
    h.step("battery: the mode in force shown read-only, nothing chosen", function() {
      h.eq("the daemon's label", dd().options.length === 1 ? dd().options[0].label : JSON.stringify(dd().options), "On battery or power-saver")
      h.eq("its word", dd().value, "auto")
      h.eq("not interactive", dd().enabled, false)
      h.eq("not faded", dd().opacity, 1.0)
      h.eq("the switch on", h.find(A(), "batterySwitch").checked, true)
      h.eq("the widget reads auto as on_battery", A().storedBatteryMode, "on_battery")
      h.markLog()
      calls = fakeShell.calls.length
      h.check("refused", !C().chooseBatteryMode("always"))
      dd().changed("always")
      C().setCursor("battery-mode", -1)
      h.key(Qt.Key_Return)
    })
    h.wait(300)
    h.step("battery: no list, no write, nothing stored", function() {
      h.eq("no list", dd().popupOpen, false)
      h.eq("no write", writesOf("video.battery_saver"), "[]")
      h.eq("no settings write", fakeShell.calls.length, calls)
    })
    h.step("battery: the switch still turns it off", function() {
      h.markLog()
      h.find(A(), "batterySwitch").toggled()
    }, function() { return has("config set -- video.battery_saver off") && settled() && row().value === "off" }, 8000)
    h.step("battery: off, remembering nothing", function() {
      h.eq("no settings write", fakeShell.calls.length, calls)
      h.eq("the session's auto reads as on_battery here", dd().value, "on_battery")
    })
    h.step("battery: back to Follow the power profile, on, at revision 22", function() {
      h.writeFile("config-show", batteryConfigLines("power_profile"))
      h.writeFile("setup-serial", ["920"])
      h.feed(['{"v":1,"type":"config_changed","serial":920}'])
    }, function() { return settled() && row().value === "power_profile" && h.model.configOptionIndex(row().options, "auto") < 0 }, 8000)

    // the daemon's notice, under the switch (and later in the dialog)
    h.step("battery: a mode written during a camera session brings the daemon's notice", function() {
      h.writeFile("battery-notice", ["Applies when the camera restarts"])
      h.markLog()
      h.find(A(), "batterySwitch").toggled()
    }, function() { return has("config set -- video.battery_saver off") && settled() && row().notice !== "" }, 8000)
    h.step("battery: the notice under the switch, as a dim line", function() {
      h.eq("the notice", h.find(A(), "batteryNotice").text, "Applies when the camera restarts")
      h.eq("shown", h.find(A(), "batteryNotice").visible, true)
      h.eq("not an error", String(h.find(A(), "batteryNotice").color) === String(C().urgent), false)
      h.check("under the switch", h.find(A(), "batteryNotice").mapToItem(null, 0, 0).y > h.find(A(), "batterySwitch").mapToItem(null, 0, 0).y)
      h.eq("no error line", h.find(A(), "batteryError").visible, false)
    })
    h.grabStep(function() { return A().popup }, "b3-panel-battery-saver-notice.png")

    // the setup dialog: a dropdown of four, the notice under the row
    h.step("battery: the dialog's Daemon section", function() {
      A().close()
      h.dialog = D()
      D().open(h.model.setupPayloadJson())
    }, function() { return D().shown && settled() }, 8000)
    h.step("battery: the mode is a dropdown (four options, too long for chips), with the notice", function() {
      h.key("4")
      h.eq("the Daemon section", D().section, "daemon")
      h.eq("the group", D().daemonView.groups[0].label, "Video processing")
      h.eq("a dropdown", dfind("configDropdown-video.battery_saver").visible, true)
      h.eq("no chips", dfind("configChoices-video.battery_saver").visible, false)
      h.eq("its value", dfind("configDropdown-video.battery_saver").value, "off")
      h.eq("four options", dfind("configDropdown-video.battery_saver").options.length, 4)
      h.eq("the notice", dfind("configNotice-video.battery_saver").text, "Applies when the camera restarts")
      h.eq("shown", dfind("configNotice-video.battery_saver").visible, true)
      h.eq("none on the other row", dfind("configNotice-video.memory").visible, false)
      h.eq("the apply text too", D().daemonView.groups[0].rows[1].applyText, "Applies at next camera start")
    })
    h.grabStep(function() { return dfind("setupCard") }, "b4-setup-battery-saver.png")
    h.step("battery: Always, from the dialog", function() {
      h.markLog()
      var view = h.model.configViewRow(D().daemonView, D().daemonView.groups[0].rows[1].stop)
      D().setCursor("config", view.stop)
      h.check("chosen", D().chooseConfig(view, 3))
    }, function() { return has("config set -- video.battery_saver always") && settled() && row().value === "always" }, 8000)
    h.step("battery: the new value, and the panel follows it", function() {
      h.eq("the dropdown shows it", dfind("configDropdown-video.battery_saver").value, "always")
      h.eq("no dialog error", S().setupError, "")
      h.eq("on in the panel's view", C().batterySaver.on, true)
    })

    // greyed while the memory is not automatic: the daemon's reason, no write
    h.step("battery: video processing set to System memory", function() {
      h.markLog()
      h.check("written", S().setConfig("video.memory", "host"))
    }, function() { return has("config set -- video.memory host") && settled() && row().enabled === false }, 8000)
    h.step("battery: the panel greys the switch, with the daemon's reason", function() {
      D().close()
      h.dialog = D()
      A().open()
      h.tab(A(), "effect")
    }, function() { return A().opened && !D().shown })
    h.wait(400)
    h.step("battery: greyed, the reason as a line and as the tooltip, no write", function() {
      h.eq("shown", h.find(A(), "batteryBlock").visible, true)
      h.eq("not interactive", h.find(A(), "batterySwitch").interactive, false)
      h.eq("faded", h.find(A(), "batterySwitch").opacity, C().greyedOpacity)
      h.eq("the reason", h.find(A(), "batteryReason").text, "Set video processing to automatic to use this")
      h.eq("still on", h.find(A(), "batterySwitch").checked, true)
      h.eq("the reason is the description now", h.find(A(), "batterySwitch").Accessible.description, "Set video processing to automatic to use this")
      h.check("refused", !C().toggleBatterySaver())
      h.eq("the Mode dropdown greyed too", h.find(A(), "batteryModeDropdown").enabled, false)
      h.eq("faded", h.find(A(), "batteryModeDropdown").opacity, C().greyedOpacity)
      h.eq("the row's label dim", String(h.find(A(), "batteryLabel").color), String(C().dim))
      h.check("no choice", !C().chooseBatteryMode("on_battery"))
      h.markLog()
      calls = fakeShell.calls.length
      h.find(A(), "batteryModeDropdown").changed("on_battery")
      C().setCursor("battery", -1)
      h.key(Qt.Key_Return)
      C().setCursor("battery-mode", -1)
      h.key(Qt.Key_Return)
    })
    h.wait(300)
    h.step("battery: the keyboard wrote nothing either", function() {
      h.eq("no write", writesOf("video.battery_saver"), "[]")
      h.eq("no list", h.find(A(), "batteryModeDropdown").popupOpen, false)
      h.eq("nothing stored", fakeShell.calls.length, calls)
    })
    h.grabStep(function() { return A().popup }, "b5-panel-battery-saver-greyed.png")
    h.step("battery: video processing automatic again, the switch is live", function() {
      h.markLog()
      h.check("written", S().setConfig("video.memory", "auto"))
    }, function() { return has("config set -- video.memory auto") && settled() && row().enabled === true }, 8000)
    h.step("battery: no reason, interactive again", function() {
      h.eq("interactive", h.find(A(), "batterySwitch").interactive, true)
      h.eq("no reason", h.find(A(), "batteryReason").visible, false)
    })

    // a failed write shows under the switch
    // the refusal is in place before the write runs (the files are written
    // by the harness's queue, not at once)
    h.step("battery: the CLI set to refuse", function() {
      h.writeFile("stderr", ["fake: refused"])
      h.writeFile("exit", ["1"])
    }, function() { return h.writerIdle() }, 3000)
    h.step("battery: a write the CLI refuses", function() {
      h.markLog()
      h.find(A(), "batterySwitch").toggled()
    }, function() { return has("config set -- video.battery_saver off") && settled() }, 8000)
    h.step("battery: the error under the switch", function() {
      h.check("an error", h.find(A(), "batteryError").visible && h.find(A(), "batteryError").text !== "", h.find(A(), "batteryError").text)
      h.eq("still on", h.find(A(), "batterySwitch").checked, true)
      h.removeFile("stderr")
      h.removeFile("exit")
    })

    // back to the state the steps after these expect
    h.step("battery: back to revision 15 with the dialog open at Backgrounds", function() {
      A().close()
      h.removeFile("battery-notice")
      h.removeFile("config-show")
      h.removeFile("setup-serial")
      h.feed([snapshotLine(rev(15))])
    }, function() { return S().record.interfaceRevision === 15 && S().configHolders.length === 0 && S().setup.config === null })
    h.step("battery: the dialog again", function() {
      h.markLog()
      h.dialog = D()
      D().open(h.model.setupPayloadJson())
    }, function() { return D().shown && settled() }, 8000)
    h.step("battery: Backgrounds", function() {
      h.key("5")
      h.eq("shown", D().section, "backgrounds")
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

  // ---- the panel's size, measured (MEASURE <state> <width>x<height>) ---------
  //
  // The effects as a revision-28 daemon publishes them on a machine with an
  // NVIDIA GPU, every effect off: one switch each, their dependents hidden,
  // enhancement not applicable here and the open-model cut-out handled by
  // NVIDIA Maxine (two entries of "Not available now"). Measured on a
  // 1080-high screen (shellRoot.card1080): the narrow default Effects view,
  // the narrow Mic tab with the microphone off, the Details view, the wide
  // layout with the preview hidden (the settings column alone) and with the
  // preview live. Each is grabbed to m9-measure-<state>.png.
  function measureEffectRows() {
    var g = function(group, label, id, type, name, v, d, o) {
      var x = { scope: "global" }
      for (var k in o) x[k] = o[k]
      return stateRow(group, label, id, type, name, v, d, x)
    }
    var maxine = "Handled by NVIDIA Maxine video effects instead"
    return [
      g("background", "Background effect", "effect.background.mode", "enum", "Effect", "none", "none", { options: "none:Off,blur:Blur,replace:Replace" }),
      g("background", "Background effect", "effect.background.blur_strength", "int", "Blur strength", 50, 50,
        { min: 0, max: 100, step: 1, unit: "%", master: "effect.background.mode", when: "blur", reason: "Choose Blur to change this" }),
      g("eye_contact", "Eye contact", "effect.eye_contact.enabled", "bool", "Eye contact", "false", "false", {}),
      g("eye_contact", "Eye contact", "effect.eye_contact.look_away", "bool", "Natural look-away", "false", "false",
        { master: "effect.eye_contact.enabled", when: "true", reason: "Turn on eye contact to change this" }),
      g("auto_frame", "Auto-framing", "effect.auto_frame.enabled", "bool", "Auto-framing", "false", "false", {}),
      g("auto_frame", "Auto-framing", "effect.auto_frame.framing", "enum", "Framing", "medium", "medium",
        { options: "tight:Tight,medium:Medium,wide:Wide", master: "effect.auto_frame.enabled", when: "true", reason: "Turn on auto-framing to change this" }),
      g("cutout", "Cut-out", "effect.cutout.chair", "bool", "Hide the chair with the background", "false", "false",
        { master: "effect.background.mode", when: "blur,replace", reason: "Turn on the background effect to change this" }),
      g("video", "Video", "effect.video.denoise", "bool", "Noise removal", "false", "false", {}),
      g("video", "Video", "effect.video.enhance", "bool", "Enhance low-resolution camera", "false", "false",
        { fixed: true, kind: "not_applicable", reason: "The camera already captures at full resolution" }),
      g("video", "Video", "effect.video.enhance_method", "enum", "Enhancement method", "ai", "ai",
        { options: "ai:AI super resolution,fast:Fast upscale", master: "effect.video.enhance", when: "true", reason: "Turn on enhancement to change this" }),
      g("video", "Video", "effect.video.hdr", "bool", "HDR look", "false", "false", {}),
      g("lighting", "Lighting", "effect.lighting.relight", "bool", "Relighting", "false", "false", {}),
      g("lighting", "Lighting", "effect.lighting.light", "enum", "Light", "neutral", "neutral",
        { options: "warm:Warm,neutral:Neutral,cool:Cool", master: "effect.lighting.relight", when: "true", reason: "Turn on relighting to change this" }),
      g("lighting", "Lighting", "effect.lighting.direction", "int", "Light direction", 0, 0,
        { min: -90, max: 90, step: 5, unit: "°", master: "effect.lighting.relight", when: "true", reason: "Turn on relighting to change this" }),
      g("lighting", "Lighting", "effect.lighting.brightness", "int", "Brightness", 100, 100,
        { min: 50, max: 200, step: 5, unit: "%", master: "effect.lighting.relight", when: "true", reason: "Turn on relighting to change this" }),
      g("cutout_onnx", "Open-model cut-out", "effect.cutout_onnx.model", "enum", "Model", "modnet", "modnet",
        { options: "modnet:MODNet", fixed: true, kind: "other_provider", reason: maxine }),
      g("cutout_onnx", "Open-model cut-out", "effect.cutout_onnx.device", "enum", "Runs on", "auto", "auto",
        { options: "auto:Automatic,cpu:CPU", fixed: true, kind: "other_provider", reason: maxine })
    ]
  }

  function measureScenario() {
    var A = function() { return h.widgetA }
    var S = function() { return h.widgetA.service }
    var P = function() { return h.widgetA.previewService }
    var C = function() { return h.content(h.widgetA) }
    var snap = function(o) {
      var m = { interface_revision: 28, settings_schema: 1, settings_revision: 5, loopback_consumers: 0, pipewire_consumers: 0,
                preview_consumers: 0, pipewire_output: "ready", config_serial: 1, modules_serial: 1,
                mic: { state: "off", consumers: 0, provider: "", latency_ms: 0, error: "" } }
      for (var k in o) m[k] = o[k]
      return snapshotLine(m)
    }
    var micRows = function() {
      var m = function(id, type, label, v, d, o) {
        var x = { scope: "global", surface: "mic" }
        for (var k in o) x[k] = o[k]
        return stateRow("input", "Microphone", id, type, label, v, d, x)
      }
      return [m("mic.input.enabled", "bool", "Noise and echo processing", "true", "true", {}),
              m("mic.input.use_as_default", "bool", "Use as default microphone", "false", "false",
                { fixed: true, kind: "busy", reason: "Turn the microphone on first" })]
    }
    var measure = function(state, limit) {
      var w = A().popup.contentWidth, hgt = A().popup.contentHeight
      console.log("MEASURE " + state + " " + w + "x" + hgt)
      var f = h.find(A(), "panelFlick")
      h.check(state + ": within the 860 cap and the 1080 screen's room (" + hgt + ")",
              hgt <= 860 && hgt <= A().popup.availableCardHeight, hgt + " vs " + A().popup.availableCardHeight)
      h.check(state + ": the body does not scroll (" + Math.round(f.contentHeight) + " in " + Math.round(f.height) + ")",
              !f.interactive && f.contentHeight <= f.height + 0.5, f.contentHeight + " in " + f.height)
      if (limit !== undefined) h.check(state + ": at most " + limit + " tall (" + hgt + ")", hgt <= limit, hgt)
    }
    // Waits until the card's size has held still for 300 ms (a Column lays
    // out on a later frame; a grab before that shows the old layout).
    var settle = function(label) {
      h.step("measure: settle (" + label + ")", function() { h.notes.settleSize = ""; h.notes.settleAt = Date.now() }, function() {
        var size = A().popup.contentWidth + "x" + A().popup.contentHeight
        if (size !== h.notes.settleSize) { h.notes.settleSize = size; h.notes.settleAt = Date.now(); return false }
        return Date.now() - h.notes.settleAt >= 300
      }, 5000)
    }
    h.step("measure: a revision-28 daemon, every effect off, the microphone off", function() {
      A().close()
      A().popup.availableCardHeight = shellRoot.card1080
      h.removeFile("settings-no-kind")
      h.writeFile("settings-state", brioState(true).concat(measureEffectRows(), micRows()))
      h.writeFile("settings-camera", [brioId])
      h.writeFile("settings-serial", ["30"])
      h.writeFile("settings-mode", ["list"])
      h.removeFile("delay")
      h.removeFile("stderr")
      h.writeFile("exit", ["0"])
      h.feed([snap({})])
    }, function() { return S().record.interfaceRevision === 28 && !!S().record.settings && S().record.settings.serial === 30 && h.writerIdle() })
    h.step("measure: the narrow setting, the preview hidden", function() {
      A().settings = { cliPath: shellRoot.cli, narrowPanel: true }
      A().open()
      h.tab(A(), "effect")
      // the disclosures as a first opening shows them: folded
      C().moreOpen = false
      C().notAvailableOpen = ({})
    }, function() { return A().opened && C() !== null && !P().switchOn })
    h.wait(500)
    h.step("measure: narrow, the default Effects view", function() {
      h.eq("narrow: one column", A().layout.wide + "," + A().popup.contentWidth, "false,520")
      h.eq("the preview a strip", h.find(A(), "previewStrip").visible, true)
      h.eq("one switch per effect, no heading", C().effectSettings.groups.map(function(g) {
        return (g.heading ? g.label + ":" : "") + g.rows.map(function(r) { return r.label }).join(",") }).join(" | "),
        "Eye contact | Auto-framing | Video:Noise removal,HDR look | Relighting")
      h.eq("the Not available line", h.find(A(), "effect-notAvailableText").text, "Not available now (2)")
      h.eq("More, folded", h.find(A(), "moreLine").visible && !h.find(A(), "moreBlock").visible, true)
      measure("narrow-effects-default", 560)
    })
    var yIn = function(name) { var it = h.find(A(), name); return it ? Math.round(it.mapToItem(C(), 0, 0).y) : -1 }
    var rightOf = function(it) { return it ? Math.round(it.mapToItem(C(), it.width, 0).x) : -1 }
    h.step("measure: narrow layout: the header's state line, the rows' rhythm, one right edge", function() {
      var state = h.find(A(), "heroState"), sw = h.find(A(), "enableSwitch"), hero = h.find(A(), "hero")
      h.check("the state line runs under the title and the controls",
              state.mapToItem(C(), 0, 0).y >= sw.mapToItem(C(), 0, sw.height).y - 0.5, state.mapToItem(C(), 0, 0).y + " vs " + sw.mapToItem(C(), 0, sw.height).y)
      h.check("across the column, on one line", rightOf(state) >= rightOf(hero) - 1 && state.lineCount === 1, rightOf(state) + "/" + rightOf(hero) + " lines " + state.lineCount)
      var heights = ["effect.eye_contact.enabled", "effect.auto_frame.enabled", "effect.video.denoise", "effect.video.hdr", "effect.lighting.relight"].map(function(id) {
        return Math.round(h.find(A(), "setting-" + id).height) })
      h.check("one height for every switch row (" + heights.join(",") + ")", heights.every(function(x) { return x === heights[0] }), heights.join(","))
      var gapRows = yIn("setting-effect.auto_frame.enabled") - yIn("setting-effect.eye_contact.enabled")
      var gapVideo = yIn("setting-effect.video.hdr") - yIn("setting-effect.video.denoise")
      h.eq("one spacing between switch rows, headed or not", gapRows, gapVideo)
      h.eq("Relighting is ruled off from the Video section", h.find(A(), "effect-settingsGroupBreak-lighting").kind, "rule")
      h.eq("the Background heading in the group headings' style", h.find(A(), "effectTitle").font.capitalization === Font.AllUppercase
           && h.find(A(), "effectTitle").font.pixelSize === h.find(A(), "effect-settingsGroupLabel-video").font.pixelSize, true)
      var body = h.find(A(), "body")
      h.notes.switchRight = rightOf(h.find(A(), "settingSwitch-effect.eye_contact.enabled"))
      h.eq("the switches end on the body's right edge", h.notes.switchRight, rightOf(body))
      h.eq("the body lines up with the tab row", Math.round(body.mapToItem(C(), 0, 0).x), Math.round(h.find(A(), "tabRow").mapToItem(C(), 0, 0).x))
      h.notes.tabRowY = yIn("tabRow")
    })
    h.step("measure: the cursor stays on its row when a row is revealed above it", function() {
      // the pointer off the rows: a row sliding under it would move the cursor
      keys.mouseMove(h.find(A(), "heroTitle"), 1, 1)
      var i = C().stops.map(function(st) { return st.id }).indexOf("effect.lighting.relight")
      C().cursorActive = true
      C().cursorIndex = i
      h.eq("on Relighting", C().currentStop.id, "effect.lighting.relight")
      S().commitSetting("effect.eye_contact.enabled", true)
    }, function() { return C().stops.some(function(st) { return st.id === "effect.eye_contact.look_away" }) && h.writerIdle() }, 5000)
    h.step("measure: still on Relighting; eye contact off again", function() {
      h.eq("the same row, not its old index's neighbour", C().currentStop.id, "effect.lighting.relight")
      S().commitSetting("effect.eye_contact.enabled", false)
    }, function() { return !C().stops.some(function(st) { return st.id === "effect.eye_contact.look_away" }) && h.writerIdle() }, 5000)
    h.step("measure: and still on Relighting once it is hidden again", function() {
      h.eq("the same row", C().currentStop.id, "effect.lighting.relight")
      C().cursorActive = false
      C().cursorIndex = 0
    })
    h.grabStep(function() { return A().popup }, "m9-measure-narrow-effects-default.png")
    h.step("measure: the Not available list opened", function() { C().toggleNotAvailable() })
    h.wait(250)
    h.step("measure: its open state is the Effects tab's own", function() {
      h.tab(A(), "camera")
      h.eq("the Camera tab's line is folded", C().notAvailable.open, false)
      h.tab(A(), "effect")
      h.eq("back on Effects: still open", C().notAvailable.open, true)
    })
    h.wait(250)
    h.step("measure: its entries and reasons", function() {
      h.eq("the Setup button on the switches' right edge", rightOf(h.find(A(), "effect-notAvailableSetup-1")), h.notes.switchRight)
      h.eq("entries", h.find(A(), "effect-notAvailableLabel-0").text + " / " + h.find(A(), "effect-notAvailableReason-0").text,
           "Enhance low-resolution camera / The camera already captures at full resolution")
      h.eq("another module's group, once", h.find(A(), "effect-notAvailableLabel-1").text + " / " + h.find(A(), "effect-notAvailableReason-1").text,
           "Open-model cut-out / Handled by NVIDIA Maxine video effects instead")
      h.eq("no third", h.find(A(), "effect-notAvailableEntry-2"), null)
    })
    settle("Not available open")
    h.step("measure: narrow, Not available now open", function() {
      h.eq("the list open", C().notAvailable.open && h.find(A(), "effect-notAvailableEntry-1").visible, true)
      measure("narrow-effects-unavailable")
    })
    h.grabStep(function() { return A().popup }, "m9-measure-narrow-effects-unavailable.png")
    h.step("measure: the Not available list folded again", function() { C().toggleNotAvailable() },
           function() { return !C().notAvailable.open })
    h.step("measure: the Mic tab, the microphone off", function() { h.tab(A(), "mic") })
    h.wait(300)
    h.step("measure: narrow, Mic off", function() {
      h.eq("no preview on the Mic tab", h.find(A(), "previewStrip").visible || h.find(A(), "previewBlock").visible, false)
      h.eq("the tab row stays where it is on the Effects tab", yIn("tabRow"), h.notes.tabRowY)
      h.eq("the microphone's switch on the settings switches' right edge", rightOf(h.find(A(), "micSwitch")), h.notes.switchRight)
      h.eq("the Effects tab's Not available line keeps its own state", C().notAvailableOpen.effect === true, false)
      h.eq("the switch and one sentence", h.find(A(), "micExplainer").visible && !h.find(A(), "micSettingsArea").visible, true)
      measure("narrow-mic-off")
    })
    h.grabStep(function() { return A().popup }, "m9-measure-narrow-mic-off.png")
    h.step("measure: the Camera tab", function() { h.tab(A(), "camera") })
    h.wait(300)
    h.step("measure: the camera's groups in today's daemon's order", function() {
      h.eq("groups", C().settingsView.groups.map(function(g) { return g.label }).join(","), "Framing & focus,Image,White balance,Exposure")
      h.eq("Framing & focus open first: field of view, then zoom", C().settingsView.groups[0].expanded + ":"
           + C().settingsView.groups[0].rows.slice(0, 2).map(function(r) { return r.label }).join(","), "true:Field of view,Zoom")
      h.eq("the tab row stays where it is", yIn("tabRow"), h.notes.tabRowY)
    })
    h.grabStep(function() { return A().popup }, "m9-measure-narrow-camera.png")
    h.step("measure: the Camera tab, White balance open", function() {
      C().settingsOpen = "white_balance"
    })
    h.wait(300)
    h.step("measure: a row's help under the cursor", function() {
      var id = "camera.white_balance.temperature_compensation"
      h.notes.helpRowH = h.find(A(), "setting-" + id).height
      h.notes.helpCardH = A().popup.contentHeight
      var i = C().stops.map(function(st) { return st.id }).indexOf(id)
      C().cursorActive = true
      C().cursorIndex = i
    })
    h.wait(250)
    h.step("measure: the help is a tip over the panel, not a line in it", function() {
      var id = "camera.white_balance.temperature_compensation"
      h.eq("the tip shows the description", h.find(A(), "settingHelpTip-" + id).visible && h.find(A(), "settingHelp-" + id).text === "Shifts the picture warmer or cooler", true)
      h.eq("the row keeps its height", h.find(A(), "setting-" + id).height, h.notes.helpRowH)
      h.eq("the card keeps its height", A().popup.contentHeight, h.notes.helpCardH)
      h.eq("Reset to defaults on the switches' right edge", rightOf(h.find(A(), "settingsReset")) >= h.notes.switchRight - Commons.Style.space(3)
           && rightOf(h.find(A(), "settingsReset")) <= h.notes.switchRight, true)
      h.eq("the camera's switches too", rightOf(h.find(A(), "settingSwitch-camera.white_balance.white_balance_automatic")), h.notes.switchRight)
      h.eq("the rows over the blocks drawn after them (a downward tip stays on top)", h.find(A(), "settingsGroups").z, 1)
    })
    h.grabStep(function() { return A().popup }, "m9-measure-narrow-help-tip.png")
    h.step("measure: the cursor off", function() {
      C().cursorActive = false
      C().cursorIndex = 0
      C().settingsOpen = null
    })
    h.step("measure: the Details view", function() { h.tab(A(), "effect"); C().toggleDetails() })
    h.wait(300)
    h.step("measure: narrow, Details", function() {
      h.eq("shown", h.find(A(), "detailsView").visible, true)
      measure("narrow-details")
    })
    h.grabStep(function() { return A().popup }, "m9-measure-narrow-details.png")
    h.step("measure: the wide layout (the setting off), the preview hidden", function() {
      C().toggleDetails()
      A().settings = { cliPath: shellRoot.cli }
    }, function() { return !A().storedNarrow && !P().switchOn && !C().detailsOpen })
    settle("wide, preview hidden")
    h.step("measure: wide, preview hidden: the settings column alone", function() {
      h.eq("the narrow setting off, the preview hidden", A().storedNarrow + "," + P().switchOn + "," + A().settings.narrowPanel, "false,false,undefined")
      h.eq("shown, this setting would be two columns", h.model.panelLayout(A().storedNarrow, true, true).wide, true)
      h.eq("one column: the same card as the narrow setting's, by design", A().layout.wide + "," + A().popup.contentWidth, "false,520")
      measure("wide-preview-hidden")
    })
    h.grabStep(function() { return A().popup }, "m9-measure-wide-preview-hidden.png")
    h.step("measure: Show preview", function() { C().togglePreview() },
           function() { return P().frames >= 3 && h.find(A(), "previewImage").status === Image.Ready }, 8000)
    h.wait(400)
    h.step("measure: wide, the preview live, the default state", function() {
      h.eq("two columns", A().layout.wide + "," + A().popup.contentWidth, "true,920")
      h.eq("the preview on the left, its summary under it", h.find(A(), "previewColumn").visible && h.find(A(), "previewSummary").visible, true)
      h.eq("the controls in a row under the frame, no backing plate",
           h.find(A(), "previewControlsRow").visible && h.find(A(), "previewHide").visible
           && !h.find(A(), "previewOverlayBacking") && !h.find(A(), "previewHideBacking"), true)
      h.check("the state line under the title, beside the controls (wide)",
              h.find(A(), "heroState").mapToItem(C(), 0, 0).y < h.find(A(), "enableSwitch").mapToItem(C(), 0, h.find(A(), "enableSwitch").height).y)
      measure("wide-preview-live")
    })
    h.grabStep(function() { return A().popup }, "m9-measure-wide-preview-live.png")
    h.step("measure: wide, the Details view beside the preview", function() { C().toggleDetails() })
    h.wait(300)
    h.step("measure: wide, Details", function() { measure("wide-details") })
    h.grabStep(function() { return A().popup }, "m9-measure-wide-details.png")
    // the preview exits on the wide layout's Mic tab: the layout does not
    // follow the error (it would go narrow, release the hold, clear the
    // failure, go wide, relaunch and fail again: a 920/520 flap)
    h.step("preview error, wide: the Mic tab, the preview live", function() {
      C().toggleDetails()
      h.tab(A(), "mic")
    }, function() { return !C().detailsOpen && P().running && A().layout.wide && A().previewHeld }, 8000)
    settle("wide, Mic tab")
    h.step("preview error, wide: every next start exits on its own", function() {
      h.notes.flapStarts = P().starts
      h.notes.flapWidth = A().popup.contentWidth
      h.notes.flapLayouts = 0
      h.notes.flapFn = function() { if (!A().layout.wide) h.notes.flapLayouts++ }
      A().layoutChanged.connect(h.notes.flapFn)
      h.writeFile("preview-exit", ["1"])
    }, function() { return h.writerIdle() })
    h.step("preview error, wide: the preview child killed", function() { h.killPid(P().pid, "KILL") },
           function() { return !P().running && P().failed }, 8000)
    h.step("preview error, wide: 3 s watched", function() {
      h.notes.flapMark = Date.now()
      h.notes.flapMin = A().popup.contentWidth
      h.notes.flapMax = A().popup.contentWidth
    }, function() {
      var w = A().popup.contentWidth
      h.notes.flapMin = Math.min(h.notes.flapMin, w)
      h.notes.flapMax = Math.max(h.notes.flapMax, w)
      return Date.now() - h.notes.flapMark >= 3000
    }, 5000)
    h.step("preview error, wide: one width, no relaunch, the error in the frame area", function() {
      A().layoutChanged.disconnect(h.notes.flapFn)
      h.eq("the width held (" + h.notes.flapMin + ".." + h.notes.flapMax + ")", h.notes.flapMin + "," + h.notes.flapMax + "," + h.notes.flapLayouts,
           h.notes.flapWidth + "," + h.notes.flapWidth + ",0")
      h.eq("no relaunch", P().starts, h.notes.flapStarts)
      h.eq("still wide, still held, still failed", A().layout.wide + "," + A().previewHeld + "," + P().failed, "true,true,true")
      var t = h.find(A(), "previewPlaceholder")
      h.check("the reason inside the frame area", h.find(A(), "previewBlock").visible && t.visible && t.text.indexOf("stopped by signal 9") !== -1, t.text)
      h.eq("drawn as an error", t.color, Commons.Color.urgent)
      h.eq("no strip in the wide layout", h.find(A(), "previewStrip").visible, false)
      h.eq("Hide under the frame", h.find(A(), "previewHide").visible, true)
      h.removeFile("preview-exit")
    }, function() { return h.writerIdle() })
    h.grabStep(function() { return A().popup }, "m9-preview-error-wide-mic.png")
    h.step("measure: hide the preview again", function() { h.tab(A(), "effect"); C().togglePreview() },
           function() { return !P().running && !P().switchOn && !A().layout.wide })
    h.step("measure: back to the default fixture", function() {
      A().close()
      A().settings = { cliPath: shellRoot.cli }
      h.writeFile("settings-mode", ["none"])
      h.feed([snapshotLine({})])
    }, function() { return S().record.interfaceRevision === 4 && h.writerIdle() })
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

    h.step("middle click: off", function() {
      A().close()
      A().iconButton.triggerPress(Qt.MiddleButton)
    }, function() { return S().record.state === "off" && !S().commandBusy }, 15000)
    h.step("off icon", function() {
      h.eq("off glyph", A().iconButton.text, glyphOf("off"))
      h.eq("enabled false", S().record.enabled, false)
    })
    h.grabStep(function() { return strip }, "live-bar-off.png")
    h.step("middle click: on", function() { A().iconButton.triggerPress(Qt.MiddleButton) },
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
      if (!h.content(A()).detailsOpen) h.content(A()).toggleDetails()
      var rows = h.model.statsRows(S().record)
      h.note("stats: " + JSON.stringify(rows))
      h.note("consumers " + S().record.consumers + ", tooltip: " + A().iconButton.tooltipText)
      h.eq("active glyph", A().iconButton.text, glyphOf("active"))
      h.eq("the live figures in the Details", h.model.detailsRows(S().record).some(function(r) { return r.label === "Frame rate" }), true)
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
