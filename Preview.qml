pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The live preview for every bar on every monitor: at most one
// `omarchy-broadcast preview --json --fps N` child, whose lease makes the
// daemon write a JPEG of what apps receive to one file; this singleton reads
// the CLI's `frame` lines and hands the panel an Image source for the newest
// one. It never opens a video device and never talks D-Bus itself. The
// qmldir beside this file declares it a singleton (see Daemon.qml).
//
// A singleton of its own, not more of Daemon.qml: the preview has its own
// readers (open panels, not attached widgets), its own run rule and its own
// failure rule, and a stopped preview must never disturb the watch or a
// queued command. It reads Daemon's record and CLI path, and nothing in
// Daemon depends on it.
//
// Run rule (Model.shouldPreview, R1): a panel is open (a registered holder),
// the daemon has the preview (interface revision 5) and the frame path is
// usable, and the preview is shown (the persisted `previewEnabled`, the
// panel's Show preview and Hide). Opening a panel with the preview hidden
// never starts the camera; closing the last one stops the preview.
//
// Holders register by identity (hold/release, idempotent); a widget gives its
// registration back in Component.onDestruction, which is all that may happen
// there. Nothing polls and there is no Timer: an unexpected exit shows its
// reason in the panel and stays down until the run rule turns false and true
// again (closing and reopening the panel always does; so does the daemon
// going away and coming back, as the watch reports it). An exit that lands
// once the rule is already false is no failure: the next open starts it. A
// change of frame rate or CLI is looked at on the next turn, and stops the
// running child only when its command would differ (a transient value that
// is back by then restarts nothing); the idle transition re-arms it on the
// next turn with the command of that moment.
//
// Settings. allowMultiple is false, so every widget carries the same layout
// entry. A widget hands its settings over each time the bar injects them
// (configure); only a value that changed since the last hand-over replaces
// the one in force (Model.previewPrefsAfter). A user's choice applies at once
// (choose); when the shell could not store it, it holds for this session and
// `unsaved` says so, until the stored value itself changes.
Singleton {
  id: root

  // ---- readers: the widgets whose panel is open -----------------------------
  property var holders: []
  readonly property int heldCount: holders.length

  // ---- preferences (Model.previewSettings) -----------------------------------
  property bool switchOn: false
  property int fps: Model.PREVIEW_FPS_DEFAULT
  // The preferences of the settings last handed over; null before the first.
  property var stored: null
  readonly property bool unsaved: Model.previewUnsaved({ enabled: switchOn, fps: fps }, stored)

  // ---- what the preview needs ------------------------------------------------
  readonly property var pathCheck: Model.previewPath(Quickshell.env("XDG_RUNTIME_DIR"))
  // The only path frame lines are compared with and the only file loaded.
  readonly property string expectedPath: pathCheck.path
  readonly property string pathReason: pathCheck.reason
  readonly property string cliPath: Daemon.cliPath
  readonly property bool supported: Model.previewSupported(Daemon.record) && expectedPath !== ""
    && Model.cliUsable(cliPath)
  readonly property bool wanted: Model.shouldPreview(heldCount, supported, switchOn, Daemon.record)

  // ---- process state ---------------------------------------------------------
  property bool armed: false
  property bool started: false
  property bool stopping: false
  // Stopped by ingest() for a line no v1 producer prints: an unexpected end.
  property bool rejected: false
  // Ended on its own: stays down until `wanted` goes false and true again.
  property bool failed: false
  property int exitCode: 0
  property bool exitCrashed: false
  readonly property bool running: previewProc.running
  readonly property int pid: previewProc.running ? Number(previewProc.processId || 0) : 0

  // ---- stream state ----------------------------------------------------------
  property bool leaseActive: false
  property int leaseFps: 0
  property bool pathMismatch: false
  property string streamError: ""
  property string exitError: ""
  // The newest accepted frame; 0 = none since the lease was taken.
  property real seq: 0
  readonly property string frameSource: Model.previewSource(expectedPath, seq)
  readonly property var placeholder: Model.previewPlaceholder({
    record: Daemon.record, pathReason: pathReason, switchOn: switchOn, wanted: wanted,
    running: previewProc.running, leaseActive: leaseActive, hasFrame: frameSource !== "",
    exitError: exitError, streamError: streamError, pathMismatch: pathMismatch
  })

  // Diagnostics, read by the test harness.
  property int starts: 0
  property int frames: 0
  property int droppedLines: 0
  property int droppedFrames: 0
  property int ignoredLines: 0
  property var lastArgv: null

  onWantedChanged: {
    // A false run rule clears a failure: the next true re-arms.
    if (!wanted) {
      failed = false
      exitError = ""
    }
    Qt.callLater(root.syncPreview)
  }
  // The child's command belongs to the input it was armed with; looked at on
  // the next turn, so a value that blips and comes back restarts nothing.
  onFpsChanged: Qt.callLater(root.restartIfStale)
  onCliPathChanged: Qt.callLater(root.restartIfStale)

  // ---- registration (by identity) ------------------------------------------

  function hold(owner) {
    if (!owner || holders.indexOf(owner) !== -1) return
    holders = holders.concat([owner])
  }

  function release(owner) {
    var index = holders.indexOf(owner)
    if (index === -1) return
    var next = holders.slice()
    next.splice(index, 1)
    holders = next
  }

  // The bar handed `owner` its settings (again).
  function configure(owner, settings) {
    if (!owner) return
    var next = Model.previewSettings(settings)
    var prefs = Model.previewPrefsAfter({ enabled: switchOn, fps: fps }, stored, next)
    stored = next
    switchOn = prefs.enabled
    fps = prefs.fps
  }

  // A user's choice in a panel ({ previewEnabled } or { previewFps }), in
  // force at once whether or not the shell stores it.
  function choose(values) {
    var prefs = Model.previewPrefsChosen({ enabled: switchOn, fps: fps }, values)
    switchOn = prefs.enabled
    fps = prefs.fps
  }

  // ---- the child -------------------------------------------------------------

  function syncPreview() {
    if (wanted && !failed) {
      if (!previewProc.running && !armed) armPreview()
    } else if (previewProc.running && !stopping) {
      stopPreview()
    }
  }

  function restartIfStale() {
    if (!previewProc.running || stopping) return
    if (JSON.stringify(Model.previewArgv(cliPath, fps)) !== JSON.stringify(lastArgv)) stopPreview()
  }

  function armPreview() {
    var argv = Model.previewArgv(cliPath, fps)
    if (!argv) return
    started = false
    stopping = false
    rejected = false
    armed = true
    resetStream()
    streamError = ""
    lastArgv = argv
    // Assign the command, then arm.
    previewProc.command = argv
    previewProc.running = true
  }

  function stopPreview() {
    stopping = true
    previewProc.running = false
  }

  function resetStream() {
    leaseActive = false
    leaseFps = 0
    pathMismatch = false
    seq = 0
  }

  function previewEnded() {
    var deliberate = stopping && !rejected
    var wasStarted = started
    var wasRejected = rejected
    armed = false
    started = false
    stopping = false
    rejected = false
    resetStream()
    if (deliberate) {
      streamError = ""
      // Never flip `running` back on in the turn it went off.
      Qt.callLater(root.syncPreview)
      return
    }
    // Only a failure while the preview is wanted stays down: one landing
    // after the panel closed (or the rule went false) is forgotten, so the
    // next open starts it, as the header promises.
    if (!wanted) {
      streamError = ""
      return
    }
    failed = true
    exitError = Model.previewExitText(exitCode, exitCrashed, wasStarted, wasRejected)
  }

  function ingest(line) {
    // Lines from a child that is being stopped belong to the old command.
    if (stopping) return
    // SplitParser has already read the whole line (it has no length cap), so
    // Model.LINE_CAP (8192) is checked after the line is in memory; the first
    // bound is the producer's own line cap. A longer line means this is not a
    // v1 producer: stop reading it.
    if (typeof line === "string" && line.length > Model.LINE_CAP) {
      droppedLines++
      rejected = true
      stopPreview()
      return
    }
    var r = Model.parsePreviewLine(line, expectedPath, seq)
    switch (r.kind) {
    case "frame":
      frames++
      seq = r.seq
      break
    case "preview":
      // A new lease: the daemon's frame numbers start again.
      resetStream()
      leaseActive = r.active
      leaseFps = r.fps
      pathMismatch = r.pathMismatch
      if (r.active) streamError = ""
      break
    case "error":
      resetStream()
      streamError = r.text
      break
    case "dropped":
      if (r.reason === "too-long") droppedLines++
      else droppedFrames++
      break
    default:
      ignoredLines++
    }
  }

  property Process previewProc: Process {
    // Line mode, as the watch: one line, one JSON value. A line that never
    // ends is buffered without a cap until it does (QML puts nothing in
    // front of SplitParser): the trade-off the watch accepts too. The
    // producer is the user's own CLI, from their own configuration, and it
    // caps its lines; a longer one is caught in ingest() once it ends.
    stdout: SplitParser {
      onRead: function(data) { root.ingest(data) }
    }
    onStarted: {
      root.started = true
      root.starts++
    }
    onExited: function(exitCode, exitStatus) {
      root.exitCode = exitCode
      root.exitCrashed = exitStatus !== 0
    }
    // A binary that cannot be started emits neither started nor exited, only
    // this transition (as for the watch).
    onRunningChanged: if (!running && root.armed) root.previewEnded()
  }
}
