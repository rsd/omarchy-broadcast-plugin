pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The one link to omarchy-broadcastd for every bar on every monitor: one
// `omarchy-broadcast watch --json` child, one command child, one record. The
// qmldir beside this file declares it a singleton; without that line the
// name resolves to the component type and every read off it is undefined.
//
// Lifecycle. Widgets attach on completion and detach in their
// Component.onDestruction, by identity. The watch runs only while at least one
// widget is attached (and no backoff is pending). A plugin reload destroys
// every widget, so the watch stops as the last one detaches. In Quickshell
// 0.3.2 the shell cannot clear the component cache (Qt.clearComponentCache is
// not a function there), so a reload from the same URL keeps this instance and
// the rebuilt widgets attach to it again; a reload from another URL makes a
// new instance and strands this one, which then has no readers and stays
// silent. Nothing here polls: the stream is event-driven, and the only timers
// are one-shots: the respawn backoff after the watch exits on its own, and
// the camera image sliders' write debounce, started only by a user's move.
//
// Settings. allowMultiple is false, so the widgets attached here are the same
// layout entry drawn once per monitor and carry the same `cliPath`; the most
// recently configured widget's value is the one in force.
Singleton {
  id: root

  // ---- readers -------------------------------------------------------------
  property var owners: []
  readonly property int attachedCount: owners.length

  // ---- state shown by the widgets ------------------------------------------
  property var record: Model.emptyRecord("connecting")
  readonly property bool available: Model.available(record)
  // Last control-command failure; cleared by the next success or snapshot.
  property string commandError: ""
  // A command is running or queued: its result has not arrived yet.
  property bool commandBusy: false
  // An on/off toggle waits (the bar's right click, the panel switch): a
  // command other than a camera image write is running or queued. Slider
  // writes never hold it; an on/off ask goes ahead of them in the queue.
  readonly property bool toggleBusy: Model.toggleBlocked(runningIntent, pendingIntents)

  // ---- CLI resolution ------------------------------------------------------
  property var cliSetting: null
  property bool configured: false
  property string cliPath: ""
  // "setting", "path", "development", or "" (none).
  property string cliSource: ""
  property bool resolving: false
  property bool resolvePending: false
  property bool resolveScheduled: false
  property string resolverFirst: ""
  property int resolverLines: 0
  readonly property string pluginDir: Model.localPathFromUrl(Qt.resolvedUrl("."))

  // ---- watch process -------------------------------------------------------
  property bool backingOff: false
  // The delay the next unexpected exit waits before the respawn.
  property int backoffMs: Model.BACKOFF_MIN_MS
  property bool watchArmed: false
  property bool watchStarted: false
  property bool watchStopping: false
  // Stopped by ingest() for a line no v1 producer prints: an unexpected end.
  property bool watchRejected: false
  property real watchStartedAt: 0
  property int watchExitCode: 0
  property bool watchExitCrashed: false
  readonly property bool watchWanted: Model.shouldWatch(attachedCount, cliPath, backingOff)
  readonly property int watchPid: watchProc.running ? Number(watchProc.processId || 0) : 0

  // Diagnostics, read by the test harness.
  property int watchStarts: 0
  property int watchStartFailures: 0
  property int resolverRuns: 0
  property int droppedLines: 0
  property int ignoredLines: 0
  property int droppedIntents: 0
  property var lastCommand: null

  // ---- command process -----------------------------------------------------
  // Intents waiting behind the running command, oldest first; see
  // Model.enqueueIntent (bounded by Model.INTENT_QUEUE_CAP).
  property var pendingIntents: []
  // The intent of the running command.
  property var runningIntent: null
  property bool commandArmed: false
  property bool commandStarted: false
  property int commandExitCode: 0
  property var commandStderr: Model.firstLineStart()

  // ---- camera image controls -------------------------------------------------
  // name -> the value a slider (or a key) moved to that the daemon has not
  // confirmed yet. The panel shows it instead of the reported value, so a
  // slider is not pulled back by a controls line about an earlier write.
  // Names of Model.CONTROL_NAMES only. Replaced whole on every change.
  property var controlDrafts: ({})
  // name -> the value last requested for it, so a write is never repeated.
  property var controlSent: ({})
  // name -> { value, line }: its last write succeeded and owns controls
  // line number `line`, still to come; that line settles a draft still at
  // the value, whatever the daemon reports (Model.settleWritten).
  property var controlSettling: ({})
  // Controls lines read; the number up to which the lines of finished
  // writes are due; the mark of the running command (Model.controlLineMark):
  // it owns line mark + 1, so an earlier write's late line is not its own.
  property int controlLines: 0
  property int controlLinesDue: 0
  property int commandLineMark: 0

  onWatchWantedChanged: Qt.callLater(root.syncWatch)

  // ---- registration (by identity) ------------------------------------------

  function attach(owner) {
    if (!owner || owners.indexOf(owner) !== -1) return
    owners = owners.concat([owner])
    // Deferred: the bar injects a widget's settings right after it completes,
    // so the first resolution sees the configured cliPath, not the default.
    // A searched path is looked up again on every attach (a reload, a new
    // monitor): the binary found last time may have gone or been installed.
    if (!configured || cliSource !== "setting") scheduleResolve()
  }

  function detach(owner) {
    var index = owners.indexOf(owner)
    if (index === -1) return
    var next = owners.slice()
    next.splice(index, 1)
    owners = next
    if (next.length === 0) syncWatch()
  }

  function configure(owner, value) {
    if (owners.indexOf(owner) === -1) return
    var normalized = value === undefined ? null : value
    if (configured && String(normalized) === String(cliSetting) && typeof normalized === typeof cliSetting) return
    cliSetting = normalized
    configured = true
    scheduleResolve()
  }

  // ---- CLI resolution: on attach, on a setting change and after a searched
  // binary failed to start (once per failure, so bounded by the backoff);
  // never on a timer of its own.

  function scheduleResolve() {
    if (resolveScheduled) return
    resolveScheduled = true
    Qt.callLater(root.resolve)
  }

  function resolve() {
    resolveScheduled = false
    if (attachedCount === 0) return
    var plan = Model.cliPlan(cliSetting, Quickshell.env("HOME"))
    if (plan.mode === "setting") {
      useCli(plan.path, "setting")
      return
    }
    if (plan.mode === "invalid") {
      // Nothing runs: no watch, no command (cliPath is empty).
      useCli("", "")
      record = Model.withLink("cli-missing", plan.reason)
      return
    }
    // A search is already out: ask again once it is back (one flag).
    if (resolverProc.running || resolving) {
      resolvePending = true
      return
    }
    resolverFirst = ""
    resolverLines = 0
    resolving = true
    resolverRuns++
    resolverProc.command = Model.resolverArgv(pluginDir)
    resolverProc.running = true
  }

  function resolverFinished() {
    resolving = false
    if (resolvePending) {
      resolvePending = false
      Qt.callLater(root.resolve)
      return
    }
    // A cliPath setting that arrived meanwhile wins over the search.
    if (Model.cliPlan(cliSetting, Quickshell.env("HOME")).mode !== "search") return
    var answer = Model.resolverAnswer(resolverFirst, resolverLines)
    if (answer !== "") {
      useCli(answer, answer.indexOf("/target/release/") !== -1 ? "development" : "path")
    } else {
      useCli("", "")
      record = Model.withLink("cli-missing", Model.resolverMissText(pluginDir))
    }
  }

  function useCli(path, source) {
    cliSource = source
    if (path === cliPath) {
      syncWatch()
      return
    }
    cliPath = path
    backoffTimer.stop()
    backingOff = false
    backoffMs = Model.BACKOFF_MIN_MS
    if (path !== "") record = Model.withLink("connecting")
    // A watch on the old binary is stopped; the idle transition re-arms it.
    if (watchProc.running) stopWatch()
    else syncWatch()
  }

  // ---- watch ---------------------------------------------------------------

  function syncWatch() {
    if (watchWanted) {
      if (!watchProc.running && !watchArmed) armWatch()
    } else if (watchProc.running && !watchStopping) {
      stopWatch()
    }
  }

  function armWatch() {
    var argv = Model.watchArgv(cliPath)
    if (!argv) return
    watchStarted = false
    watchStopping = false
    watchRejected = false
    watchArmed = true
    // Assign the command, then arm: the answer belongs to this binary.
    watchProc.command = argv
    watchProc.running = true
  }

  function stopWatch() {
    watchStopping = true
    watchProc.running = false
  }

  function watchEnded() {
    var started = watchStarted
    var rejected = watchRejected
    var deliberate = watchStopping && !rejected
    var uptime = started ? Date.now() - watchStartedAt : 0
    watchArmed = false
    watchStarted = false
    watchStopping = false
    watchRejected = false
    if (deliberate) {
      // Never flip `running` back on in the turn it went off.
      Qt.callLater(root.syncWatch)
      return
    }
    // A rejected producer never earns the short delay back.
    var delay = Model.backoffAfterExit(backoffMs, rejected ? 0 : uptime)
    if (rejected) {
      record = Model.withLink("unsupported", "omarchy-broadcast printed a line longer than " + Model.LINE_CAP
        + " characters, which no schema v1 producer does; restarting in " + Math.round(delay / 1000) + " s")
    } else if (!started) {
      watchStartFailures++
      record = Model.withLink("cli-missing", Model.CLI_MISSING_TEXT + ": " + cliPath)
      // A searched binary may have moved (cargo clean, an uninstall): look
      // again, once for this failure. A configured path is the user's.
      if (cliSource !== "setting") scheduleResolve()
    } else {
      record = Model.withLink("cli-failed", Model.watchExitText(watchExitCode, watchExitCrashed, delay))
    }
    startBackoff(delay)
  }

  function startBackoff(delay) {
    backingOff = true
    backoffTimer.interval = delay
    backoffTimer.restart()
    backoffMs = Model.nextBackoff(delay)
  }

  function ingest(line) {
    // Lines from a watch that is being stopped belong to the old binary.
    if (watchStopping) return
    // SplitParser has already read the whole line (it has no length cap); the
    // producer's 4096-byte cap is the first bound (Model.LINE_CAP). A longer
    // line means this is not a v1 producer: stop reading it, back off, retry.
    if (typeof line === "string" && line.length > Model.LINE_CAP) {
      droppedLines++
      watchRejected = true
      stopWatch()
      return
    }
    var result = Model.reduce(record, line)
    if (result.outcome === "dropped") droppedLines++
    else if (result.outcome === "invalid" || result.outcome === "ignored") ignoredLines++
    // Compared raw: two ids that differ only in what sanitising strips are
    // still two cameras.
    var camera = record.controlsCameraId
    if (result.record !== record) record = result.record
    if (result.outcome === "snapshot") commandError = ""
    var otherCamera = record.controlsCameraId !== camera
    // The controls are another camera's: no queued write or reset made for
    // the one shown before runs against it.
    if (otherCamera) dropQueuedControls()
    if (result.outcome === "snapshot" || (result.outcome === "controls" && otherCamera)) {
      // A fresh picture of the daemon, or another camera: nothing of the
      // user's pending moves applies to it, and no line is still due.
      clearControlDrafts()
      controlLinesDue = controlLines
    } else if (result.outcome === "controls") {
      controlLines++
      var settled = Model.settleWritten(controlDrafts, controlSettling, controlLines)
      controlSettling = settled.settling
      settleControlDrafts(settled.drafts)
      // Nothing written is still unconfirmed: no line is due any more (the
      // daemon prints none for a write that changed nothing).
      if (Object.keys(controlDrafts).length === 0 && !controlWritePending()) controlLinesDue = controlLines
    } else if (result.outcome === "error") {
      // Unavailable: no control is offered until the next snapshot.
      clearControlDrafts()
      controlLinesDue = controlLines
    }
  }

  // A control or reset write is running or queued.
  function controlWritePending() {
    if (runningIntent && Model.isControlIntent(runningIntent)) return true
    for (var i = 0; i < pendingIntents.length; i++) if (Model.isControlIntent(pendingIntents[i])) return true
    return false
  }

  function dropQueuedControls() {
    var before = pendingIntents.length
    pendingIntents = Model.dropControlIntents(pendingIntents)
    droppedIntents += before - pendingIntents.length
    commandBusy = commandProc.running || commandArmed || pendingIntents.length > 0
  }

  // Drafts the record confirms (or no longer offers) go, with what was sent
  // for them.
  function settleControlDrafts(drafts) {
    var next = Model.settleDrafts(drafts, record)
    var sent = controlSent
    for (var i = 0; i < Model.CONTROL_NAMES.length; i++) {
      var name = Model.CONTROL_NAMES[i]
      if (next[name] === undefined && !Model.queuedControl(pendingIntents, name)
          && !(runningIntent && runningIntent.verb === "control" && runningIntent.name === name))
        sent = Model.withKey(sent, name, undefined)
    }
    controlDrafts = next
    controlSent = sent
  }

  function clearControlDrafts() {
    controlTimer.stop()
    controlDrafts = ({})
    controlSent = ({})
    controlSettling = ({})
  }

  // ---- commands --------------------------------------------------------------

  // An intent ({ verb, on, id, effect, name, value }) becomes an argv only
  // when it runs: see Model.intentArgv. Behind a running command the queue
  // keeps the latest other ask, the latest value per control and the latest
  // reset (Model.enqueueIntent): a slider drag never queues a process per
  // move.
  function request(intent) {
    if (!Model.intentArgv(intent, cliPath, record)) return false
    if (commandProc.running || commandArmed) {
      pendingIntents = Model.enqueueIntent(pendingIntents, intent)
      commandBusy = true
      return true
    }
    return armCommand(intent)
  }

  function armCommand(intent) {
    var argv = Model.intentArgv(intent, cliPath, record)
    if (!argv) return false
    commandStderr = Model.firstLineStart()
    commandStarted = false
    commandArmed = true
    commandBusy = true
    runningIntent = intent
    commandLineMark = Model.controlLineMark(controlLines, controlLinesDue)
    lastCommand = argv
    commandProc.command = argv
    commandProc.running = true
    return true
  }

  function flushPending() {
    if (commandProc.running || commandArmed || pendingIntents.length === 0) return
    var intent = pendingIntents[0]
    pendingIntents = pendingIntents.slice(1)
    // Re-checked now: the daemon may have gone, or the CLI path changed.
    if (!armCommand(intent)) {
      droppedIntents++
      if (intent.verb === "control") controlEnded(intent, false)
      commandBusy = pendingIntents.length > 0
      // The next one, on the next turn (one at a time, never a same-turn loop).
      if (pendingIntents.length > 0) Qt.callLater(root.flushPending)
    }
  }

  function commandEnded() {
    var started = commandStarted
    var intent = runningIntent
    commandArmed = false
    commandStarted = false
    runningIntent = null
    if (!started) commandError = Model.commandFailureText(-1, "", cliPath)
    else if (commandExitCode === 0) commandError = ""
    else commandError = Model.commandFailureText(commandExitCode, commandStderr.text, cliPath)
    var ok = started && commandExitCode === 0
    if (intent && intent.verb === "control") controlEnded(intent, ok)
    // A write that went through owes the line after its mark.
    if (ok && Model.isControlIntent(intent)) controlLinesDue = Math.max(controlLinesDue, commandLineMark + 1)
    commandBusy = pendingIntents.length > 0
    // The retry is deferred to the next turn, never a same-turn re-arm.
    if (pendingIntents.length > 0) Qt.callLater(root.flushPending)
  }

  // A control write is over. Its draft stays while a newer write for the
  // same control is still to run, or the user has moved on from its value.
  // Otherwise (Model.controlWriteEnd): failed, the draft goes (the slider
  // shows the reported value again, and the panel the error); succeeded,
  // the controls line it owns settles it, or has already (the draft goes
  // now: the daemon reports what the camera took). A line of an earlier
  // write never does.
  function controlEnded(intent, ok) {
    var name = intent.name
    if (Model.queuedControl(pendingIntents, name) || controlDrafts[name] !== intent.value) return
    if (Model.controlWriteEnd(ok, controlLines, commandLineMark) === "drop") {
      controlDrafts = Model.withKey(controlDrafts, name, undefined)
      controlSent = Model.withKey(controlSent, name, undefined)
    } else {
      controlSettling = Model.withKey(controlSettling, name, { value: intent.value, line: commandLineMark + 1 })
    }
  }

  // The bar's right click. Ignored while an on/off or other non-control
  // command is running or queued (toggleBusy); slider writes do not hold it.
  function toggleEnabled() {
    if (Model.rightClickAction(record, toggleBusy) !== "toggle") return false
    return request({ verb: "enable", on: !record.enabled })
  }

  function setEnabled(on) {
    return request({ verb: "enable", on: on === true })
  }

  function selectCamera(id) {
    return request({ verb: "select", id: id })
  }

  function nextCamera() {
    return request({ verb: "next" })
  }

  // `effect` is checked against Model.EFFECTS when the command is armed.
  function setEffect(effect) {
    return request({ verb: "effect", effect: effect })
  }

  // `on` must be a boolean; Model.denoiseArgv turns it into `on` or `off`
  // when the command is armed.
  function setDenoise(on) {
    return request({ verb: "denoise", on: on === true })
  }

  // A slider moved (or a key nudged it) to `value`: kept as a draft, put on
  // the control's grid, and written CONTROLS_DEBOUNCE_MS after the last move.
  // Nothing for a control the daemon does not offer now.
  function moveControl(name, value) {
    var v = Model.clampControl(Model.controlsSupported(record) ? Model.findControl(record, name) : null, value)
    if (v === null) return false
    controlDrafts = Model.withKey(controlDrafts, name, v)
    controlTimer.restart()
    return true
  }

  // The slider was released: the draft is written at once.
  function commitControl(name, value) {
    if (!moveControl(name, value)) return false
    controlTimer.stop()
    flushControls()
    return true
  }

  // Each draft not written yet becomes a control intent; the queue keeps one
  // per control behind a running command.
  function flushControls() {
    for (var i = 0; i < Model.CONTROL_NAMES.length; i++) {
      var name = Model.CONTROL_NAMES[i]
      var v = controlDrafts[name]
      if (v === undefined || v === controlSent[name]) continue
      // Bound to the camera the slider showed (Model.controlIntentBound).
      if (request({ verb: "control", name: name, value: v, camera: record.controlsCameraId })) {
        controlSent = Model.withKey(controlSent, name, v)
      } else {
        controlDrafts = Model.withKey(controlDrafts, name, undefined)
        controlSent = Model.withKey(controlSent, name, undefined)
      }
    }
  }

  // Every control back to the camera's default; what the user had not
  // written yet is dropped with the queued writes (Model.enqueueIntent).
  function resetControls() {
    if (!request({ verb: "reset-controls", camera: record.controlsCameraId })) return false
    clearControlDrafts()
    return true
  }

  // ---- children ------------------------------------------------------------

  // One-shot: started (restarted) only by moveControl, a user's move.
  property Timer controlTimer: Timer {
    interval: Model.CONTROLS_DEBOUNCE_MS
    repeat: false
    onTriggered: root.flushControls()
  }

  property Timer backoffTimer: Timer {
    repeat: false
    onTriggered: {
      root.backingOff = false
      root.syncWatch()
    }
  }

  property Process watchProc: Process {
    // Line mode on purpose: a chunked read decodes each chunk on its own and
    // turns a multi-byte character cut by a read boundary into U+FFFD, which
    // would corrupt a camera id (measured under Quickshell 0.3.2).
    stdout: SplitParser {
      onRead: function(data) { root.ingest(data) }
    }
    onStarted: {
      root.watchStarted = true
      root.watchStartedAt = Date.now()
      root.watchStarts++
      // A failure message stays up through retries until a watch really runs.
      if (root.record.link === "cli-missing" || root.record.link === "cli-failed" || root.record.link === "unsupported")
        root.record = Model.withLink("connecting")
    }
    onExited: function(exitCode, exitStatus) {
      root.watchExitCode = exitCode
      root.watchExitCrashed = exitStatus !== 0
    }
    // A binary that cannot be started emits neither started nor exited, only
    // this transition (verified under Quickshell 0.3.2).
    onRunningChanged: if (!running && root.watchArmed) root.watchEnded()
  }

  property Process resolverProc: Process {
    stdout: SplitParser {
      // Lines are counted: only a single-line answer is used.
      onRead: function(data) {
        root.resolverLines++
        if (root.resolverLines === 1) root.resolverFirst = String(data).slice(0, Model.PATH_CAP + 1)
      }
    }
    onRunningChanged: if (!running && root.resolving) root.resolverFinished()
  }

  property Process commandProc: Process {
    // Chunks, not lines: the CLI's stderr is unbounded, and only its first
    // line (capped) is kept; see Model.firstLineFeed.
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.commandStderr = Model.firstLineFeed(root.commandStderr, String(data)) }
    }
    onStarted: root.commandStarted = true
    onExited: function(exitCode, exitStatus) { root.commandExitCode = exitStatus === 0 ? exitCode : 128 + exitCode }
    onRunningChanged: if (!running && root.commandArmed) root.commandEnded()
  }
}
