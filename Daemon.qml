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
// the camera settings' write debounce, started only by a user's move.
//
// Settings. allowMultiple is false, so the widgets attached here are the same
// layout entry drawn once per monitor and carry the same `cliPath`; the most
// recently configured widget's value is the one in force.
//
// The setup dialog (SetupDialog.qml, the plugin's overlay) reads its data
// through here too: while it holds the setup (holdSetup), the four reads of
// Model.SETUP_READS run one at a time on one more child (readProc), when it
// opens and again whenever the watch reports a change of the configuration
// or the modules, a new snapshot, or one of its writes has run. Its writes
// go through the same command queue as the panel's. It also forwards the
// panel hotkey here (openPanel), which opens one bar widget's panel.
Singleton {
  id: root

  // ---- readers -------------------------------------------------------------
  property var owners: []
  readonly property int attachedCount: owners.length
  // Whether the panel of any attached bar widget is open (notePanels): what
  // the setup dialog reports to the shell as open, so the panel hotkey,
  // routed to the overlay, still closes an open panel.
  property bool panelOpen: false

  // ---- state shown by the widgets ------------------------------------------
  property var record: Model.emptyRecord("connecting")
  readonly property bool available: Model.available(record)
  // Last control-command failure; cleared by the next success or snapshot.
  property string commandError: ""
  // A command is running or queued: its result has not arrived yet.
  property bool commandBusy: false
  // An on/off toggle waits (the bar's middle click, the panel switch): a
  // command other than a camera setting write or a setup write is running or
  // queued. Those writes never hold it; an on/off ask goes ahead of setting
  // writes in the queue.
  readonly property bool toggleBusy: Model.toggleBlocked(runningIntent, pendingIntents)
  // The microphone's switch waits: its on/off is running or queued
  // (Model.micBlocked), or has ended and the watch's `mic` line does not show
  // it yet (micAwaiting, at most Model.MIC_SWITCH_WAIT_MS). It never holds the
  // camera's, nor the camera's it.
  readonly property bool micBusy: Model.micBlocked(runningIntent, pendingIntents) || micAwaiting !== null
  // The target (true: on, false: off) of a finished `mic on|off` the record
  // does not show yet, else null.
  property var micAwaiting: null

  // ---- CLI resolution ------------------------------------------------------
  property var cliSetting: null
  property bool configured: false
  property string cliPath: ""
  // "setting", "path", or "" (none).
  property string cliSource: ""
  property bool resolving: false
  property bool resolvePending: false
  property bool resolveScheduled: false
  property string resolverFirst: ""
  property int resolverLines: 0

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

  // ---- camera settings -------------------------------------------------------
  // setting id -> the value a slider, a key, a switch or a choice moved to
  // that the daemon has not confirmed yet. The panel shows it instead of the
  // reported value, so a row is not pulled back by a delta about an earlier
  // write. Ids of the grammar only (Model.withSetting), at most
  // Model.SETTINGS_ROW_CAP. Replaced whole on every change.
  property var settingDrafts: ({})
  // id -> the value last requested for it, so a write is never repeated.
  property var settingSent: ({})
  // id -> { value, line }: its last write succeeded and owns change number
  // `line`, still to come; that change settles a draft still at the value,
  // whatever the daemon reports (Model.settleWritten).
  property var settingSettling: ({})
  // Changes read (a delta of a new rev, or the same set again); the number
  // up to which the changes of finished writes are due; the mark of the
  // running command (Model.settingLineMark): it owns change mark + 1, so an
  // earlier write's late change is not its own.
  property int settingLines: 0
  property int settingLinesDue: 0
  property int commandLineMark: 0
  // A draft was left unsent because the queue held Model.SETTING_QUEUE_CAP
  // writes (Model.queueTakes): flushSettings runs again once a command ends.
  property bool settingsDeferred: false

  // ---- setup dialog ------------------------------------------------------------
  // The dialogs that hold the setup (by identity): reads run only while one
  // does.
  property var setupHolders: []
  readonly property bool setupHeld: setupHolders.length > 0
  // The reads' results (Model.emptySetup: null = still loading), replaced
  // whole by each read; emptied when the last holder lets go, so a dialog
  // opened later never shows another moment's data.
  property var setup: Model.emptySetup()
  // A setup write is running or queued: the dialog takes no other.
  readonly property bool setupBusy: Model.setupWriteBusy(runningIntent, pendingIntents)
  // The last setup write's failure; cleared by the next success.
  property string setupError: ""
  // Reads still to run, oldest first; the one running; its lines so far.
  property var readQueue: []
  property string readKind: ""
  property var readLines: []
  property bool readArmed: false
  property bool readStarted: false
  // A line over Model.LINE_CAP, or more than Model.READ_LINES_CAP: the read
  // is stopped and fails.
  property bool readRejected: false
  // A refresh was asked while a read ran: every read runs again after it.
  property bool readAgain: false
  // A change line (snapshot, config_changed, modules_changed) came in since
  // the running setup write started: it has refreshed the reads already, so
  // the write's own end does not read them again.
  property bool setupChangeSeen: false
  property int readExitCode: 0
  property var readStderr: Model.firstLineStart()
  // Diagnostics, read by the test harness.
  property int setupReadRuns: 0

  onWatchWantedChanged: Qt.callLater(root.syncWatch)

  // ---- registration (by identity) ------------------------------------------

  function attach(owner) {
    if (!owner || owners.indexOf(owner) !== -1) return
    owners = owners.concat([owner])
    notePanels()
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
    notePanels()
    if (next.length === 0) syncWatch()
  }

  // ---- the bar widgets' panels (the setup dialog forwards the hotkey) ----------

  // The attached bar widgets, in attach order (a dialog attaches too, while
  // open; it is no panel).
  function panelOwners() {
    var out = []
    for (var i = 0; i < owners.length; i++) if (owners[i] && owners[i].panelOwner === true) out.push(owners[i])
    return out
  }

  // A widget's panel opened or closed (BarWidget.onOpenedChanged), or one
  // attached or went.
  function notePanels() {
    var widgets = panelOwners()
    var open = false
    for (var i = 0; i < widgets.length; i++) if (widgets[i].opened === true) open = true
    if (open !== panelOpen) panelOpen = open
  }

  // Opens one widget's panel, chosen as the shell chooses for its own
  // (Model.pickPanelOwner: the focused screen's). False when there is none.
  function openPanel(focusedScreen) {
    var widgets = panelOwners()
    var candidates = []
    for (var i = 0; i < widgets.length; i++)
      candidates.push({ screenName: String(widgets[i].screenName || ""), visible: widgets[i].visible === true })
    var at = Model.pickPanelOwner(candidates, focusedScreen)
    if (at < 0) return false
    widgets[at].open()
    return true
  }

  function closePanels() {
    var widgets = panelOwners()
    for (var i = 0; i < widgets.length; i++) if (widgets[i].opened === true) widgets[i].close()
  }

  // ---- the setup dialog's data -------------------------------------------------

  function holdSetup(holder) {
    if (!holder || setupHolders.indexOf(holder) !== -1) return
    setupHolders = setupHolders.concat([holder])
    refreshSetup()
  }

  function releaseSetup(holder) {
    var index = setupHolders.indexOf(holder)
    if (index === -1) return
    var next = setupHolders.slice()
    next.splice(index, 1)
    setupHolders = next
    if (next.length > 0) return
    readQueue = []
    readAgain = false
    setup = Model.emptySetup()
  }

  // Every read the daemon supports now (Model.setupReads), from the first;
  // after the one running, when one is. Nothing while no dialog holds the
  // setup.
  function refreshSetup() {
    if (!setupHeld) return
    // What a daemon whose revision dropped (or that went) no longer
    // supports is not shown from an earlier read.
    var reads = Model.setupReads(record)
    var kept = Model.setupForReads(setup, reads)
    for (var i = 0; i < Model.SETUP_READS.length; i++) {
      var kind = Model.SETUP_READS[i]
      if (kept[kind] !== setup[kind]) { setup = kept; break }
    }
    if (readProc.running || readArmed) {
      readAgain = true
      return
    }
    readQueue = reads
    Qt.callLater(root.nextRead)
  }

  function nextRead() {
    if (readProc.running || readArmed || readQueue.length === 0 || !setupHeld) return
    var kind = readQueue[0]
    readQueue = readQueue.slice(1)
    var argv = Model.setupReadArgv(cliPath, kind)
    if (!argv) {
      setup = Model.withSetupRead(setup, kind, Model.readFailed(Model.commandFailureText(-1, "", cliPath)))
      Qt.callLater(root.nextRead)
      return
    }
    readKind = kind
    readLines = []
    readStarted = false
    readRejected = false
    readStderr = Model.firstLineStart()
    readArmed = true
    setupReadRuns++
    readProc.command = argv
    readProc.running = true
  }

  function readLine(line) {
    if (readRejected) return
    if (typeof line !== "string" || line.length > Model.LINE_CAP || readLines.length >= Model.READ_LINES_CAP) {
      readRejected = true
      readProc.running = false
      return
    }
    readLines = readLines.concat([line])
  }

  function readEnded() {
    var kind = readKind
    readArmed = false
    var result
    if (!readStarted) result = Model.readFailed(Model.commandFailureText(-1, "", cliPath))
    else if (readRejected) result = Model.readFailed("omarchy-broadcast printed more than this plugin reads")
    else result = Model.setupRead(kind, readLines, readExitCode, readStderr.text)
    readLines = []
    readStarted = false
    if (setupHeld) setup = Model.withSetupRead(setup, kind, result)
    if (readAgain) {
      readAgain = false
      Qt.callLater(root.refreshSetup)
    } else {
      Qt.callLater(root.nextRead)
    }
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
    resolverProc.command = Model.resolverArgv()
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
      useCli(answer, "path")
    } else {
      useCli("", "")
      record = Model.withLink("cli-missing", Model.resolverMissText())
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
    // The setup dialog's data may have moved: read it again.
    if (result.outcome === "snapshot" || result.outcome === "config_changed" || result.outcome === "modules_changed") {
      setupChangeSeen = true
      Qt.callLater(root.refreshSetup)
    }
    if (result.outcome === "dropped") droppedLines++
    else if (result.outcome === "invalid" || result.outcome === "ignored") ignoredLines++
    // Cameras are compared raw: two ids that differ only in what sanitising
    // strips are still two cameras.
    var before = record.settings
    var beforeRecord = record
    if (result.record !== record) record = result.record
    if (micAwaiting !== null && (!Model.available(record) || Model.micReflects(record, micAwaiting))) settleMicAwait()
    if (result.outcome === "snapshot") commandError = ""
    var after = record.settings
    // The settings are another camera's, or none: no queued write or reset
    // made for the camera shown before runs against it (each also names its
    // camera, see Model.settingIntentBound).
    // (A write of a global setting is the daemon's, not the camera's: it stays.)
    if ((after ? after.camera : "") !== (before ? before.camera : "")) dropQueuedSettings()
    var sameSet = !!before && !!after && before.camera === after.camera && before.serial === after.serial
    if (result.outcome === "snapshot" || result.outcome === "error" || result.outcome === "settings_clear"
        || (result.outcome === "settings" && !sameSet)) {
      // A fresh picture of the daemon, another camera or another structure:
      // nothing of the user's pending moves applies to it, and no change is
      // still due. Moves of a global setting survive another camera or
      // structure (the daemon's own settings do not change with it).
      if (result.outcome === "settings") clearSettingDrafts([beforeRecord, record])
      else clearSettingDrafts()
      settingLinesDue = settingLines
    } else if (result.outcome === "settings_delta" || result.outcome === "settings") {
      // One more change read when the set's rev moved (a large change set is
      // several delta lines of one rev; the same set again after a missed
      // delta counts too).
      if (after.rev > before.rev) settingLines++
      var settled = Model.settleWritten(settingDrafts, settingSettling, settingLines)
      settingSettling = settled.settling
      settleSettingDrafts(settled.drafts)
      // Nothing written is still unconfirmed: no change is due any more (the
      // daemon publishes none for a write that changed nothing).
      if (Object.keys(settingDrafts).length === 0 && !settingWritePending()) settingLinesDue = settingLines
    }
  }

  // A setting or reset write is running or queued.
  function settingWritePending() {
    if (runningIntent && Model.isSettingIntent(runningIntent)) return true
    for (var i = 0; i < pendingIntents.length; i++) if (Model.isSettingIntent(pendingIntents[i])) return true
    return false
  }

  function dropQueuedSettings() {
    var before = pendingIntents.length
    pendingIntents = Model.dropSettingIntents(pendingIntents)
    droppedIntents += before - pendingIntents.length
    commandBusy = commandProc.running || commandArmed || pendingIntents.length > 0
  }

  // Drafts the record confirms (or no longer offers) go, with what was sent
  // for them.
  function settleSettingDrafts(drafts) {
    var next = Model.settleDrafts(drafts, record)
    var sent = Model.withSetting(settingSent, "", undefined)
    for (var id in sent) {
      if (Model.ownValue(next, id) === undefined && !Model.queuedSetting(pendingIntents, id)
          && !(runningIntent && runningIntent.verb === "setting" && runningIntent.id === id))
        sent = Model.withSetting(sent, id, undefined)
    }
    settingDrafts = next
    settingSent = sent
  }

  // All drafts go; given `records` (the sets the settings were of), the
  // drafts of global settings stay, with what was sent and what is settling
  // for them.
  function clearSettingDrafts(records) {
    if (records === undefined) {
      settingsTimer.stop()
      settingsDeferred = false
      settingDrafts = ({})
      settingSent = ({})
      settingSettling = ({})
      return
    }
    settingDrafts = Model.keepGlobalSettings(settingDrafts, records)
    settingSent = Model.keepGlobalSettings(settingSent, records)
    settingSettling = Model.keepGlobalSettings(settingSettling, records)
    if (Object.keys(settingDrafts).length === 0) {
      settingsTimer.stop()
      settingsDeferred = false
    }
  }

  // ---- commands --------------------------------------------------------------

  // An intent ({ verb, on, id, effect, value, camera }) becomes an argv only
  // when it runs: see Model.intentArgv. Behind a running command the queue
  // keeps the latest other ask, the latest value per setting id and the
  // latest reset (Model.enqueueIntent): a slider drag never queues a process
  // per move, and one id never has more than one write in flight.
  function request(intent) {
    if (!Model.intentArgv(intent, cliPath, record)) return false
    // A press of an action row has no draft to keep, so the queue never
    // refuses it for room (Model.ACTION_QUEUE_CAP): marked by the row's type.
    if (intent.verb === "setting") {
      var arow = Model.findSetting(record, intent.id)
      if (arow && arow.type === "action") intent = Object.assign({}, intent, { action: true })
    }
    if (commandProc.running || commandArmed) {
      // Only a setting write is ever refused here (a full queue, see
      // Model.queueTakes); flushSettings keeps the draft of one for later.
      if (!Model.queueTakes(pendingIntents, intent)) return false
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
    if (Model.isSetupIntent(intent)) setupChangeSeen = false
    commandLineMark = Model.settingLineMark(settingLines, settingLinesDue)
    lastCommand = argv
    commandProc.command = argv
    commandProc.running = true
    return true
  }

  function settleMicAwait() {
    micAwaiting = null
    micWaitTimer.stop()
  }

  function flushPending() {
    if (commandProc.running || commandArmed || pendingIntents.length === 0) return
    var intent = pendingIntents[0]
    pendingIntents = pendingIntents.slice(1)
    // Re-checked now: the daemon may have gone, or the CLI path changed.
    if (!armCommand(intent)) {
      droppedIntents++
      if (intent.verb === "setting") settingEnded(intent, false)
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
    var failure = !started ? Model.commandFailureText(-1, "", cliPath)
      : (commandExitCode === 0 ? "" : Model.commandFailureText(commandExitCode, commandStderr.text, cliPath))
    // A setup write's result is the dialog's to show, not the panel's.
    if (Model.isSetupIntent(intent)) setupError = failure
    else commandError = failure
    var ok = started && commandExitCode === 0
    // Whatever it changed (or not), the dialog shows the daemon's word: read
    // again, unless a change line since it started has done so already.
    if (Model.isSetupIntent(intent) && (!ok || !setupChangeSeen)) Qt.callLater(root.refreshSetup)
    if (intent && intent.verb === "setting") settingEnded(intent, ok)
    // A microphone on/off that went through is awaited on the watch's `mic`
    // line (bounded), so the switch does not flip back to the old word first.
    if (Model.isMicIntent(intent)) {
      if (ok && !Model.micReflects(record, intent.on)) {
        micAwaiting = intent.on === true
        micWaitTimer.restart()
      } else {
        settleMicAwait()
      }
    }
    // A write that went through owes the change after its mark.
    // (None for a value already in force: the daemon prints no change then.)
    if (ok && Model.isSettingIntent(intent) && !Model.settingNoop(record, intent, settingLines, settingLinesDue))
      settingLinesDue = Math.max(settingLinesDue, commandLineMark + 1)
    commandBusy = pendingIntents.length > 0
    // The retry is deferred to the next turn, never a same-turn re-arm.
    if (pendingIntents.length > 0) Qt.callLater(root.flushPending)
    // Drafts the full queue did not take are written now there is room (the
    // next queued command is armed first: the room is behind it).
    if (settingsDeferred) {
      settingsDeferred = false
      Qt.callLater(root.flushSettings)
    }
  }

  // A setting write is over. Its draft stays while a newer write for the
  // same id is still to run, or the user has moved on from its value.
  // Otherwise (Model.settingWriteEnd): failed, the draft goes (the row shows
  // the reported value again, and the panel the error); succeeded, the
  // change it owns settles it, or has already (the draft goes now: the
  // daemon reports what the camera took). A change of an earlier write never
  // does. An action has no draft.
  function settingEnded(intent, ok) {
    var id = intent.id
    if (Model.queuedSetting(pendingIntents, id) || Model.ownValue(settingDrafts, id) !== intent.value) return
    // A write of the value already in force gets no change line: its exit
    // settles the draft (else it would wait for a line that never comes).
    if (Model.settingWriteEnd(ok, settingLines, commandLineMark) === "drop" || (ok && Model.settingNoop(record, intent, settingLines, settingLinesDue))) {
      settingDrafts = Model.withSetting(settingDrafts, id, undefined)
      settingSent = Model.withSetting(settingSent, id, undefined)
    } else {
      settingSettling = Model.withSetting(settingSettling, id, { value: intent.value, line: commandLineMark + 1 })
    }
  }

  // The bar's middle click. Ignored while an on/off or other non-setting
  // command is running or queued (toggleBusy); setting writes and setup
  // writes do not hold it.
  function toggleEnabled() {
    if (Model.middleClickAction(record, toggleBusy) !== "toggle") return false
    return request({ verb: "enable", on: !record.enabled })
  }

  function setEnabled(on) {
    return request({ verb: "enable", on: on === true })
  }

  // The Omarchy Broadcast Mic on or off (`mic on|off`): only while the
  // daemon reports it (Model.intentArgv checks it again when it runs), and
  // not while the last one's result is still to come.
  function setMicHost(on) {
    if (micBusy || !Model.micSupported(record)) return false
    return request({ verb: "mic-host", on: on === true })
  }

  function selectCamera(id) {
    return request({ verb: "select", id: id })
  }

  function nextCamera() {
    return request({ verb: "next" })
  }

  // A row moved (a slider, a key, a switch, a choice) to `value`: kept as a
  // draft, made a value of the row (Model.rowValue: an int on its grid,
  // a strict boolean, one of its options), and written
  // CONTROLS_DEBOUNCE_MS after the last move. Nothing for a setting the
  // daemon does not offer now, or one it greys out.
  function moveSetting(id, value) {
    var row = Model.settingsSupported(record) ? Model.findSetting(record, id) : null
    var v = row && row.enabled ? Model.rowValue(row, value) : null
    if (v === null) return false
    settingDrafts = Model.withSetting(settingDrafts, row.id, v)
    settingsTimer.restart()
    return true
  }

  // The slider was released, the switch flipped or the choice clicked: the
  // draft is written at once.
  function commitSetting(id, value) {
    if (!moveSetting(id, value)) return false
    settingsTimer.stop()
    flushSettings()
    return true
  }

  // Each draft not written yet becomes a setting intent, bound to the camera
  // of the set the row showed; the queue keeps one per id behind a running
  // command. A draft the queue cannot take now (Model.SETTING_QUEUE_CAP
  // slider writes or Model.QUICK_QUEUE_CAP quick ones are waiting, none for
  // its id) stays a draft, unsent: it is not dropped and not marked sent, and
  // commandEnded calls this again. Walks only the drafts (at most
  // Model.SETTINGS_ROW_CAP ids).
  function flushSettings() {
    var drafts = Model.withSetting(settingDrafts, "", undefined)
    var camera = record.settings ? record.settings.camera : ""
    for (var id in drafts) {
      var v = drafts[id]
      if (v === Model.ownValue(settingSent, id)) continue
      var row = Model.findSetting(record, id)
      var intent = { verb: "setting", id: id, value: v, camera: camera }
      if (row && row.scope === "global") intent.scope = "global"
      // A switch or a choice is one click, not a drag: it does not wait
      // behind queued slider writes (Model.enqueueIntent).
      if (row && (row.type === "bool" || row.type === "enum")) intent.quick = true
      if ((commandProc.running || commandArmed) && !Model.queueTakes(pendingIntents, intent)) {
        settingsDeferred = true
        continue
      }
      if (request(intent)) {
        settingSent = Model.withSetting(settingSent, id, v)
      } else {
        settingDrafts = Model.withSetting(settingDrafts, id, undefined)
        settingSent = Model.withSetting(settingSent, id, undefined)
      }
    }
  }

  // An action row (a button): run once, now; it has no value to draft.
  function runSettingAction(id) {
    var row = Model.settingsSupported(record) ? Model.findSetting(record, id) : null
    if (!row || row.type !== "action" || !row.enabled) return false
    return request({ verb: "setting", id: row.id, value: true, camera: record.settings.camera, quick: true })
  }

  // Every setting of the camera back to its default; what the user had not
  // written yet is dropped with the queued writes (Model.enqueueIntent).
  function resetSettings() {
    if (!record.settings || !request({ verb: "reset-settings", camera: record.settings.camera })) return false
    clearSettingDrafts([record])
    return true
  }

  // ---- setup writes (the dialog's): one at a time, each re-read after it ------

  // A module on or off, by the id of a row the read list has; not while a
  // later config file sets its enabled key.
  function setModuleEnabled(id, on) {
    var list = setup.modules
    if (setupBusy || !list || list.ok !== true || typeof on !== "boolean") return false
    for (var i = 0; i < list.modules.length; i++) {
      var m = list.modules[i]
      if (m.id === id) return m.overriddenBy === "" && request({ verb: "setup", op: "module", id: m.id, on: on })
    }
    return false
  }

  // Stage `index` one place up (-1) or down (1): only a move the daemon
  // offered (Model.orderAfterMove), written as the whole new order.
  function moveStage(index, direction) {
    var next = setupBusy ? null : Model.orderAfterMove(setup.order, index, direction)
    return next !== null && request({ verb: "setup", op: "order", order: next })
  }

  function resetOrder() {
    var order = setup.order
    if (setupBusy || !order || order.ok !== true || order.overriddenBy !== "") return false
    return request({ verb: "setup", op: "order-reset" })
  }

  // A config key to `value`: only a row of the read configuration that the
  // daemon takes a write for, as one of the row's values (Model.configWord).
  function setConfig(id, value) {
    var row = setupBusy ? null : Model.findConfigRow(setup.config, id)
    var word = row ? Model.configWord(row, value) : null
    return word !== null && request({ verb: "setup", op: "config", id: row.id, word: word })
  }

  // ---- children ------------------------------------------------------------

  // One-shot: started (restarted) only by moveSetting, a user's move.
  property Timer settingsTimer: Timer {
    interval: Model.CONTROLS_DEBOUNCE_MS
    repeat: false
    onTriggered: root.flushSettings()
  }

  // Bounds the microphone switch's wait for the watch's `mic` line.
  property Timer micWaitTimer: Timer {
    interval: Model.MIC_SWITCH_WAIT_MS
    repeat: false
    onTriggered: root.settleMicAwait()
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

  // The setup dialog's reads, one at a time (nextRead): stdout in line mode,
  // as the watch's (a camera or module id must not be garbled), bounded by
  // readLine; stderr in chunks, as a command's.
  property Process readProc: Process {
    stdout: SplitParser {
      onRead: function(data) { root.readLine(data) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.readStderr = Model.firstLineFeed(root.readStderr, String(data)) }
    }
    onStarted: root.readStarted = true
    onExited: function(exitCode, exitStatus) { root.readExitCode = exitStatus === 0 ? exitCode : 128 + exitCode }
    onRunningChanged: if (!running && root.readArmed) root.readEnded()
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
