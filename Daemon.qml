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
//
// The background gallery (interface revision Model.MEDIA_REVISION): the
// panel's Gallery... and Add... run one flow at a time on one more child
// (mediaProc), one step after another (Model.mediaStepArgv, mediaStepEnd):
// the gallery's list, the rows the shell's image picker (omarchy-menu-images)
// would show (`--print-rows`; the picker runs only when it has one), then the
// picker itself;
// or the file chooser (omarchy-file-select), then the import of the chosen
// file (`media import background PATH --select`: converting an animated
// image or a video may take a while, so it runs here, beside the command
// queue, and an on/off never waits behind it). Each step's stdout is read in
// line mode: the list's lines as a setup read's (LINE_CAP each, at most
// Model.readLinesCap("media")), a picker's first line only (PATH_CAP), an
// import's not at all. A step still running after Model.MEDIA_WATCHDOG_MS
// (just over ten minutes) is stopped (mediaWatchdog), so a picker that never
// answers, or an import that never ends, frees the two buttons. A selection
// of the picked image is an intent of the command queue; its failure, and a
// step's, lands on the panel's failure line. The panel the flow was started
// from (mediaOpener) is opened again at the end, whatever the end (a cancel
// too), or when the import starts (it says "Adding the background…"
// meanwhile), so the user is back where they were. The last background
// gallery read (a list step's, or the setup dialog's) is kept
// (backgroundMedia): the panel's thumbnail finds the background in force
// there (a video's poster). The
// two tools are looked up on PATH (toolsProc, a fixed script as the
// resolver's) when a widget attaches and whenever a panel opens.
//
// The away image (interface revision Model.PLACEHOLDER_REVISION): the setup
// dialog's Choose... and Add... run the same flows over the `away` gallery
// (a flow's `gallery`); what they end with are setup intents (the image
// set, or imported and set), so their failure, and a step's, lands on the
// dialog's status line. The dialog hides while a flow runs (mediaBusy) and
// shows again at its end.
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
  // The panels that hold the configuration alone (holdConfig): the Battery
  // saver switch reads the daemon's row. The reads are those of
  // Model.panelReads while no dialog holds the setup, those of
  // Model.setupReads while one does.
  property var configHolders: []
  readonly property bool setupHeld: setupHolders.length > 0 || configHolders.length > 0
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

  // ---- background gallery ------------------------------------------------------
  // The two tools on PATH (Model.toolsFromLines; Model.emptyTools until the
  // first lookup has run).
  property var mediaTools: Model.emptyTools()
  property bool toolsArmed: false
  property bool toolsAgain: false
  property var toolsLines: []
  // The flow running (Model.mediaStepEnd's `flow`), or null; one at a time.
  property var mediaFlow: null
  readonly property bool mediaBusy: mediaFlow !== null
  // Add...'s import runs (the panel and the setup dialog say so).
  readonly property bool mediaImporting: mediaFlow !== null && mediaFlow.step === "import"
  // The last background gallery read that went through (Model.readMedia),
  // or null: what the panel's thumbnail looks the background in force up in.
  property var backgroundMedia: null
  // Where the daemon keeps video posters (Model.posterDir): a poster
  // anywhere else is not loaded.
  readonly property string posterDir: Model.posterDir(Quickshell.env("XDG_CACHE_HOME"), Quickshell.env("HOME"))
  property bool mediaArmed: false
  property bool mediaStarted: false
  property bool mediaRejected: false
  property bool mediaTimedOut: false
  property int mediaExitCode: 0
  property string mediaFirst: ""
  property int mediaLines: 0
  // A list step's lines (Model.readMedia reads them at its end), or a rows step's.
  property var mediaList: []
  // The bar widget whose panel started the flow (null: none was open), for
  // reopenMediaPanel.
  property var mediaOpener: null
  // Model.MEDIA_WATCHDOG_MS; the harness shortens it.
  property int mediaWatchdogMs: Model.MEDIA_WATCHDOG_MS
  property var mediaStderr: Model.firstLineStart()
  // Diagnostics, read by the test harness.
  property int mediaSteps: 0
  property int toolsRuns: 0

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
    Qt.callLater(root.probeTools)
  }

  function detach(owner) {
    var index = owners.indexOf(owner)
    if (index === -1) return
    var next = owners.slice()
    next.splice(index, 1)
    owners = next
    if (mediaOpener === owner) mediaOpener = null
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
    if (open === panelOpen) return
    panelOpen = open
    // A tool installed or removed since the last look shows on the next opening.
    if (open) Qt.callLater(root.probeTools)
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
    // A panel still holds the configuration: the dialog's other reads go,
    // that one is read again with the dialog gone.
    setup = Model.setupForReads(setup, configHolders.length > 0 ? Model.panelReads(record) : [])
    if (configHolders.length > 0) refreshSetup()
  }

  // The panel's hold on the configuration (only `config`, and only against
  // a daemon of Model.BATTERY_SAVER_REVISION or later): the Battery saver
  // switch draws the daemon's row, so the plugin reads it while a panel is
  // open.
  function holdConfig(holder) {
    if (!holder || configHolders.indexOf(holder) !== -1) return
    configHolders = configHolders.concat([holder])
    refreshSetup()
  }

  function releaseConfig(holder) {
    var index = configHolders.indexOf(holder)
    if (index === -1) return
    var next = configHolders.slice()
    next.splice(index, 1)
    configHolders = next
    if (next.length > 0 || setupHolders.length > 0) return
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
    var reads = setupHolders.length > 0 ? Model.setupReads(record) : Model.panelReads(record)
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
    if (typeof line !== "string" || line.length > Model.LINE_CAP || readLines.length >= Model.readLinesCap(readKind)) {
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
    else result = Model.setupRead(kind, readLines, readExitCode, readStderr.text, posterDir)
    readLines = []
    readStarted = false
    if (setupHeld) setup = Model.withSetupRead(setup, kind, result)
    if (kind === "media" && result && result.ok === true) backgroundMedia = result
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
    var failureOf = Model.isStartIntent(intent) ? Model.startFailureText : Model.commandFailureText
    var failure = !started ? failureOf(-1, "", cliPath)
      : (commandExitCode === 0 ? "" : failureOf(commandExitCode, commandStderr.text, cliPath))
    // A setup write's result is the dialog's to show, not the panel's.
    if (Model.isSetupIntent(intent)) setupError = failure
    else commandError = failure
    var ok = started && commandExitCode === 0
    // Whatever it changed (or not), the dialog shows the daemon's word: read
    // again, unless a change line since it started has done so already.
    if (Model.isSetupIntent(intent) && (!ok || !setupChangeSeen)) Qt.callLater(root.refreshSetup)
    if (intent && intent.verb === "setting") settingEnded(intent, ok)
    // An import adds to the gallery a dialog may be showing.
    if (intent && intent.verb === "media-import") Qt.callLater(root.refreshSetup)
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

  // Start the stopped daemon through the CLI's `start` (D-Bus activation;
  // the plugin never runs systemctl). The watch, still running, picks the
  // daemon up when it appears.
  function startDaemon() {
    if (commandBusy) return false
    return request({ verb: "start" })
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

  // Use recommended settings: `recommended apply`, for the active camera
  // whose changes the panel listed (Model.recommendedArgv checks again when
  // it runs that it is still the active camera and still has changes). Queued
  // behind a running command as any other ask; camera writes queued before
  // it run first. Nothing is drafted: the settings lines and the next
  // camera_health line show what the daemon did.
  function applyRecommended() {
    var view = Model.healthView(record)
    if (!Model.recommendedShown(view)) return false
    return request({ verb: "recommended", camera: view.camera })
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

  // ---- the background gallery: the panel's Gallery... and Add... ---------------

  // The two tools, looked up again (after the one running, when one is).
  function probeTools() {
    if (toolsProc.running || toolsArmed) { toolsAgain = true; return }
    toolsLines = []
    toolsArmed = true
    toolsRuns++
    toolsProc.command = Model.toolsArgv()
    toolsProc.running = true
  }

  function toolsLine(line) {
    if (toolsLines.length < 4) toolsLines = toolsLines.concat([String(line).slice(0, Model.PATH_CAP + 64)])
  }

  function toolsEnded() {
    toolsArmed = false
    var next = Model.toolsFromLines(toolsLines)
    toolsLines = []
    if (JSON.stringify(next) !== JSON.stringify(mediaTools)) mediaTools = next
    if (toolsAgain) {
      toolsAgain = false
      Qt.callLater(root.probeTools)
    }
  }

  // Gallery...: the panels close (the picker is a fullscreen overlay), the
  // gallery is listed, then the picker runs over its two directories.
  function openGallery() {
    var view = Model.backgroundRowView(record, mediaTools, mediaBusy)
    if (!view.visible || !view.buttons[0].enabled) return false
    return beginMediaFlow({ kind: "gallery", step: "list" })
  }

  // Add...: the panels close, then the file chooser runs.
  function addBackground() {
    var view = Model.backgroundRowView(record, mediaTools, mediaBusy)
    if (!view.visible || !view.buttons[1].enabled) return false
    return beginMediaFlow({ kind: "add", step: "pick" })
  }

  // ---- the away image: the setup dialog's Choose..., Add... and Clear ------------

  // The dialog's Away image row as drawn (Model.awayImageView), from the
  // read configuration.
  function awayImageView() {
    return Model.awayImageView(setup.config, record, mediaTools, mediaBusy || setupBusy)
  }

  // Choose...: the away gallery is listed, then the picker runs over it.
  function chooseAwayImage() {
    var view = awayImageView()
    if (!view.visible || !view.buttons[0].enabled) return false
    return beginMediaFlow({ kind: "gallery", step: "list", gallery: Model.AWAY_KIND })
  }

  // Add...: the file chooser, then the import into the away gallery.
  function addAwayImage() {
    var view = awayImageView()
    if (!view.visible || !view.buttons[1].enabled) return false
    return beginMediaFlow({ kind: "add", step: "pick", gallery: Model.AWAY_KIND })
  }

  // Clear: no away image (black wherever it would show).
  function clearAwayImage() {
    var view = awayImageView()
    if (!view.visible || !view.buttons[2].enabled) return false
    return request({ verb: "setup", op: "away-image", path: "" })
  }

  // A flow's failure line: the dialog's for the away image, else the panel's.
  function mediaFailed(flow, text) {
    if (Model.flowGallery(flow) === Model.AWAY_KIND) setupError = text
    else commandError = text
  }

  // The open panel is remembered (the first open one: a flow is started from
  // a panel), then every panel closes and the flow's first step runs.
  function beginMediaFlow(flow) {
    var widgets = panelOwners()
    var opener = null
    for (var i = 0; i < widgets.length && opener === null; i++) if (widgets[i].opened === true) opener = widgets[i]
    closePanels()
    mediaOpener = opener
    if (startMediaStep(flow)) return true
    Qt.callLater(root.reopenMediaPanel)
    return false
  }

  // A flow ended (picked, imported, refused, failed or cancelled): the panel
  // it was started from opens again, on its widget, so its failure line is
  // seen; not when that widget has gone or another panel is open meanwhile.
  function reopenMediaPanel() {
    var opener = mediaOpener
    mediaOpener = null
    if (opener === null || owners.indexOf(opener) === -1) return
    var widgets = panelOwners()
    for (var i = 0; i < widgets.length; i++) if (widgets[i] !== opener && widgets[i].opened === true) return
    opener.open()
  }

  function startMediaStep(flow) {
    var argv = Model.mediaStepArgv(flow, cliPath, mediaTools, Model.mediaCurrent(flow, record, setup.config), record)
    if (!argv || mediaProc.running || mediaArmed) {
      mediaFlow = null
      return false
    }
    mediaFlow = flow
    mediaFirst = ""
    mediaLines = 0
    mediaList = []
    mediaStarted = false
    mediaRejected = false
    mediaTimedOut = false
    mediaExitCode = 0
    mediaStderr = Model.firstLineStart()
    mediaArmed = true
    mediaSteps++
    mediaProc.command = argv
    mediaProc.running = true
    mediaWatchdog.interval = mediaWatchdogMs
    mediaWatchdog.restart()
    return true
  }

  // A list step keeps its lines, each up to Model.LINE_CAP and at most
  // Model.readLinesCap("media") of them; a picker step only its first line,
  // up to Model.PATH_CAP. Past a cap the step is stopped. An import's lines
  // are counted only (never a reason to stop it half-way). A rows step (the
  // picker's `--print-rows`) keeps the lines of up to Model.LINE_CAP, at most
  // Model.readLinesCap("media") of them, and ignores the rest: one row is
  // all it looks for, so a line past a cap is never a reason to stop it.
  function mediaLine(line) {
    if (mediaRejected) return
    mediaLines++
    if (mediaFlow !== null && mediaFlow.step === "import") return
    if (mediaFlow !== null && mediaFlow.step === "rows") {
      if (typeof line === "string" && line.length <= Model.LINE_CAP && mediaList.length < Model.readLinesCap("media"))
        mediaList = mediaList.concat([line])
      return
    }
    var list = mediaFlow !== null && mediaFlow.step === "list"
    if (!list && mediaLines > 1) return
    var cap = list ? Model.LINE_CAP : Model.PATH_CAP
    if (typeof line !== "string" || line.length > cap || (list && mediaLines > Model.readLinesCap("media"))) {
      mediaRejected = true
      mediaProc.running = false
      return
    }
    if (list) mediaList = mediaList.concat([line])
    else mediaFirst = line
  }

  // The watchdog: a step that outlived Model.MEDIA_WATCHDOG_MS is stopped
  // and the flow ends with Model.MEDIA_TIMEOUT_TEXT (an import's:
  // Model.MEDIA_IMPORT_TIMEOUT_TEXT).
  function mediaTimeout() {
    if (!mediaArmed || !mediaProc.running) return
    mediaTimedOut = true
    mediaProc.running = false
  }

  function mediaEnded() {
    var flow = mediaFlow
    mediaArmed = false
    mediaWatchdog.stop()
    var end = Model.mediaStepEnd(flow, { started: mediaStarted, code: mediaExitCode, first: mediaFirst, lines: mediaLines,
                                         list: mediaList, rejected: mediaRejected, timedOut: mediaTimedOut,
                                         stderr: mediaStderr.text, posterDir: posterDir })
    mediaFirst = ""
    mediaList = []
    if (end.error !== "") {
      mediaFailed(flow, end.error)
      // A failed or stopped import may still have left a file in the
      // gallery: a dialog showing it reads it again.
      if (flow !== null && flow.step === "import") Qt.callLater(root.refreshSetup)
    }
    if (end.flow !== null) {
      if (end.flow.media && Model.flowGallery(end.flow) === Model.MEDIA_KIND) backgroundMedia = end.flow.media
      // The next step on the next turn, never a same-turn re-arm.
      mediaFlow = end.flow
      Qt.callLater(root.nextMediaStep)
      // The import may take a while: the panel is back meanwhile, an
      // earlier failure no longer on it.
      if (end.flow.step === "import") {
        commandError = ""
        Qt.callLater(root.reopenMediaPanel)
      }
      return
    }
    mediaFlow = null
    if (end.imported) {
      // As a command that went through: the failure line clears, and the
      // gallery a dialog may be showing is read again.
      commandError = ""
      Qt.callLater(root.refreshSetup)
    }
    if (end.intent !== null && !request(end.intent)) mediaFailed(flow, Model.commandFailureText(-1, "", cliPath))
    Qt.callLater(root.reopenMediaPanel)
  }

  function nextMediaStep() {
    if (mediaFlow === null || mediaArmed) return
    var flow = mediaFlow
    if (!startMediaStep(flow)) {
      // The next step could not start (a tool gone, or the daemon,
      // meanwhile): the flow ends.
      mediaFailed(flow, flow.step === "import" ? Model.commandFailureText(-1, "", cliPath) : Model.GALLERY_FAILED_TEXT)
      Qt.callLater(root.reopenMediaPanel)
    }
  }

  // A Remove of the setup dialog: only a user item of the read gallery.
  function removeMedia(path) {
    var item = setupBusy ? null : Model.mediaUserItem(setup.media, path)
    return item !== null && request({ verb: "setup", op: "media-remove", path: item.path })
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

  // The resolver: stdout in line mode. The parser hands over each line whole,
  // however long it is (nothing here limits what it buffers before the
  // newline); once a line is delivered it is counted, and the first one is
  // kept cut to Model.PATH_CAP + 1 characters. Only a single-line answer
  // that parseResolverLine accepts is used.
  property Process resolverProc: Process {
    stdout: SplitParser {
      onRead: function(data) {
        root.resolverLines++
        if (root.resolverLines === 1) root.resolverFirst = String(data).slice(0, Model.PATH_CAP + 1)
      }
    }
    onRunningChanged: if (!running && root.resolving) root.resolverFinished()
  }

  // The setup dialog's reads, one at a time (nextRead): stdout in line mode,
  // as the watch's (a camera or module id must not be garbled); stderr in
  // chunks, as a command's. The parser delivers each stdout line whole, however
  // long, and readLine checks its length only then: a line over Model.LINE_CAP,
  // or one past the lines the read's kind allows, stops the read (readProc is
  // stopped and the read fails). So the bound is on what is kept, not on what
  // the parser buffers before a newline arrives.
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

  // Bounds one gallery step (mediaTimeout); started by startMediaStep.
  property Timer mediaWatchdog: Timer {
    repeat: false
    onTriggered: root.mediaTimeout()
  }

  // The tool lookup: a fixed script, stdout in line mode. Each line is
  // delivered whole, however long; toolsLine then keeps the first four, each
  // cut to Model.PATH_CAP + 64 characters, and drops the rest
  // (Model.toolsFromLines reads two).
  property Process toolsProc: Process {
    stdout: SplitParser {
      onRead: function(data) { root.toolsLine(data) }
    }
    onRunningChanged: if (!running && root.toolsArmed) root.toolsEnded()
  }

  // A gallery flow's steps, one at a time (startMediaStep): stdout in line
  // mode (a path must not be garbled); stderr in chunks, as a command's. The
  // parser delivers each stdout line whole, however long, and mediaLine
  // checks it only then, against the caps its own comment gives (a picker
  // step looks at its first line only). So the bounds are on what is kept
  // and on when the step is stopped, not on what the parser buffers before
  // a newline arrives.
  property Process mediaProc: Process {
    stdout: SplitParser {
      onRead: function(data) { root.mediaLine(data) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.mediaStderr = Model.firstLineFeed(root.mediaStderr, String(data)) }
    }
    onStarted: root.mediaStarted = true
    onExited: function(exitCode, exitStatus) { root.mediaExitCode = exitStatus === 0 ? exitCode : 128 + exitCode }
    onRunningChanged: if (!running && root.mediaArmed) root.mediaEnded()
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
