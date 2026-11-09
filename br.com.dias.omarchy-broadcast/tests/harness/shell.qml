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
//   OBH_CLI      CLI for the widgets' cliPath (the fake, or the real build)
//   OBH_FAKE     the fake's state directory (mock)
//   OBH_SCREENS  where PNG grabs go
//   OBH_LINKED   a symlink to the plugin dir, for the resolver checks (mock)
//   OBH_NOREPO   a plugin-named dir outside any repository (mock)
//   OBH_REPO_CLI the repository's target/release/omarchy-broadcast (mock)
//   OBH_DAEMON   omarchy-broadcastd binary; OBH_LIVE the live scratch dir (live)
//   OBH_DEVLINK  a symlink to a plugin copy inside a scratch repository whose
//                target/release/omarchy-broadcast is OBH_DEVCLI (mock)
//   OBH_NLPLUGIN a plugin dir whose path holds a newline; OBH_NLBIN a PATH
//                entry whose name holds one, with a CLI in it (mock)
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
  }

  FloatingWindow {
    id: window
    implicitWidth: 520
    implicitHeight: 900
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
              effect: "none", blur_strength: 0.5, background_image: "", interface_revision: 2 }
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
      h.eq("cameras block shown", h.find(A(), "camerasBlock").visible, true)
      h.eq("camera rows", h.find(A(), "cameraRepeater").count, 3)
      h.eq("stats hidden while idle", h.find(A(), "statsBlock").visible, false)
      h.eq("next camera shown", h.find(A(), "nextCameraButton").visible, true)
      h.eq("switch shown", h.find(A(), "enableSwitch").visible, true)
      h.eq("hero status line", h.content(A()).heroMeta, "idle")
      h.check("active row marked", h.row(A(), 0).isActive && !h.row(A(), 1).isActive)
      h.check("active row painted as current", h.row(A(), 0).current && !h.row(A(), 1).current)
      h.eq("no cursor before a key", h.content(A()).cursorActive, false)
      h.check("panel took the keyboard focus", h.catcher(A()) && h.catcher(A()).activeFocus)
    })
    h.grabStep(function() { return A().popup }, "panel-idle.png")

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
      h.eq("stops = switch + effect + rendered rows + next", c.stops.length, h.find(A(), "cameraRepeater").count + 3)
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
    h.step("Down from the effect row", function() { h.key(Qt.Key_Down) })
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
    h.step("k x5 back to the switch, Enter turns off", function() {
      for (var i = 0; i < 5; i++) h.key("k")
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
      A().close()
    })

    // left click: off, then on from the other monitor; a second click while
    // the first runs is ignored
    h.step("slow commands for the double click", function() { h.writeFile("delay", ["0.6"]) }, function() { return h.writerIdle() })
    h.step("left click turns off; a second one in flight is ignored", function() {
      A().close()
      h.markLog()
      A().iconButton.triggerPress(Qt.LeftButton)
      h.check("busy after the first click", S().commandBusy)
      A().iconButton.triggerPress(Qt.LeftButton)
      B().iconButton.triggerPress(Qt.LeftButton)
    }, function() { return h.newLogArgs().length >= 1 })
    h.wait(900)
    h.step("off argv, once", function() {
      var got = h.newLogArgs()
      h.eq("runs", got.length, 1)
      h.eq("argv", JSON.stringify(got[0]), JSON.stringify(["off"]))
      h.eq("no optimistic change", S().record.enabled, true)
      h.eq("left click does not open the panel", A().opened, false)
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
    h.step("left click on the other monitor turns on", function() {
      h.markLog()
      B().iconButton.triggerPress(Qt.LeftButton)
    }, function() { return h.newLogArgs().length >= 1 })
    h.step("on argv", function() {
      h.eq("argv", JSON.stringify(h.newLogArgs()[0]), JSON.stringify(["on"]))
      h.feed([stateLine({ state: "idle", enabled: true, active_camera: fhdId, active_camera_name: "FHD Camera" })])
    }, function() { return S().record.state === "idle" && S().record.enabled })

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
      A().close()
      h.markLog()
      A().iconButton.triggerPress(Qt.LeftButton)
      h.eq("left click opens the panel", A().opened, true)
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
      A().iconButton.triggerPress(Qt.LeftButton)
      h.eq("left click opens the panel instead", A().opened, true)
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
      h.feed([snapshotLine({ blur_strength: undefined, background_image: undefined })])
    }, function() { return S().record.link === "ok" && S().record.cliEffects === false })
    h.step("the effect row is faded and names the CLI", function() {
      ["none", "blur", "replace"].forEach(function(e) {
        h.check(e + " faded", h.find(A(), "effectChoice-" + e).opacity < 1)
      })
      h.eq("hint", h.find(A(), "effectHint").text, "The omarchy-broadcast CLI needs updating for effects.")
      h.eq("no command", h.find(A(), "effectHintCommand").visible, false)
      h.eq("no effect stop", h.content(A()).stops.filter(function(st) { return st.kind === "effect" }).length, 0)
      h.markLog()
      h.check("Blur refused", !h.content(A()).chooseEffect(1))
      h.eq("nothing ran", h.newLogArgs().length, 0)
    })
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
      A().iconButton.triggerPress(Qt.LeftButton)
      h.eq("left click opens the panel", A().opened, true)
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

    // 12 cameras (the producer's maximum) and a truncation flag: the panel
    // caps its height, scrolls, and keeps the cursor row in view
    h.step("12 cameras", function() {
      h.feed([manyCamerasLine(12, true)])
      A().open()
    }, function() { return S().record.cameras.length === 12 && h.content(A()) !== null })
    h.wait(400)
    h.step("panel capped and scrollable", function() {
      var flick = h.find(A(), "panelFlick")
      h.eq("rows", h.find(A(), "cameraRepeater").count, 12)
      h.check("card height capped at Style.space(560)", A().popup.height <= Commons.Style.space(560), A().popup.height + " > " + Commons.Style.space(560))
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
      h.feed([snapshotLine({})])
    }, function() { return S().record.cameras.length === 3 })

    // the resolver itself: PATH first, then the repo build behind a symlink
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
    var fakeBin = shellRoot.cli.replace(/\/omarchy-broadcast$/, "")
    var direct = function(dir) { return ["sh", "-c", h.model.RESOLVER_SCRIPT, "omarchy-broadcast-resolve", dir] }
    var nlPlugin = Quickshell.env("OBH_NLPLUGIN")
    var nlBin = Quickshell.env("OBH_NLBIN")
    resolverCase("PATH wins", h.model.resolverArgv(Quickshell.env("OBH_LINKED")), fakeBin + ":/usr/bin:/bin", shellRoot.cli, 0)
    resolverCase("repo build through the symlink", h.model.resolverArgv(Quickshell.env("OBH_LINKED")), "/usr/bin:/bin", Quickshell.env("OBH_REPO_CLI"), 0)
    resolverCase("nothing found", h.model.resolverArgv(Quickshell.env("OBH_NOREPO")), "/usr/bin:/bin", "", 1)
    resolverCase("empty plugin dir still searches PATH", h.model.resolverArgv(""), fakeBin + ":/usr/bin:/bin", shellRoot.cli, 0)
    resolverCase("empty plugin dir, nothing on PATH", h.model.resolverArgv(""), "/usr/bin:/bin", "", 1)
    resolverCase("plugin dir with a newline (argv refuses it)", h.model.resolverArgv(nlPlugin), "/usr/bin:/bin", "", 1)
    resolverCase("plugin dir with a newline (script refuses it)", direct(nlPlugin), "/usr/bin:/bin", "", 1)
    resolverCase("PATH entry with a newline is skipped", h.model.resolverArgv(Quickshell.env("OBH_LINKED")), nlBin + ":/usr/bin:/bin", Quickshell.env("OBH_REPO_CLI"), 0)
    h.step("newline fixtures exist", function() {
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

    h.step("left click: off", function() {
      A().close()
      A().iconButton.triggerPress(Qt.LeftButton)
    }, function() { return S().record.state === "off" && !S().commandBusy }, 15000)
    h.step("off icon", function() {
      h.eq("off glyph", A().iconButton.text, glyphOf("off"))
      h.eq("enabled false", S().record.enabled, false)
    })
    h.grabStep(function() { return strip }, "live-bar-off.png")
    h.step("left click: on", function() { A().iconButton.triggerPress(Qt.LeftButton) },
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
