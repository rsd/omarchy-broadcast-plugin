.pragma library

// Everything the bar widget decides, as pure functions over plain values, so
// tests/tst_model.qml can reach all of it without a shell, a daemon or a CLI.
//
// The input is the NDJSON stream of `omarchy-broadcast watch --json`, specified in
// docs/cli-json.md (schema v1). One record of the daemon is kept: a snapshot
// replaces it, a state line replaces its scalars, a cameras line its camera
// list, a stats line its figures, and an error line makes it unavailable until
// the next snapshot. Records are never mutated: every change returns a new
// object, so a QML property holding one notifies its readers.
//
// Every string that leaves this file for the screen has been through
// sanitize(): the shell's tooltip and some of its kit render AutoText, so
// markup is neutralised here, at the source, not at each sink.

var SCHEMA_VERSION = 1

// Product name, as in the manifest and the panel title.
var PRODUCT = "Omarchy Broadcast"

// Ingestion caps. The first cap is the producer's: the CLI writes no line
// longer than 4096 bytes (crates/omarchy-broadcast/src/json.rs, MAX_LINE_BYTES,
// asserted by its tests), in another process, before the pipe. This consumer
// cap only bounds what reaches JSON.parse: Quickshell's SplitParser hands over
// a whole line, so a longer one has already been read into memory when it is
// seen here. A line over this cap is not from a v1 producer, and the Daemon
// stops that watch (and backs off) instead of reading on.
var LINE_CAP = 8192
// Rendered rows (the house number); the producer lists at most 12.
var CAMERA_CAP = 64
// Display bounds, matching the producer's bounds in docs/cli-json.md.
var NAME_CAP = 64
var ID_CAP = 96
var USB_CAP = 16
var ERROR_CAP = 512
var MODE_CAP = 64
// The PipeWire output's state word (docs/cli-json.md bounds it to 32 bytes).
var PIPEWIRE_CAP = 32
var EFFECT_CAP = 32
// The background image path, display only; it is never sent back as an
// argument. The producer clips it to 256 bytes and keeps the end of the path
// (the file name) behind a leading ellipsis (crates/omarchy-broadcast/src/json.rs,
// MAX_PATH_BYTES), so this looser bound does not cut a v1 producer's path; it
// bounds the work for an off-contract one.
var IMAGE_PATH_CAP = 512
// A failed command's stderr: the first line, at most this many characters
// are ever kept (the CLI does not bound its stderr).
var STDERR_CAP = 512
// The part of it shown in the panel.
var DETAIL_CAP = 200
var TOOLTIP_CAP = 200
var PATH_CAP = 4096

// The CLI-missing message; where it names a path, the path follows ": ".
var CLI_MISSING_TEXT = "omarchy-broadcast CLI not found"
// Sane upper bounds for figures: anything above reads as unknown.
var COUNT_MAX = 1000000
var STAT_MAX = 1000000
// A stage's live values (`stage_values` of the snapshot): at most this many
// entries are read, their stage and name words cut to STAGE_WORD_CAP.
var STAGE_VALUES_CAP = 32
var STAGE_WORD_CAP = 48

// Respawn backoff for the watch process: 1 s doubling to 30 s. One-shot;
// armed only by an unexpected exit. It goes back to 1 s only after a watch
// has stayed up for BACKOFF_RESET_UPTIME_MS: a watch that prints its snapshot
// and dies keeps doubling instead of respawning once a second.
var BACKOFF_MIN_MS = 1000
var BACKOFF_MAX_MS = 30000
var BACKOFF_RESET_UPTIME_MS = 30000

var STATES = ["off", "idle", "starting", "active", "error"]

// The daemon interface revision from which the effects come from loadable
// modules and are offered as global settings (obc-ipc INTERFACE_REVISION 9):
// the Effect tab draws them from the settings schema only, and names no
// effect. Below it the tab says that the daemon needs updating.
var MODULES_REVISION = 9
var DAEMON_NO_EFFECTS = "The daemon needs updating for effects (omarchy-broadcastd 0.24 or newer)."
// Said in the Effect tab when the daemon offers no background effect (no
// enabled module provides the stage).
var NO_BACKGROUND_TEXT = "No effect module provides a background effect. Right click the bar icon to set up modules."
// The interface revision of the background gallery (obc-ipc INTERFACE_REVISION
// 15: `media list|import|remove` and `effect replace --image`): the Effect
// tab's Background row and the setup dialog's Backgrounds section. Below it
// the tab keeps the read-only image row.
var MEDIA_REVISION = 15
// The interface revision of the away image (obc-ipc INTERFACE_REVISION 17:
// `output.placeholder`, an editable `effect.fallback_image` and the `away`
// gallery of `media list|import`): the setup dialog's Away image row and the
// Effect tab's Away image row (its Setup... button). Below it the dialog
// keeps the read-only image row and the tab has no such row.
var PLACEHOLDER_REVISION = 17
// The interface revision from which a video's `media_item` line says whether
// the CPU path can play it (`cpu_ready`) and, when it cannot, the ffmpeg
// command that converts it (`convert_command`): the setup dialog's
// Backgrounds rows show it. Below it the keys are never read.
var VIDEO_CONVERT_REVISION = 19
// The largest interface revision the producer can print (a u32).
var REVISION_MAX = 4294967295

// Material Design glyphs from the bar's Nerd Font (checked by rendering them).
var GLYPH_WEBCAM = String.fromCodePoint(0xF05A0)
var GLYPH_WEBCAM_OFF = String.fromCodePoint(0xF1737)
var GLYPH_ALERT = String.fromCodePoint(0xF0028)
var GLYPH_WARNING = String.fromCodePoint(0xF002A) // mdi-alert-outline
var GLYPH_RADIO_ON = String.fromCodePoint(0xF043E)
var GLYPH_RADIO_OFF = String.fromCodePoint(0xF043D)
var GLYPH_NEXT = String.fromCodePoint(0xF04AD)
// mdi-microphone, the glyph the shell's own microphone indicator draws.
var GLYPH_MIC = String.fromCodePoint(0xF036C)

// Unicode "—": what an unknown figure shows, never 0.
var UNKNOWN = "\u2014"

// ---------------------------------------------------------------- sanitising

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

// Display copy of an untrusted string: not a string -> "". Removed: markup
// characters (< > &), bidi marks, embeddings, overrides and isolates (U+061C,
// U+200E, U+200F, U+202A..U+202E, U+2066..U+2069), the zero-width space and
// the byte order mark (U+200B, U+FEFF), and the invisible formatting block
// U+2060..U+206F (word joiner, invisible operators, deprecated format
// controls). Control characters (newlines included) become spaces, runs of
// spaces collapse, and the result is cut to `cap` characters with an
// ellipsis. Kept on purpose: the zero-width joiner and non-joiner (U+200D,
// U+200C), which emoji sequences and Persian or Arabic words need, and the
// variation selectors and tag characters of emoji; none of them reorders
// text. Other invisible characters (soft hyphen, Hangul fillers, ...) are not
// removed either. The input is pre-cut so a huge string costs a bounded
// amount of work; a string that lost its tail there still ends in the
// ellipsis, however little of it is left. `keepAmpersand`: an "&" stays (see
// settingText; without "<" no markup can form, but the shell's
// PanelActionButton and PanelToolTip still get no "&" from this plugin).
function sanitize(value, cap, keepAmpersand) {
  if (typeof value !== "string") return ""
  var limit = Math.max(1, Math.floor(Number(cap) || 1))
  var precut = value.length > limit * 4
  var s = precut ? value.slice(0, limit * 4) : value
  s = s.replace(keepAmpersand === true ? /[<>\u061c\u200b\u200e\u200f\u202a-\u202e\u2060-\u206f\ufeff]/g
                                       : /[<>&\u061c\u200b\u200e\u200f\u202a-\u202e\u2060-\u206f\ufeff]/g, "")
  s = s.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, " ")
  s = s.replace(/ {2,}/g, " ").trim()
  if (s.length > limit || (precut && s.length >= limit)) {
    s = s.slice(0, limit - 1)
    // Never leave half a surrogate pair at the cut.
    var last = s.charCodeAt(s.length - 1)
    if (last >= 0xd800 && last <= 0xdbff) s = s.slice(0, -1)
    s = s + "\u2026"
  } else if (precut) {
    s = s + "\u2026"
  }
  return s
}

function hasControl(s) {
  return /[\u0000-\u001f\u007f]/.test(s)
}

// A camera id as an argv element: exact value, but only a string of 1..96
// UTF-16 units that the producer did not clip (a clipped id ends with the
// ellipsis and can no longer be selected, per docs/cli-json.md). Otherwise "".
function selectableId(value) {
  if (typeof value !== "string") return ""
  if (value.length === 0 || value.length > ID_CAP) return ""
  if (value.charAt(value.length - 1) === "\u2026") return ""
  return value
}

// A USB vid:pid as the producer writes it: four lower-case hex digits a side.
function usbSelector(value) {
  return typeof value === "string" && /^[0-9a-f]{4}:[0-9a-f]{4}$/.test(value) ? value : ""
}

// An id kept only for comparison (active camera vs list rows), never shown.
function rawId(value) {
  return typeof value === "string" && value.length <= ID_CAP * 2 ? value : ""
}

// The daemon's interface revision: an integer in 0..REVISION_MAX, else -1
// (unknown; read as a daemon without effects).
function interfaceRevision(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
    && value >= 0 && value <= REVISION_MAX ? value : -1
}

// A count: an integer in 0..COUNT_MAX, else -1 (unknown).
function count(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
    && value >= 0 && value <= COUNT_MAX ? value : -1
}

// A stats figure: a finite number in 0..STAT_MAX, else null (unknown; -1 on
// the wire).
function statNumber(value) {
  return typeof value === "number" && isFinite(value) && value >= 0 && value <= STAT_MAX ? value : null
}

// ---------------------------------------------------------------- the record

// `link` says whether the record speaks for a live daemon:
//   ok           a snapshot has been read; the scalars below are current
//   connecting   the watch has not printed its first line yet
//   not-running  error line, code daemon-not-running
//   unreachable  error line, code dbus-error or any unknown code
//   cli-missing  the CLI could not be found or started
//   cli-failed   the watch process exited on its own
//   unsupported  the CLI printed a schema version newer than 1, or a line no
//                v1 producer prints
// Anything but `ok` is unavailable: no controls, no stale figures. So is an
// `ok` record whose state string this plugin does not know (see available()).
function emptyRecord(link, linkText) {
  return {
    link: typeof link === "string" && link !== "" ? link : "connecting",
    linkText: typeof linkText === "string" ? sanitize(linkText, ERROR_CAP) : "",
    state: "",
    rawState: "",
    enabled: false,
    error: "",
    warning: "",
    activeCamera: "",
    activeCameraName: "",
    consumers: -1,
    // The split of `consumers` (docs/cli-json.md): processes holding the
    // loopback and links to the PipeWire node; -1 when unknown. A preview
    // lease (interface revision 5) is in `consumers` but in neither of these.
    loopbackConsumers: -1,
    pipewireConsumers: -1,
    // Preview leases (interface revision 5), in `consumers` too; -1 unknown.
    previewConsumers: -1,
    // The PipeWire output's state word, display copy; "" when not reported.
    pipewireOutput: "",
    outputMode: "",
    effect: "",
    backgroundImage: "",
    backgroundImageSet: false,
    // The raw background image path, kept only when it is a usable absolute
    // path (mediaPath): the thumbnail's source and the gallery's --selected
    // argument, never shown. "" otherwise (a clipped path among them).
    backgroundImagePath: "",
    interfaceRevision: -1,
    // The daemon's ConfigSerial and ModulesSerial as the snapshot reports
    // them (`config_serial`, `modules_serial`; 0 from a CLI or daemon that
    // predates them), moved on by `config_changed` and `modules_changed`
    // lines. The setup dialog reads its data again when one moves.
    configSerial: 0,
    modulesSerial: 0,
    cameras: [],
    camerasTotal: 0,
    camerasTruncated: false,
    camerasCapped: false,
    stats: null,
    // The live values stages report (`stage_values`, [] when the camera is
    // idle, nothing reports or the daemon predates them): stageValueList().
    stageValues: [],
    // The snapshot's settings schema (`settings_schema`): "absent" when the
    // snapshot has no such field (a CLI that predates the settings),
    // "number" when it is a number (settingsSchema: that number when it is
    // a whole one, else -1), "null" otherwise (a daemon below
    // SETTINGS_REVISION prints null).
    settingsField: "absent",
    settingsSchema: -1,
    // The committed settings set (see commitSettings): { rev, serial,
    // camera, groups, groupsTotal }, or null. `camera` is the raw id (see
    // rawId): what binds a write to the camera its row showed, and what
    // every write names.
    settings: null,
    // A set whose settings_group lines are still arriving, or null.
    settingsAssembly: null,
    // A settings_clear line said there is nothing to show.
    settingsCleared: false,
    // The snapshot's microphone (`mic`, interface revision MIC_REVISION):
    // "absent" when the snapshot has no such field (a CLI that predates the
    // microphone), "object" when it is one, "null" otherwise (a daemon below
    // MIC_REVISION). `mic` is micFields() of it, or null; a `mic` line
    // replaces it.
    micField: "absent",
    mic: null,
    // The camera's health (interface revision HEALTH_REVISION): healthFields
    // of the snapshot's `camera_health`, or null (null or absent there); a
    // `camera_health` line replaces it.
    health: null
  }
}

function copyRecord(record) {
  var out = {}
  for (var key in record) out[key] = record[key]
  return out
}

// The stream is connected and a snapshot has been read: state, cameras and
// stats lines apply. (The reducer's gate.)
function linked(record) {
  return !!record && record.link === "ok"
}

// The daemon can be shown and controlled: linked, and in a state this plugin
// knows. An unknown state string (only an off-contract producer sends one; a
// new state would bump the schema) is unavailable everywhere: the icon, the
// controls, the clicks and the panel all treat it so.
function available(record) {
  return linked(record) && STATES.indexOf(record.state) >= 0
}

function unknownState(record) {
  return linked(record) && record.state === "unknown"
}

// The `stage_values` of a snapshot or state line: [{ stage, name, value }],
// bounded. An entry that is not an object with a stage, a name and a finite
// number in 0..STAT_MAX is skipped; anything but an array reads as none.
function stageValueList(value) {
  var src = Array.isArray(value) ? value : []
  var n = Math.min(src.length, STAGE_VALUES_CAP)
  var out = []
  for (var i = 0; i < n; i++) {
    var e = src[i]
    if (!isPlainObject(e)) continue
    var stage = sanitize(e.stage, STAGE_WORD_CAP)
    var name = sanitize(e.name, STAGE_WORD_CAP)
    var v = statNumber(e.value)
    if (stage === "" || name === "" || v === null) continue
    out.push({ stage: stage, name: name, value: v })
  }
  return out
}

function applyScalars(r, m) {
  r.state = STATES.indexOf(m.state) >= 0 ? m.state : "unknown"
  r.rawState = sanitize(m.state, MODE_CAP)
  r.enabled = m.enabled === true
  r.error = sanitize(m.error, ERROR_CAP)
  // Interface revision 11; absent from an older daemon, and not an error:
  // the daemon keeps streaming (see visualFor).
  r.warning = sanitize(m.warning, ERROR_CAP)
  r.activeCamera = rawId(m.active_camera)
  r.activeCameraName = sanitize(m.active_camera_name, NAME_CAP)
  r.consumers = count(m.consumers)
  r.loopbackConsumers = count(m.loopback_consumers)
  r.pipewireConsumers = count(m.pipewire_consumers)
  r.previewConsumers = count(m.preview_consumers)
  r.pipewireOutput = sanitize(m.pipewire_output, PIPEWIRE_CAP)
  r.outputMode = sanitize(m.output_mode, MODE_CAP)
  r.effect = sanitize(m.effect, EFFECT_CAP)
  r.backgroundImage = sanitize(m.background_image, IMAGE_PATH_CAP)
  // Whether the daemon holds an image, from the raw field: the display copy
  // above may sanitise to "" and must not decide what can be chosen.
  r.backgroundImageSet = typeof m.background_image === "string" && m.background_image !== ""
  r.backgroundImagePath = mediaPath(m.background_image)
  // The running daemon's interface revision, on the same lines: a new CLI may
  // still be talking to a daemon started before the upgrade.
  r.interfaceRevision = interfaceRevision(m.interface_revision)
  // The key is absent from an older daemon. A snapshot starts from the empty
  // record, so absent reads as none there; a state line that omits it leaves
  // the values as they were.
  if (m.stage_values !== undefined) r.stageValues = stageValueList(m.stage_values)
  // No stats line arrives outside `active`; clear the figures as it is left.
  if (r.state !== "active") {
    r.stats = null
    r.stageValues = []
  }
}

// Reads at most CAMERA_CAP entries of whatever array arrived: the traversal is
// bounded too, not just what is kept.
//
// `selectId` is the argv selector for the row, "" when the row cannot be
// selected. The CLI reads the word `next` as the NextCamera command even after
// `--` (crates/omarchy-broadcast/src/main.rs), so a camera whose id is literally
// "next" is selected by its USB vid:pid instead, when it has one that no other
// listed camera shares; otherwise it cannot be selected (`selectNote` says why).
function cameraList(value) {
  var src = Array.isArray(value) ? value : []
  var n = Math.min(src.length, CAMERA_CAP)
  var out = []
  var usbCount = {}
  for (var i = 0; i < n; i++) {
    var c = src[i]
    if (!isPlainObject(c)) continue
    var id = rawId(c.id)
    var displayId = sanitize(c.id, ID_CAP)
    var name = sanitize(c.name, NAME_CAP)
    var usb = usbSelector(c.usb)
    if (usb !== "") usbCount[usb] = (usbCount[usb] || 0) + 1
    out.push({
      id: id,
      selectId: selectableId(c.id),
      selectNote: "",
      usbSelector: usb,
      displayId: displayId,
      name: name,
      usb: sanitize(c.usb, USB_CAP),
      label: name !== "" ? name : (displayId !== "" ? displayId : "Unnamed camera")
    })
  }
  for (var j = 0; j < out.length; j++) {
    if (out[j].selectId !== "next") continue
    var u = out[j].usbSelector
    if (u !== "" && usbCount[u] === 1) {
      out[j].selectId = u
    } else {
      out[j].selectId = ""
      out[j].selectNote = "Its id is the word next, which the CLI reads as Next camera"
    }
  }
  return { cameras: out, capped: src.length > CAMERA_CAP, total: src.length }
}

function applyCameras(r, m) {
  var list = cameraList(m.cameras)
  r.cameras = list.cameras
  r.camerasCapped = list.capped
  r.camerasTotal = list.total
  r.camerasTruncated = m.cameras_truncated === true || list.capped
}

// One line of the stream -> { kind, reason, message, version }.
//   message      a v1 object with a string `type`
//   dropped      longer than LINE_CAP; never parsed
//   unsupported  a v1+ producer: integer v > 1
//   invalid      not JSON, not an object, no usable v or type
//   ignored      blank
function parseLine(text) {
  if (typeof text !== "string") return { kind: "invalid", reason: "not-text" }
  if (text.length > LINE_CAP) return { kind: "dropped", reason: "too-long" }
  if (text.trim() === "") return { kind: "ignored", reason: "blank" }
  var m
  try {
    m = JSON.parse(text)
  } catch (e) {
    return { kind: "invalid", reason: "malformed" }
  }
  if (!isPlainObject(m)) return { kind: "invalid", reason: "not-object" }
  if (m.v !== SCHEMA_VERSION) {
    if (typeof m.v === "number" && isFinite(m.v) && Math.floor(m.v) === m.v && m.v > SCHEMA_VERSION)
      return { kind: "unsupported", reason: "version", version: m.v }
    return { kind: "invalid", reason: "version" }
  }
  if (typeof m.type !== "string") return { kind: "invalid", reason: "type" }
  return { kind: "message", message: m }
}

// Apply one raw line to a record. Returns { record, outcome }; `record` is the
// same object when nothing changed. Outcomes: snapshot, state, cameras,
// stats, mic, camera_health, settings_group (a part of a set kept), settings (a set committed),
// settings_delta, settings_clear, config_changed, modules_changed, error, ignored (an unknown type, such as
// the `controls` line of interface revision 6, or a line that cannot apply
// in the current link state), dropped, invalid, unsupported.
function reduce(record, text) {
  var base = record || emptyRecord("connecting")
  var p = parseLine(text)
  if (p.kind === "unsupported") {
    if (base.link === "unsupported") return { record: base, outcome: "unsupported" }
    return {
      record: emptyRecord("unsupported", "omarchy-broadcast prints output schema v" + p.version
        + "; this plugin reads v" + SCHEMA_VERSION + ". Update the plugin."),
      outcome: "unsupported"
    }
  }
  if (p.kind !== "message") return { record: base, outcome: p.kind }
  return applyMessage(base, p.message)
}

function applyMessage(record, m) {
  var r
  switch (m.type) {
  case "snapshot":
    r = emptyRecord("ok")
    applyScalars(r, m)
    applyCameras(r, m)
    // A snapshot starts a new picture of the daemon: the settings set that
    // follows it (or a settings_clear) replaces whatever was shown.
    r.settingsField = m.settings_schema === undefined ? "absent"
      : (typeof m.settings_schema === "number" ? "number" : "null")
    r.settingsSchema = interfaceRevision(m.settings_schema)
    r.configSerial = settingsNumber(m.config_serial)
    r.modulesSerial = settingsNumber(m.modules_serial)
    r.micField = m.mic === undefined ? "absent" : (isPlainObject(m.mic) ? "object" : "null")
    r.mic = micFields(m.mic)
    r.health = healthFields(m.camera_health)
    return { record: r, outcome: "snapshot" }
  case "state":
    // Unavailable until the next snapshot (docs/cli-json.md, "Writing a client").
    if (!linked(record)) return { record: record, outcome: "ignored" }
    r = copyRecord(record)
    applyScalars(r, m)
    return { record: r, outcome: "state" }
  case "cameras":
    if (!linked(record)) return { record: record, outcome: "ignored" }
    r = copyRecord(record)
    r.activeCamera = rawId(m.active_camera)
    applyCameras(r, m)
    return { record: r, outcome: "cameras" }
  case "stats":
    if (!linked(record) || record.state !== "active") return { record: record, outcome: "ignored" }
    r = copyRecord(record)
    r.stats = {
      fps: statNumber(m.fps),
      latencyMs: statNumber(m.latency_p50_ms),
      cpuPercent: statNumber(m.cpu_percent),
      gpuPercent: statNumber(m.gpu_percent)
    }
    return { record: r, outcome: "stats" }
  case "mic":
    // The microphone changed (interface revision MIC_REVISION): its fields
    // replace the snapshot's.
    if (!linked(record)) return { record: record, outcome: "ignored" }
    r = copyRecord(record)
    r.micField = "object"
    r.mic = micFields(m)
    return { record: r, outcome: "mic" }
  case "camera_health":
    // The camera's health changed (interface revision HEALTH_REVISION): the
    // whole value, replacing the snapshot's.
    if (!linked(record)) return { record: record, outcome: "ignored" }
    r = copyRecord(record)
    r.health = healthFields(m)
    return { record: r, outcome: "camera_health" }
  case "settings_group":
    // A line of a settings set; the set is committed by its last line.
    if (!linked(record)) return { record: record, outcome: "ignored" }
    r = copyRecord(record)
    var outcome = applySettingsGroup(r, m)
    return outcome === "ignored" ? { record: record, outcome: outcome } : { record: r, outcome: outcome }
  case "settings_delta":
    if (!linked(record)) return { record: record, outcome: "ignored" }
    var set = settingsDelta(record.settings, m)
    if (!set) return { record: record, outcome: "ignored" }
    r = copyRecord(record)
    r.settings = set
    return { record: r, outcome: "settings_delta" }
  case "settings_clear":
    // No camera, so nothing to show: the set and any half-assembled one go.
    if (!linked(record)) return { record: record, outcome: "ignored" }
    r = copyRecord(record)
    r.settings = null
    r.settingsAssembly = null
    r.settingsCleared = true
    return { record: r, outcome: "settings_clear" }
  case "config_changed":
  case "modules_changed":
    // The daemon's configuration (ConfigChanged) or its modules
    // (ModulesSerial) moved: the setup dialog reads them again. A serial
    // that is not one a producer prints is ignored.
    if (!linked(record)) return { record: record, outcome: "ignored" }
    var serial = settingsNumber(m.serial)
    if (serial === 0) return { record: record, outcome: "ignored" }
    r = copyRecord(record)
    if (m.type === "config_changed") r.configSerial = serial
    else r.modulesSerial = serial
    return { record: r, outcome: m.type }
  case "error":
    // An unknown code is treated like dbus-error, as the contract asks.
    r = emptyRecord(m.code === "daemon-not-running" ? "not-running" : "unreachable",
                    typeof m.error === "string" ? m.error : "")
    return { record: r, outcome: "error" }
  default:
    return { record: record, outcome: "ignored" }
  }
}

function withLink(link, text) {
  return emptyRecord(link, text)
}

function isActiveCamera(record, camera) {
  return !!record && !!camera && camera.id !== "" && camera.id === record.activeCamera
}

// The active camera for display: its row's label (a cameras line moves the
// active camera without a new name), else the daemon's name for it, else its
// sanitised id when it is not in the list; "" when no camera is active.
function activeCameraLabel(record) {
  if (!record) return ""
  if (record.activeCamera !== "") {
    var cams = record.cameras || []
    for (var i = 0; i < cams.length; i++) if (cams[i].id === record.activeCamera) return cams[i].label
  }
  if (record.activeCameraName !== "") return record.activeCameraName
  return record.activeCamera !== "" ? sanitize(record.activeCamera, ID_CAP) : ""
}

// ---------------------------------------------------------------- visuals

// The six bar states.
function visualKey(record) {
  if (!available(record)) return "unavailable"
  return record.state
}

// state -> { glyph, colorRole: foreground | accent | urgent, dimmed, faded }.
// The webcam glyph family: idle, starting and active share the webcam and
// differ by colour (foreground, accent at half strength, accent); off is the
// crossed-out webcam and unavailable the warning sign, both dimmed. `faded`
// is the half-strength accent of `starting`; `dimmed` the muted look of off
// and unavailable. A non-empty `error` outside the `error` state only shows
// in the tooltip and the panel. A `warning` never changes the visual: it
// follows `state` only.
function visualFor(key) {
  switch (key) {
  case "off": return { key: key, glyph: GLYPH_WEBCAM_OFF, colorRole: "foreground", dimmed: true, faded: false }
  case "idle": return { key: key, glyph: GLYPH_WEBCAM, colorRole: "foreground", dimmed: false, faded: false }
  case "starting": return { key: key, glyph: GLYPH_WEBCAM, colorRole: "accent", dimmed: false, faded: true }
  case "active": return { key: key, glyph: GLYPH_WEBCAM, colorRole: "accent", dimmed: false, faded: false }
  case "error": return { key: key, glyph: GLYPH_ALERT, colorRole: "urgent", dimmed: false, faded: false }
  default: return { key: "unavailable", glyph: GLYPH_WARNING, colorRole: "foreground", dimmed: true, faded: false }
  }
}

// The bar's visual: visualFor(visualKey(record)), except that while the
// camera's privacy shutter is closed (shutterClosed) the glyph is the
// crossed-out webcam. The key, colour role and dimming stay the state's own.
function barVisual(record) {
  var v = visualFor(visualKey(record))
  if (shutterClosed(record)) v.glyph = GLYPH_WEBCAM_OFF
  return v
}

var VISUAL_KEYS = ["off", "idle", "starting", "active", "error", "unavailable"]

// ---------------------------------------------------------------- text

function consumersText(n) {
  if (typeof n !== "number" || n < 0) return "unknown"
  return n === 1 ? "1 consumer" : n + " consumers"
}

function stateLabel(record) {
  if (unknownState(record)) return "unsupported state"
  if (!available(record)) return "unavailable"
  return record.state
}

// Short link-state phrase for the tooltip.
function linkLabel(record) {
  if (unknownState(record)) return "unsupported state"
  switch (record ? record.link : "") {
  case "ok": return ""
  case "not-running": return "daemon not running"
  case "unreachable": return "daemon unreachable"
  case "cli-missing": return CLI_MISSING_TEXT
  case "cli-failed": return "omarchy-broadcast watch stopped"
  case "unsupported": return "unsupported omarchy-broadcast version"
  default: return "connecting\u2026"
  }
}

// The panel header's status line. The header upper-cases it, so it carries
// no command names; the specifics are in the panel body.
function heroMeta(record) {
  if (available(record)) return record.state
  if (!record || record.link === "connecting") return "connecting\u2026"
  return "unavailable"
}

function tooltipText(record) {
  var prefix = PRODUCT + ": "
  var text
  if (!available(record)) {
    text = prefix + linkLabel(record)
  } else if (record.state === "error") {
    text = prefix + "error" + (record.error !== "" ? " \u00b7 " + sanitize(record.error, 80) : "")
    if (record.warning !== "") text += " \u00b7 warning: " + sanitize(record.warning, 60)
  } else if (record.state === "off") {
    text = prefix + "off" + (record.error !== "" ? " \u00b7 error: " + sanitize(record.error, 60) : "")
    if (record.warning !== "") text += " \u00b7 warning: " + sanitize(record.warning, 60)
  } else {
    var camera = activeCameraLabel(record)
    var parts = [prefix + record.state]
    parts.push(camera !== "" ? camera : "no camera")
    if (record.consumers >= 0) parts.push(consumersText(record.consumers))
    if (shutterClosed(record)) parts.push("camera shutter closed")
    var effect = effectSummary(record)
    if (effect !== "") parts.push(effect)
    if (record.error !== "") parts.push("error: " + sanitize(record.error, 60))
    if (record.warning !== "") parts.push("warning: " + sanitize(record.warning, 60))
    text = parts.join(" \u00b7 ")
  }
  return sanitize(text, TOOLTIP_CAP)
}

// Where a message about a missing program ends on a path, the path is split
// off to draw on a line of its own: `text` is what comes before it, `path` the
// rest (the path may hold spaces, so everything after the first " /" is the
// path). A text with no " /" after a non-empty start comes back whole, with an
// empty path. The panel draws the path on its own line, wrapping at any
// character (it does not prefer a "/"), so a long path reads as one string.
// Only for strings this plugin builds with the path last (the CLI-missing
// messages): it is not a general parser for daemon text.
function splitTrailingPath(text) {
  var m = typeof text === "string" ? /^(\S[\s\S]*?) (\/[\s\S]*)$/.exec(text) : null
  return m ? { text: m[1], path: m[2] } : { text: typeof text === "string" ? text : "", path: "" }
}

// The text of the last control command's failure for the panel, split the same
// way when it is the CLI-missing one (its text is built here, path last); any
// other failure carries the CLI's own words and is shown whole.
function commandErrorParts(text) {
  if (typeof text === "string" && text.indexOf(CLI_MISSING_TEXT + ": ") === 0) return splitTrailingPath(text)
  return { text: typeof text === "string" ? text : "", path: "" }
}

// The panel's message when the daemon cannot be used:
// { title, path, detail, hint, commandText }. `path` is a file path the title
// ends on (see splitTrailingPath), drawn on a line of its own; `commandText` is
// plain text the user can copy (drawn on a line of its own); the plugin never
// runs it.
function unavailableMessage(record) {
  var msg = unavailableMessageText(record)
  // The Start button: only for a stopped daemon, never for a missing CLI or
  // an error (unknownState and the other links get none).
  msg.startable = !unknownState(record) && !!record && record.link === "not-running"
  return msg
}

function unavailableMessageText(record) {
  var link = record ? record.link : "connecting"
  var detail = record ? record.linkText : ""
  if (unknownState(record)) {
    return { title: "omarchy-broadcastd reports a state this plugin does not know"
               + (record.rawState !== "" ? ": " + record.rawState : ""),
             path: "", detail: "", hint: "Update the plugin.", commandText: "" }
  }
  switch (link) {
  case "ok":
    return { title: "", path: "", detail: "", hint: "", commandText: "" }
  case "not-running":
    return { title: "omarchy-broadcastd is not running", path: "", detail: "",
             hint: "To start it at every login:", commandText: "systemctl --user enable --now omarchy-broadcastd" }
  case "unreachable":
    return { title: "omarchy-broadcastd is not answering", path: "", detail: detail,
             hint: "Retrying every 2 s. Its log:", commandText: "journalctl --user -u omarchy-broadcastd" }
  case "cli-missing":
    // The text ends on the path it searched or was given, when it names one.
    var parts = splitTrailingPath(detail !== "" ? detail : CLI_MISSING_TEXT)
    return { title: parts.text, path: parts.path, detail: "",
             hint: "Install omarchy-broadcast-bin\n"
               + "or -git from the AUR\n"
               + "(see INSTALL.md).\n"
               + "Or set the cliPath setting.",
             commandText: "" }
  case "cli-failed":
    return { title: "omarchy-broadcast watch stopped", path: "", detail: detail, hint: "", commandText: "" }
  case "unsupported":
    return { title: "Unsupported omarchy-broadcast version", path: "", detail: detail, hint: "", commandText: "" }
  default:
    return { title: "Connecting to omarchy-broadcastd\u2026", path: "", detail: "", hint: "", commandText: "" }
  }
}

// The Camera tab's camera dropdown: { visible, options, value, notes }.
// options: { value (the camera's id), label } of every camera listed, a
// camera that cannot be chosen marked so (its note, in `notes`, says why);
// `value` the active camera's id ("" for none). The USB ids are in the
// Details view.
var CAMERA_PICKER_LABEL = "Camera"
var CAMERA_UNSELECTABLE_MARK = " (cannot be chosen)"
function cameraPickerView(record) {
  var out = { visible: false, options: [], value: "", notes: [] }
  if (!available(record)) return out
  var cams = Array.isArray(record.cameras) ? record.cameras : []
  for (var i = 0; i < cams.length && i < CAMERA_CAP; i++) {
    var c = cams[i]
    var active = isActiveCamera(record, c)
    var blocked = c.selectId === "" && !active
    out.options.push({ value: c.id, label: blocked ? c.label + CAMERA_UNSELECTABLE_MARK : c.label })
    if (active) out.value = c.id
    if (c.selectNote !== "") out.notes.push(c.label + ": " + c.selectNote)
  }
  out.visible = out.options.length > 0
  return out
}

// The camera a choice of the dropdown selects: the selectable id of the
// listed camera `value` names, or null (none such, the active one, or one
// that cannot be chosen).
function cameraChoice(record, value) {
  var cams = record && Array.isArray(record.cameras) ? record.cameras : []
  for (var i = 0; i < cams.length && i < CAMERA_CAP; i++) {
    var c = cams[i]
    if (c.id !== value || typeof value !== "string" || value === "") continue
    return c.selectId !== "" && !isActiveCamera(record, c) ? c.selectId : null
  }
  return null
}

// The row under the camera list when not every camera is shown.
function truncationText(record) {
  if (!record || !record.camerasTruncated) return ""
  if (record.camerasCapped)
    return "Showing " + record.cameras.length + " of " + record.camerasTotal + " cameras"
  return "More cameras are connected; they are not shown"
}

function formatStat(value, decimals, unit) {
  if (value === null || value === undefined || typeof value !== "number" || !isFinite(value)
      || value < 0 || value > STAT_MAX)
    return UNKNOWN
  return value.toFixed(decimals) + unit
}

// Rows for the live figures; empty unless the state is active. Before the
// first stats line of an active period every figure reads unknown.
function statsRows(record) {
  if (!available(record) || record.state !== "active") return []
  var s = record.stats || {}
  return [
    { label: "Frame rate", value: formatStat(s.fps, 1, " fps") },
    { label: "Latency (p50)", value: formatStat(s.latencyMs, 1, " ms") },
    { label: "CPU", value: formatStat(s.cpuPercent, 1, " %") },
    { label: "GPU", value: formatStat(s.gpuPercent, 1, " %") }
  ]
}

// A value a stage reports: the first `name` of `stage` in the record, else
// null. Only while the camera is active (the daemon sends none otherwise).
function stageValue(record, stage, name) {
  if (!available(record) || record.state !== "active" || !Array.isArray(record.stageValues)) return null
  for (var i = 0; i < record.stageValues.length; i++) {
    var e = record.stageValues[i]
    if (e.stage === stage && e.name === name) return e.value
  }
  return null
}

// A zoom factor as the panel shows it: "Zoom 1.24\u00d7" (1.00\u00d7 is the full
// frame); "" for no value or one that is not a positive number.
function zoomLabel(value) {
  if (typeof value !== "number" || !isFinite(value) || value <= 0 || value > STAT_MAX) return ""
  return "Zoom " + value.toFixed(2) + "\u00d7"
}

// The settings group whose stage reports a live value: the group's id and
// the stage, value name and label it is shown with. Anything else in a group
// stays generic: a group with no entry here shows no live line.
// This table is the one place the plugin names a live stage value (a
// documented exception to "the plugin names no settings"): adding an entry is
// a deliberate decision, and tests/check-source.py pins the table to exactly
// this one entry so that growth fails visibly. The generic alternative, the
// daemon publishing the label, the unit and the group with each value, is
// future work.
var LIVE_GROUPS = {
  auto_frame: { stage: "auto-frame", name: "zoom", label: zoomLabel }
}

// The live line a settings group shows under its rows, "" for none: the
// value its stage reports while the camera is active, and only while the
// group is switched on (its `effect.<group>.enabled` switch, by the
// daemon's naming; a group with no such switch is not gated by one).
function groupLiveText(record, groupId) {
  if (!LIVE_GROUPS.hasOwnProperty(groupId)) return ""
  var live = LIVE_GROUPS[groupId]
  var gate = findSetting(record, "effect." + groupId + ".enabled")
  if (gate && gate.value !== true) return ""
  return live.label(stageValue(record, live.stage, live.name))
}

// ---------------------------------------------------------------- effects

// The background effect as the daemon's settings schema describes it: the
// row of EFFECT_MODE_SETTING, a global enum whose options (their values and
// labels) are the daemon's. Nothing here names an effect: the options, their
// labels, whether the row can be changed now and why not all come from the
// schema.
function effectModeRow(record) {
  var row = settingsSupported(record) ? findSetting(record, EFFECT_MODE_SETTING) : null
  return row && row.type === "enum" && row.scope === "global" ? row : null
}

// The tooltip's effect phrase: "background: <the mode's label>" while the
// mode is not its default (the default is no effect), else "".
function effectSummary(record) {
  var row = effectModeRow(record)
  if (!row || row.value === "" || row.value === row.defaultValue) return ""
  var at = optionIndex(row.options, row.value)
  return at >= 0 ? "background: " + row.options[at].label : ""
}

// Whether the daemon holds a background image. Read from the raw field
// (backgroundImageSet), never from the sanitised display copy.
function hasBackgroundImage(record) {
  return !!record && record.backgroundImageSet === true
}

// Whether the effects come from the daemon's modules: an available daemon
// at interface revision MODULES_REVISION or later. An unknown revision
// counts as no.
function moduleEffects(record) {
  return available(record) && record.interfaceRevision >= MODULES_REVISION
}

// The Effect tab's choice row, exactly as drawn:
//   { visible, hint, id, enabled, reason, options }
// options: { value, label, selected, faded, tooltip }, the mode row's own,
// in its order; `selected` follows the user's draft while one is
// unconfirmed (Daemon.settingDrafts). `visible` is false, with `hint`
// saying why, while the daemon predates module effects (or the CLI or the
// plugin predates its settings), and while no enabled module offers the
// background effect. While the set is still loading neither is shown. A row
// the daemon greys out (the camera is off, a module is loading) is drawn
// faded with the daemon's reason under it. `value` is the choice shown (the
// draft while one is unconfirmed): the rows under the choice follow it.
function effectModeView(record, drafts) {
  var out = { visible: false, hint: "", id: "", enabled: false, reason: "", options: [], value: "" }
  if (!available(record)) return out
  if (!moduleEffects(record)) { out.hint = DAEMON_NO_EFFECTS; return out }
  if (!settingsSupported(record)) { out.hint = settingsMissingText(record); return out }
  if (!isPlainObject(record.settings)) return out
  var row = effectModeRow(record)
  if (!row) { out.hint = NO_BACKGROUND_TEXT; return out }
  // A choice that cannot run here (no GPU for it, its models missing) is in
  // the tab's "Not available now" list instead (effectSettingsView).
  if (UNAVAILABLE_KINDS.indexOf(row.kind) >= 0) return out
  var value = shownSettingValue(row, drafts)
  out.visible = true
  out.value = value
  out.id = row.id
  out.enabled = row.enabled
  out.reason = row.enabled ? "" : row.reason
  for (var i = 0; i < row.options.length && i < SETTING_OPTION_CAP; i++) {
    var o = row.options[i]
    out.options.push({ value: o.value, label: o.label, selected: o.value === value, faded: !row.enabled,
                       tooltip: row.enabled ? "" : row.reason })
  }
  return out
}

// The index of the selected choice of an effectModeView, else -1.
function effectModeSelected(view) {
  var options = isPlainObject(view) && Array.isArray(view.options) ? view.options : []
  for (var i = 0; i < options.length; i++) if (options[i].selected) return i
  return -1
}

// Whether the Effect tab draws its choice row (a keyboard stop).
function effectModeShown(record) {
  return effectModeView(record, null).visible
}

// The background image path as the panel shows it: the sanitised copy inside
// a left-to-right isolate (U+2066 ... U+2069). A POSIX path is left-to-right
// by structure, so the segments keep their order even when a file name starts
// with right-to-left text (a first-strong isolate, U+2068, would take its
// direction from that name and show the path reversed). sanitize() has
// already removed every bidi control the daemon sent, these two included.
function imagePathText(record) {
  if (!record || typeof record.backgroundImage !== "string" || record.backgroundImage === "") return UNKNOWN
  return "\u2066" + record.backgroundImage + "\u2069"
}

// Read-only rows under the choices: the background image the daemon holds,
// whatever the effect. Empty when unavailable, below MODULES_REVISION or
// with no image, and while the Background row (backgroundRowShown) shows
// the image instead.
function effectRows(record) {
  if (!moduleEffects(record) || !hasBackgroundImage(record) || backgroundRowShown(record)) return []
  return [{ label: "Background image", value: imagePathText(record) }]
}

// Exit status of a control command -> a short, capped message for the panel.
// `code` -1 means the command could not be started at all.
function commandFailureText(code, stderrLine, cliPath) {
  var detail = typeof stderrLine === "string" ? stderrLine.slice(0, STDERR_CAP).replace(/^omarchy-broadcast:\s*/, "") : ""
  detail = sanitize(detail, DETAIL_CAP)
  var text
  switch (code) {
  case -1: text = CLI_MISSING_TEXT + ": " + (typeof cliPath === "string" ? cliPath : ""); break
  case 1: text = "The daemon refused the request" + (detail !== "" ? ": " + detail : ""); break
  case 2: text = "Invalid command line (a plugin bug)" + (detail !== "" ? ": " + detail : ""); break
  case 3: text = "omarchy-broadcastd is not running"; break
  case 4: text = "D-Bus failure" + (detail !== "" ? ": " + detail : ""); break
  default: text = "Command failed with status " + code + (detail !== "" ? ": " + detail : "")
  }
  return sanitize(text, DETAIL_CAP + 60)
}

// The panel's message when the `start` command failed. A CLI that predates
// `start` answers with clap's "unrecognized subcommand" (exit 2).
var START_UNSUPPORTED_TEXT = "This omarchy-broadcast version cannot start the daemon; use the command below"
function startFailureText(code, stderrLine, cliPath) {
  if (code === 2 && typeof stderrLine === "string" && /unrecognized subcommand/i.test(stderrLine.slice(0, STDERR_CAP)))
    return START_UNSUPPORTED_TEXT
  if (code === -1) return commandFailureText(code, stderrLine, cliPath)
  var detail = typeof stderrLine === "string" ? stderrLine.slice(0, STDERR_CAP).replace(/^omarchy-broadcast:\s*/, "") : ""
  detail = sanitize(detail, DETAIL_CAP)
  return sanitize("Could not start omarchy-broadcastd" + (detail !== "" ? ": " + detail : " (status " + code + ")"), DETAIL_CAP + 60)
}

// How long a one-shot command (never the long-lived watch) may run before the
// plugin kills it: `start` (the CLI bounds it at 30 s itself), then the rest.
var START_TIMEOUT_MS = 45000
var COMMAND_TIMEOUT_MS = 30000
// The two PATH lookups (resolverArgv, toolsArgv: `command -v`, answering at
// once) are bounded much shorter; a setup read is bounded as a command.
var LOOKUP_TIMEOUT_MS = 5000
function commandTimeoutText(ms) {
  return "omarchy-broadcast did not answer within " + Math.max(1, Math.round(ms / 1000)) + " s"
}

function isStartIntent(intent) {
  return isPlainObject(intent) && intent.verb === "start"
}

// The watch's exit, for the panel. `crashed` is Quickshell's exitStatus
// (1 = killed by a signal, whose number is then the exit code).
function watchExitText(code, crashed, delayMs) {
  var how = crashed ? "stopped by signal " + code : "exited with status " + code
  return "omarchy-broadcast watch " + how + "; restarting in " + Math.round(delayMs / 1000) + " s"
}

// ---------------------------------------------------------------- stderr framing

// A command's stderr arrives in chunks (SplitParser with an empty marker), so
// at most one pipe read (64 KiB) is ever held, never a whole unbounded line.
// The first non-blank line is kept, capped to STDERR_CAP; the rest is ignored.
// A multi-byte character cut by a read boundary decodes as U+FFFD: harmless
// in a display-only message, which is why stdout (camera ids) is not read
// this way.
function firstLineStart() {
  return { text: "", done: false }
}

function firstLineFeed(state, chunk) {
  if (!state || state.done || typeof chunk !== "string" || chunk === "") return state
  var text = state.text
  var rest = chunk
  while (rest !== "") {
    var nl = rest.indexOf("\n")
    var part = nl === -1 ? rest : rest.slice(0, nl)
    text = text + part.slice(0, Math.max(0, STDERR_CAP - text.length))
    if (text.length >= STDERR_CAP) return { text: text, done: true }
    if (nl === -1) return { text: text, done: false }
    if (text.trim() !== "") return { text: text, done: true }
    // A blank first line: start over on the next one.
    text = ""
    rest = rest.slice(nl + 1)
  }
  return { text: text, done: false }
}

// ---------------------------------------------------------------- commands

// A runnable CLI path: absolute, bounded, no control characters.
function cliUsable(cli) {
  return typeof cli === "string" && cli.length > 1 && cli.length <= PATH_CAP
    && cli.charAt(0) === "/" && !hasControl(cli)
}

function watchArgv(cli) {
  return cliUsable(cli) ? [cli, "watch", "--json"] : null
}

function enableArgv(cli, on) {
  return cliUsable(cli) ? [cli, on ? "on" : "off"] : null
}

// Middle click: flips the persisted switch, only when the daemon's state is
// known. Privacy fails closed: an `off` the user could not see is never
// flipped, and `on` would D-Bus-activate a stopped daemon.
function toggleArgv(cli, record) {
  if (!available(record)) return null
  return enableArgv(cli, !record.enabled)
}

// The id goes after `--`, as one argv element: never parsed as an option.
// The word `next` is never sent: the CLI reads it as NextCamera.
function selectArgv(cli, id) {
  var safe = selectableId(id)
  if (!cliUsable(cli) || safe === "" || safe === "next") return null
  return [cli, "camera", "--", safe]
}

// Start the stopped daemon: the CLI's `start` D-Bus-activates it without
// changing its state. The plugin never runs systemctl.
function startArgv(cli) {
  return cliUsable(cli) ? [cli, "start"] : null
}

function nextArgv(cli) {
  return cliUsable(cli) ? [cli, "camera", "next"] : null
}

function canNext(record) {
  return available(record) && record.cameras.length >= 2
}

// A control request is kept as an intent, { verb, on, id, effect, value, camera },
// and turned into an argv when it runs: with the CLI path and the availability of that moment,
// so a request queued behind a slow one never runs against a daemon that has
// gone meanwhile (`on`/`off`/`camera`/`settings`/`config`/`modules`/`order`/`mic`/`recommended` would D-Bus-activate it) or
// with a CLI path that has changed. null = do not run.
function intentArgv(intent, cli, record) {
  if (!intent || typeof intent !== "object") return null
  switch (intent.verb) {
  case "enable": return available(record) ? enableArgv(cli, intent.on === true) : null
  case "select": return available(record) ? selectArgv(cli, intent.id) : null
  case "next": return canNext(record) ? nextArgv(cli) : null
  case "start": return record && record.link === "not-running" && !unknownState(record) ? startArgv(cli) : null
  case "setup": return setupIntentArgv(cli, record, intent)
  case "setting": return settingIntentArgv(cli, record, intent)
  case "mic-host": return micSupported(record) ? micHostArgv(cli, intent.on === true) : null
  case "reset-settings": return settingsSupported(record) && settingIntentBound(intent, record) ? resetSettingsArgv(cli, record.settings.camera) : null
  case "background": return backgroundRowShown(record) ? backgroundArgv(cli, intent.path) : null
  case "media-import": return backgroundRowShown(record) ? mediaImportArgv(cli, intent.path) : null
  case "recommended": return recommendedArgv(cli, record, intent)
  default: return null
  }
}

// Middle click on the bar icon: "toggle", "open-panel" (unavailable: never
// flip a state the user cannot see) or "ignore" (`busy`: a command other
// than a camera setting write or a setup write is in flight or queued, see
// toggleBlocked; its result has not arrived, so the target of a toggle is
// unknown; the panel switch follows the same rule through its `busy`).
function middleClickAction(record, busy) {
  if (!available(record)) return "open-panel"
  return busy === true ? "ignore" : "toggle"
}

// What a click on the bar icon does, by button ("left", "middle" or
// "right"): left opens and closes the panel ("panel"), middle turns the
// camera on or off (middleClickAction), right opens the setup dialog
// ("setup"), whatever the daemon's state: the dialog says what is wrong.
function clickAction(button, record, busy) {
  if (button === "middle") return middleClickAction(record, busy)
  if (button === "right") return "setup"
  return "panel"
}

// What the bar icon's clicks do, for its accessible description: constants
// only, worded for the state the middle click would act on.
function barClickHelp(record) {
  if (!available(record)) return "Click or middle click: open the panel. Right click: open the setup."
  return "Click: open the panel. Middle click: " + (record.enabled ? "turn the camera off." : "turn the camera on.")
    + " Right click: open the setup."
}

// The watch runs only while it has readers, a CLI is known and no respawn
// backoff is pending. A singleton stranded by a reload has no readers, so it
// goes silent. (A re-resolution in flight leaves a running watch alone: the
// answer is usually the same binary.)
function shouldWatch(attached, cliPath, backingOff) {
  return typeof attached === "number" && attached > 0 && cliUsable(cliPath) && backingOff !== true
}

function nextBackoff(ms) {
  var current = typeof ms === "number" && isFinite(ms) ? ms : BACKOFF_MIN_MS
  return Math.min(BACKOFF_MAX_MS, Math.max(BACKOFF_MIN_MS, current) * 2)
}

// The delay before the next respawn, given the one that is due (`prevMs`) and
// how long the watch that just ended had been running. Only a watch that
// stayed up BACKOFF_RESET_UPTIME_MS earns the minimum back.
function backoffAfterExit(prevMs, uptimeMs) {
  var prev = typeof prevMs === "number" && isFinite(prevMs)
    ? Math.min(BACKOFF_MAX_MS, Math.max(BACKOFF_MIN_MS, prevMs)) : BACKOFF_MIN_MS
  var up = typeof uptimeMs === "number" && isFinite(uptimeMs) ? uptimeMs : 0
  return up >= BACKOFF_RESET_UPTIME_MS ? BACKOFF_MIN_MS : prev
}

// ---------------------------------------------------------------- preview

// The live preview (docs/cli-json.md, `omarchy-broadcast preview --json`):
// the daemon writes a 480x270 JPEG of what apps receive to one fixed file and
// the CLI prints a `frame` line after each atomic replace. The plugin reads
// that file through an Image, never the camera device and never D-Bus.

// The daemon interface revision that added the preview lease (obc-ipc
// INTERFACE_REVISION 5; the CLI prints it as interface_revision).
var PREVIEW_REVISION = 5
// The frame rates `preview --fps` accepts; the first is the default.
var PREVIEW_FPS_CHOICES = [15, 30]
var PREVIEW_FPS_DEFAULT = 15
// Where the daemon writes the frame, under $XDG_RUNTIME_DIR.
var PREVIEW_SUBPATH = "/omarchy-broadcast/preview.jpg"
// An error line's code, display only.
var PREVIEW_CODE_CAP = 64
// Settings: an entry with more keys than this is not rewritten (a write
// replaces the whole entry, so dropping keys to stay bounded would lose them).
var SETTINGS_KEY_CAP = 256
var PREVIEW_OLD_DAEMON = "Preview needs omarchy-broadcast 0.18 or newer"
var PREVIEW_IDLE_TEXT = "Preview off"
var PREVIEW_OFF_TEXT = "Preview off"
var PREVIEW_CAMERA_OFF_TEXT = "Camera off"
var PREVIEW_STARTING_TEXT = "Starting preview…"
var PREVIEW_RETRY_HINT = "Reopen the panel to retry."
// A preview preference the shell did not store (no layout entry to write, or
// an entry over SETTINGS_KEY_CAP): it holds for this session only.
var PREVIEW_UNSAVED_TEXT = "Could not save the preview setting"
var PREVIEW_RATE_TOOLTIP = "How often this preview refreshes. The camera feed apps receive is not affected."
var PREVIEW_FPS_TOOLTIPS = { 15: PREVIEW_RATE_TOOLTIP, 30: PREVIEW_RATE_TOOLTIP }

// $XDG_RUNTIME_DIR -> { path, reason }: the frame file the daemon writes,
// or "" and why the preview cannot be used. The directory must be absolute
// and hold no "..", no control characters and none of "?#%" (the path ends
// up in a file:// URL, where those would change what is read), and must not
// start with "//" (file:////host/... reads "host" as a URL host). Trailing
// slashes are dropped, as the daemon's path join drops them. The result is
// the only path frame lines are compared with, and the only one ever loaded.
function previewPath(runtimeDir) {
  if (typeof runtimeDir !== "string" || runtimeDir === "")
    return { path: "", reason: "XDG_RUNTIME_DIR is not set" }
  if (runtimeDir.length > PATH_CAP || runtimeDir.charAt(0) !== "/")
    return { path: "", reason: "XDG_RUNTIME_DIR is not an absolute path" }
  if (runtimeDir.charAt(1) === "/")
    return { path: "", reason: "XDG_RUNTIME_DIR starts with //" }
  if (/[\u0000-\u001f\u007f-\u009f\u2028\u2029?#%]/.test(runtimeDir) || runtimeDir.indexOf("..") !== -1)
    return { path: "", reason: "XDG_RUNTIME_DIR holds characters the preview cannot use" }
  var dir = runtimeDir.replace(/\/+$/, "")
  if (dir === "") return { path: "", reason: "XDG_RUNTIME_DIR is the root directory" }
  return { path: dir + PREVIEW_SUBPATH, reason: "" }
}

// The running daemon has the preview lease: available, revision 5 or more.
// An unknown revision counts as no.
function previewSupported(record) {
  return available(record) && typeof record.interfaceRevision === "number"
    && record.interfaceRevision >= PREVIEW_REVISION
}

// The consumers other than preview leases: loopback + PipeWire; -1 unknown.
function otherConsumers(record) {
  if (!record || record.loopbackConsumers < 0 || record.pipewireConsumers < 0
      || typeof record.loopbackConsumers !== "number" || typeof record.pipewireConsumers !== "number")
    return -1
  return record.loopbackConsumers + record.pipewireConsumers
}

// Whether the one preview process runs: a panel is open (`held` registered
// holders), the preview can work (`supported`: daemon revision, frame path,
// CLI), and the preview is shown (`switchOn`: the remembered shown/hidden
// state the panel's Show preview and Hide write). Hidden, it never runs,
// whoever else uses the camera: the panel then draws a one-line strip, with
// no frame to read. `record` is not read (kept for the call's shape).
function shouldPreview(held, supported, switchOn, record) {
  if (!(typeof held === "number" && held > 0) || supported !== true) return false
  return switchOn === true
}

// Only 15 or 30 is ever passed, as its own argv element.
function previewArgv(cli, fps) {
  if (!cliUsable(cli) || PREVIEW_FPS_CHOICES.indexOf(fps) < 0) return null
  return [cli, "preview", "--json", "--fps", fps === 30 ? "30" : "15"]
}

// The persisted preferences, read back: `previewEnabled` is on only for a
// real true; `previewFps` is 30 only for the number 30, else the default.
// Nothing is ever written back from here.
function previewFpsValue(value) {
  return value === 30 ? 30 : PREVIEW_FPS_DEFAULT
}

function previewSettings(settings) {
  var s = isPlainObject(settings) ? settings : {}
  return { enabled: s.previewEnabled === true, fps: previewFpsValue(s.previewFps) }
}

// The preferences in force once the bar hands a widget its settings again.
// `current`: the ones in force; `last`: the settings (previewSettings form)
// handed over before, null for none yet; `next`: the ones handed over now.
// Only a value that changed since the last hand-over replaces the one in
// force, so a widget re-injected with the same entry (a monitor plugged in,
// a bar rebuilt) never undoes a choice the shell could not store this
// session, and a value that did change (a write that came back, an edited
// shell.json) always wins. The first hand-over is taken as it is.
function previewPrefsAfter(current, last, next) {
  var n = { enabled: !!next && next.enabled === true, fps: previewFpsValue(next ? next.fps : undefined) }
  if (!isPlainObject(last) || !isPlainObject(current)) return n
  return {
    enabled: n.enabled !== (last.enabled === true) ? n.enabled : current.enabled === true,
    fps: n.fps !== previewFpsValue(last.fps) ? n.fps : previewFpsValue(current.fps)
  }
}

// A user's preference values applied to the preferences in force, as
// settingsEntry would write them: only a boolean previewEnabled and a
// previewFps of 15 or 30 take effect.
function previewPrefsChosen(current, values) {
  var c = isPlainObject(current) ? current : {}
  var out = { enabled: c.enabled === true, fps: previewFpsValue(c.fps) }
  if (!isPlainObject(values)) return out
  if (typeof values.previewEnabled === "boolean") out.enabled = values.previewEnabled
  if (PREVIEW_FPS_CHOICES.indexOf(values.previewFps) >= 0) out.fps = values.previewFps
  return out
}

// Whether the settings the bar gave already hold every one of `values`: a
// write of them changes nothing (the shell answers false for an unchanged
// entry as for one it did not find).
function settingsHold(settings, values) {
  if (!isPlainObject(settings) || !isPlainObject(values)) return false
  var keys = Object.keys(values)
  if (keys.length === 0) return false
  for (var i = 0; i < keys.length; i++) if (settings[keys[i]] !== values[keys[i]]) return false
  return true
}

// The preferences in force differ from the ones the settings hold: a choice
// of this session that is not stored. `stored` null: no settings handed over.
function previewUnsaved(current, stored) {
  if (!isPlainObject(current) || !isPlainObject(stored)) return false
  return (current.enabled === true) !== (stored.enabled === true)
    || previewFpsValue(current.fps) !== previewFpsValue(stored.fps)
}

// The layout entry to write for a user's change: { id, ...the settings as the
// bar gave them, ...values }. Only previewEnabled (a boolean), previewFps
// (15 or 30), panelTab (a word of PANEL_TABS) and batterySaverMode (a word of
// BATTERY_SAVER_MODES) may be written; anything
// else, or nothing to write, is null. The settings given are not modified.
function settingsEntry(moduleName, settings, values) {
  if (typeof moduleName !== "string" || moduleName === "" || !isPlainObject(values)) return null
  var entry = { id: moduleName }
  if (settings !== null && settings !== undefined) {
    if (!isPlainObject(settings)) return null
    var keys = Object.keys(settings)
    if (keys.length > SETTINGS_KEY_CAP) return null
    for (var i = 0; i < keys.length; i++) if (keys[i] !== "id") entry[keys[i]] = settings[keys[i]]
  }
  var wrote = false
  if (values.previewEnabled !== undefined) {
    if (typeof values.previewEnabled !== "boolean") return null
    entry.previewEnabled = values.previewEnabled
    wrote = true
  }
  if (values.previewFps !== undefined) {
    if (PREVIEW_FPS_CHOICES.indexOf(values.previewFps) < 0) return null
    entry.previewFps = values.previewFps
    wrote = true
  }
  if (values.panelTab !== undefined) {
    if (PANEL_TABS.indexOf(values.panelTab) < 0) return null
    entry.panelTab = values.panelTab
    wrote = true
  }
  if (values.batterySaverMode !== undefined) {
    if (BATTERY_SAVER_MODES.indexOf(values.batterySaverMode) < 0) return null
    entry.batterySaverMode = values.batterySaverMode
    wrote = true
  }
  return wrote ? entry : null
}

// An entry as the bar hands settings to a widget: without its id.
// Whether a change of a widget's `settings` is the bar's hand-over: one
// that comes once the widget is complete (`completed`). The bar hands the
// settings to a widget it has made (after its loader has loaded it), while
// the one change that comes before, as the widget is created, is the base
// widget's empty default (the layout entry's own id never reaches the
// widget either: the bar strips it). Taking that empty default as a
// hand-over would undo a preview choice the shell could not store, and
// clear a preview failure, each time a widget is made (a monitor plugged in).
function barHandOver(completed) {
  return completed === true
}

function settingsFromEntry(entry) {
  var out = {}
  if (!isPlainObject(entry)) return out
  for (var key in entry) if (key !== "id") out[key] = entry[key]
  return out
}

// A frame sequence number: a positive integer the double can hold exactly.
function previewSeq(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
    && value >= 1 && value <= 9007199254740991 ? value : 0
}

// The Image source for a frame: the validated path, never one from a line,
// and the sequence number so that every frame is a new URL.
function previewSource(expectedPath, seq) {
  var n = previewSeq(seq)
  if (typeof expectedPath !== "string" || expectedPath === "" || n === 0) return ""
  return "file://" + expectedPath + "?" + n
}

// What an error line's code means for the preview.
function previewErrorText(code) {
  switch (code) {
  case "unsupported-daemon": return PREVIEW_OLD_DAEMON
  case "daemon-not-running": return "omarchy-broadcastd is not running"
  default: return "Preview stream error: " + (code !== "" ? code : "unknown")
  }
}

// One stdout line of `preview --json` -> { kind, ... }:
//   frame    { seq }: a v1 frame line for exactly `expectedPath`, whose seq is
//            a positive integer above `lastSeq`
//   preview  { active, fps, pathMismatch }: the lease was taken or lost
//   error    { code, text }: an outage; the code is sanitised and capped
//   dropped  { reason }: too long (never parsed), or a frame line with a bad
//            seq (seq), another path (path) or an old seq (stale)
//   invalid  not JSON, not an object, not v 1, no type
//   ignored  blank, or a type this plugin does not read
function parsePreviewLine(text, expectedPath, lastSeq) {
  var p = parseLine(text)
  if (p.kind === "dropped") return { kind: "dropped", reason: p.reason }
  if (p.kind === "ignored") return { kind: "ignored", reason: p.reason }
  if (p.kind !== "message") return { kind: "invalid", reason: p.reason }
  var m = p.message
  switch (m.type) {
  case "frame":
    var seq = previewSeq(m.seq)
    if (seq === 0) return { kind: "dropped", reason: "seq" }
    if (typeof expectedPath !== "string" || expectedPath === "" || m.path !== expectedPath)
      return { kind: "dropped", reason: "path" }
    if (seq <= previewSeq(lastSeq)) return { kind: "dropped", reason: "stale" }
    return { kind: "frame", seq: seq }
  case "preview":
    if (m.active === false) return { kind: "preview", active: false, fps: 0, pathMismatch: false }
    if (m.active !== true) return { kind: "invalid", reason: "active" }
    return {
      kind: "preview",
      active: true,
      fps: PREVIEW_FPS_CHOICES.indexOf(m.fps) >= 0 ? m.fps : 0,
      // The daemon writes elsewhere than this shell expects (its
      // XDG_RUNTIME_DIR differs): every frame line would be dropped.
      pathMismatch: typeof m.path === "string" && m.path !== expectedPath
    }
  case "error":
    var code = sanitize(m.code, PREVIEW_CODE_CAP)
    return { kind: "error", code: code, text: previewErrorText(code) }
  default:
    return { kind: "ignored", reason: "type" }
  }
}

// The preview process ended on its own. `started` false: it never ran.
// Exit status 2 is clap's usage error: a CLI without the `preview` command.
function previewExitText(code, crashed, started, rejected) {
  var what
  if (rejected) what = "omarchy-broadcast preview printed a line longer than " + LINE_CAP + " characters"
  else if (!started) what = "omarchy-broadcast preview could not be started"
  else if (crashed) what = "omarchy-broadcast preview stopped by signal " + code
  else if (code === 2) what = "This omarchy-broadcast has no preview command (it needs 0.18 or newer)"
  else what = "omarchy-broadcast preview exited with status " + code
  return what + ". " + PREVIEW_RETRY_HINT
}

// The panel's preview area, from a plain state object:
//   { record, pathReason, switchOn, wanted, running, leaseActive, hasFrame,
//     exitError, streamError, pathMismatch }
// -> { mode, text, error }. mode: "hidden" (the daemon is unavailable; the
// panel says so elsewhere), "note" (one line, no frame area: the preview
// cannot work here, ended with an error, or nothing is shown or starting),
// "box" (the 16:9 frame area while the preview starts) or "image" (frames).
// `error`: the text is a failure (drawn in the urgent colour).
function previewPlaceholder(state) {
  var s = isPlainObject(state) ? state : {}
  var record = s.record
  if (!available(record)) return { mode: "hidden", text: "", error: false }
  if (!previewSupported(record)) return { mode: "note", text: PREVIEW_OLD_DAEMON, error: false }
  if (typeof s.pathReason === "string" && s.pathReason !== "")
    return { mode: "note", text: "Preview unavailable: " + s.pathReason, error: false }
  if (typeof s.exitError === "string" && s.exitError !== "") return { mode: "note", text: s.exitError, error: true }
  if (typeof s.streamError === "string" && s.streamError !== "") return { mode: "note", text: s.streamError, error: true }
  if (s.pathMismatch === true)
    return { mode: "note", text: "omarchy-broadcastd writes its preview elsewhere than this shell expects (XDG_RUNTIME_DIR differs)", error: true }
  if (s.running === true && s.leaseActive === true && s.hasFrame === true) return { mode: "image", text: "", error: false }
  if (s.running === true || s.wanted === true || s.switchOn === true)
    return { mode: "box", text: PREVIEW_STARTING_TEXT, error: false }
  var text = record.enabled === false || record.state === "off" ? PREVIEW_CAMERA_OFF_TEXT
    : (record.state === "idle" ? PREVIEW_IDLE_TEXT : PREVIEW_OFF_TEXT)
  return { mode: "note", text: text, error: false }
}

// The Preview switch and the frame-rate choices are drawn (and are cursor
// stops) only where the preview can work.
function previewControlsShown(record, pathReason) {
  return previewSupported(record) && (typeof pathReason !== "string" || pathReason === "")
}

// The frame-rate choices: { value, label, tooltip, selected } (constants
// only: the shell's Button draws them without PlainText).
function fpsOptions(fps) {
  var current = previewFpsValue(fps)
  var out = []
  for (var i = 0; i < PREVIEW_FPS_CHOICES.length; i++) {
    var v = PREVIEW_FPS_CHOICES[i]
    out.push({ value: v, label: v === 30 ? "30 fps" : String(v), tooltip: PREVIEW_FPS_TOOLTIPS[v], selected: v === current })
  }
  return out
}

// ---------------------------------------------------------------- camera settings

// The camera's settings as the daemon publishes them (D-Bus interface
// revision 7; docs/cli-json.md: the `settings_group`, `settings_delta` and
// `settings_clear` lines of `omarchy-broadcast watch --json`). The daemon is
// the only authority: it decides which settings a camera has, their type,
// range and labels, whether each can be changed now (`enabled`) and why not
// (`disabled_reason`). The plugin draws whatever arrives through one generic
// renderer (SettingsView.qml) that knows four types; it never names a
// setting, and never decides `enabled` from `enabled_when`: `enabled` is the
// daemon's word, always. `enabled_when` and the daemon's `disabled_kind` are
// read for layout only (settingPlacement, rowMaster): where a row is drawn
// (under its master, in the "Not available now" list, or not at all while
// its master is off), never whether it takes input. A condition on a setting
// the set does not hold, or an operator this plugin does not know, places
// nothing. The daemon keeps each camera's values and applies them
// at every open; a change applies live while the daemon has the camera open
// (state `starting` or `active`) and is stored for the next open otherwise.

// The daemon interface revision that added the settings (obc-ipc
// INTERFACE_REVISION 7) and the settings schema this plugin reads.
var SETTINGS_REVISION = 7
var SETTINGS_SCHEMA = 1
// A setting id, an option value and a group id, exactly as the daemon's
// grammar allows them; anything else is not a setting of a v1 producer.
var SETTING_ID_RE = /^[a-z0-9]+(\.[a-z0-9_]+){1,3}$/
var SETTING_ID_CAP = 48
// An option value is a word, or a capture mode (revision 12: WxH@FPS, the rate
// a whole number or a fraction: 3840x2160@30, 1920x1080@30000/1001).
var OPTION_VALUE_RE = /^[a-z0-9_@/]{1,32}$/
// An option value of a microphone setting (a group of surface MIC_SURFACE)
// may also be a PipeWire node name (the input device's choices:
// alsa_input.usb-...): letters of either case, digits and _ . : @ / + -,
// starting with a letter or a digit, at most 128 characters (the producer's
// bound). A name the producer clipped ends in an ellipsis and is no value.
var MIC_OPTION_VALUE_RE = /^[A-Za-z0-9][A-Za-z0-9_.:@/+-]{0,127}$/
var GROUP_ID_RE = /^[a-z0-9_]{1,32}$/
// Words the grammars above allow that must never be a key: assigning an
// object's `__proto__` re-parents it (and reading it gives Object.prototype),
// and `constructor` / `prototype` read inherited members of a plain object.
// A group id or an option value that is one of them is refused outright
// (a setting id cannot be one: it holds a dot), and every map this file keys
// by a daemon string is prototype-free (Object.create(null)) or read through
// ownValue() as well.
var RESERVED_KEYS = ["__proto__", "constructor", "prototype"]
// Display bounds, the producer's (docs/cli-json.md).
var SETTING_LABEL_CAP = 48
var SETTING_REASON_CAP = 96
var SETTING_UNIT_CAP = 16
// A setting's description (revision 26), the producer's bound.
var SETTING_DESCRIPTION_CAP = 160
var OPTION_LABEL_CAP = 32
// Rendering caps (the producer's are 64 settings a camera and 16 options a
// setting); past them the panel says "Showing N of M".
var SETTINGS_GROUP_CAP = 16
// A set holds the groups of each place they are drawn (the camera's, the
// global ones of the Effect tab and the microphone's), each up to
// SETTINGS_GROUP_CAP.
var SETTINGS_SET_GROUP_CAP = 3 * SETTINGS_GROUP_CAP
var SETTINGS_PER_GROUP_CAP = 16
var SETTING_OPTION_CAP = 16
var SETTINGS_ROW_CAP = 64
// Lines of one set: a v1 producer puts at least one setting on a line, and
// publishes at most 64. A set announcing more is never waited for.
var SETTINGS_LINES_CAP = 64
// Entries of one line ever looked at: a v1 producer puts at most 8 settings
// on a line and at most 16 changes on a delta line.
var SETTINGS_LINE_LOOK = 16
// A slider of more positions than this is not drawn.
var SETTING_STEPS_MAX = 1000000
// Device values are signed 32-bit integers.
var SETTING_INT_MIN = -2147483648
var SETTING_INT_MAX = 2147483647
var SETTING_TYPES = ["bool", "int", "enum", "action"]
// An enum is a row of buttons while it has at most this many choices whose
// labels together fit the row; otherwise a dropdown.
var SEGMENTED_MAX_OPTIONS = 4
var SEGMENTED_MAX_CHARS = 28
// A slider (or a key) writes this long after its last move, and at once on
// release; a switch, a choice or an action writes at once.
var CONTROLS_DEBOUNCE_MS = 150
// Commands waiting behind a running one (see enqueueIntent). Every kind the
// queue can hold, and its most:
//   other ask (select, next, enable, recommended ...)        1
//   setup write (config, modules, order: the setup dialog)  SETUP_QUEUE_CAP
//   reset                                                    1
//   slider write (setting, no quick), one per id             SETTING_QUEUE_CAP
//   quick write (setting, quick, not action), one per id     QUICK_QUEUE_CAP
//   settings action (setting, action:true), one per id       ACTION_QUEUE_CAP
//   microphone on/off (mic-host)                             MIC_QUEUE_CAP
// An action has no draft to keep for later, so a refusal would lose the
// click: it is never refused for room. Its bound is SETTINGS_ROW_CAP, the most
// rows (so action ids) a record can show, so no press of a real row is ever
// refused. The kinds add up to INTENT_QUEUE_CAP: the trim to it never cuts
// what this module queued.
var SETTING_QUEUE_CAP = 8
var QUICK_QUEUE_CAP = 4
var ACTION_QUEUE_CAP = SETTINGS_ROW_CAP
// A setup write is refused while another is running or queued
// (setupWriteBusy), so one is ever queued.
var SETUP_QUEUE_CAP = 1
// A microphone on/off ask replaces the one queued before it.
var MIC_QUEUE_CAP = 1
var INTENT_QUEUE_CAP = SETTING_QUEUE_CAP + QUICK_QUEUE_CAP + ACTION_QUEUE_CAP + SETUP_QUEUE_CAP + MIC_QUEUE_CAP + 2
var SETTINGS_TITLE = ""
// Why a setting is disabled (D-Bus interface revision 28, the setting's
// `disabled_kind`), and where the panel draws it then (settingPlacement):
//   parent_off      hidden; revealed under its master when its rule holds
//   not_applicable, not_installed, needs_hardware, other_provider,
//   unavailable     in the tab's "Not available now (n)" list, with the reason
//   busy, device    in place, greyed; the reason on hover or focus
// Any other value, none (an older daemon) or "" while disabled: greyed in
// place, as before the key, except that a row whose `enabled_when` does not
// hold reads as parent_off (layout only).
var DISABLED_KINDS = ["parent_off", "not_applicable", "not_installed", "needs_hardware", "other_provider", "unavailable", "busy", "device"]
var UNAVAILABLE_KINDS = ["not_applicable", "not_installed", "needs_hardware", "other_provider", "unavailable"]
// The kinds whose "Not available now" entry offers Setup... (the setup
// dialog: modules, backends and diagnostics), where something can be
// installed, enabled or chosen: all but not_applicable (nothing to set up).
var SETUP_KINDS = ["unavailable", "needs_hardware", "not_installed", "other_provider"]
// The producer's bounds on a rule (docs/cli-json.md): at most 4 conditions,
// an `in` of at most 8 operands; a string operand is at most an option value
// long.
var WHEN_CAP = 4
var WHEN_IN_CAP = 8
var WHEN_OPS = ["eq", "ne", "in"]
var WHEN_VALUE_CAP = 128
// The "Not available now" line and the "More" disclosure (constants only:
// the kit's Button draws the Setup label).
var NOT_AVAILABLE_TEXT = "Not available now"
var NOT_AVAILABLE_SETUP_LABEL = "Setup…"
var NOT_AVAILABLE_SETUP_TOOLTIP = "Open the setup: modules, backends and diagnostics"
var MORE_TEXT = "More"
var SETTINGS_RESET_LABEL = "Reset to defaults"
var SETTINGS_RESET_TOOLTIP = "Set every setting of this camera back to its default and forget the stored values"
var SETTINGS_IDLE_TEXT = "Not in use: changes apply when an app next uses the camera."
var SETTINGS_LIVE_TEXT = "Changes apply live."
var SETTINGS_EMPTY_TEXT = "This camera reports no settings."
// The states in which the daemon has the camera open and writes a setting
// to it at once (docs/cli-json.md, "Where a change applies").
var SETTINGS_LIVE_STATES = ["starting", "active"]
// Said instead of the settings: the CLI predates them (its snapshot has no
// settings_schema field), the daemon does (null, or an interface revision
// below SETTINGS_REVISION), or the daemon speaks a newer settings schema.
var CLI_NO_SETTINGS = "The omarchy-broadcast CLI needs updating for camera settings (omarchy-broadcast 0.22 or newer)."
var DAEMON_NO_SETTINGS = "The daemon needs updating for camera settings (omarchy-broadcastd 0.22 or newer)."
var PLUGIN_OLD_SETTINGS = "Update the plugin to show these camera settings."

// Group header glyphs (Material chevron down / right).
var GLYPH_EXPANDED = String.fromCodePoint(0xF0140)
var GLYPH_COLLAPSED = String.fromCodePoint(0xF0142)

// ---- field readers

// A daemon string of the settings (a label, a reason, a unit, a choice) for
// the screen: sanitize() with its cap, keeping "&" ("Focus & zoom"). Every
// one of them reaches only PlainText sinks: this plugin's Texts and the
// kit's Button, ButtonGroup and Dropdown labels (PlainText in qs.Ui); none
// is ever given to PanelActionButton or PanelToolTip, which draw AutoText.
function settingText(value, cap) {
  return sanitize(value, cap, true)
}

// A set's revision or serial: an integer in 1..REVISION_MAX (0 is never
// published), else 0.
function settingsNumber(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
    && value >= 1 && value <= REVISION_MAX ? value : 0
}

function reservedKey(value) {
  return RESERVED_KEYS.indexOf(value) >= 0
}

// map[key] when `key` is a string and an own key of `map`, else undefined:
// never an inherited member, whatever the key.
function ownValue(map, key) {
  return map !== null && typeof map === "object" && typeof key === "string"
    && Object.prototype.hasOwnProperty.call(map, key) ? map[key] : undefined
}

// A setting id as the daemon's grammar has it, else "".
function settingId(value) {
  return typeof value === "string" && value.length <= SETTING_ID_CAP && SETTING_ID_RE.test(value) && !reservedKey(value) ? value : ""
}

function optionValueOf(value, surface) {
  var re = surface === MIC_SURFACE ? MIC_OPTION_VALUE_RE : OPTION_VALUE_RE
  return typeof value === "string" && re.test(value) && !reservedKey(value) ? value : ""
}

// A group id as the daemon's grammar has it, else "".
function groupIdOf(value) {
  return typeof value === "string" && GROUP_ID_RE.test(value) && !reservedKey(value) ? value : ""
}

// A device integer: a whole number in the signed 32-bit range, else null.
function settingInt(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
    && value >= SETTING_INT_MIN && value <= SETTING_INT_MAX ? value : null
}

// An index in 0..max-1 (or 1..max with `base` 1), else -1.
function lineIndex(value, base, max) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
    && value >= base && value < max + base ? value : -1
}

// "Showing N of M <what>" when not all are shown, else "".
function showingText(shown, total, what) {
  return total > shown ? "Showing " + shown + " of " + total + " " + what : ""
}

// The options of an enum: at most SETTING_OPTION_CAP looked at; a valid,
// new value each (optionValueOf, by the group's surface), with a label (its
// value when the label sanitises to nothing). `total` counts the valid ones
// and those past the cap.
function settingOptions(value, surface) {
  var src = Array.isArray(value) ? value : []
  var n = Math.min(src.length, SETTING_OPTION_CAP)
  var out = []
  var seen = Object.create(null)
  for (var i = 0; i < n; i++) {
    var o = src[i]
    if (!isPlainObject(o)) continue
    var v = optionValueOf(o.value, surface)
    if (v === "" || seen[v] === true) continue
    seen[v] = true
    var label = settingText(o.label, OPTION_LABEL_CAP)
    out.push({ value: v, label: label !== "" ? label : v })
  }
  return { options: out, total: out.length + (src.length - n) }
}

function optionIndex(options, value) {
  var list = Array.isArray(options) ? options : []
  for (var i = 0; i < list.length && i < SETTING_OPTION_CAP; i++) if (list[i].value === value) return i
  return -1
}

// A value within [min, max].
function clampInt(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// Where a setting's value is kept: "global" (the daemon's own, such as the
// background effect) or "camera" (per camera: every other value, an absent
// scope included). The Camera tab draws the camera ones, the Effect tab the
// global ones, but those of a group of surface MIC_SURFACE: the Mic tab
// draws those (groupSurface).
function settingScope(s) {
  return isPlainObject(s) && s.scope === "global" ? "global" : "camera"
}

// Where a client shows a group (interface revision MIC_REVISION, the group's
// `surface`): MIC_SURFACE for a group of global settings that says so, else
// "" (a daemon that gives no surface, or one this plugin does not know, or
// a group of camera settings: drawn by scope, as before the microphone).
function groupSurface(g, scope) {
  return scope === "global" && isPlainObject(g) && g.surface === MIC_SURFACE ? MIC_SURFACE : ""
}

// The daemon's `disabled_kind` (revision 28): one of DISABLED_KINDS, else ""
// (absent, an older daemon, or a word this plugin does not know: greyed in
// place, as before the key).
function disabledKind(value) {
  return typeof value === "string" && DISABLED_KINDS.indexOf(value) >= 0 ? value : ""
}

// One operand of a rule: a boolean, a number or a short string (else
// undefined: the condition is not read).
function whenOperand(v) {
  if (typeof v === "boolean") return v
  if (typeof v === "number" && isFinite(v)) return v
  if (typeof v === "string" && v.length <= WHEN_VALUE_CAP) return v
  return undefined
}

// A setting's `enabled_when` -> [{ id, op, value }] of the conditions this
// plugin reads (an id of the grammar, a known op, an operand of the right
// shape; `in` takes a list of at most WHEN_IN_CAP), at most WHEN_CAP of them.
// `known` is false when any condition was not read: the rule cannot then be
// told to fail, only to hold. Layout only (settingPlacement, rowMaster).
function settingWhen(value) {
  var src = Array.isArray(value) ? value : []
  var out = { conditions: [], known: true }
  for (var i = 0; i < src.length && i < WHEN_CAP; i++) {
    var c = src[i]
    var id = isPlainObject(c) ? settingId(c.id) : ""
    var op = isPlainObject(c) && WHEN_OPS.indexOf(c.op) >= 0 ? c.op : ""
    var operand
    if (op === "in") {
      if (Array.isArray(c.value) && c.value.length <= WHEN_IN_CAP) {
        operand = []
        for (var j = 0; j < c.value.length; j++) {
          var v = whenOperand(c.value[j])
          if (v === undefined) { operand = undefined; break }
          operand.push(v)
        }
      }
    } else if (op !== "") {
      operand = whenOperand(c.value)
    }
    if (id === "" || operand === undefined) { out.known = false; continue }
    out.conditions.push({ id: id, op: op, value: operand })
  }
  if (src.length > WHEN_CAP) out.known = false
  return out
}

// Whether a rule holds for the values of the set (`values`: id -> value):
// true, false, or null when it cannot be told (a condition this plugin did
// not read, or one on a setting the set does not hold). Layout only.
function whenHolds(when, values) {
  if (!isPlainObject(when) || !Array.isArray(when.conditions)) return null
  var unknown = when.known !== true
  for (var i = 0; i < when.conditions.length && i < WHEN_CAP; i++) {
    var c = when.conditions[i]
    if (!values || !Object.prototype.hasOwnProperty.call(values, c.id)) { unknown = true; continue }
    var v = values[c.id]
    var ok = c.op === "in" ? c.value.indexOf(v) >= 0 : (c.op === "eq" ? v === c.value : v !== c.value)
    if (!ok) return false
  }
  return unknown ? null : true
}

// Whether a "Not available now" entry of `kind` offers Setup....
function notAvailableSetup(kind) {
  return SETUP_KINDS.indexOf(kind) >= 0
}

// Where the panel draws a row (layout only; `enabled` stays the daemon's):
//   "shown"        enabled
//   "hidden"       disabled with kind parent_off, or (no kind) a rule that
//                  does not hold: revealed when its master allows it
//   "unavailable"  a kind of UNAVAILABLE_KINDS: in the "Not available now" list
//   "greyed"       busy, device, or no kind and no failing rule: in place
function settingPlacement(row, values) {
  if (!row || row.enabled) return "shown"
  if (row.kind === "parent_off") return "hidden"
  if (UNAVAILABLE_KINDS.indexOf(row.kind) >= 0) return "unavailable"
  if (row.kind === "busy" || row.kind === "device") return "greyed"
  return whenHolds(row.when, values) === false ? "hidden" : "greyed"
}

// The setting a row's rule names first (its master), or "".
function rowMaster(row) {
  var w = row && isPlainObject(row.when) && Array.isArray(row.when.conditions) ? row.when.conditions : []
  return w.length > 0 ? w[0].id : ""
}

// id -> value of every row of the set (what a rule is evaluated against):
// the daemon's values, not a draft (a dependent shows once the daemon has
// taken the master's change, as its `enabled` does).
function settingValues(set) {
  var out = Object.create(null)
  var groups = isPlainObject(set) && Array.isArray(set.groups) ? set.groups : []
  for (var g = 0; g < groups.length && g < SETTINGS_SET_GROUP_CAP; g++) {
    var rows = groups[g].rows
    for (var r = 0; r < rows.length && r < SETTINGS_PER_GROUP_CAP; r++) out[rows[r].id] = rows[r].value
  }
  return out
}

// One setting of a settings_group line -> a row, or null (skipped): an id of
// the grammar, a known type, and for each type its fields:
//   int     min, max, step, default, value: device integers; max > min,
//           step > 0, at most SETTING_STEPS_MAX steps; value and default
//           clamped into [min, max]; `unit` optional
//   bool    value a boolean (a switch never claims a state nobody reported)
//   enum    at least one valid option; a value (or default) that is not
//           one of them reads as "" (no choice selected)
//   action  nothing more
// `scope` is read as settingScope reads it; `surface` is the group's
// (groupSurface), which decides the grammar of an option value
// (optionValueOf). `kind` is the daemon's disabled_kind (disabledKind: ""
// while enabled, absent or unknown) and `when` its enabled_when rule
// (settingWhen), both for layout only. Unknown fields (hint, ...) are not
// read. A setting
// of a known type that is skipped (a fixed int, max == min; too many steps;
// a field missing) still counts in its group's total (settingKnown), so the
// group says that not all are shown; one of an unknown type does not.
function settingEntry(s, surface) {
  if (!isPlainObject(s)) return null
  var id = settingId(s.id)
  if (id === "" || typeof s.type !== "string" || SETTING_TYPES.indexOf(s.type) < 0) return null
  var label = settingText(s.label, SETTING_LABEL_CAP)
  var enabled = s.enabled === true
  var scope = settingScope(s)
  var e = {
    id: id, type: s.type, label: label !== "" ? label : id, scope: scope,
    // Only a global setting is the microphone's (groupSurface).
    surface: surface === MIC_SURFACE && scope === "global" ? MIC_SURFACE : "", stored: s.stored === true, enabled: enabled,
    reason: enabled ? "" : settingText(s.disabled_reason, SETTING_REASON_CAP),
    kind: enabled ? "" : disabledKind(s.disabled_kind), when: settingWhen(s.enabled_when),
    description: settingText(s.description, SETTING_DESCRIPTION_CAP), displayOffset: null, displayScale: null, displayRaw: false,
    value: null, defaultValue: null, min: 0, max: 0, step: 0, unit: "", options: [], optionsTotal: 0
  }
  if (s.type === "int") {
    var min = settingInt(s.min)
    var max = settingInt(s.max)
    var step = settingInt(s.step)
    var value = settingInt(s.value)
    var def = settingInt(s["default"])
    if (min === null || max === null || step === null || value === null || def === null) return null
    if (!(max > min) || !(step > 0) || (max - min) / step > SETTING_STEPS_MAX) return null
    e.min = min
    e.max = max
    e.step = step
    e.value = clampInt(value, min, max)
    e.defaultValue = clampInt(def, min, max)
    e.unit = settingText(s.unit, SETTING_UNIT_CAP)
    // Display transform (revision 27): optional integers, a scale above
    // zero. A key that is present but invalid means no transform at all:
    // the raw value shows, without the unit (displayRaw), as a client that
    // does not apply the transform shows it. Either key valid alone makes
    // the transform; the raw value is what is kept and written.
    var hasOffset = s.display_offset !== undefined
    var hasScale = s.display_scale !== undefined
    var dOffset = settingInt(s.display_offset)
    var dScale = settingInt(s.display_scale)
    if (dScale !== null && !(dScale > 0)) dScale = null
    if ((hasOffset && dOffset === null) || (hasScale && dScale === null)) {
      e.displayRaw = true
    } else if (dOffset !== null || dScale !== null) {
      e.displayOffset = dOffset !== null ? dOffset : 0
      e.displayScale = dScale !== null ? dScale : 1
    }
  } else if (s.type === "bool") {
    if (typeof s.value !== "boolean") return null
    e.value = s.value
    e.defaultValue = s["default"] === true
  } else if (s.type === "enum") {
    var opts = settingOptions(s.options, e.surface)
    if (opts.options.length === 0) return null
    e.options = opts.options
    e.optionsTotal = opts.total
    e.value = optionIndex(opts.options, s.value) >= 0 ? s.value : ""
    e.defaultValue = optionIndex(opts.options, s["default"]) >= 0 ? s["default"] : ""
  }
  return e
}

// Whether `s` is a setting of a type this plugin draws, whether or not its
// fields make a row.
function settingKnown(s) {
  return isPlainObject(s) && typeof s.type === "string" && SETTING_TYPES.indexOf(s.type) >= 0
}

// A settings_group line's message -> its validated parts, or null (the
// line's envelope is not one a v1 producer prints; it is ignored). The
// camera is "" only on a line of global settings (no camera is active). At most
// SETTINGS_LINE_LOOK settings of the line are looked at; `total` counts the
// rows kept, the known-type ones skipped, and those past the look cap. A
// group that is not one of the grammar (its id, its label object) is kept as
// a refused group: the line still fills its place in the set, so the rest of
// the set commits, and the refused group is counted as not shown (`key`
// tells the lines of one refused group apart from another's).
function settingsGroupLine(m) {
  if (!isPlainObject(m) || m.schema !== SETTINGS_SCHEMA) return null
  var rev = settingsNumber(m.rev)
  var serial = settingsNumber(m.serial)
  // "" is the literal empty string only (no camera); a value that is not a
  // string, or is too long, is no camera at all: the line is ignored.
  if (typeof m.camera !== "string" || m.camera.length > ID_CAP * 2) return null
  var camera = m.camera
  var count = lineIndex(m.count, 1, SETTINGS_LINES_CAP)
  var parts = lineIndex(m.parts, 1, SETTINGS_LINES_CAP)
  if (rev === 0 || serial === 0 || count < 0 || parts < 0) return null
  var index = lineIndex(m.index, 0, count)
  var part = lineIndex(m.part, 1, parts)
  if (index < 0 || part < 0) return null
  var g = m.group
  var envelope = { rev: rev, serial: serial, camera: camera, index: index, count: count, group: null }
  var gid = isPlainObject(g) ? groupIdOf(g.id) : ""
  if (gid === "") {
    var raw = isPlainObject(g) && typeof g.id === "string" ? g.id : ""
    envelope.group = { refused: true, key: raw !== "" && raw.length <= ID_CAP ? "=" + raw : "#" + index }
    return envelope
  }
  var src = Array.isArray(g.settings) ? g.settings : []
  // A group's settings share one scope: the first one's. Only a group of
  // global settings is published with no camera (the set then holds only
  // those); a camera group needs the camera it is for.
  var scope = src.length > 0 ? settingScope(src[0]) : "camera"
  if (camera === "" && scope !== "global") {
    // Not a group of a set with no camera: refused, so the line still fills
    // its place and the set commits without it.
    envelope.group = { refused: true, key: "#" + index }
    return envelope
  }
  var surface = groupSurface(g, scope)
  var n = Math.min(src.length, SETTINGS_LINE_LOOK)
  var rows = []
  var skipped = 0
  for (var i = 0; i < n; i++) {
    var e = settingEntry(src[i], surface)
    if (e) rows.push(e)
    else if (settingKnown(src[i])) skipped++
  }
  var label = settingText(g.label, SETTING_LABEL_CAP)
  envelope.group = { refused: false, id: gid, scope: scope, surface: surface, label: label !== "" ? label : gid, rows: rows,
                     total: rows.length + skipped + (src.length - n) }
  return envelope
}

// The lines of an assembled set -> the committed set: groups in the order
// they first appear, the parts of a group joined, a repeated setting id kept
// once (its first row), and the caps applied: SETTINGS_PER_GROUP_CAP rows a
// group, then SETTINGS_GROUP_CAP groups and SETTINGS_ROW_CAP rows in all, in
// order. Each group keeps the number of its settings the daemon sent that
// count (`total`, see settingsGroupLine), and the set the number of groups
// (`groupsTotal`) for the "Showing N of M" lines: every group drawn, every
// one past the cap, and every refused one; a group whose every setting is of
// an unknown type is neither drawn nor counted. The maps are prototype-free:
// a group or setting id is never a key of Object.prototype. At most
// SETTINGS_LINES_CAP lines of SETTINGS_LINE_LOOK rows are walked.
function commitSettings(a) {
  var all = []
  var byId = Object.create(null)
  var seen = Object.create(null)
  var refused = Object.create(null)
  var refusedCount = 0
  for (var i = 0; i < a.count && i < SETTINGS_LINES_CAP; i++) {
    var line = a.lines[i]
    if (line.group.refused) {
      if (refused[line.group.key] !== true) {
        refused[line.group.key] = true
        refusedCount++
      }
      continue
    }
    // A group is told apart by its scope and surface as well as its id: a
    // camera group, a global one and a microphone one may share an id.
    var key = line.group.scope + ":" + line.group.surface + ":" + line.group.id
    var g = byId[key]
    if (g === undefined) {
      g = { id: line.group.id, scope: line.group.scope, surface: line.group.surface, label: line.group.label, rows: [], total: 0 }
      byId[key] = g
      all.push(g)
    }
    g.total += line.group.total
    for (var r = 0; r < line.group.rows.length && r < SETTINGS_LINE_LOOK; r++) {
      var row = line.group.rows[r]
      if (seen[row.id] === true) { g.total--; continue }
      seen[row.id] = true
      if (g.rows.length < SETTINGS_PER_GROUP_CAP) g.rows.push(row)
    }
  }
  // The caps apply to each place a group is drawn on its own (the camera's,
  // the global ones, the microphone's), so that no tab's groups crowd
  // another's out (a refused group counts with the camera's).
  var out = []
  var counted = { camera: refusedCount, global: 0, mic: 0 }
  var shown = { camera: 0, global: 0, mic: 0 }
  var rows = { camera: 0, global: 0, mic: 0 }
  for (var k = 0; k < all.length; k++) {
    var total = Math.max(all[k].rows.length, all[k].total)
    if (total === 0) continue
    var sc = all[k].scope
    var place = all[k].surface === MIC_SURFACE ? "mic" : sc
    counted[place]++
    if (shown[place] >= SETTINGS_GROUP_CAP) continue
    var kept = all[k].rows.slice(0, Math.max(0, SETTINGS_ROW_CAP - rows[place]))
    rows[place] += kept.length
    shown[place]++
    out.push({ id: all[k].id, scope: sc, surface: all[k].surface, label: all[k].label, rows: kept, total: total })
  }
  return { rev: a.rev, serial: a.serial, camera: a.camera, groups: out, groupsTotal: counted.camera, globalGroupsTotal: counted.global,
           micGroupsTotal: counted.mic }
}

// One settings_group line applied to the record (a copy): kept in the set
// being assembled; a line of another rev, serial, camera or count starts a
// new set (the half-assembled one is dropped); a repeated index is ignored;
// the set's last line commits it. A line older than the committed set (the
// same serial and camera, a lower rev) is ignored: it would put back values
// a delta has moved on from. Returns the outcome: "settings" (a set
// committed), "settings_group" (a part kept), or "ignored".
function applySettingsGroup(r, m) {
  var line = settingsGroupLine(m)
  if (!line) return "ignored"
  var set = isPlainObject(r.settings) ? r.settings : null
  if (set && set.serial === line.serial && set.camera === line.camera && line.rev < set.rev) return "ignored"
  var a = r.settingsAssembly
  if (!a || a.rev !== line.rev || a.serial !== line.serial || a.camera !== line.camera || a.count !== line.count) {
    var empty = []
    for (var i = 0; i < line.count; i++) empty.push(null)
    a = { rev: line.rev, serial: line.serial, camera: line.camera, count: line.count, lines: empty, received: 0 }
  }
  if (a.lines[line.index] !== null) return "ignored"
  var lines = a.lines.slice()
  lines[line.index] = line
  a = { rev: a.rev, serial: a.serial, camera: a.camera, count: a.count, lines: lines, received: a.received + 1 }
  if (a.received < a.count) {
    r.settingsAssembly = a
    return "settings_group"
  }
  r.settingsAssembly = null
  r.settings = commitSettings(a)
  r.settingsCleared = false
  return "settings"
}

// A change of a delta applied to a copy of `row`: each key only when it is
// of the right type (an absent or mistyped key keeps the row's value); an
// int clamped into the row's range, an enum value that is not one of its
// options reads as "".
function settingChanged(row, c) {
  var out = {}
  for (var key in row) if (Object.prototype.hasOwnProperty.call(row, key)) out[key] = row[key]
  if (row.type === "int") {
    var v = settingInt(c.value)
    if (v !== null) out.value = clampInt(v, row.min, row.max)
  } else if (row.type === "bool") {
    if (typeof c.value === "boolean") out.value = c.value
  } else if (row.type === "enum") {
    if (typeof c.value === "string") out.value = optionIndex(row.options, c.value) >= 0 ? c.value : ""
  }
  if (typeof c.stored === "boolean") out.stored = c.stored
  if (typeof c.enabled === "boolean") out.enabled = c.enabled
  if (out.enabled) out.reason = ""
  else if (typeof c.disabled_reason === "string") out.reason = settingText(c.disabled_reason, SETTING_REASON_CAP)
  // A change that carries `enabled` carries the kind with it (absent: an
  // older daemon, read as none).
  if (out.enabled) out.kind = ""
  else if (typeof c.enabled === "boolean" || c.disabled_kind !== undefined) out.kind = disabledKind(c.disabled_kind)
  return out
}

// A settings_delta applied to the committed set -> a new set, or null when it
// does not apply: no set, another schema, serial or camera, or a rev older
// than the set's (a delta of the set's own rev applies: a large change set
// spans several lines of one rev). At most SETTINGS_LINE_LOOK changes are
// looked at; a change for an id the set does not show is skipped.
function settingsDelta(set, m) {
  if (!set || !isPlainObject(m) || m.schema !== SETTINGS_SCHEMA) return null
  var rev = settingsNumber(m.rev)
  if (rev === 0 || rev < set.rev || settingsNumber(m.serial) !== set.serial || typeof m.camera !== "string" || rawId(m.camera) !== set.camera) return null
  var groups = []
  var where = Object.create(null)
  for (var g = 0; g < set.groups.length; g++) {
    groups.push({ id: set.groups[g].id, scope: set.groups[g].scope, surface: set.groups[g].surface, label: set.groups[g].label,
                  rows: set.groups[g].rows.slice(), total: set.groups[g].total })
    for (var r = 0; r < set.groups[g].rows.length; r++) where[set.groups[g].rows[r].id] = [g, r]
  }
  var changes = Array.isArray(m.changes) ? m.changes : []
  var n = Math.min(changes.length, SETTINGS_LINE_LOOK)
  for (var i = 0; i < n; i++) {
    var c = changes[i]
    if (!isPlainObject(c)) continue
    var id = settingId(c.id)
    var at = id !== "" ? where[id] : undefined
    if (at === undefined) continue
    groups[at[0]].rows[at[1]] = settingChanged(groups[at[0]].rows[at[1]], c)
  }
  return { rev: rev, serial: set.serial, camera: set.camera, groups: groups, groupsTotal: set.groupsTotal, globalGroupsTotal: set.globalGroupsTotal,
           micGroupsTotal: set.micGroupsTotal }
}

// ---- capability

// Whether the settings can be read and set: an available daemon at interface
// revision SETTINGS_REVISION or later, through a CLI that reports a settings
// schema this plugin reads. An unknown revision counts as no.
function settingsSupported(record) {
  return available(record) && record.interfaceRevision >= SETTINGS_REVISION
    && record.settingsField === "number" && record.settingsSchema >= 1 && record.settingsSchema <= SETTINGS_SCHEMA
}

// Why the settings cannot be shown while the daemon is available: the CLI
// (no settings_schema field at all), a newer schema than this plugin reads,
// or the daemon (null, or an interface revision below SETTINGS_REVISION).
// "" otherwise.
function settingsMissingText(record) {
  if (!available(record) || settingsSupported(record)) return ""
  if (record.settingsField === "absent") return CLI_NO_SETTINGS
  if (record.settingsField === "number" && record.interfaceRevision >= SETTINGS_REVISION
      && record.settingsSchema > SETTINGS_SCHEMA)
    return PLUGIN_OLD_SETTINGS
  return DAEMON_NO_SETTINGS
}

// Whether the daemon has the camera open, so a setting it is given is written
// to the camera at once: `starting` as well as `active`.
function settingsLive(record) {
  return available(record) && SETTINGS_LIVE_STATES.indexOf(record.state) >= 0
}

// A row of the committed set by id, or null.
function findSetting(record, id) {
  var set = record && isPlainObject(record.settings) ? record.settings : null
  if (!set || typeof id !== "string") return null
  for (var g = 0; g < set.groups.length && g < SETTINGS_SET_GROUP_CAP; g++) {
    var rows = set.groups[g].rows
    for (var r = 0; r < rows.length && r < SETTINGS_PER_GROUP_CAP; r++) if (rows[r].id === id) return rows[r]
  }
  return null
}

// ---- values

// An int value on the row's grid: min + k * step, rounded to the nearest k
// and kept within [min, max]. null for a value that is not a finite number
// within [min, max], or a row that is not an int.
function snapSetting(row, value) {
  if (!row || row.type !== "int" || typeof value !== "number" || !isFinite(value)) return null
  if (value < row.min || value > row.max) return null
  var kmax = Math.floor((row.max - row.min) / row.step)
  var k = Math.max(0, Math.min(kmax, Math.round((value - row.min) / row.step)))
  return row.min + k * row.step
}

// As snapSetting, for what a slider or a key produces: clamped into range
// first. null for a value that is not a finite number.
function clampSetting(row, value) {
  if (!row || row.type !== "int" || typeof value !== "number" || !isFinite(value)) return null
  return snapSetting(row, clampInt(value, row.min, row.max))
}

// One Left/Right press on a slider: about a twentieth of the range, on the
// step grid, at least one step.
function settingKeyStep(row) {
  if (!row || row.type !== "int") return 0
  return Math.max(row.step, Math.round((row.max - row.min) / 20 / row.step) * row.step)
}

// One Left/Right press on a slider: it moves by settingKeyStep. null when
// nothing moves, and for every other type: a choice row's Left/Right walk
// its chip cursor (choiceCursorAfter) and write nothing until Enter or Space,
// as the panel's other choice rows do; a dropdown opens on Enter.
function settingNudge(row, current, direction) {
  if (!row || row.type !== "int" || !(direction === 1 || direction === -1)) return null
  if (typeof current !== "number" || !isFinite(current)) return null
  return clampSetting(row, current + direction * settingKeyStep(row))
}

// A value the user chose, made a value of the row: an int clamped onto its
// grid, a strict boolean, one of the row's option values. null otherwise
// (and always for an action: it has no value).
function rowValue(row, value) {
  if (!row) return null
  if (row.type === "int") return clampSetting(row, value)
  if (row.type === "bool") return typeof value === "boolean" ? value : null
  if (row.type === "enum") return typeof value === "string" && optionIndex(row.options, value) >= 0 ? value : null
  return null
}

// The value a row shows: the user's draft while one is unconfirmed (see
// Daemon.settingDrafts), else what the daemon reports.
function shownSettingValue(row, drafts) {
  if (!row) return null
  var v = rowValue(row, ownValue(drafts, row.id))
  return v === null ? row.value : v
}

// A value as the panel writes it: an int with its unit, an option's label.
function settingValueText(row, value) {
  if (!row) return ""
  if (row.type === "int") {
    var n = settingInt(value)
    if (n === null) return UNKNOWN
    if (row.displayRaw === true) return String(n)
    var unit = row.unit !== "" ? " " + row.unit : ""
    if (row.displayOffset !== null && row.displayOffset !== undefined && row.displayScale !== null && row.displayScale !== undefined) {
      var shown = (n - row.displayOffset) * row.displayScale
      return (shown >= 0 ? "+" + String(shown) : "\u2212" + String(-shown)) + unit
    }
    return String(n) + unit
  }
  if (row.type === "enum") {
    var at = optionIndex(row.options, value)
    return at >= 0 ? row.options[at].label : UNKNOWN
  }
  if (row.type === "bool") return value === true ? "On" : "Off"
  return ""
}

// What a screen reader is told about a row besides its label: the value it
// shows, and for a row the daemon greys out that it is unavailable, its
// value (what auto is doing is worth reading) and the daemon's reason.
function settingDescription(row) {
  if (!row) return ""
  var value = typeof row.valueText === "string" ? row.valueText : ""
  var note = typeof row.description === "string" ? row.description : ""
  if (row.enabled) return note !== "" ? (value !== "" ? value + ". " + note : note) : value
  var parts = ["Unavailable"]
  if (value !== "") parts.push(value)
  if (typeof row.reason === "string" && row.reason !== "") parts.push(row.reason)
  if (note !== "") parts.push(note)
  return parts.join(". ")
}

// Whether an enum's options are drawn as a row of buttons: at most
// SEGMENTED_MAX_OPTIONS of them, with labels that fit SEGMENTED_MAX_CHARS
// together. The panel's settings and the setup dialog's configuration rows
// share the rule; a row that fails it is a dropdown.
function fitsSegmented(options) {
  var list = Array.isArray(options) ? options : []
  var chars = 0
  for (var i = 0; i < list.length; i++) chars += String(list[i].label).length
  return list.length <= SEGMENTED_MAX_OPTIONS && chars <= SEGMENTED_MAX_CHARS
}

// The widget a row gets: an int of exactly two values is a switch (on: its
// maximum), any other int a slider; a bool a switch; an enum a row of
// buttons while fitsSegmented, else a dropdown.
function settingWidget(row) {
  if (!row) return ""
  if (row.type === "int") return intIsSwitch(row) ? "switch" : "slider"
  if (row.type === "bool") return "switch"
  if (row.type === "action") return "action"
  return fitsSegmented(row.options) ? "segmented" : "dropdown"
}

// An int that takes exactly two values (its minimum and its maximum).
function intIsSwitch(row) {
  return !!row && row.type === "int" && typeof row.min === "number" && typeof row.max === "number"
    && row.max > row.min && row.max - row.min === row.step
}

// Whether a switch row shows on: a bool's true, a two-value int at its
// maximum.
function switchChecked(row, value) {
  if (!row) return false
  return row.type === "int" ? value === row.max : value === true
}

// The value a click on a switch row writes: the other one of its two.
function switchFlip(row) {
  if (!row) return null
  if (row.type === "int") return row.value === row.max ? row.min : row.max
  return row.value !== true
}

// ---- the panel's view

// The group that is open: at most one at a time (an accordion, so the
// Camera tab is never taller than its tallest group). `open` is the panel's
// choice of this session (memory only): a group id (that group, while the
// set has it), "" (the user closed the open group: none), or anything else,
// a group the set does not have included (no choice): the first group the
// tab draws, in the daemon's order. "" when none is open. Only the camera's
// groups count: the global ones are never in the accordion.
function openGroupId(open, set) {
  if (!isPlainObject(set) || !Array.isArray(set.groups)) return ""
  var first = ""
  for (var i = 0; i < set.groups.length && i < SETTINGS_SET_GROUP_CAP; i++) {
    var g = set.groups[i]
    if (g.scope === "global") continue
    if (first === "" && groupDrawn(g, set)) first = g.id
    if (open !== "" && typeof open === "string" && g.id === open) return open
  }
  if (first === "" || open === "") return ""
  return first
}

// Whether a group is an entry of the accordion: it has a row the panel
// draws in place (shown or greyed), or none at all (cut to nothing by a cap:
// it is drawn, to say so).
function groupDrawn(group, set) {
  if (group.rows.length === 0) return true
  var values = settingValues(set)
  for (var r = 0; r < group.rows.length && r < SETTINGS_PER_GROUP_CAP; r++) {
    var at = settingPlacement(group.rows[r], values)
    if (at === "shown" || at === "greyed") return true
  }
  return false
}

// The settings section of a tab, exactly as it is drawn:
//   { visible, hint, note, groups, truncation, reset, rowCount, setKey,
//     title, collapsible, unavailable }
// groups: { id, label, heading, index, expanded, glyph, rows, truncation,
// live }, where the rows of a collapsed group are not listed, `heading` is
// whether its label is drawn (a group that is one master and its
// dependents is not headed: the master's row is the heading), and `live` is
// a read-only line under the rows ("" for none, see groupLiveText); a row:
//   { id, type, widget, label, enabled, greyed, kind, reason, description,
//     help, depth, checked, displayOffset, displayScale, value, valueText,
//     min, max, step, options, selectedIndex, optionsNote, stop }
// Only rows the panel draws in place are listed (settingPlacement: shown or
// greyed); `depth` 1 draws a row under its master (the first setting its
// rule names, an earlier row of the same group). `help` is what the row
// says under the cursor: its reason while greyed, its description. `stop`
// numbers the rows drawn, top to bottom (the keyboard's stops, see
// cursorStops). `unavailable` lists what the tab's "Not available now"
// line holds (unavailableEntries). `hint` replaces everything when the
// settings cannot be shown (an old CLI or daemon, a newer schema, a camera
// without settings); `note` says whether a change applies live or at the
// next open. `open` is the panel's choice of open group (openGroupId).
// `setKey` names the set (its camera and serial): a row of another key is
// another camera's or another structure's, whatever its place (a held
// slider lets go). `collapsible` is whether the groups open and close (one
// at a time).
function emptySettingsView() {
  return { visible: false, hint: "", note: "", groups: [], truncation: "", reset: false, rowCount: 0, setKey: "",
           title: "", collapsible: true, unavailable: [] }
}

function viewRowOf(row, drafts, stop, depth) {
  var value = shownSettingValue(row, drafts)
  var widget = settingWidget(row)
  var help = row.enabled ? row.description
    : (row.reason !== "" && row.description !== "" ? row.reason + ". " + row.description : (row.reason !== "" ? row.reason : row.description))
  return {
    id: row.id, type: row.type, widget: widget, label: row.label, enabled: row.enabled, greyed: !row.enabled,
    kind: row.kind || "", reason: row.reason, description: row.description, help: help, depth: depth === 1 ? 1 : 0,
    checked: widget === "switch" ? switchChecked(row, value) : false,
    displayOffset: row.displayOffset, displayScale: row.displayScale,
    value: value, valueText: settingValueText(row, value), min: row.min, max: row.max,
    step: row.step, options: row.options, selectedIndex: row.type === "enum" ? optionIndex(row.options, value) : -1,
    optionsNote: showingText(row.options.length, row.optionsTotal, "choices"), stop: stop
  }
}

// Where every row of the set is drawn: id -> settingPlacement, over the
// daemon's values (settingValues).
function setPlacements(set) {
  var values = settingValues(set)
  var out = Object.create(null)
  var groups = isPlainObject(set) && Array.isArray(set.groups) ? set.groups : []
  for (var g = 0; g < groups.length && g < SETTINGS_SET_GROUP_CAP; g++) {
    var rows = groups[g].rows
    for (var r = 0; r < rows.length && r < SETTINGS_PER_GROUP_CAP; r++) out[rows[r].id] = settingPlacement(rows[r], values)
  }
  return out
}

// One group laid out for a tab: { rows, topLevel, unavailable, stop, looked }.
// `rows` are the rows drawn in place (viewRowOf, numbered from `stop`; none
// when `collapsed`, though the rest is still worked out), `topLevel` how many
// of them are not under a master, `unavailable` the group's entries for the
// "Not available now" list: one per row placed there, except a row whose
// master is not drawn either (its master's entry says it) and, for kind
// other_provider, one for the whole group (another module does the group's
// job). `skip(row)` true leaves a row out entirely. `looked` counts every
// row looked at, wherever it is drawn: the rows past it (the cap) are what a
// group's "Showing N of M" counts out.
function layoutGroup(group, placements, drafts, stop, collapsed, skip) {
  var out = { rows: [], topLevel: 0, unavailable: [], stop: stop, looked: 0 }
  var depthOf = Object.create(null)
  var provided = false
  for (var r = 0; r < group.rows.length && r < SETTINGS_PER_GROUP_CAP; r++) {
    var row = group.rows[r]
    out.looked++
    if (skip && skip(row)) continue
    var at = placements[row.id]
    var master = rowMaster(row)
    if (at === "unavailable") {
      var masterAt = master !== "" ? placements[master] : undefined
      if (masterAt === "unavailable" || masterAt === "hidden") continue
      if (row.kind === "other_provider") {
        if (provided) continue
        provided = true
        out.unavailable.push({ key: group.id + ":" + row.id, label: group.label !== "" ? group.label : row.label,
                               reason: row.reason, setup: notAvailableSetup(row.kind), kind: row.kind })
        continue
      }
      out.unavailable.push({ key: group.id + ":" + row.id, label: row.label, reason: row.reason,
                             setup: notAvailableSetup(row.kind), kind: row.kind })
      continue
    }
    if (at !== "shown" && at !== "greyed") continue
    var depth = master !== "" && depthOf[master] !== undefined ? 1 : 0
    depthOf[row.id] = depth
    if (depth === 0) out.topLevel++
    if (!collapsed) out.rows.push(viewRowOf(row, drafts, out.stop++, depth))
  }
  return out
}

// The tab's "Not available now" line: { visible, count, text, glyph, open,
// entries, note } (entries listed only while open, at most
// SETTINGS_ROW_CAP of them; `count` and the text say the real number, and
// `note` "Showing N of M entries" when the list is cut). `open` is the
// panel's choice of the session for that tab (memory only).
function notAvailableView(view, open) {
  var list = isPlainObject(view) && Array.isArray(view.unavailable) ? view.unavailable : []
  var total = list.length
  var n = Math.min(total, SETTINGS_ROW_CAP)
  var out = { visible: total > 0, count: total, text: total > 0 ? NOT_AVAILABLE_TEXT + " (" + total + ")" : "",
              open: total > 0 && open === true, glyph: total > 0 && open === true ? GLYPH_EXPANDED : GLYPH_COLLAPSED,
              entries: [], note: "" }
  if (out.open) {
    out.note = showingText(n, total, "entries")
    for (var i = 0; i < n; i++) {
      var e = list[i]
      out.entries.push({ key: e.key, label: e.label, reason: e.reason, setup: e.setup === true, index: i })
    }
  }
  return out
}

// The keyboard stops of a "Not available now" line: the line, then each
// entry's Setup button while open (`id`: the entry's key).
function notAvailableStops(view) {
  var out = []
  if (!isPlainObject(view) || view.visible !== true) return out
  out.push({ kind: "unavailable", index: -1 })
  var list = Array.isArray(view.entries) ? view.entries : []
  for (var i = 0; i < list.length && i < SETTINGS_ROW_CAP; i++) if (list[i].setup) out.push({ kind: "unavailable-setup", index: i, id: String(list[i].key || "") })
  return out
}

// The Camera tab's section: the groups whose settings are per camera.
function settingsView(record, open, drafts) {
  var out = emptySettingsView()
  out.title = SETTINGS_TITLE
  if (!available(record)) return out
  if (!settingsSupported(record)) {
    out.hint = settingsMissingText(record)
    out.visible = out.hint !== ""
    return out
  }
  var set = record.settings
  if (!isPlainObject(set)) {
    out.hint = record.settingsCleared === true && record.activeCamera !== "" ? SETTINGS_EMPTY_TEXT : ""
    out.visible = out.hint !== ""
    return out
  }
  out.setKey = JSON.stringify([set.camera, set.serial])
  var openId = openGroupId(open, set)
  var placements = setPlacements(set)
  var stop = 0
  var cameraGroups = 0
  for (var g = 0; g < set.groups.length && g < SETTINGS_SET_GROUP_CAP; g++) {
    var group = set.groups[g]
    if (group.scope === "global") continue
    cameraGroups++
    var expanded = group.id === openId
    var laid = layoutGroup(group, placements, drafts, stop, !expanded, null)
    stop = laid.stop
    out.unavailable = out.unavailable.concat(laid.unavailable)
    // A group whose rows are all drawn elsewhere (hidden, or in the "Not
    // available now" list) is no accordion entry; one cut to nothing by a
    // cap is, to say so.
    if (laid.topLevel === 0 && group.rows.length > 0) continue
    out.groups.push({
      id: group.id, label: group.label, heading: true, index: out.groups.length, expanded: expanded,
      glyph: expanded ? GLYPH_EXPANDED : GLYPH_COLLAPSED,
      rows: laid.rows, truncation: expanded ? showingText(laid.looked, group.total, "settings") : "",
      live: groupLiveText(record, group.id)
    })
  }
  out.rowCount = stop
  // "Showing N of M groups": N is what is drawn (commitSettings keeps only
  // groups to draw), M counts the refused and capped ones too, less those
  // with nothing to draw in place.
  var undrawn = cameraGroups - out.groups.length
  out.truncation = showingText(out.groups.length, Math.max(0, set.groupsTotal - undrawn), "groups")
  if (out.groups.length === 0) {
    // A set of global settings only: there is no camera, and nothing to say.
    out.hint = set.camera !== "" && out.unavailable.length === 0 ? SETTINGS_EMPTY_TEXT : ""
    if (set.camera === "") out.truncation = ""
    // Drawn while it has a hint or a "Not available now" line to say (the
    // line is a cursor stop only while it is drawn).
    out.visible = out.hint !== "" || out.unavailable.length > 0
    return out
  }
  out.visible = true
  out.note = settingsLive(record) ? SETTINGS_LIVE_TEXT : SETTINGS_IDLE_TEXT
  out.reset = true
  return out
}

// The breaks between the groups of a tab that draws them all open (the
// Effect and Mic tabs), so that a heading's section reads as one, and rows
// that are not in it never read as its items. Each group gets `breakAbove`:
//   "gap"   a headed group after anything drawn: a gap above its heading
//   "rule"  a group with no heading right after a headed section (the
//           section above, `headedAbove`, for the first): a gap with a
//           faint line, which ends that section
//   ""      none: a group with no heading after one with none flows on as
//           rows of the same rhythm (one master and its dependents each)
// The lead group (what follows the background choice) is part of the
// section above it. `drawnAbove`: something is drawn above the first group.
function markGroupBreaks(groups, headedAbove, drawnAbove) {
  var list = Array.isArray(groups) ? groups : []
  var headed = headedAbove === true
  var drawn = drawnAbove === true
  for (var i = 0; i < list.length; i++) {
    var g = list[i]
    if (g.lead === true) { g.breakAbove = ""; drawn = true; continue }
    if (g.heading === true) g.breakAbove = drawn ? "gap" : ""
    else g.breakAbove = headed ? "rule" : ""
    headed = g.heading === true
    drawn = true
  }
  return list
}

// The setting the Effect tab's dedicated choice row owns: the background
// effect. The only one this plugin names; every other global setting is
// drawn by the generic renderer.
var EFFECT_MODE_SETTING = "effect.background.mode"

// The Effect tab's generic section: every group of global settings, all open
// (no accordion, no reset: the camera's reset never reaches them), without
// the setting the dedicated row owns, and without the microphone's groups
// (the Mic tab draws those). The rows whose master is the background
// effect's choice (its strength, ...) come first, in a group of their own
// with no heading (`lead`), drawn under the choice row: they follow the
// choice. A group left with nothing to draw is not drawn. Nothing
// (`visible` false) when the daemon publishes no other global setting, or
// predates module effects (MODULES_REVISION: the tab then says it needs
// updating).
function effectSettingsView(record, drafts) {
  var out = emptySettingsView()
  out.collapsible = false
  if (!moduleEffects(record) || !settingsSupported(record) || !isPlainObject(record.settings)) return out
  var set = record.settings
  out.setKey = JSON.stringify([set.camera, set.serial])
  var placements = setPlacements(set)
  var stop = 0
  var skippedGroups = 0
  var effectGroups = []
  for (var a = 0; a < set.groups.length && a < SETTINGS_SET_GROUP_CAP; a++)
    if (set.groups[a].scope === "global" && set.groups[a].surface !== MIC_SURFACE) effectGroups.push(set.groups[a])
  // The choice's dependents (rows whose rule names the choice first), from
  // every group, drawn under the choice.
  var follows = function(row) { return rowMaster(row) === EFFECT_MODE_SETTING }
  var lead = { id: "background-follows", label: "", rows: [], total: 0 }
  for (var b = 0; b < effectGroups.length; b++) {
    var gr = effectGroups[b].rows
    for (var c = 0; c < gr.length && c < SETTINGS_PER_GROUP_CAP; c++)
      if (follows(gr[c]) && lead.rows.length < SETTINGS_PER_GROUP_CAP) lead.rows.push(gr[c])
  }
  var leadOut = { rows: [], unavailable: [], stop: 0 }
  if (lead.rows.length > 0) {
    // The choice is drawn above them, as their master: each is under it.
    leadOut = layoutGroup(lead, placements, drafts, stop, false, null)
    for (var d = 0; d < leadOut.rows.length; d++) leadOut.rows[d].depth = 1
    stop = leadOut.stop
    if (leadOut.rows.length > 0)
      out.groups.push({ id: lead.id, label: "", heading: false, lead: true, index: 0, expanded: true, glyph: "",
                        rows: leadOut.rows, truncation: "", live: "" })
  }
  for (var g = 0; g < effectGroups.length; g++) {
    var group = effectGroups[g]
    var unavailableMode = []
    for (var m = 0; m < group.rows.length && m < SETTINGS_PER_GROUP_CAP; m++) {
      var row = group.rows[m]
      // The choice itself cannot run here: the list names it by its group.
      if (row.id === EFFECT_MODE_SETTING && placements[row.id] === "unavailable")
        unavailableMode.push({ key: group.id + ":" + row.id, label: group.label !== "" ? group.label : row.label,
                               reason: row.reason, setup: notAvailableSetup(row.kind), kind: row.kind })
    }
    var laid = layoutGroup(group, placements, drafts, stop, false,
                           function(r) { return r.id === EFFECT_MODE_SETTING || follows(r) })
    stop = laid.stop
    out.unavailable = out.unavailable.concat(unavailableMode, laid.unavailable)
    if (laid.rows.length === 0) { skippedGroups++; continue }
    out.groups.push({
      id: group.id, label: group.label, heading: laid.topLevel > 1, lead: false, index: out.groups.length, expanded: true, glyph: "",
      rows: laid.rows, truncation: showingText(laid.looked, group.total, "settings"),
      live: groupLiveText(record, group.id)
    })
  }
  out.unavailable = out.unavailable.concat(leadOut.unavailable)
  // The background choice above heads its own section.
  var modeShown = effectModeShown(record)
  markGroupBreaks(out.groups, modeShown, modeShown)
  out.rowCount = stop
  out.truncation = showingText(out.groups.length - (out.groups.length > 0 && out.groups[0].lead === true ? 1 : 0) + skippedGroups,
                               set.globalGroupsTotal, "groups")
  // Drawn while it has rows, or a "Not available now" line to say.
  out.visible = out.groups.length > 0 || out.unavailable.length > 0
  return out
}

// Whether the Effect tab draws the daemon's global settings (a daemon that
// publishes some besides the background effect's choice).
function effectSettingsShown(view) {
  return isPlainObject(view) && Array.isArray(view.groups) && view.groups.length > 0
}

// The open group after the user opens (`open` true) or closes group `id`:
// opening one closes the one open before; closing the open one leaves none
// open (""); closing a group that is not open changes nothing. `current` and
// the result are panel choices as openGroupId reads them.
function groupOpenAfter(current, set, id, open) {
  var shown = openGroupId(current, set)
  if (open === true) return typeof id === "string" && id !== "" ? id : current
  return id === shown ? "" : current
}

// A segmented row's chip under the keyboard after a Left/Right press
// (`direction` -1 or 1) from `index`: within the row's options, no wrap. A
// cursor that is on no chip yet starts from the selected one (or the first).
function choiceCursorAfter(row, index, direction) {
  var n = row && Array.isArray(row.options) ? Math.min(row.options.length, SETTING_OPTION_CAP) : 0
  if (n === 0) return -1
  var from = typeof index === "number" && index >= 0 && index < n ? index
    : Math.max(0, typeof row.selectedIndex === "number" ? row.selectedIndex : -1)
  return Math.max(0, Math.min(n - 1, from + (direction > 0 ? 1 : (direction < 0 ? -1 : 0))))
}

// The chip a keyboard cursor lands on when it arrives on a segmented row:
// the selected choice, else the first.
function choiceCursorStart(row) {
  return row && typeof row.selectedIndex === "number" && row.selectedIndex >= 0 ? row.selectedIndex : 0
}

// The row of the view at keyboard stop `stop`, or null.
function viewRow(view, stop) {
  var groups = view && Array.isArray(view.groups) ? view.groups : []
  for (var g = 0; g < groups.length && g < SETTINGS_GROUP_CAP; g++) {
    var rows = groups[g].rows
    for (var r = 0; r < rows.length && r < SETTINGS_PER_GROUP_CAP; r++) if (rows[r].stop === stop) return rows[r]
  }
  return null
}

// ---- writes

// The words a value is written as: a decimal integer (a leading minus is
// fine: it comes after `--`), true or false, or an option value.
var SETTING_VALUE_RE = /^(-?[0-9]{1,10}|true|false|[a-z0-9_@/]{1,32})$/

// A value of `row` as its argv word, or null: an int put on the row's grid
// and written by String() (a device integer has no exponent), a strict
// boolean as true/false, an enum only as one of that row's option values, an
// action only as true (from a real true).
function settingArgvValue(row, value) {
  if (!row) return null
  if (row.type === "int") {
    var v = settingInt(snapSetting(row, value))
    return v === null ? null : String(v)
  }
  if (row.type === "bool") return typeof value === "boolean" ? (value ? "true" : "false") : null
  if (row.type === "enum") return typeof value === "string" && optionIndex(row.options, value) >= 0 ? value : null
  if (row.type === "action") return value === true ? "true" : null
  return null
}

// The camera goes in its own `--camera=` element (validated as camera
// selections are), the id and the value after `--`, each one argv element:
// nothing is ever parsed as an option, and nothing reaches a shell.
function settingArgv(cli, camera, id, word) {
  var cam = selectableId(camera)
  if (!cliUsable(cli) || cam === "" || settingId(id) === "" || typeof word !== "string" || !SETTING_VALUE_RE.test(word))
    return null
  return [cli, "settings", "set", "--camera=" + cam, "--", id, word]
}

// A global setting is the daemon's own, not a camera's: no camera is named
// (the daemon ignores it for such an id), and one intent is good whichever
// camera is active, or none.
function settingArgvGlobal(cli, id, word) {
  if (!cliUsable(cli) || settingId(id) === "" || typeof word !== "string" || !SETTING_VALUE_RE.test(word))
    return null
  return [cli, "settings", "set", "--", id, word]
}

// A microphone setting is a global one: written as one, after `--`, with
// the wider word grammar of its option values (a PipeWire node name, see
// MIC_OPTION_VALUE_RE).
var MIC_SETTING_VALUE_RE = /^(-?[0-9]{1,10}|true|false|[A-Za-z0-9][A-Za-z0-9_.:@/+-]{0,127})$/

function settingArgvMic(cli, id, word) {
  if (!cliUsable(cli) || settingId(id) === "" || typeof word !== "string" || !MIC_SETTING_VALUE_RE.test(word))
    return null
  return [cli, "settings", "set", "--", id, word]
}

function resetSettingsArgv(cli, camera) {
  var cam = selectableId(camera)
  return cliUsable(cli) && cam !== "" ? [cli, "settings", "reset", "--camera=" + cam] : null
}

// A setting or reset intent runs only against the camera whose settings the
// panel showed when it was made (`camera`, the committed set's): every write
// names that camera, and none runs once the set is another camera's.
function settingIntentBound(intent, record) {
  return isPlainObject(intent) && isPlainObject(record) && isPlainObject(record.settings)
    && typeof intent.camera === "string" && intent.camera !== "" && intent.camera === record.settings.camera
}

// The argv for a setting intent ({ verb: "setting", id, value, camera })
// under `record`: the settings are offered, the intent is bound to the set's
// camera (a camera row; a global row is bound to no camera), the row is in
// the set and enabled now, and the value is one of the row's; null otherwise.
function settingIntentArgv(cli, record, intent) {
  if (!settingsSupported(record)) return null
  var row = isPlainObject(intent) ? findSetting(record, intent.id) : null
  if (!row || !row.enabled) return null
  if (row.scope !== "global" && !settingIntentBound(intent, record)) return null
  var word = settingArgvValue(row, intent.value)
  if (word === null) return null
  if (row.surface === MIC_SURFACE) return settingArgvMic(cli, row.id, word)
  return row.scope === "global" ? settingArgvGlobal(cli, row.id, word) : settingArgv(cli, record.settings.camera, row.id, word)
}

function isSettingIntent(intent) {
  return isPlainObject(intent) && (intent.verb === "setting" || intent.verb === "reset-settings")
}

// Whether the queue takes `intent`: anything but a setting write always; a
// write when, counting the queued writes of other ids (a queued write for the
// same id is replaced, so it does not count), fewer than the cap of its own
// kind are queued: SETTING_QUEUE_CAP slider writes, QUICK_QUEUE_CAP quick
// writes or ACTION_QUEUE_CAP actions (an action is never refused for quick
// writes: it has no draft to keep). A write the queue does not take is not
// lost: the Daemon keeps its draft unsent and writes it once a queued command
// has run (Daemon.flushSettings). Nothing is ever evicted to make room, so no
// other ask is dropped and no draft is left waiting on a write that will
// never run.
function queueTakes(queue, intent) {
  if (isSetupIntent(intent)) return !setupWriteBusy(null, queue)
  if (!isPlainObject(intent) || intent.verb !== "setting") return true
  var q = Array.isArray(queue) ? queue : []
  var count = { slider: 0, quick: 0, action: 0 }
  for (var i = 0; i < q.length && i < INTENT_QUEUE_CAP; i++) {
    if (!isPlainObject(q[i]) || q[i].verb !== "setting") continue
    if (q[i].id === intent.id) continue
    count[queueKind(q[i])]++
  }
  var kind = queueKind(intent)
  var cap = kind === "action" ? ACTION_QUEUE_CAP : (kind === "quick" ? QUICK_QUEUE_CAP : SETTING_QUEUE_CAP)
  return count[kind] < cap
}

// Which bound a queued setting write counts against.
function queueKind(intent) {
  if (intent.action === true) return "action"
  return isQuickIntent(intent) ? "quick" : "slider"
}

// The command queue behind a running command, as a pure step: `intent`
// added to `queue` (a new array; neither is modified). A queued write for
// the same setting id is replaced by the newer one, and a reset replaces
// every queued write and reset (it supersedes them), so a slider drag never
// queues more than one command per setting. Any other ask replaces the
// other ask queued before it (the latest wins); a setup write (the setup
// dialog's) is neither replaced by one nor replaces one, and a microphone
// on/off replaces only the one before it. The new intent goes last, so
// the order of what the user did is kept, except an on/off ask (the
// camera's or the microphone's): it goes first, so turning the camera off
// never waits behind slider writes, and a
// discrete ask (isQuickIntent) goes ahead of the queued slider writes. A
// write queueTakes refuses leaves the queue as it was. So the queue holds at
// most one other ask, one reset, SETTING_QUEUE_CAP slider writes,
// QUICK_QUEUE_CAP quick writes, ACTION_QUEUE_CAP actions, SETUP_QUEUE_CAP
// setup writes and MIC_QUEUE_CAP microphone on/off asks, which is
// INTENT_QUEUE_CAP (the table above SETTING_QUEUE_CAP): the input is cut to it
// as a backstop only, and nothing is ever cut from a queue this function made.
function enqueueIntent(queue, intent) {
  var q = Array.isArray(queue) ? queue.slice(0, INTENT_QUEUE_CAP) : []
  if (!isPlainObject(intent) || !queueTakes(q, intent)) return q
  var out = []
  for (var i = 0; i < q.length; i++) {
    var p = q[i]
    if (!isPlainObject(p)) continue
    if (intent.verb === "setting") {
      if (p.verb === "setting" && p.id === intent.id) continue
    } else if (intent.verb === "reset-settings") {
      // The camera's reset supersedes the camera's writes only: a global
      // write (intent.scope) is not the camera's to reset.
      if (isSettingIntent(p) && !isGlobalIntent(p)) continue
    } else if (isSetupIntent(intent)) {
      // One setup write at a time (queueTakes); every other ask stays.
      if (isSetupIntent(p)) continue
    } else if (isMicIntent(intent)) {
      // The latest microphone on/off wins; every other ask stays.
      if (isMicIntent(p)) continue
    } else if (!isSettingIntent(p) && !isSetupIntent(p) && !isMicIntent(p)) {
      // An other ask replaces the other ask before it; a setup write and a
      // microphone on/off stay.
      continue
    }
    out.push(p)
  }
  if (intent.verb === "enable" || isMicIntent(intent)) {
    // An on/off ask of the camera or the microphone goes first.
    out.unshift(intent)
  } else if (isQuickIntent(intent)) {
    // A discrete ask (an effect, noise removal, a switch, a choice, a
    // button) goes ahead of the queued slider writes, but never ahead of a
    // reset (it came after it) and never past a write of its own id (that
    // one was replaced above, so none is queued). The sliders' coalesced
    // latest values stay queued and run after it.
    var pos = out.length
    for (var j = out.length - 1; j >= 0; j--) {
      if (out[j].verb === "reset-settings") break
      if (out[j].verb === "setting" && !isQuickIntent(out[j])) pos = j
    }
    out.splice(pos, 0, intent)
  } else {
    out.push(intent)
  }
  return out
}

// An ask that is a discrete user action, not a stream of values: an effect or
// noise removal, a switch, a choice or a button (the Daemon marks a setting
// write `quick` by its row's type). Such an ask does not wait behind
// queued slider writes (Model.enqueueIntent).
function isQuickIntent(intent) {
  return isPlainObject(intent)
    && intent.verb === "setting" && intent.quick === true
}

// A queued write of a global setting (made with its row's scope).
function isGlobalIntent(intent) {
  return isPlainObject(intent) && intent.verb === "setting" && intent.scope === "global"
}

// The queue without its camera setting and reset intents (a new array): what
// is left once the settings belong to another camera. A write of a global
// setting stays: it is the daemon's, whichever camera is active.
function dropSettingIntents(queue) {
  var q = Array.isArray(queue) ? queue.slice(0, INTENT_QUEUE_CAP) : []
  return q.filter(function(p) { return isPlainObject(p) && (!isSettingIntent(p) || isGlobalIntent(p)) })
}

// `map` (setting id -> anything) without the ids that are not global
// settings in any of `records`: what a camera change or a camera reset
// leaves of the drafts, what was sent and what is settling.
function keepGlobalSettings(map, records) {
  var out = {}
  var recs = Array.isArray(records) ? records : []
  var d = withSetting(map, "", undefined)
  for (var id in d) {
    for (var i = 0; i < recs.length; i++) {
      var row = findSetting(recs[i], id)
      if (row && row.scope === "global") { out[id] = d[id]; break }
    }
  }
  return out
}

// Whether an on/off toggle must wait: a command other than a camera setting
// write, a setup write or a microphone on/off is running or queued, so its
// result (and with it the target of the toggle) has not arrived. Setting
// writes never hold the switch, and the setup dialog's writes (a module, the
// order, a config key) are settings-type writes too: they do not either; the
// microphone's on/off is another device's (micBlocked holds its own switch).
function toggleBlocked(running, queue) {
  var holds = function(intent) { return isPlainObject(intent) && !isSettingIntent(intent) && !isSetupIntent(intent) && !isMicIntent(intent) }
  if (holds(running)) return true
  var q = Array.isArray(queue) ? queue : []
  for (var i = 0; i < q.length && i < INTENT_QUEUE_CAP; i++)
    if (holds(q[i])) return true
  return false
}

// Whether a queued intent writes setting `id`.
function queuedSetting(queue, id) {
  var q = Array.isArray(queue) ? queue : []
  for (var i = 0; i < q.length && i < INTENT_QUEUE_CAP; i++)
    if (isPlainObject(q[i]) && q[i].verb === "setting" && q[i].id === id) return true
  return false
}

// ---- drafts (the values the user moved to that the daemon has not confirmed)

// A copy of `map` (setting id -> value) with `id` set to `value` (undefined:
// removed). Only own keys that are ids of the grammar (never a reserved
// key, see RESERVED_KEYS), at most SETTINGS_ROW_CAP of them, are copied.
function withSetting(map, id, value) {
  var out = {}
  var n = 0
  if (isPlainObject(map)) {
    for (var k in map) {
      if (n >= SETTINGS_ROW_CAP) break
      if (settingId(k) === "" || !Object.prototype.hasOwnProperty.call(map, k) || map[k] === undefined) continue
      out[k] = map[k]
      n++
    }
  }
  if (settingId(id) === "") return out
  if (value === undefined) delete out[id]
  else out[id] = value
  return out
}

// The drafts still unconfirmed under `record`: a draft goes once the daemon
// reports that very value, or once its row is no longer offered or no
// longer enabled.
function settleDrafts(drafts, record) {
  var out = {}
  if (!isPlainObject(drafts) || !settingsSupported(record)) return out
  var d = withSetting(drafts, "", undefined)
  for (var id in d) {
    var row = findSetting(record, id)
    if (row && row.enabled && row.value !== d[id]) out[id] = d[id]
  }
  return out
}

// Which settings change belongs to which write. The daemon publishes one
// change (a settings_delta of a new rev) after each set or reset that
// changes something, in the order of the writes, but it can reach the watch
// after the next write has started. A command armed when `lines` changes
// have been read, while the changes of finished writes are due up to `due`,
// owns change number mark + 1 (mark = settingLineMark(lines, due)); an
// earlier write's late change never counts as its own.
function settingLineMark(lines, due) {
  var l = typeof lines === "number" && isFinite(lines) ? lines : 0
  var d = typeof due === "number" && isFinite(due) ? due : 0
  return Math.max(l, d)
}

// A setting write is over and its draft is still the value it wrote, with
// no newer write for that id queued: "drop" the draft now (it failed, or
// its own change has been read: the row shows what the camera took), or
// "settle" it on its own change, still to come.
function settingWriteEnd(ok, lines, mark) {
  if (ok !== true) return "drop"
  return typeof lines === "number" && typeof mark === "number" && lines > mark ? "drop" : "settle"
}

// A setting write whose value is already the one the daemon reports: it was
// in force before the write (or its change has been read), so the daemon
// publishes no change line for it and none is due. The write's command
// exiting 0 is what settles its draft, not a line. Only when the value is
// also stored (a write of the shown but unstored value does print a line,
// flipping `stored`), and only when no earlier write's line is still owed
// (`due` > `lines`): the record may then be stale. Without `lines` and `due`
// the owed-line check is skipped.
function settingNoop(record, intent, lines, due) {
  if (!isPlainObject(intent) || intent.verb !== "setting") return false
  if (typeof lines === "number" && typeof due === "number" && due > lines) return false
  var row = findSetting(record, intent.id)
  return !!row && row.type !== "action" && row.stored === true && row.value === intent.value
}

// After a change: `settling` maps an id to { value, line }, a write that
// ended well and the number of the change it owns. A draft still at that
// value goes once `lines` reaches that change, whatever the daemon
// reported; an entry whose draft has moved on (or gone) is dropped. Returns
// { drafts, settling }, new objects.
function settleWritten(drafts, settling, lines) {
  var d = withSetting(drafts, "", undefined)
  var s = withSetting(settling, "", undefined)
  var out = {}
  for (var id in s) {
    var entry = s[id]
    if (!isPlainObject(entry) || ownValue(d, id) === undefined || ownValue(d, id) !== entry.value) continue
    if (typeof lines === "number" && lines >= entry.line) delete d[id]
    else out[id] = entry
  }
  return { drafts: d, settling: out }
}

// ---------------------------------------------------------------- panel tabs

// The panel's three tabs, in order: the words are the stored `panelTab`
// setting's values (manifest schema `options`, same order), and the only
// ones ever written. The first is the default. A stored word of an older
// version ("status": the Status tab, now the header's Details view) reads
// as the default.
var PANEL_TABS = ["effect", "camera", "mic"]
var PANEL_TAB_DEFAULT = "effect"
var PANEL_TAB_LABELS = { effect: "Effects", camera: "Camera", mic: "Mic" }
var PANEL_TAB_DESCRIPTIONS = {
  effect: "Background effect and the video effects",
  camera: "Camera choice and camera settings",
  mic: "The Omarchy Broadcast Mic: its processing and input"
}

// The stored tab, read back: a word of PANEL_TABS exactly, else the default.
// Nothing is ever written back from here.
function panelTabValue(value) {
  return typeof value === "string" && PANEL_TABS.indexOf(value) >= 0 ? value : PANEL_TAB_DEFAULT
}

// The tab row: { value, label, description, selected, glyph, name },
// constants only. `health` (healthView): while the active camera's health
// has warnings, the Camera tab carries the caution sign (`glyph`) and says
// so in its accessible `name`, so it shows from another tab; the warnings
// themselves are only in the Camera tab. A closed privacy shutter
// (`health.shutterClosed`) raises the same sign and names itself in `name`;
// with both a warning and a closed shutter the name says both.
var PANEL_TAB_WARNING_NAME = "Camera, with a warning"
var PANEL_TAB_SHUTTER_NAME = "Camera, shutter closed"
var PANEL_TAB_SHUTTER_WARNING_NAME = "Camera, shutter closed, with a warning"
function panelTabOptions(tab, health) {
  var current = panelTabValue(tab)
  var warned = isPlainObject(health) && Array.isArray(health.warnings) && health.warnings.length > 0
  var shut = isPlainObject(health) && health.shutterClosed === true
  var out = []
  for (var i = 0; i < PANEL_TABS.length; i++) {
    var v = PANEL_TABS[i]
    var flag = (warned || shut) && v === "camera"
    out.push({ value: v, label: PANEL_TAB_LABELS[v], description: PANEL_TAB_DESCRIPTIONS[v], selected: v === current,
               glyph: flag ? GLYPH_WARNING : "", name: flag ? (shut ? (warned ? PANEL_TAB_SHUTTER_WARNING_NAME : PANEL_TAB_SHUTTER_NAME) : PANEL_TAB_WARNING_NAME) : PANEL_TAB_LABELS[v] })
  }
  return out
}

// ---------------------------------------------------------------- consumers

var PIPEWIRE_OFF = "off"

// The consumers split by kind, as one phrase: Apps (apps holding the
// virtual camera device), PipeWire links and Preview leases. Shown only while
// the PipeWire output is reported and not "off" (docs/cli-json.md: a client
// shows the split only then); "" otherwise, or while any part is unknown.
function consumersByKind(record) {
  if (!available(record) || record.pipewireOutput === "" || record.pipewireOutput === PIPEWIRE_OFF) return ""
  if (record.loopbackConsumers < 0 || record.pipewireConsumers < 0) return ""
  var parts = ["Apps " + record.loopbackConsumers, "PipeWire " + record.pipewireConsumers]
  if (record.previewConsumers >= 0) parts.push("Preview " + record.previewConsumers)
  return parts.join(" \u00b7 ")
}

// ---------------------------------------------------------------- details

// This plugin's version, for the Details view and its copy (a bug report).
// tests/check-source.py holds it equal to the manifest's `version`.
var PLUGIN_VERSION = "0.37.11"
var DETAILS_TITLE = "Details"
var DETAILS_COPY_LABEL = "Copy"
var DETAILS_COPIED_TEXT = "Copied"
var DETAILS_BACK_LABEL = "Back"

// The active camera's row of the list, or null.
function activeCameraRow(record) {
  var cams = record && Array.isArray(record.cameras) ? record.cameras : []
  for (var i = 0; i < cams.length; i++) if (isActiveCamera(record, cams[i])) return cams[i]
  return null
}

// The Details view, opened from the header's (i): { label, value } rows,
// every value a display copy: the state, the camera and its USB id
// (VID:PID), the output mode, the PipeWire output, the consumers by kind,
// the live figures while active, the microphone, the daemon's interface
// revision (it reports no version number) and this plugin's version. The
// daemon reports no firmware version, so none is shown. Nothing while the
// daemon is unavailable but the plugin's version.
function detailsRows(record) {
  var rows = []
  if (available(record)) {
    var camera = activeCameraLabel(record)
    var cam = activeCameraRow(record)
    rows.push({ label: "State", value: record.state })
    rows.push({ label: "Camera", value: camera !== "" ? camera : "none" })
    if (cam && cam.usb !== "") rows.push({ label: "USB id", value: cam.usb })
    rows.push({ label: "Output", value: record.outputMode !== "" ? record.outputMode : UNKNOWN })
    rows.push({ label: "PipeWire", value: record.pipewireOutput !== "" ? record.pipewireOutput : UNKNOWN })
    var split = consumersByKind(record)
    rows.push({ label: "Used by", value: split !== "" ? split : (record.consumers >= 0 ? consumersText(record.consumers) : UNKNOWN) })
    var stats = statsRows(record)
    for (var i = 0; i < stats.length; i++) rows.push(stats[i])
    var mic = micView(record)
    if (mic.visible) {
      rows.push({ label: "Microphone", value: mic.rows[0].value })
      if (mic.runsOn !== "") rows.push({ label: "Mic runs on", value: mic.runsOn.replace(/^Runs on: /, "") })
    }
    rows.push({ label: "Daemon API", value: record.interfaceRevision >= 0 ? "revision " + record.interfaceRevision : UNKNOWN })
  } else {
    rows.push({ label: "State", value: stateLabel(record) })
  }
  rows.push({ label: "Plugin", value: PLUGIN_VERSION })
  return rows
}

// The text the Details view's Copy puts on the clipboard: one "label: value"
// line each, under the product's name.
function detailsText(rows) {
  var list = Array.isArray(rows) ? rows : []
  var lines = [PRODUCT]
  for (var i = 0; i < list.length && i < 32; i++) lines.push(list[i].label + ": " + list[i].value)
  return lines.join("\n")
}

// ---------------------------------------------------------------- header

// The header's state line, in words (plain text, sentence case):
//   "Off", "Ready: starts when an app uses the camera", "Starting…",
//   "In use by 1 app, 30 fps", "Preview only, 30 fps", "Error",
//   "Connecting…", "Unavailable".
// The rate is the live figure's, while one is reported.
var HEADER_READY_TEXT = "Ready: starts when an app uses the camera"
function headerState(record) {
  if (!available(record)) return !record || record.link === "connecting" ? "Connecting…" : "Unavailable"
  switch (record.state) {
  case "off": return "Off"
  case "idle": return HEADER_READY_TEXT
  case "starting": return "Starting…"
  case "error": return "Error"
  case "active":
    var apps = otherConsumers(record)
    var text = apps > 0 ? (apps === 1 ? "In use by 1 app" : "In use by " + apps + " apps")
      : (record.previewConsumers > 0 ? "Preview only" : "In use")
    var fps = record.stats ? record.stats.fps : null
    if (typeof fps === "number" && isFinite(fps) && fps > 0 && fps <= STAT_MAX) text += ", " + Math.round(fps) + " fps"
    return text
  default: return record.state
  }
}

// The main switch's label (it turns the virtual camera on or off).
var MAIN_SWITCH_LABEL = "Virtual camera"

// ---------------------------------------------------------------- layout

// The panel's two layouts (decided here, drawn by BroadcastPanel and sized
// by BarWidget): wide, two columns (the live preview on the left with a
// short summary under it, the tabs on the right), while the user shows the
// preview where it can run and the widget's `narrowPanel` setting is off;
// else one column of PANEL_NARROW_WIDTH with the preview as a one-line
// strip, or its frame above the tabs (narrow, never on the Mic tab). The height is the
// content's, capped at PANEL_HEIGHT_CAP and by the screen: past it only the
// body (the tab's content) scrolls.
var PANEL_WIDE_WIDTH = 920
var PANEL_NARROW_WIDTH = 520
var PANEL_HEIGHT_CAP = 860

// The stored `narrowPanel` setting, read back: on only for a real true.
function narrowPanelValue(value) {
  return value === true
}

// Whether the preview draws its frame area (else a strip, or nothing): it
// shows a frame or starts one.
function previewFrameShown(placeholder) {
  return isPlainObject(placeholder) && (placeholder.mode === "box" || placeholder.mode === "image")
}

// { wide, width }: wide while not `narrow`, the preview is shown (the
// user's switch, `switchOn`) and it can run here (`controls`,
// previewControlsShown). Never from the preview's placeholder: a preview
// that fails shows its error in the wide frame area (previewStripView), and
// the layout stays put. Were it to follow the placeholder, a failure would
// make the layout narrow, so the narrow Mic tab would release the preview
// (previewHeld), which clears the failure, the layout would go wide again,
// the preview would be held and relaunched, and fail again: a loop.
function panelLayout(narrow, switchOn, controls) {
  var wide = narrow !== true && switchOn === true && controls === true
  return { wide: wide, width: wide ? PANEL_WIDE_WIDTH : PANEL_NARROW_WIDTH }
}

// The preview's place in the panel, exactly as drawn:
//   { mode, text, error, button }
// mode: "frame" (the 16:9 area, its controls in a row under it; in the wide
// layout also while the preview fails: `text` and `error` then say why,
// drawn inside the frame area, see panelLayout), "strip" (one
// line, `text` and `button`), or "none" (nothing: the daemon is unavailable,
// or the narrow layout's Mic tab). `button`: "show" (Show preview: the
// preview is off and can run), "hide" (it is on but failed: turn it off),
// or "". `controls`: the preview can run here (previewControlsShown).
var PREVIEW_SHOW_LABEL = "Show preview"
var PREVIEW_HIDE_LABEL = "Hide preview"
var PREVIEW_GRID_LABEL = "Grid"
var PREVIEW_GRID_TOOLTIP = "Rule-of-thirds grid over the preview"
var PREVIEW_RATE_LABEL = "Preview:"
var PREVIEW_RATE_NAME = "Preview refresh rate"
function previewStripView(placeholder, switchOn, controls, layout, tab) {
  var p = isPlainObject(placeholder) ? placeholder : { mode: "hidden", text: "", error: false }
  var out = { mode: "none", text: "", error: false, button: "" }
  if (p.mode === "hidden") return out
  var wide = isPlainObject(layout) && layout.wide === true
  if (!wide && panelTabValue(tab) === "mic") return out
  if (previewFrameShown(p)) { out.mode = "frame"; return out }
  if (wide) {
    out.mode = "frame"
    out.text = p.text
    out.error = p.error === true
    return out
  }
  out.mode = "strip"
  out.text = p.text
  out.error = p.error === true
  if (controls === true) out.button = switchOn === true ? "hide" : "show"
  return out
}

// Whether an open panel holds the preview (it runs only while one does):
// while it has a place to draw it, which the narrow layout's Mic tab does
// not (previewStripView); the wide layout's preview column stays on every
// tab. `layout` is panelLayout's, which never follows the placeholder, so a
// failure does not move the hold (and clear itself, see panelLayout). `tab` is the tab shown, read through panelTabValue.
function previewHeld(opened, layout, tab) {
  if (opened !== true) return false
  return (isPlainObject(layout) && layout.wide === true) || panelTabValue(tab) !== "mic"
}

// The wide layout's summary under the preview: { label, value } rows of
// the camera, the output format, the apps using it and the microphone.
function previewSummaryRows(record) {
  if (!available(record)) return []
  var camera = activeCameraLabel(record)
  var rows = [
    { label: "Camera", value: camera !== "" ? camera : "none" },
    { label: "Format", value: record.outputMode !== "" ? record.outputMode : UNKNOWN }
  ]
  var apps = otherConsumers(record)
  rows.push({ label: "Apps", value: apps < 0 ? UNKNOWN : (apps === 0 ? "None" : String(apps)) })
  if (micSupported(record)) rows.push({ label: "Mic", value: micStateLabel(record.mic) })
  return rows
}

// ---------------------------------------------------------------- microphone

// The Omarchy Broadcast Mic (interface revision 13, docs/cli-json.md): the
// snapshot's `mic` and the `mic` line give its state, the applications
// recording from it, the modules processing it, the delay they add and any
// error; its settings are global settings whose groups carry `surface`
// "mic" (the daemon's own input group, then one group per audio module
// stage), which the Mic tab draws generically, as the Effect tab draws the
// video effects'. Nothing here names an effect or a setting: labels,
// choices, why a row is greyed (studio voice already removing noise and
// echo, say) and what a row costs (its label) are the daemon's.
var MIC_REVISION = 13
var MIC_SURFACE = "mic"
var MIC_STATES = ["off", "passthrough", "starting", "active", "error"]
var MIC_STATE_LABELS = { off: "Off", passthrough: "On, not processed", starting: "Starting", active: "Processing", error: "Error" }
// The producer's bounds (crates/omarchy-broadcast/src/json.rs).
var MIC_PROVIDER_CAP = 256
// The daemon's own group of the microphone (its switch, its input device and
// the default-microphone actions): every other group is a module's.
var MIC_INPUT_GROUP = "input"
var DAEMON_NO_MIC = "The daemon needs updating for the microphone (omarchy-broadcastd 0.29 or newer)."
var CLI_NO_MIC = "The omarchy-broadcast CLI needs updating for the microphone."
var MIC_NO_MODULES_TEXT = "No microphone modules installed: the microphone passes the sound through unprocessed."
// The same while the microphone is off: nothing passes through then.
var MIC_NO_MODULES_OFF_TEXT = "No microphone modules installed"
var MIC_PRODUCT = "Omarchy Broadcast Mic"

// The `mic` of a snapshot, or a `mic` line -> { state, rawState, consumers,
// provider, latencyMs, error }, or null (not an object). An unknown state
// reads as "unknown" (a later revision's word), shown as the daemon sent it.
function micFields(m) {
  if (!isPlainObject(m)) return null
  return {
    state: MIC_STATES.indexOf(m.state) >= 0 ? m.state : "unknown",
    rawState: sanitize(m.state, MODE_CAP),
    consumers: count(m.consumers),
    provider: sanitize(m.provider, MIC_PROVIDER_CAP),
    latencyMs: statNumber(m.latency_ms),
    error: sanitize(m.error, ERROR_CAP)
  }
}

// Whether the microphone can be shown and driven: an available daemon at
// MIC_REVISION or later, through a CLI that reports it. An unknown revision
// counts as no.
function micSupported(record) {
  return available(record) && record.interfaceRevision >= MIC_REVISION && isPlainObject(record.mic)
}

// Why the Mic tab cannot show the microphone while the daemon is available:
// the daemon (below MIC_REVISION, or an unknown revision), or the CLI (a
// snapshot with no `mic` at all). "" otherwise.
function micMissingText(record) {
  if (!available(record) || micSupported(record)) return ""
  if (record.interfaceRevision >= MIC_REVISION && record.micField === "absent") return CLI_NO_MIC
  return DAEMON_NO_MIC
}

// The microphone host runs (its state is not `off`): what `mic on` started.
function micHostOn(record) {
  return micSupported(record) && record.mic.state !== "off"
}

// Whether the record already shows the microphone host as `on` says (true:
// not off, false: off): what the switch waits for after `mic on|off` ends.
function micReflects(record, on) {
  return micSupported(record) && (record.mic.state !== "off") === (on === true)
}

// How long the microphone's switch waits for the watch's `mic` line after
// its command ended, at most (ms).
var MIC_SWITCH_WAIT_MS = 3000

// "N apps recording", or UNKNOWN.
function micConsumersText(n) {
  if (typeof n !== "number" || n < 0) return UNKNOWN
  if (n === 0) return "None"
  return n === 1 ? "1 app" : n + " apps"
}

function micStateLabel(mic) {
  if (!isPlainObject(mic)) return UNKNOWN
  var known = ownValue(MIC_STATE_LABELS, mic.state)
  if (known !== undefined) return known
  return mic.rawState !== "" ? mic.rawState : UNKNOWN
}

// Whether the daemon's `provider` and `latency_ms` describe something in
// force: only while the microphone starts or processes. In the other states
// (passthrough, error) the sound is not processed and no module runs.
function micProcessing(mic) {
  return isPlainObject(mic) && (mic.state === "active" || mic.state === "starting")
}

// The delay the processing adds: "None" while nothing is processed (the
// daemon reports 0), else in milliseconds; UNKNOWN when not reported.
function micLatencyText(mic) {
  if (!isPlainObject(mic) || mic.latencyMs === null) return UNKNOWN
  if (mic.latencyMs === 0) return "None"
  return formatStat(mic.latencyMs, 1, " ms")
}

// The Mic tab's own part, above the settings, exactly as drawn:
//   { visible, hint, hostOn, stateLine, explainer, rows, runsOn, error }
// `visible`: the microphone is shown (else `hint` says why: an old daemon
// or CLI). `hostOn`: the switch of the microphone itself (`mic on|off`).
// While it is off the tab says only what the microphone is (`explainer`);
// while it is on, one line of its state (`stateLine`: "Processing, 1 app
// recording, adds 12 ms"). rows: { label, value } for the Details view;
// `runsOn` the modules processing it, as the daemon words it ("" unless the
// state is active or starting, as the added delay is "None" unless it is);
// `error` the daemon's.
var MIC_EXPLAINER_TEXT = "A microphone with noise and echo removed. Turn it on, then choose “Omarchy Broadcast Mic” in your apps."
function micStateLine(m) {
  var parts = [micStateLabel(m)]
  if (typeof m.consumers === "number" && m.consumers >= 0)
    parts.push(m.consumers === 0 ? "no app recording" : (m.consumers === 1 ? "1 app recording" : m.consumers + " apps recording"))
  if (micProcessing(m) && typeof m.latencyMs === "number" && m.latencyMs > 0 && m.latencyMs <= STAT_MAX)
    parts.push("adds " + Math.round(m.latencyMs) + " ms")
  return parts.join(", ")
}

function micView(record) {
  var out = { visible: false, hint: "", hostOn: false, stateLine: "", explainer: "", rows: [], runsOn: "", error: "" }
  if (!available(record)) return out
  if (!micSupported(record)) { out.hint = micMissingText(record); return out }
  var m = record.mic
  out.visible = true
  out.hostOn = m.state !== "off"
  out.stateLine = out.hostOn ? micStateLine(m) : ""
  out.explainer = out.hostOn ? "" : MIC_EXPLAINER_TEXT
  out.rows = [
    { label: "State", value: micStateLabel(m) },
    { label: "Consumers", value: out.hostOn ? micConsumersText(m.consumers) : "None" },
    { label: "Added delay", value: micProcessing(m) ? micLatencyText(m) : "None" }
  ]
  out.runsOn = micProcessing(m) && m.provider !== "" ? "Runs on: " + m.provider : ""
  out.error = m.error
  return out
}

// The Mic tab's settings: every group of surface MIC_SURFACE, all open (no
// accordion, no reset), laid out as effectSettingsView lays out the Effect
// tab's (dependents under their master, what cannot run here in the "Not
// available now" list). Nothing while the microphone is off: the tab then
// says only what it is (micView). `note` says that no audio module is
// installed when the daemon's own group is the only one; nothing while the
// set is still loading, or the microphone is not supported (micView says
// why).
function micSettingsView(record, drafts) {
  var out = emptySettingsView()
  out.collapsible = false
  if (!micSupported(record) || !settingsSupported(record) || !isPlainObject(record.settings)) return out
  if (!micHostOn(record)) return out
  var set = record.settings
  // The microphone's settings are global: no camera in the key, so another
  // camera never closes an open dropdown or lets go of a held slider (that
  // is all a key change does, see SettingsView's rowKey).
  out.setKey = JSON.stringify([MIC_SURFACE, set.serial])
  var placements = setPlacements(set)
  var stop = 0
  var modules = false
  var undrawn = 0
  for (var g = 0; g < set.groups.length && g < SETTINGS_SET_GROUP_CAP; g++) {
    var group = set.groups[g]
    if (group.surface !== MIC_SURFACE) continue
    if (group.id !== MIC_INPUT_GROUP) modules = true
    if (out.groups.length >= SETTINGS_GROUP_CAP) continue
    var laid = layoutGroup(group, placements, drafts, stop, false, null)
    stop = laid.stop
    out.unavailable = out.unavailable.concat(laid.unavailable)
    if (laid.rows.length === 0) { undrawn++; continue }
    out.groups.push({
      id: group.id, label: group.label, heading: laid.topLevel > 1, index: out.groups.length, expanded: true, glyph: "",
      rows: laid.rows, truncation: showingText(laid.looked, group.total, "settings"),
      live: ""
    })
  }
  markGroupBreaks(out.groups, false, false)
  out.rowCount = stop
  // "Showing N of M groups": M counts the groups the view could draw, not
  // one it never draws (no row to show).
  var groupsTotal = typeof set.micGroupsTotal === "number" ? Math.max(0, set.micGroupsTotal - undrawn) : 0
  out.truncation = showingText(out.groups.length, groupsTotal, "groups")
  out.note = modules ? "" : MIC_NO_MODULES_TEXT
  out.visible = out.groups.length > 0 || out.note !== "" || out.unavailable.length > 0
  return out
}

function micSettingsShown(view) {
  return isPlainObject(view) && Array.isArray(view.groups) && view.groups.length > 0
}

// The bar's microphone indicator: { visible, glyph, tooltip }. Shown while
// applications record from the Omarchy Broadcast Mic, whatever the camera
// does; nothing polls for it (the watch's `mic` lines move it).
function micInUse(record) {
  return micHostOn(record) && record.mic.consumers > 0
}

function micTooltipText(record) {
  if (!micSupported(record)) return ""
  var m = record.mic
  var parts = [MIC_PRODUCT + ": " + micStateLabel(m).toLowerCase()]
  if (m.state !== "off" && m.consumers >= 0) parts.push(m.consumers === 1 ? "1 app recording" : m.consumers + " apps recording")
  if (m.error !== "") parts.push("error: " + sanitize(m.error, 60))
  return sanitize(parts.join(" · "), TOOLTIP_CAP)
}

function micIndicator(record) {
  var on = micInUse(record)
  return { visible: on, glyph: GLYPH_MIC, tooltip: on ? micTooltipText(record) : "", urgent: on && record.mic.state === "error" }
}

// A click on the bar's microphone indicator: left opens the panel on the Mic
// tab ("open-mic": for this opening only, the stored tab is left as it is),
// or closes it when it is open ("close"); right opens the setup dialog
// ("setup"); the middle click is the camera icon's and does nothing here
// ("ignore").
function micClickAction(button, opened) {
  if (button === "right") return "setup"
  if (button === "middle") return "ignore"
  return opened === true ? "close" : "open-mic"
}

// `mic on` (enabled and started, again at every login) or `mic off` (the
// previous default microphone back, then stopped and disabled).
function micHostArgv(cli, on) {
  return cliUsable(cli) && typeof on === "boolean" ? [cli, "mic", on ? "on" : "off"] : null
}

function isMicIntent(intent) {
  return isPlainObject(intent) && intent.verb === "mic-host"
}

// Whether the microphone's switch must wait: its on/off is running or
// queued, so its result has not arrived.
function micBlocked(running, queue) {
  if (isMicIntent(running)) return true
  var q = Array.isArray(queue) ? queue : []
  for (var i = 0; i < q.length && i < INTENT_QUEUE_CAP; i++) if (isMicIntent(q[i])) return true
  return false
}

// ---------------------------------------------------------------- camera health

// The camera's health (interface revision 20): the snapshot's
// `camera_health` (null below it; absent from a CLI that predates it) and the
// watch's `camera_health` lines, each the whole value. What the daemon knows
// of the camera named by its active camera: the rate of good frames it really
// delivers and its capture mode's rate (-1: not measured), the damaged frames
// it dropped, warnings for people, effect suggestions and the changes "Use
// recommended settings" would make. Shown only for the active camera, in the
// Camera tab; nothing is written without a click (`settings set` for a
// suggestion, `recommended apply` for the recommended settings), and nothing
// shown is kept past the next line: the daemon's next value replaces it all.
var HEALTH_REVISION = 20
var HEALTH_WARNINGS_CAP = 8
var HEALTH_SUGGESTIONS_CAP = 8
var HEALTH_RECOMMENDED_CAP = 32
var HEALTH_REASON_CAP = DETAIL_CAP
var HEALTH_VALUE_CAP = 48
// The camera's status lines (revision 26): "Shutter closed" first, then
// "Show Mode: desk view" and the like.
var HEALTH_STATUS_REVISION = 26
var HEALTH_STATUS_CAP = 4
var HEALTH_STATUS_LINE_CAP = 96
var HEALTH_SHUTTERS = ["", "open", "closed"]
var HEALTH_SHOW_MODES = ["", "normal", "desk_view"]
// "Delivers ... of ... fps" shows below this share of the capture mode's rate.
var HEALTH_DELIVERS_SHARE = 0.95
var RECOMMENDED_TITLE = "RECOMMENDED FOR THIS CAMERA"
var RECOMMENDED_LABEL = "Use recommended settings"
var RECOMMENDED_TOOLTIP = "Set this camera's settings to the recommended values listed below"
// Folded, the health shows this many suggestions and the recommended
// changes as one line, so the settings' groups keep their room on a 1080
// screen; each opens on its line (healthView's `open`).
var HEALTH_SUGGESTIONS_FOLDED = 1
var HEALTH_FEWER_TEXT = "Fewer suggestions"

// A `camera_health` object -> { camera, deliveredFps, nominalFps,
// corruptFrames, warnings, suggestions, hasRecommendation, recommended }, or
// null (not an object). `camera` is the raw id (rawId), compared with the
// active camera, never shown; a figure not measured is null (-1 on the wire);
// `corruptFrames` is -1 when unknown. A suggestion is kept only with a setting
// id of the daemon's grammar and a value word (OPTION_VALUE_RE, or a decimal
// integer); a recommended change only with a setting id and a label. Every
// list is read to its cap only.
function healthFields(m) {
  if (!isPlainObject(m)) return null
  var warnings = []
  var src = Array.isArray(m.warnings) ? m.warnings : []
  for (var i = 0; i < src.length && i < HEALTH_WARNINGS_CAP; i++) {
    var w = sanitize(src[i], ERROR_CAP)
    if (w !== "") warnings.push(w)
  }
  var suggestions = []
  src = Array.isArray(m.suggestions) ? m.suggestions : []
  for (var j = 0; j < src.length && j < HEALTH_SUGGESTIONS_CAP; j++) {
    var s = src[j]
    if (!isPlainObject(s)) continue
    var sid = settingId(s.setting)
    var word = typeof s.value === "string" && (/^-?[0-9]{1,10}$/.test(s.value) || optionValueOf(s.value, "") !== "") ? s.value : ""
    if (sid === "" || word === "") continue
    suggestions.push({ setting: sid, value: word, reason: settingText(s.reason, HEALTH_REASON_CAP) })
  }
  var recommended = []
  src = Array.isArray(m.recommended) ? m.recommended : []
  for (var k = 0; k < src.length && k < HEALTH_RECOMMENDED_CAP; k++) {
    var c = src[k]
    if (!isPlainObject(c)) continue
    var cid = settingId(c.setting)
    var label = settingText(c.label, SETTING_LABEL_CAP)
    if (cid === "" || label === "") continue
    recommended.push({ setting: cid, label: label, value: settingText(c.value, HEALTH_VALUE_CAP),
                       current: settingText(c.current, HEALTH_VALUE_CAP) })
  }
  var status = []
  src = Array.isArray(m.status) ? m.status : []
  for (var q = 0; q < src.length && q < HEALTH_STATUS_CAP; q++) {
    var line = settingText(src[q], HEALTH_STATUS_LINE_CAP)
    if (line !== "") status.push(line)
  }
  return {
    camera: rawId(m.camera),
    shutter: typeof m.shutter === "string" && HEALTH_SHUTTERS.indexOf(m.shutter) >= 0 ? m.shutter : "",
    showMode: typeof m.show_mode === "string" && HEALTH_SHOW_MODES.indexOf(m.show_mode) >= 0 ? m.show_mode : "",
    status: status,
    deliveredFps: statNumber(m.delivered_fps),
    nominalFps: statNumber(m.nominal_fps),
    corruptFrames: count(m.corrupt_frames),
    warnings: warnings,
    suggestions: suggestions,
    hasRecommendation: m.has_recommendation === true,
    recommended: recommended
  }
}

// A rate as the panel writes it: at most one decimal, none when whole
// (19.5, 30).
function fpsText(value) {
  return String(Math.round(value * 10) / 10)
}

// "Delivers 19.5 of 30 fps" while the camera delivers less than
// HEALTH_DELIVERS_SHARE of its capture mode's rate, both measured; else "".
function deliversText(health) {
  if (!isPlainObject(health)) return ""
  var got = health.deliveredFps, nominal = health.nominalFps
  if (got === null || nominal === null || !(nominal > 0) || !(got < nominal * HEALTH_DELIVERS_SHARE)) return ""
  return "Delivers " + fpsText(got) + " of " + fpsText(nominal) + " fps"
}

// The health shown: the daemon's value while it is the active camera's (an
// available daemon, a camera named, the one in force); null otherwise.
function shownHealth(record) {
  if (!available(record) || !isPlainObject(record.health)) return null
  var h = record.health
  return h.camera !== "" && h.camera === record.activeCamera ? h : null
}

// True only while a session runs (state active or starting) on a daemon that
// reports the shutter (revision >= HEALTH_STATUS_REVISION) and the active
// camera's health says the privacy shutter is closed.
function shutterClosed(record) {
  if (!available(record) || record.interfaceRevision < HEALTH_STATUS_REVISION) return false
  if (record.state !== "active" && record.state !== "starting") return false
  var h = shownHealth(record)
  return h !== null && h.shutter === "closed"
}

// A suggestion's value as a value of its row: a switch "on"/"true" or
// "off"/"false", an option of the row, an integer on its grid; null when it
// is none of these.
function suggestionValue(row, word) {
  if (!row || typeof word !== "string") return null
  if (row.type === "bool") {
    if (word === "on" || word === "true") return true
    if (word === "off" || word === "false") return false
    return null
  }
  if (row.type === "int") return /^-?[0-9]{1,10}$/.test(word) ? snapSetting(row, Number(word)) : null
  return rowValue(row, word)
}

// The button of a suggestion: Turn on, Turn off, Use <option>, Set to <n>.
function suggestionAction(row, value) {
  if (row.type === "bool") return value === true ? "Turn on" : "Turn off"
  if (row.type === "enum") return "Use " + settingValueText(row, value)
  return "Set to " + settingValueText(row, value)
}

// The Camera tab's health part, exactly as drawn:
//   { visible, camera, delivers, warnings, suggestions, recommended,
//     shownSuggestions, more, changes }
// `delivers`: deliversText. `suggestions`: { setting, label, reason, action,
// value } for each suggestion the panel can act on now: its setting is a
// global row of the settings set, enabled, not at that value already, and
// the value is one of the row's; any other is not shown (it would offer a
// button that writes nothing). `recommended`: { setting, text } where text
// is "Label: current → value" (the daemon's display texts). `camera`: the
// raw id the recommended settings are for. Nothing at all unless the
// daemon's health is the active camera's (shownHealth).
// `open` is the panel's choice of the session: { camera, suggestions,
// changes }, each list open (true) or folded; it holds only for the camera
// it names, so another camera starts folded. Folded, `shownSuggestions`
// (the suggestions drawn, and walked by the cursor) is
// HEALTH_SUGGESTIONS_FOLDED. `more`: { visible, text, glyph }, the line that
// opens and folds the suggestions ("+2 more", "Fewer suggestions"), shown
// only while there are more than fold. `changes`: { open, text, glyph },
// the line that opens and folds the recommended changes ("2 changes:
// Sharpness, Anti-flicker"; "" while there are none).
function healthView(record, open) {
  var out = { visible: false, shutterClosed: shutterClosed(record), camera: "", delivers: "", status: [], warnings: [], suggestions: [], recommended: [], shownSuggestions: 0,
              more: { visible: false, text: "", glyph: "" }, changes: { open: false, text: "", glyph: "" } }
  var h = shownHealth(record)
  if (!h) return out
  out.camera = h.camera
  out.delivers = deliversText(h)
  if (record.interfaceRevision >= HEALTH_STATUS_REVISION) {
    for (var t = 0; t < h.status.length && t < HEALTH_STATUS_CAP; t++)
      out.status.push({ text: h.status[t], strong: t === 0 && h.shutter === "closed" })
  }
  out.warnings = h.warnings.slice(0, HEALTH_WARNINGS_CAP)
  var supported = settingsSupported(record)
  for (var i = 0; i < h.suggestions.length && i < HEALTH_SUGGESTIONS_CAP; i++) {
    var s = h.suggestions[i]
    var row = supported ? findSetting(record, s.setting) : null
    if (!row || row.scope !== "global" || !row.enabled) continue
    var v = suggestionValue(row, s.value)
    if (v === null || v === row.value) continue
    out.suggestions.push({ setting: row.id, label: row.label, reason: s.reason, action: suggestionAction(row, v), value: v })
  }
  for (var j = 0; j < h.recommended.length && j < HEALTH_RECOMMENDED_CAP; j++) {
    var c = h.recommended[j]
    out.recommended.push({ setting: c.setting, label: c.label, text: c.label + ": " + c.current + " → " + c.value })
  }
  var mine = isPlainObject(open) && open.camera === h.camera
  var listOpen = mine && open.suggestions === true
  var n = out.suggestions.length
  out.shownSuggestions = listOpen ? n : Math.min(n, HEALTH_SUGGESTIONS_FOLDED)
  if (n > HEALTH_SUGGESTIONS_FOLDED)
    out.more = { visible: true, text: listOpen ? HEALTH_FEWER_TEXT : "+" + (n - HEALTH_SUGGESTIONS_FOLDED) + " more",
                 glyph: listOpen ? GLYPH_EXPANDED : GLYPH_COLLAPSED }
  if (out.recommended.length > 0) {
    var changesOpen = mine && open.changes === true
    var count = out.recommended.length + (out.recommended.length === 1 ? " change: " : " changes: ")
    out.changes = { open: changesOpen, text: count + out.recommended.map(function(x) { return x.label }).join(", "),
                    glyph: changesOpen ? GLYPH_EXPANDED : GLYPH_COLLAPSED }
  }
  out.visible = out.delivers !== "" || out.status.length > 0 || out.warnings.length > 0 || out.suggestions.length > 0
  return out
}

// The panel's `open` after a click on the suggestions' ("suggestions") or
// the changes' ("changes") line: that list flipped, for the camera shown;
// the other kept only while it is the same camera's.
function healthOpenAfter(open, view, which) {
  var camera = isPlainObject(view) ? view.camera : ""
  var mine = isPlainObject(open) && open.camera === camera
  var next = { camera: camera, suggestions: mine && open.suggestions === true, changes: mine && open.changes === true }
  if (which === "suggestions") next.suggestions = !next.suggestions
  else if (which === "changes") next.changes = !next.changes
  return next
}

// Whether "Use recommended settings" is offered: the active camera's health
// lists changes.
function recommendedShown(view) {
  return isPlainObject(view) && Array.isArray(view.recommended) && view.recommended.length > 0
}

// `recommended apply` for the camera the panel showed the changes of
// (`intent.camera`): only while that is still the active camera and the
// daemon still lists changes for it. The CLI applies them to the active
// camera (it names none), so the check is made when the intent runs.
function recommendedArgv(cli, record, intent) {
  if (!cliUsable(cli) || !isPlainObject(intent) || typeof intent.camera !== "string" || intent.camera === "") return null
  var h = shownHealth(record)
  if (!h || h.camera !== intent.camera || h.recommended.length === 0) return null
  return [cli, "recommended", "apply"]
}

// ---------------------------------------------------------------- keyboard cursor

// The panel's keyboard stops, top to bottom, as the panel lays them out
// (`p`, what the panel draws):
//   the header's on/off switch, its (i) (the Details view), then while
//   `p.details` only the view's Back and Copy;
//   the preview's (`p.preview`, previewStripView): the strip's button (one
//   stop, "preview") while it has one, or the row under the frame, while the preview
//   can run (`p.previewControls`), Hide ("preview"), the grid and the
//   refresh rate (one stop for its choices);
//   the tab row (one stop; Left/Right change the tab): after the preview's
//   stops in the wide layout (`p.wide`, the preview column on the left),
//   before them in the narrow one (the preview drawn under the tab row);
//   then only the stops of the tab shown (`p.tab`, read through
//   panelTabValue):
//   effect  the background effect's choices (one stop for the row;
//           Left/Right walk its choices, as in the shell's button groups)
//           while drawn (effectModeView), the Background row while
//           `p.backgroundRow` (backgroundRowDrawn: one stop; Left/Right walk
//           Gallery... and Add...), the rows of `p.effectSettings`
//           (effectSettingsView, drawn generically: the choice's dependents
//           first; no group heading is a stop), the "Not available now"
//           line and its Setup buttons (`p.notAvailable`, notAvailableView),
//           then "More" while it holds anything, and while `p.moreOpen` the
//           Battery saver switch and its Mode dropdown (one stop each; Enter
//           opens the list, Left/Right do nothing) while `p.batterySaver`
//           (batterySaverView) is visible, and the Away image button;
//   camera  the camera dropdown while there is a camera (`p.cameraCount`),
//           each suggestion's button drawn (`p.health.shownSuggestions`),
//           the line that opens or folds the rest, Use recommended settings
//           and the line that opens or folds its changes, while `p.health`
//           (healthView) offers them, then from `p.settings` (the
//           settingsView the panel draws, so collapsed groups and capped
//           rows are no stops) each group header (index: its place in the
//           view) and the rows of an open group (index: the row's `stop`),
//           the "Not available now" line and its Setup buttons, and Reset
//           to defaults at the bottom;
//   mic     the microphone's switch (while micView shows it), then the rows
//           of `p.micSettings` (micSettingsView, drawn generically) and the
//           "Not available now" line and its Setup buttons.
// A stop that stands for one of several rows (a setting, a group header, a
// Setup button) carries the row's `id` too (cursorAfter anchors on it).
// While the daemon is unavailable the only stop is "start" (a stopped daemon).
function cursorStops(record, p) {
  // The one control drawn while the daemon is down: the Start button.
  if (!available(record)) return unavailableMessage(record).startable ? [{ kind: "start", index: -1 }] : []
  var q = isPlainObject(p) ? p : {}
  var stops = [{ kind: "switch", index: -1 }, { kind: "info", index: -1 }]
  if (q.details === true) {
    stops.push({ kind: "details-back", index: -1 })
    stops.push({ kind: "details-copy", index: -1 })
    return stops
  }
  var preview = isPlainObject(q.preview) ? q.preview : { mode: "none", button: "" }
  var previewStops = []
  if (preview.mode === "strip" && preview.button !== "") previewStops.push({ kind: "preview", index: -1 })
  else if (preview.mode === "frame" && q.previewControls === true) {
    previewStops.push({ kind: "preview", index: -1 })
    previewStops.push({ kind: "grid", index: -1 })
    previewStops.push({ kind: "fps", index: -1 })
  }
  // Wide: the preview column first; narrow: the preview is drawn under the
  // tab row (so the tabs never move between tabs), and walked after it.
  if (q.wide === true) stops = stops.concat(previewStops, [{ kind: "tabs", index: -1 }])
  else stops = stops.concat([{ kind: "tabs", index: -1 }], previewStops)
  var rowsOf = function(view) {
    var out = []
    var groups = isPlainObject(view) && Array.isArray(view.groups) ? view.groups : []
    for (var g = 0; g < groups.length && g < SETTINGS_GROUP_CAP; g++) {
      var rows = Array.isArray(groups[g].rows) ? groups[g].rows : []
      for (var r = 0; r < rows.length && r < SETTINGS_PER_GROUP_CAP; r++) out.push({ kind: "setting", index: rows[r].stop, id: rows[r].id })
    }
    return out
  }
  var shown = panelTabValue(q.tab)
  if (shown === "effect") {
    if (effectModeShown(record)) stops.push({ kind: "effect", index: -1 })
    if (q.backgroundRow === true) stops.push({ kind: "background", index: -1 })
    stops = stops.concat(rowsOf(q.effectSettings), notAvailableStops(q.notAvailable))
    var battery = isPlainObject(q.batterySaver) && q.batterySaver.visible === true
    var away = placeholderSupported(record)
    if (battery || away) {
      stops.push({ kind: "more", index: -1 })
      if (q.moreOpen === true) {
        if (battery) {
          stops.push({ kind: "battery", index: -1 })
          stops.push({ kind: "battery-mode", index: -1 })
        }
        if (away) stops.push({ kind: "away", index: -1 })
      }
    }
  } else if (shown === "mic") {
    if (micSupported(record)) stops.push({ kind: "mic-host", index: -1 })
    stops = stops.concat(rowsOf(q.micSettings), notAvailableStops(q.notAvailable))
  } else if (shown === "camera") {
    if ((Number(q.cameraCount) || 0) > 0) stops.push({ kind: "camera", index: -1 })
    var health = q.health
    var hints = isPlainObject(health) && Array.isArray(health.suggestions) ? health.suggestions : []
    var drawn = isPlainObject(health) ? Math.min(Number(health.shownSuggestions) || 0, hints.length) : 0
    for (var sg = 0; sg < drawn && sg < HEALTH_SUGGESTIONS_CAP; sg++) stops.push({ kind: "suggestion", index: sg })
    if (drawn > 0 && isPlainObject(health.more) && health.more.visible === true) stops.push({ kind: "suggestions-more", index: -1 })
    if (recommendedShown(health)) {
      stops.push({ kind: "recommended", index: -1 })
      stops.push({ kind: "recommended-changes", index: -1 })
    }
    var settings = q.settings
    var groups = isPlainObject(settings) && Array.isArray(settings.groups) ? settings.groups : []
    for (var g = 0; g < groups.length && g < SETTINGS_GROUP_CAP; g++) {
      stops.push({ kind: "group", index: g, id: String(groups[g].id || "") })
      var rows = Array.isArray(groups[g].rows) ? groups[g].rows : []
      for (var r = 0; r < rows.length && r < SETTINGS_PER_GROUP_CAP; r++) stops.push({ kind: "setting", index: rows[r].stop, id: rows[r].id })
    }
    stops = stops.concat(notAvailableStops(q.notAvailable))
    if (isPlainObject(settings) && settings.reset === true) stops.push({ kind: "reset", index: -1 })
  }
  return stops
}

function clampCursor(index, length) {
  if (!(length > 0)) return 0
  var i = Math.floor(Number(index) || 0)
  return Math.max(0, Math.min(length - 1, i))
}

// Rows that are one stop each (group headers, settings, suggestions, Setup
// buttons of the "Not available now" list) are told apart by index.
function stopHasIndex(kind) {
  return kind === "group" || kind === "setting" || kind === "suggestion" || kind === "unavailable-setup"
}

function stopIndex(stops, kind, index) {
  for (var i = 0; i < stops.length; i++)
    if (stops[i].kind === kind && (!stopHasIndex(kind) || stops[i].index === index)) return i
  return -1
}

// The cursor's index once the stops change from `before` to `after` (a row
// revealed or hidden above it, a group opened, a daemon delta): the same
// stop where it still is, by kind and, for a row, by its id (a stop without
// one, a suggestion, by its index); else the old index, kept in range.
function cursorAfter(before, index, after) {
  var next = Array.isArray(after) ? after : []
  if (next.length === 0) return 0
  var prev = Array.isArray(before) && before.length > 0 ? before[clampCursor(index, before.length)] : null
  if (isPlainObject(prev) && typeof prev.kind === "string") {
    var keyed = stopHasIndex(prev.kind)
    var id = typeof prev.id === "string" && prev.id !== "" ? prev.id : ""
    for (var i = 0; i < next.length; i++) {
      var s = next[i]
      if (!isPlainObject(s) || s.kind !== prev.kind) continue
      if (!keyed || (id !== "" ? s.id === id : s.index === prev.index)) return i
    }
  }
  return clampCursor(index, next.length)
}

// ---------------------------------------------------------------- CLI path

// Settings value -> plan. `setting`: use that path, which must be absolute (a
// leading "~/" is the home directory). A bare name or a relative path is
// refused, never looked up: the setting names a binary, and running "rm off"
// from the shell's working directory is what a typo would otherwise do.
// `search`: run the resolver. `invalid`: not a usable value; nothing runs.
function cliPlan(setting, home) {
  if (setting === undefined || setting === null) return { mode: "search" }
  if (typeof setting !== "string") return { mode: "invalid", reason: "the cliPath setting is not text" }
  var s = setting.trim()
  if (s === "") return { mode: "search" }
  if (s.length > PATH_CAP || hasControl(s))
    return { mode: "invalid", reason: "the cliPath setting is not a usable path" }
  if (s.indexOf("~/") === 0) {
    if (typeof home !== "string" || home.charAt(0) !== "/") return { mode: "invalid", reason: "HOME is not set" }
    s = home.replace(/\/+$/, "") + s.slice(1)
  }
  if (s.charAt(0) !== "/" || s.length < 2) return { mode: "invalid", reason: "cliPath must be an absolute path" }
  return { mode: "setting", path: s }
}

// The resolver: `omarchy-broadcast` on PATH. A cliPath setting never comes
// here (Model.cliPlan). A path holding a newline is never printed (it would
// read as two answers).
var RESOLVER_SCRIPT = ""
  + "nl='\n'; "
  + "p=$(command -v omarchy-broadcast 2>/dev/null) && case $p in *\"$nl\"*) ;; /*) printf '%s\\n' \"$p\"; exit 0;; esac; "
  + "exit 1"

// Always an argv.
function resolverArgv() {
  return ["sh", "-c", RESOLVER_SCRIPT, "omarchy-broadcast-resolve"]
}

// What the resolver searched, for the panel when it found nothing.
function resolverMissText() {
  return "omarchy-broadcast is not on PATH"
}

// One stdout line of the resolver -> an absolute path, or "".
function parseResolverLine(line) {
  if (typeof line !== "string") return ""
  var s = line.trim()
  if (s === "" || s.length > PATH_CAP || s.charAt(0) !== "/") return ""
  if (hasControl(s)) return ""
  return s
}

// The resolver's answer: exactly one line, an absolute path. Anything else
// (no line, two lines) is no answer.
function resolverAnswer(firstLine, lineCount) {
  return lineCount === 1 ? parseResolverLine(firstLine) : ""
}

// A widget setting as given (cliPlan type-checks it); absent -> null.
function settingValue(settings, key) {
  if (settings === null || typeof settings !== "object") return null
  var value = settings[key]
  return value === undefined ? null : value
}

// ---------------------------------------------------------------- setup dialog

// The setup dialog (SetupDialog.qml, the plugin's overlay): the effect
// modules, the order their stages run in, the backend profile and pins, the
// daemon's configuration and a read-only diagnosis. Its data comes from four
// one-shot reads (docs/cli-json.md): `modules list --json`, `order show
// --json` (interface revision MODULES_REVISION), `config show --json` and
// `config files --json` (CONFIG_REVISION), run by the Daemon singleton when
// the dialog opens and again whenever the watch reports a change
// (`config_changed`, `modules_changed`, a new snapshot) or a write of the
// dialog has run. As everywhere else the daemon is the only authority: which
// keys can be written, which file overrides one, which stage moves are
// valid (the order line's `up`/`down`) all arrive with the data; the plugin
// draws them, and a write is re-read, never assumed.

// The interface revision of the configuration schema and its writes
// (GetConfigSchema, SetConfig; obc-ipc INTERFACE_REVISION 10) and the
// schema version of the config rows this plugin reads.
var CONFIG_REVISION = 10
var CONFIG_SCHEMA = 1
// The sections, in the order of the list on the left (keys 1 to 6). The
// Backgrounds one is listed only from MEDIA_REVISION (setupSections).
var SETUP_SECTIONS = ["modules", "order", "backends", "daemon", "backgrounds", "diagnostics"]
var SETUP_SECTION_LABELS = {
  modules: "Modules", order: "Order", backends: "Backends", daemon: "Daemon", backgrounds: "Backgrounds", diagnostics: "Diagnostics"
}
var SETUP_SECTION_DESCRIPTIONS = {
  modules: "The effect modules and whether each one is enabled",
  order: "The order the effect stages run in",
  backends: "The backend profile and the module that provides each stage",
  daemon: "The daemon's configuration",
  backgrounds: "The background images of the gallery: the bundled ones and your own",
  diagnostics: "Interface revision, errors, configuration files and module problems"
}
// The reads behind the sections, in the order they run.
var SETUP_READS = ["modules", "order", "config", "files", "media"]
var SETUP_TITLE = "Omarchy Broadcast setup"
var SETUP_OLD_DAEMON = "The daemon needs updating for the setup dialog (omarchy-broadcastd 0.24 or newer)."
var SETUP_OLD_CONFIG = "The daemon needs updating to show its configuration here (omarchy-broadcastd 0.25 or newer)."
var SETUP_OLD_PLUGIN = "Update the plugin to show the daemon's configuration."
var SETUP_LOADING = "Loading…"
var SETUP_SAVING = "Saving…"
// Where the daemon looks by default (modules.dirs; docs/modules.md).
var MODULES_EMPTY_TEXT = "No effect modules installed. Install omarchy-broadcast-onnx-git from the AUR, or the omarchy-broadcast-maxine-*-git modules for NVIDIA GPUs. A module's manifest goes in ~/.local/share/omarchy-broadcast/modules.d (your own) or /usr/lib/omarchy-broadcast/modules.d (packaged)."
var ORDER_EMPTY_TEXT = "No effect stages to order"
var BACKENDS_EMPTY_TEXT = "No backend settings: no module offers a stage."
var OVERRIDDEN_PREFIX = "Overridden by "
var ORDER_RESET_LABEL = "Reset order"
var ORDER_TRUNCATED_TEXT = "The daemon reports more stages than are shown; change the order with omarchy-broadcast order set."
var APPLY_TEXTS = { reload: "Applies at next camera start", restart: "Needs a daemon restart" }
var FILE_STATUS_TEXTS = { loaded: "Loaded", absent: "Not present", error: "Error" }
var MANAGED_FILE_TEXT = "Written by this dialog and the CLI"
// Shown in Diagnostics to copy, never run.
var DIAGNOSTIC_COMMANDS = ["omarchy-broadcast modules", "journalctl --user -u omarchy-broadcastd"]

// Caps. The producer's: a module list of at most MODULE_LINES_CAP lines
// (the header counts the rest), 32 stages a module and in an order, 16 config
// files; this plugin draws at most these.
var MODULE_LINES_CAP = 64
var SETUP_MODULE_CAP = 32
var MODULE_STAGE_CAP = 32
var ORDER_CAP = 32
var CONFIG_LINES_CAP = 64
var CONFIG_GROUP_CAP = 16
var CONFIG_GROUP_ROW_CAP = 48
var CONFIG_ROW_CAP = 128
var CONFIG_OPTION_CAP = 16
// A config option label is bounded like any config label (docs/cli-json.md).
var CONFIG_OPTION_LABEL_CAP = 48
var CONFIG_FILES_CAP = 16
var CONFIG_LIST_CAP = 16
// Lines of one read ever looked at: the longest is a module list.
var READ_LINES_CAP = MODULE_LINES_CAP + 2
// Display bounds (the producer's, docs/cli-json.md).
var MODULE_ID_CAP = 64
var MODULE_VERSION_CAP = 32
var MODULE_REASON_CAP = 96
var CONFIG_KEY_CAP = 128
var CONFIG_DESCRIPTION_CAP = 160
var CONFIG_VALUE_CAP = 160
var CONFIG_REASON_CAP = 160
var CONFIG_NOTICE_CAP = 160
var CONFIG_FILE_CAP = 96
var CONFIG_DIR_CAP = 256
// The payload a summon carries: a view and a config key only.
var SETUP_PAYLOAD_CAP = 1024

// The grammars (docs/modules.md, "Reserved names"; a config key is a dotted
// path whose last parts may be a module id).
var MODULE_ID_RE = /^[a-z0-9]+(\.[a-z0-9-]+)+$/
var STAGE_ID_RE = /^[a-z][a-z0-9-]{0,31}$/
// Any number of parts (bounded by CONFIG_KEY_CAP): a module id has as many
// as the daemon's valid_module_id allows within its 64 bytes.
var CONFIG_KEY_RE = /^[a-z][a-z0-9_]*(\.[a-z0-9_-]+)+$/
// An option value of a config enum: a word, a module id, an output mode
// (output.mode: 1920x1080@60), or "" (Automatic).
var CONFIG_OPTION_RE = /^([a-z0-9][a-z0-9_.@/-]{0,63})?$/
// The words a config value is written as: a decimal number, true or false,
// an option value ("" included). Each is one argv element after `--`.
var CONFIG_WORD_RE = /^(-?[0-9]{1,16}(\.[0-9]{1,6})?|true|false|[a-z0-9][a-z0-9_.@/-]{0,63}|)$/
var CONFIG_TYPES = ["bool", "int", "float", "enum", "string", "path", "list"]
var CONFIG_APPLY = ["live", "reload", "restart"]
var MODULE_STATUSES = ["available", "unavailable", "disabled"]
// A module's kind (docs/modules.md; `kind` of a module line from interface
// revision 13) as the Modules section names it; another kind is shown as
// the daemon words it, and a daemon that gives none shows no kind.
var MODULE_KIND_LABELS = { "video-stage": "Camera effect", "audio-filter": "Microphone effect", "analyser": "Analyser" }
// The mark on a module whose declared conflicts are not enforced (the config
// key `modules.forced.<id>`; a debug override), shown in its own urgent line.
var MODULE_FORCED_TEXT = "Forced: conflicts are not enforced (debug override)"
var FILE_STATUSES = ["loaded", "absent", "error"]

// ---- payload and the panel it forwards to

// The overlay's open() payload -> { view, focus }: "setup" only for an
// object whose `view` is "setup" (the right click's); anything else, the
// empty payload of the panel hotkey and the shell's "{}" included, is the
// bar panel ("panel"). `focus` is the key of the config row the dialog opens
// at (the panel's Away image row), a key of the grammar, else "".
//
// The payload never carries a program to run. Any process of the user can
// summon the overlay with a payload of its own choosing, so a path read from
// it would let that process pick the executable the shell starts; a `cliPath`
// key (or any other key but the two above) is ignored. A dialog that has to
// find the CLI itself (no widget attached) uses the resolver, as a widget
// without a cliPath setting does.
function setupPayload(json) {
  var p = null
  if (typeof json === "string" && json !== "" && json.length <= SETUP_PAYLOAD_CAP) {
    try { p = JSON.parse(json) } catch (e) { p = null }
  }
  if (!isPlainObject(p) || p.view !== "setup") return { view: "panel", focus: "" }
  return { view: "setup", focus: configKeyOf(p.focus) }
}

// The right click's payload: the view, and the config row to open at when
// one is asked for (a key of the grammar). It names no executable; see
// setupPayload.
function setupPayloadJson(focus) {
  var p = { view: "setup" }
  if (configKeyOf(focus) !== "") p.focus = focus
  return JSON.stringify(p)
}

// The section that draws config key `key`: Backends for its profile and
// pins, else Daemon.
function configKeySection(key) {
  return backendKey(typeof key === "string" ? key : "") ? "backends" : "daemon"
}

// Which bar widget's panel a forwarded hotkey opens: `candidates` are
// { screenName, visible }, one per widget (one per monitor). As the shell's
// own bar does for its panels (BarModel.pickPanelSlot): the copies on the
// focused screen when there are any, else all of them; among those, the
// first drawn one, else the first. -1 for none.
function pickPanelOwner(candidates, focusedScreen) {
  var rows = Array.isArray(candidates) ? candidates : []
  var pool = []
  for (var i = 0; i < rows.length; i++) if (isPlainObject(rows[i])) pool.push(i)
  var focused = typeof focusedScreen === "string" ? focusedScreen : ""
  if (focused !== "") {
    var onFocused = pool.filter(function(at) { return rows[at].screenName === focused })
    if (onFocused.length > 0) pool = onFocused
  }
  for (var k = 0; k < pool.length; k++) if (rows[pool[k]].visible === true) return pool[k]
  return pool.length > 0 ? pool[0] : -1
}

// ---- field readers

function moduleIdOf(value) {
  return typeof value === "string" && value.length <= MODULE_ID_CAP && MODULE_ID_RE.test(value) ? value : ""
}

function stageIdOf(value) {
  return typeof value === "string" && STAGE_ID_RE.test(value) && !reservedKey(value) ? value : ""
}

function configKeyOf(value) {
  return typeof value === "string" && value.length <= CONFIG_KEY_CAP && CONFIG_KEY_RE.test(value) && !reservedKey(value) ? value : ""
}

// A file name relative to the config dir (`source`, `overridden_by`, a
// config file's path), for the screen.
function fileText(value) {
  return sanitize(value, CONFIG_FILE_CAP)
}

// An integer the JavaScript number holds exactly, else null.
function configInt(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
    && Math.abs(value) <= 9007199254740991 ? value : null
}

// A finite number within +-1e15 (so toFixed never gives an exponent), else null.
function configFloat(value) {
  return typeof value === "number" && isFinite(value) && Math.abs(value) < 1e15 ? value : null
}

// The decimals a step needs (0.05 -> 2), at most 6.
function stepDecimals(step) {
  for (var d = 0; d < 6; d++) {
    var scaled = step * Math.pow(10, d)
    if (Math.abs(scaled - Math.round(scaled)) < 1e-9) return d
  }
  return 6
}

// ---- reading a command's lines

// A read's raw stdout lines -> { messages, error }: the v1 objects, at most
// READ_LINES_CAP lines looked at (an over-cap line is dropped by parseLine),
// and the text of an `error` line (the last one) or of a newer schema.
function setupMessages(lines) {
  var src = Array.isArray(lines) ? lines : []
  var out = []
  var error = ""
  for (var i = 0; i < src.length && i < READ_LINES_CAP; i++) {
    var p = parseLine(src[i])
    if (p.kind === "unsupported")
      return { messages: [], error: "omarchy-broadcast prints output schema v" + p.version + "; this plugin reads v" + SCHEMA_VERSION + ". Update the plugin." }
    if (p.kind !== "message") continue
    if (p.message.type === "error") error = setupErrorText(p.message)
    else out.push(p.message)
  }
  return { messages: out, error: error }
}

// An `error` line of a read, for the screen.
function setupErrorText(m) {
  if (m.code === "daemon-not-running") return "omarchy-broadcastd is not running"
  var text = sanitize(m.error, DETAIL_CAP)
  if (m.code === "unsupported-daemon") return text !== "" ? text : SETUP_OLD_DAEMON
  return text !== "" ? text : "The daemon could not be read"
}

function readFailed(text) {
  return { ok: false, error: text }
}

// The text a read that gave nothing usable fails with: its error line, else
// what its exit status says (commandFailureText), else `fallback`.
function readFailure(got, code, stderrText, fallback) {
  if (got.error !== "") return readFailed(got.error)
  if (typeof code === "number" && code !== 0) return readFailed(commandFailureText(code, stderrText, ""))
  return readFailed(fallback)
}

// ---- modules list

// A stage object of a `module` line -> { id, slot, device, rank, available,
// reason, selected }, or null.
function moduleStageEntry(o) {
  if (!isPlainObject(o)) return null
  var id = stageIdOf(o.id)
  if (id === "") return null
  return {
    id: id, slot: sanitize(o.slot, STAGE_WORD_CAP), device: sanitize(o.device, STAGE_WORD_CAP),
    rank: configInt(o.rank) !== null ? o.rank : 0, available: o.available === true,
    reason: o.available === true ? "" : settingText(o.reason, MODULE_REASON_CAP), selected: o.selected === true
  }
}

// The `module` object -> a row, or null (no id of the grammar). An unknown
// status reads as "unavailable".
function moduleEntry(o) {
  if (!isPlainObject(o)) return null
  var id = moduleIdOf(o.id)
  if (id === "") return null
  var name = settingText(o.name, NAME_CAP)
  var status = MODULE_STATUSES.indexOf(o.status) >= 0 ? o.status : "unavailable"
  var src = Array.isArray(o.stages) ? o.stages : []
  var stages = []
  for (var i = 0; i < src.length && i < MODULE_STAGE_CAP; i++) {
    var st = moduleStageEntry(src[i])
    if (st) stages.push(st)
  }
  return {
    id: id, name: name !== "" ? name : id, version: settingText(o.version, MODULE_VERSION_CAP),
    kind: sanitize(o.kind, STAGE_WORD_CAP), enabled: o.enabled === true, status: status, forced: o.forced === true,
    reason: status === "available" ? "" : settingText(o.reason, MODULE_REASON_CAP),
    overriddenBy: fileText(o.overridden_by), stages: stages,
    stagesTruncated: o.stages_truncated === true || src.length > MODULE_STAGE_CAP
  }
}

// `modules list --json` -> { ok, serial, profile, profileOverriddenBy,
// modules, total } or { ok: false, error }. The `modules` header counts the
// `module` lines; the list is used only when every one of them arrived (each
// index once), as a set of settings lines is.
function readModules(lines, code, stderrText) {
  var got = setupMessages(lines)
  var head = null
  var byIndex = []
  var received = 0
  for (var i = 0; i < got.messages.length; i++) {
    var m = got.messages[i]
    if (m.type === "modules" && head === null) {
      var count = lineIndex(m.count, 0, MODULE_LINES_CAP + 1)
      if (count < 0) continue
      head = { serial: settingsNumber(m.serial), count: count, profile: sanitize(m.profile, STAGE_WORD_CAP),
               profileOverriddenBy: fileText(m.profile_overridden_by) }
      for (var n = 0; n < count; n++) byIndex.push(null)
    }
  }
  if (head === null) return readFailure(got, code, stderrText, "omarchy-broadcast printed no module list")
  for (var j = 0; j < got.messages.length; j++) {
    var l = got.messages[j]
    if (l.type !== "module" || lineIndex(l.count, 0, MODULE_LINES_CAP + 1) !== head.count) continue
    var index = lineIndex(l.index, 0, head.count)
    if (index < 0 || byIndex[index] !== null) continue
    byIndex[index] = { entry: moduleEntry(l.module) }
    received++
  }
  if (received < head.count) return readFailed("The module list arrived incomplete")
  var modules = []
  var seen = Object.create(null)
  for (var k = 0; k < byIndex.length; k++) {
    var e = byIndex[k].entry
    if (!e || seen[e.id] === true) continue
    seen[e.id] = true
    modules.push(e)
  }
  return { ok: true, serial: head.serial, profile: head.profile, profileOverriddenBy: head.profileOverriddenBy,
           modules: modules.slice(0, SETUP_MODULE_CAP), total: modules.length }
}

// ---- stage order

// `order show --json` -> { ok, order, stages, overriddenBy, truncated } or
// { ok: false, error }. `stages` follows `order` (the stage ids of the
// grammar, each once, at most ORDER_CAP): { id, slot, up, down }, where
// up/down are the daemon's word that the swap with the previous / next
// stage would be accepted (false when the line does not say: a daemon below
// CONFIG_REVISION, or a stage it does not describe). A truncated order can
// not be written back whole, so nothing in it moves.
function readOrder(lines, code, stderrText) {
  var got = setupMessages(lines)
  var m = null
  for (var i = 0; i < got.messages.length && m === null; i++) if (got.messages[i].type === "order") m = got.messages[i]
  if (m === null || !Array.isArray(m.order)) return readFailure(got, code, stderrText, "omarchy-broadcast printed no stage order")
  var info = Object.create(null)
  var described = Array.isArray(m.stages) ? m.stages : []
  for (var d = 0; d < described.length && d < ORDER_CAP; d++) {
    var s = described[d]
    var sid = isPlainObject(s) ? stageIdOf(s.id) : ""
    if (sid !== "" && info[sid] === undefined) info[sid] = s
  }
  var truncated = m.order_truncated === true || m.order.length > ORDER_CAP
  var order = []
  var stages = []
  var seen = Object.create(null)
  for (var k = 0; k < m.order.length && k < ORDER_CAP; k++) {
    var id = stageIdOf(m.order[k])
    if (id === "" || seen[id] === true) { truncated = true; continue }
    seen[id] = true
    order.push(id)
    var st = info[id]
    stages.push({ id: id, slot: st ? sanitize(st.slot, STAGE_WORD_CAP) : "",
                  up: !truncated && !!st && st.up === true, down: !truncated && !!st && st.down === true })
  }
  if (truncated) for (var t = 0; t < stages.length; t++) { stages[t].up = false; stages[t].down = false }
  return { ok: true, order: order, stages: stages, overriddenBy: fileText(m.overridden_by), truncated: truncated }
}

// The order after moving stage `index` up (`direction` -1) or down (1): a
// new array, or null when the daemon does not allow that move (its up/down),
// the order is overridden or truncated, or there is no such stage.
function orderAfterMove(order, index, direction) {
  if (!isPlainObject(order) || order.ok !== true || order.truncated || order.overriddenBy !== "") return null
  var st = order.stages[index]
  if (!st || !(direction === -1 || direction === 1)) return null
  if (direction === -1 ? !st.up : !st.down) return null
  var other = index + direction
  if (other < 0 || other >= order.order.length) return null
  var next = order.order.slice()
  next[index] = order.order[other]
  next[other] = order.order[index]
  return next
}

// ---- configuration schema

// The options of a config enum: { value, label }, at most CONFIG_OPTION_CAP
// looked at; "" is a value (a pin's "Automatic").
function configOptions(value) {
  var src = Array.isArray(value) ? value : []
  var n = Math.min(src.length, CONFIG_OPTION_CAP)
  var out = []
  var seen = Object.create(null)
  for (var i = 0; i < n; i++) {
    var o = src[i]
    if (!isPlainObject(o) || typeof o.value !== "string" || !CONFIG_OPTION_RE.test(o.value) || reservedKey(o.value)) continue
    if (seen["=" + o.value] === true) continue
    seen["=" + o.value] = true
    var label = settingText(o.label, CONFIG_OPTION_LABEL_CAP)
    out.push({ value: o.value, label: label !== "" ? label : (o.value !== "" ? o.value : UNKNOWN) })
  }
  return { options: out, total: out.length + (src.length - n) }
}

// One row of a config_group line -> a row, or null (skipped: a key not of
// the grammar, an unknown type, a value not of its type):
//   bool         value a boolean
//   int, float   value a number (an int a whole one); min, max and step
//                make it adjustable (`bounded`) when they are numbers with
//                max > min, step > 0 and at most SETTING_STEPS_MAX steps;
//                the value is then clamped into range
//   enum         at least one option; a value that is not one reads as ""
//   string, path value a string (a display copy)
//   list         value an array of strings (display copies, at most
//                CONFIG_LIST_CAP)
// plus the fields every row has: label, description, editable, source,
// overridden_by, apply, enabled, disabled_reason and notice.
function configEntry(s) {
  if (!isPlainObject(s)) return null
  var id = configKeyOf(s.id)
  if (id === "" || typeof s.type !== "string" || CONFIG_TYPES.indexOf(s.type) < 0) return null
  var label = settingText(s.label, SETTING_LABEL_CAP)
  var enabled = s.enabled === true
  var e = {
    id: id, type: s.type, label: label !== "" ? label : id,
    description: settingText(s.description, CONFIG_DESCRIPTION_CAP),
    value: null, defaultValue: null, min: 0, max: 0, step: 0, bounded: false, decimals: 0,
    unit: settingText(s.unit, SETTING_UNIT_CAP), options: [], optionsTotal: 0, itemsTotal: 0,
    editable: s.editable === true, source: fileText(s.source), overriddenBy: fileText(s.overridden_by),
    apply: CONFIG_APPLY.indexOf(s.apply) >= 0 ? s.apply : "live",
    enabled: enabled, reason: enabled ? "" : settingText(s.disabled_reason, CONFIG_REASON_CAP),
    // What the daemon says about the row's state now, when it has something
    // to ("Applies when the camera restarts"); "" for none (interface
    // revision 22; a daemon below it never prints the field).
    notice: settingText(s.notice, CONFIG_NOTICE_CAP),
    // A path row's raw value, kept only when it is a usable absolute path
    // (mediaPath): a thumbnail's source and a picker's --selected, never
    // shown. "" otherwise.
    rawPath: ""
  }
  if (s.type === "bool") {
    if (typeof s.value !== "boolean") return null
    e.value = s.value
    e.defaultValue = typeof s["default"] === "boolean" ? s["default"] : null
  } else if (s.type === "int" || s.type === "float") {
    var num = s.type === "int" ? configInt : configFloat
    var v = num(s.value)
    if (v === null) return null
    var min = num(s.min)
    var max = num(s.max)
    var step = num(s.step)
    e.bounded = min !== null && max !== null && step !== null && max > min && step > 0 && (max - min) / step <= SETTING_STEPS_MAX
    if (e.bounded) {
      e.min = min
      e.max = max
      e.step = step
      v = Math.max(min, Math.min(max, v))
    }
    e.decimals = s.type === "float" ? stepDecimals(e.bounded ? step : 0.01) : 0
    e.value = v
    e.defaultValue = num(s["default"])
  } else if (s.type === "enum") {
    var opts = configOptions(s.options)
    if (opts.options.length === 0) return null
    e.options = opts.options
    e.optionsTotal = opts.total
    e.value = configOptionIndex(opts.options, s.value) >= 0 ? s.value : null
    e.defaultValue = configOptionIndex(opts.options, s["default"]) >= 0 ? s["default"] : null
  } else if (s.type === "string" || s.type === "path") {
    if (typeof s.value !== "string") return null
    e.value = sanitize(s.value, CONFIG_VALUE_CAP)
    if (s.type === "path") e.rawPath = mediaPath(s.value)
  } else {
    if (!Array.isArray(s.value)) return null
    var items = []
    for (var i = 0; i < s.value.length && i < CONFIG_LIST_CAP; i++)
      if (typeof s.value[i] === "string") items.push(sanitize(s.value[i], CONFIG_FILE_CAP))
    e.value = items
    e.itemsTotal = s.value.length
  }
  return e
}

function configOptionIndex(options, value) {
  var list = Array.isArray(options) ? options : []
  for (var i = 0; i < list.length && i < CONFIG_OPTION_CAP; i++) if (list[i].value === value) return i
  return -1
}

// A config_group line -> { serial, index, count, group } or null (an
// envelope a v1 producer does not print). A group id not of the grammar is
// kept as a refused group, so the rest of the set still commits.
function configGroupLine(m) {
  if (!isPlainObject(m) || m.type !== "config_group" || typeof m.schema !== "number") return null
  var serial = settingsNumber(m.serial)
  var count = lineIndex(m.count, 1, CONFIG_LINES_CAP)
  if (serial === 0 || count < 0) return null
  var index = lineIndex(m.index, 0, count)
  if (index < 0) return null
  var g = m.group
  var gid = isPlainObject(g) ? groupIdOf(g.id) : ""
  if (gid === "") return { serial: serial, schema: m.schema, index: index, count: count, group: null }
  var src = Array.isArray(g.settings) ? g.settings : []
  var n = Math.min(src.length, SETTINGS_LINE_LOOK)
  var rows = []
  for (var i = 0; i < n; i++) {
    var e = configEntry(src[i])
    if (e) rows.push(e)
  }
  var label = settingText(g.label, SETTING_LABEL_CAP)
  return { serial: serial, schema: m.schema, index: index, count: count,
           group: { id: gid, label: label !== "" ? label : gid, rows: rows } }
}

// `config show --json` -> { ok, serial, groups } or { ok: false, error }:
// the lines of one serial and count, each index once (the assembly rule of
// settings_group); groups in the order they first appear, the parts of one
// joined, a repeated key kept once, CONFIG_GROUP_CAP groups of at most
// CONFIG_GROUP_ROW_CAP rows and CONFIG_ROW_CAP rows in all. A schema newer
// than CONFIG_SCHEMA is not drawn: the plugin says it needs updating.
function readConfig(lines, code, stderrText) {
  var got = setupMessages(lines)
  var first = null
  var slots = []
  var received = 0
  for (var i = 0; i < got.messages.length; i++) {
    var line = configGroupLine(got.messages[i])
    if (!line) continue
    if (first === null) {
      if (line.schema > CONFIG_SCHEMA) return readFailed(SETUP_OLD_PLUGIN)
      if (line.schema !== CONFIG_SCHEMA) continue
      first = line
      for (var n = 0; n < line.count; n++) slots.push(null)
    }
    if (line.serial !== first.serial || line.count !== first.count || line.schema !== first.schema) continue
    if (slots[line.index] !== null) continue
    slots[line.index] = line
    received++
  }
  if (first === null) return readFailure(got, code, stderrText, "omarchy-broadcast printed no configuration")
  if (received < first.count) return readFailed("The configuration arrived incomplete")
  var groups = []
  var byId = Object.create(null)
  var seen = Object.create(null)
  var rows = 0
  for (var k = 0; k < slots.length; k++) {
    var grp = slots[k].group
    if (grp === null) continue
    var g = byId[grp.id]
    if (g === undefined) {
      if (groups.length >= CONFIG_GROUP_CAP) continue
      g = { id: grp.id, label: grp.label, rows: [] }
      byId[grp.id] = g
      groups.push(g)
    }
    for (var r = 0; r < grp.rows.length; r++) {
      var row = grp.rows[r]
      if (seen[row.id] === true || g.rows.length >= CONFIG_GROUP_ROW_CAP || rows >= CONFIG_ROW_CAP) continue
      seen[row.id] = true
      g.rows.push(row)
      rows++
    }
  }
  return { ok: true, serial: first.serial, groups: groups }
}

// A row of the read configuration by key, or null.
function findConfigRow(config, key) {
  if (!isPlainObject(config) || config.ok !== true || typeof key !== "string") return null
  for (var g = 0; g < config.groups.length && g < CONFIG_GROUP_CAP; g++) {
    var rows = config.groups[g].rows
    for (var r = 0; r < rows.length && r < CONFIG_GROUP_ROW_CAP; r++) if (rows[r].id === key) return rows[r]
  }
  return null
}

// `config files --json` -> { ok, dir, files, truncated } or { ok: false,
// error }: the files in load order, { path, status, managed, reason }; an
// unknown status reads as "error".
function readConfigFiles(lines, code, stderrText) {
  var got = setupMessages(lines)
  var m = null
  for (var i = 0; i < got.messages.length && m === null; i++) if (got.messages[i].type === "config_files") m = got.messages[i]
  if (m === null || !Array.isArray(m.files)) return readFailure(got, code, stderrText, "omarchy-broadcast printed no configuration files")
  var files = []
  for (var k = 0; k < m.files.length && k < CONFIG_FILES_CAP; k++) {
    var f = m.files[k]
    if (!isPlainObject(f)) continue
    var status = FILE_STATUSES.indexOf(f.status) >= 0 ? f.status : "error"
    files.push({ path: fileText(f.path), status: status, managed: f.managed === true,
                 reason: settingText(f.reason, CONFIG_REASON_CAP) })
  }
  return { ok: true, dir: sanitize(m.dir, CONFIG_DIR_CAP), files: files,
           truncated: m.files_truncated === true || m.files.length > CONFIG_FILES_CAP }
}

// One read's result by kind (SETUP_READS), from its stdout lines, exit
// status and first stderr line (`posterDir`: the gallery's, readMedia).
function setupRead(kind, lines, code, stderrText, posterDir) {
  if (kind === "media") return readMedia(lines, code, stderrText, MEDIA_KIND, posterDir)
  if (kind === "modules") return readModules(lines, code, stderrText)
  if (kind === "order") return readOrder(lines, code, stderrText)
  if (kind === "config") return readConfig(lines, code, stderrText)
  if (kind === "files") return readConfigFiles(lines, code, stderrText)
  return readFailed("")
}

// The reads the daemon supports now, in order: the modules and the order
// from MODULES_REVISION, the configuration and its files from
// CONFIG_REVISION, the background gallery from MEDIA_REVISION; none while
// it is unavailable.
function setupReads(record) {
  if (!available(record) || record.interfaceRevision < MODULES_REVISION) return []
  var out = ["modules", "order"]
  if (record.interfaceRevision >= CONFIG_REVISION) out.push("config", "files")
  if (mediaSupported(record)) out.push("media")
  return out
}

// How many stdout lines a read takes: the gallery's header, its items (at
// most MEDIA_ITEM_CAP) and an error line; READ_LINES_CAP for every other.
// Every line is watch-sized (LINE_CAP).
function readLinesCap(kind) {
  return kind === "media" ? MEDIA_ITEM_CAP + 2 : READ_LINES_CAP
}

// The argv of read `kind` (fixed words only), or null.
function setupReadArgv(cli, kind) {
  if (!cliUsable(cli)) return null
  if (kind === "modules") return [cli, "modules", "list", "--json"]
  if (kind === "order") return [cli, "order", "show", "--json"]
  if (kind === "config") return [cli, "config", "show", "--json"]
  if (kind === "files") return [cli, "config", "files", "--json"]
  if (kind === "media") return mediaListArgv(cli)
  return null
}

// Every read, not yet loaded (null): what the dialog shows as loading.
function emptySetup() {
  return { modules: null, order: null, config: null, files: null, media: null }
}

// `setup` with only the reads of `reads` kept (a new object): what a daemon
// whose revision dropped (or that went) still supports; the others read as
// not loaded.
function setupForReads(setup, reads) {
  var out = emptySetup()
  var kinds = Array.isArray(reads) ? reads : []
  if (isPlainObject(setup))
    for (var i = 0; i < SETUP_READS.length; i++)
      if (kinds.indexOf(SETUP_READS[i]) >= 0) out[SETUP_READS[i]] = setup[SETUP_READS[i]] || null
  return out
}

// `setup` with read `kind` replaced by `result` (a new object).
function withSetupRead(setup, kind, result) {
  var out = emptySetup()
  if (isPlainObject(setup)) for (var i = 0; i < SETUP_READS.length; i++) out[SETUP_READS[i]] = setup[SETUP_READS[i]] || null
  if (SETUP_READS.indexOf(kind) >= 0) out[kind] = result
  return out
}

// ---- writes (intents { verb: "setup", op, ... }, re-checked when they run)

// The word a config row's value is written as, or null: a boolean as
// true/false, a bounded number put on its grid (an int by String, a float
// with its step's decimals), an option value of the row (Automatic is "").
// Only for a row the daemon accepts a write for now: editable, enabled, not
// overridden by a later file.
function configWord(row, value) {
  if (!isPlainObject(row) || !row.editable || !row.enabled || row.overriddenBy !== "") return null
  if (row.type === "bool") return typeof value === "boolean" ? (value ? "true" : "false") : null
  if (row.type === "enum") return typeof value === "string" && configOptionIndex(row.options, value) >= 0 ? value : null
  if ((row.type === "int" || row.type === "float") && row.bounded) {
    var v = configStep(row, value)
    if (v === null) return null
    return row.type === "int" ? String(v) : v.toFixed(row.decimals)
  }
  return null
}

// A number put on a bounded row's grid (min + k * step, within range), or
// null.
function configStep(row, value) {
  if (!isPlainObject(row) || !row.bounded || typeof value !== "number" || !isFinite(value)) return null
  var kmax = Math.floor((row.max - row.min) / row.step + 1e-9)
  var k = Math.max(0, Math.min(kmax, Math.round((value - row.min) / row.step)))
  var v = row.min + k * row.step
  if (row.type === "int") return Math.round(v)
  return Number(v.toFixed(row.decimals))
}

// One Left/Right press (or a - / + button) on a number row: about a
// twentieth of the range, on the step grid, at least one step; null when it
// would not move.
function configNudge(row, direction) {
  if (!isPlainObject(row) || !row.bounded || !(direction === 1 || direction === -1)) return null
  var unit = Math.max(row.step, Math.round((row.max - row.min) / 20 / row.step) * row.step)
  var v = configStep(row, row.value + direction * unit)
  return v === null || v === row.value ? null : v
}

function configSetArgv(cli, key, word) {
  if (!cliUsable(cli) || configKeyOf(key) === "" || typeof word !== "string" || !CONFIG_WORD_RE.test(word)) return null
  return [cli, "config", "set", "--", key, word]
}

function moduleEnableArgv(cli, id, on) {
  var m = moduleIdOf(id)
  if (!cliUsable(cli) || m === "" || typeof on !== "boolean") return null
  return [cli, "modules", on ? "enable" : "disable", m]
}

// The whole order, every id of the stage grammar and once: one argv element.
function orderSetArgv(cli, order) {
  if (!cliUsable(cli) || !Array.isArray(order) || order.length === 0 || order.length > ORDER_CAP) return null
  var seen = Object.create(null)
  for (var i = 0; i < order.length; i++) {
    if (stageIdOf(order[i]) === "" || seen[order[i]] === true) return null
    seen[order[i]] = true
  }
  return [cli, "order", "set", order.join(",")]
}

function orderResetArgv(cli) {
  return cliUsable(cli) ? [cli, "order", "reset"] : null
}

// A setup intent's argv under `record`, re-checked when it runs: the daemon
// is available at the revision the write needs (a module or the order:
// MODULES_REVISION; a config key: CONFIG_REVISION), and every word is
// checked again.
function setupIntentArgv(cli, record, intent) {
  if (!isPlainObject(intent) || !available(record) || record.interfaceRevision < MODULES_REVISION) return null
  switch (intent.op) {
  case "module": return moduleEnableArgv(cli, intent.id, intent.on)
  case "order": return orderSetArgv(cli, intent.order)
  case "order-reset": return orderResetArgv(cli)
  case "config": return record.interfaceRevision >= CONFIG_REVISION ? configSetArgv(cli, intent.id, intent.word) : null
  case "media-remove": return mediaSupported(record) ? mediaRemoveArgv(cli, intent.path) : null
  case "away-image": return placeholderSupported(record) ? awayImageArgv(cli, intent.path) : null
  case "away-import": return placeholderSupported(record) ? mediaImportArgv(cli, intent.path, AWAY_KIND) : null
  default: return null
  }
}

function isSetupIntent(intent) {
  return isPlainObject(intent) && intent.verb === "setup"
}

// A setup write is running or queued: the dialog takes no other until its
// result (and the read after it) is in, so one is ever queued.
function setupWriteBusy(running, queue) {
  if (isSetupIntent(running)) return true
  var q = Array.isArray(queue) ? queue : []
  for (var i = 0; i < q.length && i < INTENT_QUEUE_CAP; i++) if (isSetupIntent(q[i])) return true
  return false
}

// ---- the dialog's views

// The sections the dialog lists for `record`, in order: every word of
// SETUP_SECTIONS, Backgrounds only from MEDIA_REVISION (an unknown or
// unavailable daemon lists the other five).
function setupSections(record) {
  var media = mediaSupported(record)
  return SETUP_SECTIONS.filter(function(v) { return v !== "backgrounds" || media })
}

// `sections` as given when it is a list of section words, else the
// sections of an unknown daemon (setupSections(null)).
function sectionList(sections) {
  if (!Array.isArray(sections) || sections.length === 0) return setupSections(null)
  for (var i = 0; i < sections.length; i++) if (SETUP_SECTIONS.indexOf(sections[i]) < 0) return setupSections(null)
  return sections
}

// The section shown: a word of `sections` (setupSections), else the first.
function setupSectionValue(value, sections) {
  var list = sectionList(sections)
  return typeof value === "string" && list.indexOf(value) >= 0 ? value : list[0]
}

// The section list: { value, label, description, number, selected }.
function setupSectionOptions(section, sections) {
  var list = sectionList(sections)
  var current = setupSectionValue(section, list)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var v = list[i]
    out.push({ value: v, label: SETUP_SECTION_LABELS[v], description: SETUP_SECTION_DESCRIPTIONS[v],
               number: String(i + 1), selected: v === current })
  }
  return out
}

// What the daemon lets the dialog do: { modules, config, text, hint,
// commandText }. `modules`: Modules and Order work (MODULES_REVISION);
// `config`: Backends and Daemon too (CONFIG_REVISION). `text` replaces every
// section but Diagnostics while the daemon is unavailable (with the panel's
// hint and command) or predates the dialog.
function setupGate(record) {
  var out = { modules: false, config: false, text: "", hint: "", commandText: "" }
  if (!available(record)) {
    var msg = unavailableMessage(record)
    out.text = msg.title
    out.hint = msg.hint
    out.commandText = msg.commandText
    return out
  }
  if (record.interfaceRevision < MODULES_REVISION) { out.text = SETUP_OLD_DAEMON; return out }
  out.modules = true
  out.config = record.interfaceRevision >= CONFIG_REVISION
  return out
}

// A read's state as a section hint: loading, its failure, or "" (loaded).
function readHint(result) {
  if (result === null || result === undefined) return SETUP_LOADING
  return result.ok === true ? "" : (result.error !== "" ? result.error : "The daemon could not be read")
}

// A status word and the daemon's reason as one line: "Status: reason", or the
// status alone when the reason is empty or only repeats it (the daemon sends
// status "disabled" with reason "Disabled" for a module the user turned off).
function statusReasonText(statusText, reason) {
  var r = typeof reason === "string" ? reason : ""
  if (r === "" || r.toLowerCase() === String(statusText).toLowerCase()) return statusText
  return statusText + ": " + r
}

function overriddenText(file) {
  return typeof file === "string" && file !== "" ? OVERRIDDEN_PREFIX + file : ""
}

// A module's kind for the screen (MODULE_KIND_LABELS), or "".
function moduleKindText(kind) {
  if (typeof kind !== "string" || kind === "") return ""
  var known = ownValue(MODULE_KIND_LABELS, kind)
  return known !== undefined ? known : kind
}

// The Modules section: { hint, rows, truncation }; a row:
//   { id, title, statusText, reason, statusLine, kindText, stagesText, checked,
//     switchable, note, forced, forcedText, stageNotes, index }
// `forced` is the daemon's word that the module's conflicts are not enforced;
// `forcedText` is the mark for it (else ""); `stageNotes` lists an enabled, usable
// module's refused stages, one "id: reason" line each, else "".
// `stagesText` leads with the kind (moduleKindText), when the daemon gives one.
// `switchable` is false while a later config file sets the module's
// enabled key (`note` says which file).
function modulesSectionView(setup, record) {
  var out = { hint: "", rows: [], truncation: "" }
  var gate = setupGate(record)
  if (!gate.modules) { out.hint = gate.text; return out }
  var list = isPlainObject(setup) ? setup.modules : null
  out.hint = readHint(list)
  if (out.hint !== "") return out
  if (list.modules.length === 0) { out.hint = MODULES_EMPTY_TEXT; return out }
  for (var i = 0; i < list.modules.length && i < SETUP_MODULE_CAP; i++) {
    var m = list.modules[i]
    var ids = []
    for (var s = 0; s < m.stages.length && s < MODULE_STAGE_CAP; s++) ids.push(m.stages[s].id)
    var statusText = m.status === "available" ? "Available" : (m.status === "disabled" ? "Disabled" : "Unavailable")
    var kindText = moduleKindText(m.kind)
    var notes = []
    if (m.enabled && m.status === "available") {
      for (var t = 0; t < m.stages.length && t < MODULE_STAGE_CAP; t++) {
        var sg = m.stages[t]
        if (!sg.available) notes.push(sg.id + (sg.reason !== "" ? ": " + sg.reason : ": unavailable"))
      }
    }
    var stages = ids.length > 0 ? "Stages: " + ids.join(", ") + (m.stagesTruncated ? ", …" : "") : ""
    out.rows.push({
      id: m.id, title: m.name + (m.version !== "" ? " " + m.version : ""),
      statusText: statusText, kindText: kindText,
      reason: m.reason, forced: m.forced,
      statusLine: statusReasonText(statusText, m.reason), forcedText: m.forced ? MODULE_FORCED_TEXT : "",
      stageNotes: notes.join("\n"),
      stagesText: [kindText, stages].filter(function(t) { return t !== "" }).join(" \u00b7 "),
      checked: m.enabled, switchable: m.overriddenBy === "", note: overriddenText(m.overriddenBy), index: i
    })
  }
  out.truncation = showingText(out.rows.length, list.total, "modules")
  return out
}

// The Order section: { hint, rows, reset, note }; a row:
//   { id, position, slot, up, down, index }
// up/down are the daemon's (readOrder); none moves, and Reset order is not
// offered, while a later config file sets the order (`note`).
function orderSectionView(setup, record) {
  var out = { hint: "", rows: [], reset: false, note: "" }
  var gate = setupGate(record)
  if (!gate.modules) { out.hint = gate.text; return out }
  var order = isPlainObject(setup) ? setup.order : null
  out.hint = readHint(order)
  if (out.hint !== "") return out
  if (order.order.length === 0) { out.hint = ORDER_EMPTY_TEXT; return out }
  var locked = order.overriddenBy !== ""
  for (var i = 0; i < order.stages.length && i < ORDER_CAP; i++) {
    var st = order.stages[i]
    out.rows.push({ id: st.id, position: String(i + 1), slot: st.slot, up: !locked && st.up, down: !locked && st.down, index: i })
  }
  out.reset = !locked
  out.note = locked ? overriddenText(order.overriddenBy) : (order.truncated ? ORDER_TRUNCATED_TEXT : "")
  return out
}

// A Diagnostics value longer than this (the daemon's warning or error) is
// drawn under its label, wrapped, instead of on its line, elided.
var INFO_WRAP_CHARS = 48

// A config value as the dialog writes it.
function configValueText(row, value) {
  if (!isPlainObject(row)) return ""
  var v = value === undefined ? row.value : value
  if (row.type === "bool") return v === true ? "On" : "Off"
  if (row.type === "int" || row.type === "float") {
    if (typeof v !== "number" || !isFinite(v)) return UNKNOWN
    return (row.type === "float" ? v.toFixed(row.decimals) : String(v)) + (row.unit !== "" ? " " + row.unit : "")
  }
  if (row.type === "enum") {
    var at = configOptionIndex(row.options, v)
    return at >= 0 ? row.options[at].label : UNKNOWN
  }
  if (row.type === "list") {
    var items = Array.isArray(v) ? v : []
    if (items.length === 0) return "None"
    return items.join(", ") + (row.itemsTotal > items.length ? ", …" : "")
  }
  return typeof v === "string" && v !== "" ? v : "Not set"
}

// The widget a config row gets: "switch" (bool), "choices" (enum: a row of
// buttons, while fitsSegmented; "dropdown" for an enum of many or long
// choices, such as output.mode), "stepper" (a bounded number: - and +),
// "away" (the away image's path row, while `away`: the daemon is at
// PLACEHOLDER_REVISION; a thumbnail, its name, Choose..., Add... and
// Clear), or "text" (the value, read-only): every row the daemon does not
// take a write for now (configWord's rule), and every other string, path or
// list.
function configWidget(row, away) {
  if (!isPlainObject(row) || !row.editable || !row.enabled || row.overriddenBy !== "") return "text"
  if (row.type === "path" && row.id === AWAY_IMAGE_KEY) return away === true ? "away" : "text"
  if (row.type === "bool") return "switch"
  if (row.type === "enum") return fitsSegmented(row.options) ? "choices" : "dropdown"
  if ((row.type === "int" || row.type === "float") && row.bounded) return "stepper"
  return "text"
}

// A config row as drawn: { id, type, widget, label, description, value,
// valueText, options, note, notice, applyText, greyed, stop }. `note` is
// "Overridden by <file>" for a row a later file sets, else the daemon's reason
// for a greyed one; `notice` is what the daemon says about the row's state
// now, "" for none; `applyText` says when a change takes effect (not for a live
// one); `stop` is the keyboard stop of an interactive row, -1 for text.
// `away` as for configWidget.
function configRowView(row, stop, away) {
  var widget = configWidget(row, away)
  var options = []
  for (var i = 0; row.type === "enum" && i < row.options.length && i < CONFIG_OPTION_CAP; i++)
    options.push({ value: row.options[i].value, label: row.options[i].label, selected: row.options[i].value === row.value })
  var overridden = row.overriddenBy !== ""
  return {
    id: row.id, type: row.type, widget: widget, label: row.label, description: row.description, value: row.value,
    valueText: configValueText(row), options: options,
    note: overridden ? overriddenText(row.overriddenBy) : (row.enabled ? "" : row.reason),
    notice: typeof row.notice === "string" ? row.notice : "",
    applyText: APPLY_TEXTS[row.apply] !== undefined && widget !== "text" ? APPLY_TEXTS[row.apply] : "",
    greyed: overridden || !row.enabled, stop: widget === "text" ? -1 : stop
  }
}

// Whether a key of the modules group is one Backends draws: the profile and
// a stage's pin.
function backendKey(id) {
  return id === "modules.profile" || id.indexOf("modules.pin.") === 0
}

// Rows drawn directly under another, out of their own group: the key of
// the follower, the key of the row it follows. The away image's picker sits
// under the switch that shows it when there is no camera picture.
var CONFIG_ROW_FOLLOWS = { "effect.fallback_image": "output.placeholder" }

// The rows of the read configuration that `pick(group, row)` keeps, as
// groups of configRowView rows numbered for the keyboard from 0, top to
// bottom (`away` as for configWidget). A row of CONFIG_ROW_FOLLOWS is moved
// directly under the row it follows while that one is kept; else it stays
// in its own group. A group left with no row is not drawn.
function configGroupsView(config, pick, away) {
  var picked = []
  var kept = {}
  for (var g = 0; g < config.groups.length && g < CONFIG_GROUP_CAP; g++) {
    var group = config.groups[g]
    var rows = []
    for (var r = 0; r < group.rows.length && r < CONFIG_GROUP_ROW_CAP; r++) {
      if (!pick(group, group.rows[r])) continue
      rows.push(group.rows[r])
      kept[group.rows[r].id] = true
    }
    picked.push({ group: group, rows: rows })
  }
  var moved = function(row) {
    return Object.prototype.hasOwnProperty.call(CONFIG_ROW_FOLLOWS, row.id) && kept[CONFIG_ROW_FOLLOWS[row.id]] === true
  }
  var followers = {}
  for (var p = 0; p < picked.length; p++)
    for (var f = 0; f < picked[p].rows.length; f++)
      if (moved(picked[p].rows[f])) followers[CONFIG_ROW_FOLLOWS[picked[p].rows[f].id]] = picked[p].rows[f]
  var groups = []
  var stop = 0
  var add = function(list, row) {
    var view = configRowView(row, stop, away)
    if (view.stop >= 0) stop++
    list.push(view)
  }
  for (var q = 0; q < picked.length; q++) {
    var views = []
    for (var i = 0; i < picked[q].rows.length; i++) {
      var row = picked[q].rows[i]
      if (moved(row)) continue
      add(views, row)
      if (Object.prototype.hasOwnProperty.call(followers, row.id)) add(views, followers[row.id])
    }
    if (views.length > 0) groups.push({ id: picked[q].group.id, label: picked[q].group.label, rows: views })
  }
  return { groups: groups, stops: stop }
}

// ---- battery saver (video.battery_saver, interface revision 22)

// The daemon runs the video effects without the NVIDIA GPU, in system memory,
// when the mode says so: `off` never, `on_battery` while the machine runs on
// its battery, `power_profile` while the power profile is power-saver,
// `always`, and from interface revision 23 `auto` (on battery or while the
// power profile is power-saver; that daemon's default). The setup dialog
// draws the mode as any enum; the panel has a switch for it, which writes
// `off` or the last mode that was not `off`, and under it a Mode dropdown
// that chooses that mode.
var BATTERY_SAVER_REVISION = 22
// The revision whose daemon knows the mode `auto`.
var BATTERY_SAVER_AUTO_REVISION = 23
var BATTERY_SAVER_KEY = "video.battery_saver"
var BATTERY_SAVER_OFF = "off"
var BATTERY_SAVER_AUTO = "auto"
// The modes the switch turns on, in the dropdown's order, and the first (the
// default): the words of the daemon's enum other than `off`; the manifest's
// `batterySaverMode` has the same options and default. `auto` only from
// BATTERY_SAVER_AUTO_REVISION; below it the fallback is the default.
var BATTERY_SAVER_MODES = ["auto", "on_battery", "power_profile", "always"]
var BATTERY_SAVER_MODE_DEFAULT = "auto"
var BATTERY_SAVER_MODE_FALLBACK = "on_battery"
// The dropdown's labels by mode: the daemon's own labels for the same words
// (its setup dialog's), so one setting has one name.
var BATTERY_SAVER_MODE_LABELS = {
  auto: "On battery or power saver",
  on_battery: "On battery",
  power_profile: "Follow the power profile",
  always: "Always"
}
var BATTERY_SAVER_LABEL = "Battery saver"
var BATTERY_SAVER_MODE_ROW_LABEL = "Mode"
var BATTERY_SAVER_MODE_NAME = "Battery saver mode"
var BATTERY_SAVER_NOW_MARK = "Now: "

// The daemon knows `auto`: one of BATTERY_SAVER_AUTO_REVISION or later (an
// unknown revision is not one).
function batterySaverAutoSupported(record) {
  return available(record) && record.interfaceRevision >= BATTERY_SAVER_AUTO_REVISION
}

// The remembered mode, read back against `record`: a word of
// BATTERY_SAVER_MODES exactly, `auto` only from a daemon that knows it.
// Nothing stored (null or undefined) reads as `auto` from such a daemon;
// `auto` from an older one, and anything else, as on_battery.
function batterySaverModeValue(value, record) {
  var auto = batterySaverAutoSupported(record)
  if (value === null || value === undefined || value === BATTERY_SAVER_AUTO)
    return auto ? BATTERY_SAVER_AUTO : BATTERY_SAVER_MODE_FALLBACK
  return typeof value === "string" && BATTERY_SAVER_MODES.indexOf(value) >= 0 ? value : BATTERY_SAVER_MODE_FALLBACK
}

// The panel's switch is offered by a daemon of BATTERY_SAVER_REVISION or
// later (an unknown revision is not one).
function batterySaverSupported(record) {
  return available(record) && record.interfaceRevision >= BATTERY_SAVER_REVISION
}

// The reads the panel holds for the switch: only the configuration, and only
// from a daemon that has the row.
function panelReads(record) {
  return batterySaverSupported(record) ? ["config"] : []
}

// The row of the read configuration, or null (not read yet, the read
// failed, or the daemon does not publish it).
function batterySaverRow(config) {
  var row = findConfigRow(config, BATTERY_SAVER_KEY)
  return row !== null && row.type === "enum" ? row : null
}

// The part of the daemon's description that says what is in force, from
// "Now: " to its end ("Now: on battery, the camera runs without the NVIDIA
// GPU"); "" when it has none.
function batterySaverNow(description) {
  if (typeof description !== "string") return ""
  var at = description.lastIndexOf(BATTERY_SAVER_NOW_MARK)
  return at >= 0 ? description.slice(at).trim() : ""
}

// The Mode dropdown's choices, [{ value, label }] in BATTERY_SAVER_MODES'
// order with BATTERY_SAVER_MODE_LABELS: `auto` only against a daemon that knows it,
// and only the modes the daemon's row lists among its options.
function batterySaverModeOptions(record, row) {
  var out = []
  if (!isPlainObject(row)) return out
  var auto = batterySaverAutoSupported(record)
  for (var i = 0; i < BATTERY_SAVER_MODES.length; i++) {
    var word = BATTERY_SAVER_MODES[i]
    if (word === BATTERY_SAVER_AUTO && !auto) continue
    if (configOptionIndex(row.options, word) < 0) continue
    out.push({ value: word, label: BATTERY_SAVER_MODE_LABELS[word] })
  }
  return out
}

// The switch and the Mode dropdown as drawn: { visible, on, enabled, reason,
// now, notice, mode, modes, modeValue, modeLabel, modeReadOnly, modeEnabled }.
// Visible only against a daemon of BATTERY_SAVER_REVISION or later that
// published the row. `on`: the mode is not `off`. `enabled` and `reason`:
// the daemon's (the row is greyed while video.memory is not automatic, and
// its write refused). `mode`: the word a click on the switch writes: `off`
// while on, else the remembered mode (`stored`, through
// batterySaverModeValue; one the dropdown does not offer reads as on_battery
// when offered, else as its first choice); null when nothing can be written now (hidden,
// greyed, or the word is not one of the daemon's options).
// The dropdown: `modes` its choices (batterySaverModeOptions); `modeValue`
// the word it shows, the daemon's mode while the saver is on, else the
// remembered one, and `modeLabel` that word's label. A mode in force that
// the plugin does not offer (`auto` against a revision-22 view, a later
// word) is `modeReadOnly`: shown with the daemon's label for it (the raw
// word without one), never chosen nor written. `modeEnabled`: a choice can
// be made (the row is live, the value not read-only, there are choices).
function batterySaverView(record, config, stored) {
  var out = { visible: false, on: false, enabled: false, reason: "", now: "", notice: "", mode: null,
              modes: [], modeValue: "", modeLabel: "", modeReadOnly: false, modeEnabled: false }
  if (!batterySaverSupported(record)) return out
  var row = batterySaverRow(config)
  if (row === null) return out
  out.modes = batterySaverModeOptions(record, row)
  var remembered = batterySaverModeValue(stored, record)
  // A remembered mode the dropdown does not offer (a row without `auto`):
  // on_battery when offered, else the first choice, so the switch can still
  // turn on and the dropdown never shows a raw word.
  if (out.modes.length > 0 && configOptionIndex(out.modes, remembered) < 0) {
    remembered = configOptionIndex(out.modes, BATTERY_SAVER_MODE_FALLBACK) >= 0
      ? BATTERY_SAVER_MODE_FALLBACK : out.modes[0].value
  }
  out.visible = true
  out.on = row.value !== null && row.value !== BATTERY_SAVER_OFF
  out.enabled = row.enabled && row.editable && row.overriddenBy === ""
  out.reason = row.overriddenBy !== "" ? overriddenText(row.overriddenBy) : (row.enabled ? "" : row.reason)
  out.now = batterySaverNow(row.description)
  out.notice = row.notice
  if (out.enabled) {
    var word = out.on ? BATTERY_SAVER_OFF : remembered
    if (configOptionIndex(row.options, word) >= 0) out.mode = word
  }
  out.modeValue = out.on ? String(row.value) : remembered
  var offered = configOptionIndex(out.modes, out.modeValue)
  if (offered >= 0) {
    out.modeLabel = out.modes[offered].label
  } else if (out.on) {
    out.modeReadOnly = true
    var daemon = configOptionIndex(row.options, out.modeValue)
    out.modeLabel = daemon >= 0 && row.options[daemon].label !== "" ? row.options[daemon].label : out.modeValue
  } else {
    out.modeLabel = BATTERY_SAVER_MODE_LABELS[out.modeValue] || out.modeValue
  }
  out.modeEnabled = out.enabled && !out.modeReadOnly && out.modes.length > 0
  return out
}

// A choice of the Mode dropdown, checked against the view: the word, when it
// is one of its choices and differs from the one shown, while the dropdown
// takes a choice (batterySaverView's modeEnabled); else null (nothing to do).
// The panel writes it to the daemon while the saver is on, and remembers it.
function batterySaverModeChoice(view, value) {
  if (!isPlainObject(view) || view.visible !== true || view.modeEnabled !== true || typeof value !== "string") return null
  if (value === view.modeValue || configOptionIndex(view.modes, value) < 0) return null
  return BATTERY_SAVER_MODES.indexOf(value) >= 0 ? value : null
}

// The mode to remember when the switch turns the saver off: the row's mode
// in force, when it is one the Mode dropdown offers against `record`
// (batterySaverModeOptions), else null (nothing to remember: the mode is
// off already, unknown, or `auto` from a daemon below
// BATTERY_SAVER_AUTO_REVISION).
function batterySaverMemory(config, record) {
  var row = batterySaverRow(config)
  if (row === null || typeof row.value !== "string") return null
  return configOptionIndex(batterySaverModeOptions(record, row), row.value) >= 0 ? row.value : null
}

// The Backends section: { hint, groups, stops }: the modules group's profile
// row and its pin rows (one per stage), written with `config set`.
function backendsSectionView(setup, record) {
  var out = { hint: "", groups: [], stops: 0 }
  var gate = setupGate(record)
  if (!gate.modules) { out.hint = gate.text; return out }
  if (!gate.config) { out.hint = SETUP_OLD_CONFIG; return out }
  var config = isPlainObject(setup) ? setup.config : null
  out.hint = readHint(config)
  if (out.hint !== "") return out
  var v = configGroupsView(config, function(group, row) { return group.id === "modules" && backendKey(row.id) })
  if (v.groups.length === 0) { out.hint = BACKENDS_EMPTY_TEXT; return out }
  out.groups = v.groups
  out.stops = v.stops
  return out
}

// The Daemon section: { hint, groups, stops }: every group of the
// configuration but the modules one (Modules, Order and Backends draw it).
function daemonSectionView(setup, record) {
  var out = { hint: "", groups: [], stops: 0 }
  var gate = setupGate(record)
  if (!gate.modules) { out.hint = gate.text; return out }
  if (!gate.config) { out.hint = SETUP_OLD_CONFIG; return out }
  var config = isPlainObject(setup) ? setup.config : null
  out.hint = readHint(config)
  if (out.hint !== "") return out
  var v = configGroupsView(config, function(group) { return group.id !== "modules" }, placeholderSupported(record))
  out.groups = v.groups
  out.stops = v.stops
  if (v.groups.length === 0) out.hint = "The daemon reports no configuration."
  return out
}

// The index of a config row view's selected option, else -1.
function configSelected(rowView) {
  var options = isPlainObject(rowView) && Array.isArray(rowView.options) ? rowView.options : []
  for (var i = 0; i < options.length; i++) if (options[i].selected) return i
  return -1
}

// The row at keyboard stop `stop` of a Backends or Daemon view, or null.
function configViewRow(view, stop) {
  var groups = isPlainObject(view) && Array.isArray(view.groups) ? view.groups : []
  for (var g = 0; g < groups.length && g < CONFIG_GROUP_CAP; g++) {
    var rows = groups[g].rows
    for (var r = 0; r < rows.length && r < CONFIG_GROUP_ROW_CAP; r++) if (rows[r].stop === stop) return rows[r]
  }
  return null
}

// The Diagnostics section, read-only: { rows, filesHint, dir, files,
// problems, problemsHint, commands }. rows: { label, value } (the interface
// revision and the daemon's error); files: { path, statusText, reason, note }
// in load order (`note` marks the managed one); problems: { title, reason },
// each module that is not available and each stage of an available module
// that cannot run.
function diagnosticsView(setup, record) {
  var out = { rows: [], filesHint: "", dir: "", files: [], problems: [], problemsHint: "", commands: DIAGNOSTIC_COMMANDS.slice() }
  var linkedOk = available(record)
  out.rows.push({ label: "D-Bus API", value: linkedOk && record.interfaceRevision >= 0 ? "revision " + record.interfaceRevision : UNKNOWN })
  if (linkedOk && record.warning !== "") out.rows.push({ label: "Daemon warning", value: record.warning })
  out.rows.push({ label: "Daemon error", value: linkedOk ? (record.error !== "" ? record.error : "None") : unavailableMessage(record).title })
  var gate = setupGate(record)
  var files = isPlainObject(setup) ? setup.files : null
  if (!gate.config) out.filesHint = gate.modules ? SETUP_OLD_CONFIG : gate.text
  else out.filesHint = readHint(files)
  if (out.filesHint === "") {
    out.dir = files.dir
    for (var i = 0; i < files.files.length && i < CONFIG_FILES_CAP; i++) {
      var f = files.files[i]
      out.files.push({ path: f.path, statusText: FILE_STATUS_TEXTS[f.status], reason: f.reason,
                       note: f.managed ? MANAGED_FILE_TEXT : "" })
    }
    if (files.truncated) out.files.push({ path: "…", statusText: "", reason: "", note: "" })
  }
  var list = isPlainObject(setup) ? setup.modules : null
  out.problemsHint = gate.modules ? readHint(list) : gate.text
  if (out.problemsHint === "") {
    for (var m = 0; m < list.modules.length && m < SETUP_MODULE_CAP; m++) {
      var mod = list.modules[m]
      if (mod.status !== "available") {
        out.problems.push({ title: mod.name, reason: statusReasonText(mod.status === "disabled" ? "Disabled" : "Unavailable", mod.reason) })
        continue
      }
      for (var s = 0; s < mod.stages.length && s < MODULE_STAGE_CAP; s++)
        if (!mod.stages[s].available)
          out.problems.push({ title: mod.name + ", stage " + mod.stages[s].id, reason: mod.stages[s].reason !== "" ? mod.stages[s].reason : "Unavailable" })
    }
    if (out.problems.length === 0) out.problemsHint = "No module problems"
  }
  return out
}

// Where the dialog's content scrolls to from `contentY` by `delta` pixels,
// kept within the content (a view `viewHeight` tall over `contentHeight`).
function scrollTarget(contentY, contentHeight, viewHeight, delta) {
  var y = typeof contentY === "number" && isFinite(contentY) ? contentY : 0
  var h = typeof contentHeight === "number" && isFinite(contentHeight) ? contentHeight : 0
  var v = typeof viewHeight === "number" && isFinite(viewHeight) ? viewHeight : 0
  var d = typeof delta === "number" && isFinite(delta) ? delta : 0
  return Math.max(0, Math.min(Math.max(0, h - v), y + d))
}

// The dialog's keyboard stops, top to bottom: the section entries of
// `sections` (setupSections; omitted, the five of an unknown daemon), then
// the shown section's controls:
//   modules   each module whose switch can be flipped
//   order     each stage that can move (Left/Right pick Move up or Move
//             down, Enter moves; Ctrl+Up/Down moves at once), then Reset
//             order when offered
//   backends, daemon  each interactive config row (index: its `stop`)
//   backgrounds  each of the user's own backgrounds (its Remove button, then
//             the Copy button of the convert command it shows, if any)
//   diagnostics  nothing (it only shows)
// `view` is the shown section's view, as drawn.
function setupStops(section, view, sections) {
  var list = sectionList(sections)
  var stops = []
  for (var i = 0; i < list.length; i++) stops.push({ kind: "section", index: i })
  var shown = setupSectionValue(section, list)
  if (!isPlainObject(view) || view.hint !== "") return stops
  if (shown === "modules") {
    for (var m = 0; m < view.rows.length; m++) if (view.rows[m].switchable) stops.push({ kind: "module", index: m })
  } else if (shown === "order") {
    for (var o = 0; o < view.rows.length; o++) if (view.rows[o].up || view.rows[o].down) stops.push({ kind: "stage", index: o })
    if (view.reset) stops.push({ kind: "order-reset", index: -1 })
  } else if (shown === "backends" || shown === "daemon") {
    for (var s = 0; s < view.stops; s++) stops.push({ kind: "config", index: s })
  } else if (shown === "backgrounds") {
    var mrows = Array.isArray(view.rows) ? view.rows : []
    for (var b = 0; b < mrows.length && b < MEDIA_ITEM_CAP; b++) {
      stops.push({ kind: "media-remove", index: b })
      if (typeof mrows[b].convertCommand === "string" && mrows[b].convertCommand !== "") stops.push({ kind: "media-copy", index: b })
    }
  }
  return stops
}

// The button of a stage row a Left/Right press lands on (0 Move up, 1 Move
// down), from `current`: only an offered one; -1 when neither is.
function stageButtonAfter(row, current, direction) {
  if (!isPlainObject(row)) return -1
  var offered = [row.up === true, row.down === true]
  var want = direction > 0 ? 1 : (direction < 0 ? 0 : current)
  if (want === 0 || want === 1) { if (offered[want]) return want }
  if (offered[current === 1 ? 1 : 0]) return current === 1 ? 1 : 0
  return offered[0] ? 0 : (offered[1] ? 1 : -1)
}

// ---------------------------------------------------------------- background gallery
//
// Interface revision MEDIA_REVISION. `media list background --json` prints
// a `media` header line (the bundled and the user gallery directories, the
// number of items that follow) and then one `media_item` line per item, each
// path whole, each label at most 96 bytes, every line at most 4096 bytes
// (the watch's LINE_CAP bounds them here). A directory too long for its line
// is "", and its items are left out. The Effect tab's Background row shows the image in force and
// offers Gallery... (the shell's image picker, `omarchy-menu-images`, over
// the two directories) and Add... (the desktop file chooser,
// `omarchy-file-select`, then `media import background PATH --select`); the
// setup dialog's Backgrounds section lists the user's own items with Remove
// (`media remove PATH`). Raw paths are kept only to be passed as argv
// elements; everything shown is a sanitised display copy.

var MEDIA_KIND = "background"
// The gallery of the away image (PLACEHOLDER_REVISION): the same lines and
// commands, its own two directories; what it selects is `effect.fallback_image`.
var AWAY_KIND = "away"
// The effect option the gallery's image is for: the row is offered only
// while the daemon's background mode setting has this option.
var BACKGROUND_REPLACE = "replace"
// The producer lists at most this many items.
var MEDIA_ITEM_CAP = 500
var MEDIA_LABEL_CAP = 96
var MEDIA_DIMENSION_MAX = 65535
// The file chooser's filter for Add... (`media import` checks the content,
// not the name): for a background still images (PNG, JPEG, still WebP),
// animated GIF, WebP and APNG (the daemon converts them to a video at
// import, with ffmpeg) and videos; the away image takes still images only.
var MEDIA_EXTENSIONS = "png jpg jpeg webp gif apng mp4 m4v mov mkv webm"
var AWAY_EXTENSIONS = "png jpg jpeg webp"
// The names of a video file (mediaVideoName): what the panel's thumbnail
// goes by when the read gallery does not list the background in force.
var MEDIA_VIDEO_EXTENSIONS = ["mp4", "m4v", "mov", "mkv", "webm"]
// A `media_item` of a video: `media_type` this, `duration_ms` at most
// MEDIA_DURATION_MAX_MS (else unknown and not shown).
var MEDIA_TYPE_VIDEO = "video"
var MEDIA_DURATION_MAX_MS = 86400000
// A video's poster is a JPEG file directly in the daemon's poster cache:
// exactly <cache>/omarchy-broadcast/posters (posterDir) when the shell knows
// the cache root, else a directory ending in this; any other poster path is
// not loaded.
var POSTER_DIR_SUFFIX = "/omarchy-broadcast/posters"
// Past this many rows the setup dialog's Backgrounds list says "Showing N
// of M backgrounds" (each row is a decoded thumbnail).
var MEDIA_ROW_CAP = 64
var MEDIA_VIDEO_WORD = "video"
// The setup dialog's note over the folder path(s) of the user's own backgrounds
// (one folder, or the pictures and the videos folder).
var MEDIA_FOLDER_NOTE_TEXT = "Your own backgrounds are kept in this folder; files you copy there appear here:"
var MEDIA_FOLDERS_NOTE_TEXT = "Your own backgrounds are kept in these folders; files you copy there appear here:"
// Under the Backgrounds row of a video the CPU path cannot play: the note,
// the command (as the daemon prints it, a monospace text one can select)
// and the button that copies it. The command is at most this many characters
// (three paths' worth); a longer one is dropped, never cut.
var CONVERT_NOTE_TEXT = "Without an NVIDIA GPU this video shows as a still. To play it without one, convert it in a terminal; the copy lands in your videos folder:"
var CONVERT_COPY_LABEL = "Copy"
var CONVERT_COPIED_TEXT = "Copied"
var MEDIA_COMMAND_CAP = IMAGE_PATH_CAP * 3
var MEDIA_ADD_TITLE = "Add a background"
var GALLERY_TOOL = "omarchy-menu-images"
var CHOOSER_TOOL = "omarchy-file-select"
var BACKGROUND_ROW_LABEL = "Background"
var BACKGROUND_NONE_TEXT = "No background image"
var GALLERY_LABEL = "Gallery…"
var ADD_LABEL = "Add…"
var GALLERY_TOOLTIP = "Choose a background image from the gallery"
var ADD_TOOLTIP = "Add an image or video to your gallery and use it as the background"
var GALLERY_MISSING_TEXT = GALLERY_TOOL + " is not on PATH: update Omarchy to choose from the gallery."
var CHOOSER_MISSING_TEXT = CHOOSER_TOOL + " is not on PATH: update Omarchy to add a background."
var GALLERY_FAILED_TEXT = "The gallery could not open"
var CHOOSER_FAILED_TEXT = "The file chooser could not open"
var GALLERY_REFUSED_TEXT = "That file is not in the gallery; nothing was changed"
var GALLERY_NO_FOLDER_TEXT = "The gallery has no folder this plugin can use"
var MEDIA_INCOMPLETE_TEXT = "omarchy-broadcast printed an incomplete background gallery"
var AWAY_INCOMPLETE_TEXT = "omarchy-broadcast printed an incomplete away image gallery"
var CHOOSER_PATH_TEXT = "The file chooser returned a path this plugin cannot use"
var MEDIA_OVERLONG_TEXT = "omarchy-broadcast printed more than this plugin reads"
// A step still running after MEDIA_WATCHDOG_MS is stopped: just over
// omarchy-file-select's own 600-second answer timeout, so a picker or chooser
// that never answers cannot keep Gallery... and Add... faded for good.
var MEDIA_WATCHDOG_MS = 610000
var MEDIA_TIMEOUT_TEXT = "The picker did not answer in ten minutes; nothing was changed"
// Add...'s import (its last step, `media import background PATH --select`)
// runs under the same watchdog: converting an animated image or a long clip
// can take seconds to minutes, and ten minutes bounds it.
var MEDIA_IMPORT_TIMEOUT_TEXT = "Adding the background did not finish in ten minutes; this plugin stopped waiting for it"
// The hint while a flow runs (the two buttons are faded meanwhile).
var GALLERY_WAITING_TEXT = "Waiting for the gallery…"
var CHOOSER_WAITING_TEXT = "Waiting for the file chooser…"
var MEDIA_IMPORTING_TEXT = "Adding the background…"
var MEDIA_OLD_DAEMON = "The daemon needs updating for the background gallery (D-Bus interface revision 15)."
var MEDIA_EMPTY_TEXT = "You have not added any backgrounds yet. Add one with Add… in the panel's Effect tab."
// Gallery... / Choose... with nothing to pick (see mediaStepEnd): the gallery
// lists no item, or the picker would show none of them.
var GALLERY_NONE_TEXT = "No backgrounds yet. Add one with Add…"
var AWAY_GALLERY_NONE_TEXT = "No away images yet. Add one with Add…"
var GALLERY_NO_ROWS_TEXT = "The picker cannot show any of the gallery's backgrounds. Add another with Add…"
var AWAY_GALLERY_NO_ROWS_TEXT = "The picker cannot show any of the gallery's away images. Add another with Add…"
// mdi-image, the glyph the shell's own panels draw for an image file: the
// thumbnail's placeholder.
var GLYPH_IMAGE = String.fromCodePoint(0xF02E9)
// mdi-file-video, the glyph the shell's own panels draw for a video file:
// the badge on a video's thumbnail.
var GLYPH_FILE_VIDEO = String.fromCodePoint(0xF022B)
var MEDIA_REMOVE_LABEL = "Remove"
var MEDIA_CONFIRM_LABEL = "Confirm remove"

// The daemon has the background gallery: available, at MEDIA_REVISION or
// later. An unknown revision counts as no.
function mediaSupported(record) {
  return available(record) && record.interfaceRevision >= MEDIA_REVISION
}

// A path as an argv element and an Image source: an absolute path of at
// most PATH_CAP characters, without control characters (C0, C1, U+2028,
// U+2029), without an empty, "." or ".." segment and not ending in "/";
// else "". A path the producer clipped (it starts with an ellipsis) is no
// path at all.
function mediaPath(value) {
  if (typeof value !== "string" || value.length < 2 || value.length > PATH_CAP || value.charAt(0) !== "/") return ""
  if (/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(value)) return ""
  var parts = value.slice(1).split("/")
  for (var i = 0; i < parts.length; i++) if (parts[i] === "" || parts[i] === "." || parts[i] === "..") return ""
  return value
}

// A gallery directory: a mediaPath, trailing slashes dropped first; "" else
// (the root directory among them).
function mediaDir(value) {
  if (typeof value !== "string") return ""
  return mediaPath(value.replace(/\/+$/, ""))
}

// Whether `path` is a file directly in directory `dir` (both checked; the
// picker lists a directory's files, never a subdirectory's).
function mediaInDir(path, dir) {
  var p = mediaPath(path)
  var d = mediaDir(dir)
  if (p === "" || d === "" || p.indexOf(d + "/") !== 0) return false
  return p.slice(d.length + 1).indexOf("/") < 0
}

// A file's name without its directory and last extension, as a display
// copy (sanitize, MEDIA_LABEL_CAP); "" for no name.
function mediaStem(path) {
  if (typeof path !== "string" || path === "") return ""
  var name = path.slice(path.lastIndexOf("/") + 1)
  var dot = name.lastIndexOf(".")
  if (dot > 0) name = name.slice(0, dot)
  return sanitize(name, MEDIA_LABEL_CAP)
}

// The Image source of a checked path: file:// and the path, each segment
// percent-encoded (a "#", "?" or "%" in a file name is part of the name, not
// of the URL); "" for anything else.
function mediaImageSource(path) {
  var p = mediaPath(path)
  if (p === "") return ""
  return "file://" + p.split("/").map(function(seg) { return encodeURIComponent(seg) }).join("/")
}

// A width or height: an integer in 1..MEDIA_DIMENSION_MAX, else 0 (unknown).
function mediaDimension(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
    && value >= 1 && value <= MEDIA_DIMENSION_MAX ? value : 0
}

// A video's length in milliseconds: an integer in 1..MEDIA_DURATION_MAX_MS,
// else 0 (unknown).
function mediaDuration(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
    && value >= 1 && value <= MEDIA_DURATION_MAX_MS ? value : 0
}

// A length as M:SS (minutes not wrapped into hours), rounded to the second
// and at least 0:01; "" for an unknown one.
function mediaDurationText(ms) {
  var d = mediaDuration(ms)
  if (d === 0) return ""
  var secs = Math.max(1, Math.round(d / 1000))
  var s = secs % 60
  return Math.floor(secs / 60) + ":" + (s < 10 ? "0" : "") + s
}

// Whether a file's name is a video's (MEDIA_VIDEO_EXTENSIONS, any case).
function mediaVideoName(path) {
  if (typeof path !== "string") return false
  var name = path.slice(path.lastIndexOf("/") + 1)
  var dot = name.lastIndexOf(".")
  return dot > 0 && MEDIA_VIDEO_EXTENSIONS.indexOf(name.slice(dot + 1).toLowerCase()) >= 0
}

// The daemon's poster directory, as it derives it: <cache>/omarchy-broadcast/posters
// with <cache> $XDG_CACHE_HOME, else $HOME/.cache (a variable that is not
// an absolute path is ignored, as the XDG specification says); "" when
// neither is usable.
function posterDir(xdgCacheHome, home) {
  var cache = mediaDir(xdgCacheHome)
  if (cache === "") {
    var h = mediaDir(home)
    cache = h !== "" ? h + "/.cache" : ""
  }
  return cache !== "" ? mediaDir(cache + POSTER_DIR_SUFFIX) : ""
}

// A video's poster as a checked path: a mediaPath of a .jpg or .jpeg file
// directly in `dir` (posterDir) when it is given, else (no cache root
// known) directly in a directory ending in POSTER_DIR_SUFFIX; else ""
// (none: the placeholder glyph). Only a poster read from a `media_item`
// line is ever given here.
function mediaPoster(value, dir) {
  var p = mediaPath(value)
  if (p === "" || !/\.jpe?g$/i.test(p)) return ""
  var parent = p.slice(0, p.lastIndexOf("/"))
  var root = mediaDir(dir)
  if (root !== "") return parent === root ? p : ""
  return parent.length > POSTER_DIR_SUFFIX.length && parent.slice(-POSTER_DIR_SUFFIX.length) === POSTER_DIR_SUFFIX ? p : ""
}

// An item's size text: its size (W×H), then for a video "video" and its
// length (M:SS); each part only when known.
function mediaSizeText(w, h, video, durationMs) {
  var parts = []
  if (w > 0 && h > 0) parts.push(w + "\u00d7" + h)
  if (video) {
    var d = mediaDurationText(durationMs)
    parts.push(d !== "" ? MEDIA_VIDEO_WORD + ", " + d : MEDIA_VIDEO_WORD)
  }
  return parts.join(", ")
}

// A video's convert_command as a display and copy text: a string of 1 to
// MEDIA_COMMAND_CAP characters with no control character (a newline would run
// a second command when pasted) and no character that reorders or hides text
// (the sanitize set); "" for anything else, nothing is cut.
function mediaConvertCommand(value) {
  if (typeof value !== "string" || value.trim() === "" || value.length > MEDIA_COMMAND_CAP) return ""
  if (/[\u0000-\u001f\u007f-\u009f\u2028\u2029\u061c\u200b\u200e\u200f\u202a-\u202e\u2060-\u206f\ufeff]/.test(value)) return ""
  return value
}

// An item of a `media` line -> { path, label, bundled, width, height,
// video, durationMs, poster, sizeText, convertCommand }, or null: a mediaPath directly in
// its own directory (the bundled one for a bundled item, else the user's
// pictures folder or videos folder).
// `label` is the daemon's, sanitised, else the file's stem; `video` whether
// `media_type` is "video" (any other value reads as a still image);
// `poster` a video's checked poster path (mediaPoster over `posterDir`),
// "" for a still or none; `convertCommand` the checked convert_command of a
// video that is not `cpu_ready` (mediaConvertCommand), "" for any other item.
function mediaItem(o, bundledDir, userDir, videoDir, posterDir) {
  if (!isPlainObject(o)) return null
  var path = mediaPath(o.path)
  var bundled = o.bundled === true
  if (path === "") return null
  if (bundled ? !mediaInDir(path, bundledDir) : !mediaInDir(path, userDir) && !mediaInDir(path, videoDir)) return null
  var label = sanitize(o.label, MEDIA_LABEL_CAP)
  if (label === "") label = mediaStem(path)
  var w = mediaDimension(o.width)
  var hgt = mediaDimension(o.height)
  var video = o.media_type === MEDIA_TYPE_VIDEO
  var dur = video ? mediaDuration(o.duration_ms) : 0
  return { path: path, label: label, bundled: bundled, width: w, height: hgt, video: video, durationMs: dur,
           poster: video ? mediaPoster(o.poster, posterDir) : "", sizeText: mediaSizeText(w, hgt, video, dur),
           convertCommand: video && o.cpu_ready === false ? mediaConvertCommand(o.convert_command) : "" }
}

// A read gallery item's thumbnail: { source, video }, a still's own file or
// a video's poster (mediaPoster over `posterDir`; "" for the placeholder).
function mediaItemThumb(it, posterDir) {
  if (it.video !== true) return { source: mediaImageSource(it.path), video: false }
  return { source: mediaImageSource(mediaPoster(it.poster, posterDir)), video: true }
}

// A gallery file's thumbnail -> { source, video }: `source` the Image
// source (mediaImageSource: a still's own file, a video's poster; "" for
// the placeholder glyph), `video` whether it gets the video badge. `media`
// is a read gallery (readMedia), or null: an item of it with exactly this
// path is what decides; a path it does not list (or no gallery read) is a
// video by its name (mediaVideoName), with no poster known.
function mediaThumb(path, media) {
  var p = mediaPath(path)
  if (p === "") return { source: "", video: false }
  if (isPlainObject(media) && media.ok === true && Array.isArray(media.items)) {
    for (var i = 0; i < media.items.length && i < MEDIA_ITEM_CAP; i++) {
      var it = media.items[i]
      if (!isPlainObject(it) || it.path !== p) continue
      return mediaItemThumb(it, media.posterDir)
    }
  }
  if (mediaVideoName(p)) return { source: "", video: true }
  return { source: mediaImageSource(p), video: false }
}

// A gallery kind: AWAY_KIND, else MEDIA_KIND (the background gallery, the
// default of every function that takes one).
function mediaKindOf(kind) {
  return kind === AWAY_KIND ? AWAY_KIND : MEDIA_KIND
}

// One stdout line of `media list <kind> --json` (`kind`: mediaKindOf) -> { kind, ... }:
//   media        { header: { bundledDir, userDir, videoDir, count, truncated } }: the
//                header; a directory is "" when the producer left it out
//                (too long) or it is unusable (`video_dir` is also "" when
//                absent: an older daemon, the away gallery), and `count` is the number of
//                item lines that follow (0..MEDIA_ITEM_CAP)
//   item         { item }: a `media_item` line's object, checked against the
//                header's directories by readMedia (mediaItem)
//   error        { error }: an `error` line, for the screen
//   unsupported  { error }: a newer schema
//   invalid      anything else (not JSON, another v, type or kind, a count
//                that is no integer or over MEDIA_ITEM_CAP, a line over
//                LINE_CAP)
function parseMediaLine(text, kind) {
  if (typeof text !== "string" || text.length > LINE_CAP || text.trim() === "") return { kind: "invalid" }
  var m
  try { m = JSON.parse(text) } catch (e) { return { kind: "invalid" } }
  if (!isPlainObject(m)) return { kind: "invalid" }
  if (m.v !== SCHEMA_VERSION) {
    if (typeof m.v === "number" && isFinite(m.v) && Math.floor(m.v) === m.v && m.v > SCHEMA_VERSION)
      return { kind: "unsupported", error: "omarchy-broadcast prints output schema v" + m.v + "; this plugin reads v" + SCHEMA_VERSION + ". Update the plugin." }
    return { kind: "invalid" }
  }
  if (m.type === "error") return { kind: "error", error: setupErrorText(m) }
  if (m.kind !== mediaKindOf(kind)) return { kind: "invalid" }
  if (m.type === "media_item") return { kind: "item", item: m }
  if (m.type !== "media") return { kind: "invalid" }
  var n = m.items
  if (typeof n !== "number" || !isFinite(n) || Math.floor(n) !== n || n < 0 || n > MEDIA_ITEM_CAP) return { kind: "invalid" }
  if (typeof m.bundled_dir !== "string" || typeof m.user_dir !== "string") return { kind: "invalid" }
  return { kind: "media", header: { bundledDir: mediaDir(m.bundled_dir), userDir: mediaDir(m.user_dir),
                                    videoDir: mediaDir(m.video_dir), count: n, truncated: m.items_truncated === true } }
}

// The gallery read (SETUP_READS "media", and the Gallery... flow's first
// step; `kind` the gallery's, mediaKindOf): { ok: true, bundledDir, userDir, videoDir, items, bundledCount, truncated },
// or readFailed with the error line, the exit status or a fallback. The
// header comes first and exactly as many item lines as it counts follow it,
// nothing else: an item line before it, a second header, a line of another
// kind after it, or fewer or more items than counted, and the read is
// incomplete (MEDIA_INCOMPLETE_TEXT). An item outside its own directory
// (mediaItem; every item of a directory that is "") is dropped, and counts
// as truncation. The away gallery has no videos folder: its `videoDir` is "".
function readMedia(lines, code, stderrText, kind, posterDir) {
  var away = mediaKindOf(kind) === AWAY_KIND
  var incomplete = away ? AWAY_INCOMPLETE_TEXT : MEDIA_INCOMPLETE_TEXT
  var src = Array.isArray(lines) ? lines : []
  var error = ""
  var header = null
  var raw = []
  for (var i = 0; i < src.length && i < MEDIA_ITEM_CAP + 2; i++) {
    var p = parseMediaLine(src[i], kind)
    if (p.kind === "unsupported") return readFailed(p.error)
    if (header === null) {
      if (p.kind === "error") error = p.error
      else if (p.kind === "media") header = p.header
      else if (p.kind === "item") return readFailed(incomplete)
      continue
    }
    if (p.kind === "error") return readFailed(p.error)
    if (p.kind !== "item" || raw.length >= header.count) return readFailed(incomplete)
    raw.push(p.item)
  }
  if (header === null) return readFailure({ error: error }, code, stderrText, away ? "omarchy-broadcast printed no away image gallery" : "omarchy-broadcast printed no background gallery")
  if (src.length > MEDIA_ITEM_CAP + 2 || raw.length !== header.count) return readFailed(incomplete)
  var out = { ok: true, bundledDir: header.bundledDir, userDir: header.userDir, videoDir: away ? "" : header.videoDir,
              posterDir: mediaDir(posterDir), items: [], bundledCount: 0, truncated: header.truncated }
  for (var k = 0; k < raw.length; k++) {
    var it = mediaItem(raw[k], out.bundledDir, out.userDir, out.videoDir, out.posterDir)
    if (it === null) { out.truncated = true; continue }
    if (it.bundled) out.bundledCount++
    out.items.push(it)
  }
  return out
}

// ---- argv (fixed words; each path checked again with mediaPath)

function mediaListArgv(cli, kind) {
  return cliUsable(cli) ? [cli, "media", "list", mediaKindOf(kind), "--json"] : null
}

// Selects `path` as the replacement background (and the effect with it).
function backgroundArgv(cli, path) {
  var p = mediaPath(path)
  return cliUsable(cli) && p !== "" ? [cli, "effect", BACKGROUND_REPLACE, "--image", p] : null
}

// Copies `path` into the user's gallery of `kind` (mediaKindOf), checks it
// and selects it (the background; the away image: `effect.fallback_image`).
function mediaImportArgv(cli, path, kind) {
  var p = mediaPath(path)
  return cliUsable(cli) && p !== "" ? [cli, "media", "import", mediaKindOf(kind), p, "--select"] : null
}

// The away image set to `path` (a checked path), or cleared ("": the
// daemon's empty value); after `--`, as every config write.
function awayImageArgv(cli, path) {
  if (!cliUsable(cli) || typeof path !== "string") return null
  var p = path === "" ? "" : mediaPath(path)
  return path === "" || p !== "" ? [cli, "config", "set", "--", AWAY_IMAGE_KEY, p] : null
}

function mediaRemoveArgv(cli, path) {
  var p = mediaPath(path)
  return cliUsable(cli) && p !== "" ? [cli, "media", "remove", p] : null
}

// The shell's image picker over the gallery's directories (the bundled, the
// user's pictures and videos folders, those the producer did not leave out), the image in force preselected when
// there is one.
function galleryArgv(tool, media, current) {
  var dirs = galleryDirs(media)
  if (!cliUsable(tool) || dirs.length === 0) return null
  var argv = [tool, "--show-labels"]
  var sel = mediaPath(current)
  if (sel !== "") argv.push("--selected", sel)
  return argv.concat(dirs)
}

// A read gallery's directories the picker is given, in the order bundled,
// pictures, videos: a directory the producer left out ("") is not offered;
// with none (or no gallery read), there is nothing to pick from: [].
function galleryDirs(media) {
  if (!isPlainObject(media) || media.ok !== true) return []
  return [mediaDir(media.bundledDir), mediaDir(media.userDir), mediaDir(media.videoDir)].filter(function(d) { return d !== "" })
}

// A read gallery's own (not bundled) folders, pictures first: the ones the
// producer did not leave out.
function galleryOwnDirs(media) {
  if (!isPlainObject(media)) return []
  return [mediaDir(media.userDir), mediaDir(media.videoDir)].filter(function(d) { return d !== "" })
}

// Whether `path` is a file directly in one of the read gallery's own folders.
function mediaInOwnDirs(path, media) {
  var dirs = galleryOwnDirs(media)
  for (var i = 0; i < dirs.length; i++) if (mediaInDir(path, dirs[i])) return true
  return false
}

// The picker's rows, as it would open them (step "rows"): the same
// directories, `--print-rows` printing `image<TAB>thumbnail` lines and
// exiting before the shell's picker opens.
function galleryRowsArgv(tool, media) {
  var dirs = galleryDirs(media)
  return !cliUsable(tool) || dirs.length === 0 ? null : [tool, "--print-rows", "--show-labels"].concat(dirs)
}

// Whether the rows the picker printed (`image<TAB>thumbnail`, one per line;
// an empty line when it has none) hold at least one with a thumbnail whose
// image is a file directly in one of the gallery's directories.
function galleryHasRow(lines, media) {
  var dirs = galleryDirs(media)
  if (!Array.isArray(lines)) return false
  for (var i = 0; i < lines.length && i < MEDIA_ITEM_CAP + 2; i++) {
    var line = lines[i]
    if (typeof line !== "string" || line.length > LINE_CAP) continue
    var tab = line.indexOf("\t")
    if (tab < 0 || tab === line.length - 1) continue
    var image = line.slice(0, tab)
    for (var d = 0; d < dirs.length; d++) if (mediaInDir(image, dirs[d])) return true
  }
  return false
}

function fileSelectArgv(tool, kind) {
  var away = mediaKindOf(kind) === AWAY_KIND
  return cliUsable(tool) ? [tool, "--title", away ? AWAY_ADD_TITLE : MEDIA_ADD_TITLE,
                            "--extensions", away ? AWAY_EXTENSIONS : MEDIA_EXTENSIONS] : null
}

// ---- the two tools, looked up on PATH (as the resolver looks up the CLI)

// Prints "<name> <path>" for each tool found; a path holding a newline is
// never printed. The names are its positional arguments (toolsArgv): nothing
// is spliced into the script's text.
var TOOLS_SCRIPT = ""
  + "nl='\n'; "
  + "for t do "
  + "p=$(command -v \"$t\" 2>/dev/null) && case $p in *\"$nl\"*) ;; /*) printf '%s %s\\n' \"$t\" \"$p\";; esac; "
  + "done; exit 0"

// Always an argv: the script, its $0, then the two names as $1 and $2.
function toolsArgv() {
  return ["sh", "-c", TOOLS_SCRIPT, "omarchy-broadcast-tools", GALLERY_TOOL, CHOOSER_TOOL]
}

// Not looked up yet: neither offered.
function emptyTools() {
  return { known: false, gallery: "", chooser: "" }
}

// The probe's stdout lines -> { known: true, gallery, chooser }: each an
// absolute path, else "" (not found).
function toolsFromLines(lines) {
  var out = { known: true, gallery: "", chooser: "" }
  var src = Array.isArray(lines) ? lines : []
  for (var i = 0; i < src.length && i < 4; i++) {
    var line = typeof src[i] === "string" ? src[i] : ""
    var sp = line.indexOf(" ")
    if (sp < 0) continue
    var name = line.slice(0, sp)
    var path = parseResolverLine(line.slice(sp + 1))
    if (name === GALLERY_TOOL && out.gallery === "") out.gallery = path
    else if (name === CHOOSER_TOOL && out.chooser === "") out.chooser = path
  }
  return out
}

// ---- the Gallery... and Add... flows, one step at a time
//
// A flow is { kind: "gallery" | "add", step, media, path, gallery }:
// "gallery" first lists the gallery (step "list", the CLI), then asks the
// picker tool for the rows it would show over its directories (step
// "rows", `--print-rows`), then runs the picker itself (step "pick"), only
// when it has a row; "add" runs the file
// chooser (step "pick") and, for a background, then imports the chosen
// file (step "import", the CLI, `path` the file): converting an animated
// image or a video can take a while, and as a step it runs beside the
// command queue (an on/off never waits behind it), under the flow's
// watchdog, with the panel open again and saying so. `gallery` is the gallery's kind (mediaKindOf: the background's
// when absent, the panel's; AWAY_KIND for the setup dialog's away image). A
// step's end gives { flow, intent, error }: the next step, else the command
// intent to queue (a background selection or an import; for the away image
// setup intents: `away-image` and `away-import`, the dialog's writes), else
// the error line ("" for none: a cancel, or an import that went through:
// `imported` true), the panel's or, for the away image, the dialog's.

// The gallery kind of a flow (mediaKindOf of its `gallery`).
function flowGallery(flow) {
  return isPlainObject(flow) ? mediaKindOf(flow.gallery) : MEDIA_KIND
}

// The image in force a flow's picker preselects: the background's raw path,
// or the away image's (the read configuration's row).
function mediaCurrent(flow, record, config) {
  if (flowGallery(flow) === AWAY_KIND) return awayImagePath(config)
  return isPlainObject(record) && typeof record.backgroundImagePath === "string" ? record.backgroundImagePath : ""
}

// The argv of a flow's current step, or null. The import runs only while
// `record` shows the Background row (backgroundRowShown).
function mediaStepArgv(flow, cli, tools, current, record) {
  if (!isPlainObject(flow)) return null
  var t = isPlainObject(tools) ? tools : emptyTools()
  if (flow.kind === "add" && flow.step === "import")
    return flowGallery(flow) === MEDIA_KIND && backgroundRowShown(record) ? mediaImportArgv(cli, flow.path) : null
  if (flow.kind === "gallery" && flow.step === "list") return t.gallery !== "" ? mediaListArgv(cli, flowGallery(flow)) : null
  if (flow.kind === "gallery" && flow.step === "rows") return galleryRowsArgv(t.gallery, flow.media)
  if (flow.kind === "gallery" && flow.step === "pick") return galleryArgv(t.gallery, flow.media, current)
  if (flow.kind === "add" && flow.step === "pick") return fileSelectArgv(t.chooser, flowGallery(flow))
  return null
}

// The picker's answer -> the path, only when it is one line and exactly the
// path of an item of the gallery just read; else "". The picker lists files
// the daemon skipped (other formats, links), and none of them is ever
// selected.
function galleryChoice(firstLine, lineCount, media) {
  if (lineCount !== 1 || !isPlainObject(media) || media.ok !== true || !Array.isArray(media.items)) return ""
  var p = mediaPath(firstLine)
  if (p === "") return ""
  for (var i = 0; i < media.items.length && i < MEDIA_ITEM_CAP; i++) if (media.items[i].path === p) return p
  return ""
}

// A step's end -> { flow, intent, error, imported }. `result`: { started,
// code, first, lines, list, rejected, timedOut, stderr, posterDir } (whether the process ran, its exit status, its first
// stdout line, how many lines it printed, every line of a list step,
// whether a line was over the cap, whether the watchdog stopped it, its
// first stderr line, the poster directory: posterDir).
function mediaStepEnd(flow, result) {
  var out = { flow: null, intent: null, error: "", imported: false }
  if (!isPlainObject(flow) || !isPlainObject(result)) return out
  var r = result
  var lines = typeof r.lines === "number" ? r.lines : 0
  var first = typeof r.first === "string" ? r.first : ""
  var detail = sanitize(typeof r.stderr === "string" ? r.stderr.slice(0, STDERR_CAP) : "", DETAIL_CAP)
  var gallery = flowGallery(flow)
  var away = gallery === AWAY_KIND
  if (r.timedOut === true) { out.error = flow.step === "import" ? MEDIA_IMPORT_TIMEOUT_TEXT : MEDIA_TIMEOUT_TEXT; return out }
  if (flow.kind === "gallery" && flow.step === "list") {
    if (r.started !== true) { out.error = CLI_MISSING_TEXT; return out }
    if (r.rejected === true) { out.error = MEDIA_OVERLONG_TEXT; return out }
    var media = readMedia(Array.isArray(r.list) ? r.list : [], r.code, r.stderr, gallery, r.posterDir)
    if (media.ok !== true) { out.error = media.error; return out }
    if (galleryDirs(media).length === 0) { out.error = GALLERY_NO_FOLDER_TEXT; return out }
    // Nothing listed: nothing to pick, and the picker is not run (see "rows").
    if (media.items.length === 0) { out.error = away ? AWAY_GALLERY_NONE_TEXT : GALLERY_NONE_TEXT; return out }
    out.flow = { kind: "gallery", step: "rows", media: media, gallery: gallery }
    return out
  }
  if (flow.kind === "gallery" && flow.step === "rows") {
    if (r.started !== true || r.code !== 0) {
      out.error = GALLERY_FAILED_TEXT + (r.started === true && detail !== "" ? ": " + detail : "")
      return out
    }
    // Never run the picker without a row to show. When omarchy-menu-images
    // builds no rows (it drops a row whose thumbnail fails: a damaged
    // picture, a video its thumbnailer rejects, a lock that timed out),
    // Omarchy's picker falls back to the desktop theme's backgrounds, which
    // must never be shown or chosen from here: the gallery and the desktop
    // wallpapers are unrelated.
    if (!galleryHasRow(r.list, flow.media)) { out.error = away ? AWAY_GALLERY_NO_ROWS_TEXT : GALLERY_NO_ROWS_TEXT; return out }
    out.flow = { kind: "gallery", step: "pick", media: flow.media, gallery: gallery }
    return out
  }
  if (flow.kind === "gallery" && flow.step === "pick") {
    if (r.started !== true || r.code !== 0) {
      out.error = GALLERY_FAILED_TEXT + (r.started === true && detail !== "" ? ": " + detail : "")
      return out
    }
    // Nothing printed: the picker was closed without a choice.
    if (r.rejected !== true && (lines === 0 || (lines === 1 && first === ""))) return out
    var chosen = r.rejected === true ? "" : galleryChoice(first, lines, flow.media)
    if (chosen === "") { out.error = GALLERY_REFUSED_TEXT; return out }
    out.intent = away ? { verb: "setup", op: "away-image", path: chosen } : { verb: "background", path: chosen }
    return out
  }
  if (flow.kind === "add" && flow.step === "pick") {
    // 1: nothing picked (a decision, not an error); 2 or anything else: the
    // chooser did not run.
    if (r.started === true && r.code === 1) return out
    if (r.started !== true || r.code !== 0) { out.error = CHOOSER_FAILED_TEXT; return out }
    var picked = lines === 1 && r.rejected !== true ? mediaPath(first) : ""
    if (picked === "") { out.error = lines === 0 ? "" : CHOOSER_PATH_TEXT; return out }
    if (away) out.intent = { verb: "setup", op: "away-import", path: picked }
    else out.flow = { kind: "add", step: "import", path: picked, gallery: gallery }
    return out
  }
  if (flow.kind === "add" && flow.step === "import") {
    // Its stdout (the stored path) is not read: the watch reports the
    // background it selected.
    if (r.started !== true) { out.error = CLI_MISSING_TEXT; return out }
    if (r.code !== 0) { out.error = commandFailureText(r.code, typeof r.stderr === "string" ? r.stderr : "", ""); return out }
    out.imported = true
    return out
  }
  return out
}

// ---- the Effect tab's Background row

// The daemon's background mode setting offers the replacement background.
function backgroundOffered(record) {
  var row = effectModeRow(record)
  return !!row && optionIndex(row.options, BACKGROUND_REPLACE) >= 0
}

// Whether the Effect tab draws the Background row (a keyboard stop): the
// daemon has the gallery and offers the replacement background.
function backgroundRowShown(record) {
  return mediaSupported(record) && backgroundOffered(record)
}

// Whether the Background row is drawn now: it can be (backgroundRowShown)
// and the background effect's choice shown is the replacement background
// (the image is what that choice uses; the draft counts, so the row comes
// with the click).
function backgroundRowDrawn(record, drafts) {
  if (!backgroundRowShown(record)) return false
  var mode = effectModeView(record, drafts)
  return mode.visible && mode.value === BACKGROUND_REPLACE
}

// The Background row, exactly as drawn (only while backgroundRowDrawn):
//   { visible, label, source, video, buttons: [{ label, enabled, tooltip }] }
// `source` and `video` are the thumbnail's (mediaThumb of the raw path over
// `media`, the last background gallery read, or null: a still's own file,
// a listed video's poster, "" for the placeholder; `video` the badge);
// `label` the image's file stem (or the display copy's, when
// the raw path is not usable), else BACKGROUND_NONE_TEXT. Gallery... is
// button 0, Add... button 1; each is disabled, its tooltip saying why, while
// its tool is not on PATH (`tools`, the Daemon's probe), and both while a
// flow runs (`busy`).
function backgroundRowView(record, tools, busy, media, drafts) {
  var out = { visible: false, label: "", source: "", video: false, buttons: [] }
  if (!backgroundRowDrawn(record, drafts)) return out
  var t = isPlainObject(tools) ? tools : emptyTools()
  out.visible = true
  var thumb = mediaThumb(record.backgroundImagePath, media)
  out.source = thumb.source
  out.video = thumb.video
  var label = record.backgroundImagePath !== "" ? mediaStem(record.backgroundImagePath) : mediaStem(record.backgroundImage)
  out.label = label !== "" ? label : BACKGROUND_NONE_TEXT
  var gallery = t.gallery !== ""
  var chooser = t.chooser !== ""
  out.buttons.push({ label: GALLERY_LABEL, enabled: gallery && busy !== true,
                     tooltip: gallery || !t.known ? GALLERY_TOOLTIP : GALLERY_MISSING_TEXT, missing: t.known && !gallery })
  out.buttons.push({ label: ADD_LABEL, enabled: chooser && busy !== true,
                     tooltip: chooser || !t.known ? ADD_TOOLTIP : CHOOSER_MISSING_TEXT, missing: t.known && !chooser })
  return out
}

// The hint under the Background row: while a flow runs (`flow`, the
// Daemon's mediaFlow) what it waits for (the import: MEDIA_IMPORTING_TEXT),
// else which tool is missing, else "".
function backgroundHint(view, flow) {
  if (!isPlainObject(view) || !view.visible) return ""
  if (isPlainObject(flow)) {
    if (flow.kind === "add" && flow.step === "import") return MEDIA_IMPORTING_TEXT
    return flow.kind === "add" ? CHOOSER_WAITING_TEXT : GALLERY_WAITING_TEXT
  }
  var out = []
  for (var i = 0; i < view.buttons.length; i++) if (view.buttons[i].missing) out.push(view.buttons[i].tooltip)
  return out.join(" ")
}

// ---- the setup dialog's Backgrounds section

// { hint, bundledText, folderText, folderPath, videoFolderPath, rows, emptyText, truncation, busyText }; a row (one
// of the user's own items, at most MEDIA_ROW_CAP of them; past it
// `truncation` says "Showing N of M backgrounds"): { path, label, sizeText,
// source, video, confirming, index, convertCommand } (`source` and `video` its thumbnail's,
// mediaItemThumb of the first item of its path, the gallery indexed once).
// `folderText` says that the user's own backgrounds are kept in a folder (or,
// with a videos folder too, in these folders) and `folderPath` and
// `videoFolderPath` which (the listed `userDir` and `videoDir`, checked paths
// shown as plain text), "" while unknown. `convertCommand` is the command that
// converts a video the CPU path cannot play ("" for none, and always below
// VIDEO_CONVERT_REVISION): the dialog shows it, with CONVERT_NOTE_TEXT, under
// the row.
// `emptyText` is said under the bundled count when the user has none. `confirming` is the
// path whose Remove was pressed once (the second press removes it).
// `busyText` is MEDIA_IMPORTING_TEXT while `importing` (the panel's Add...
// imports a file; the section is read again when it ends).
function mediaSectionView(setup, record, confirming, importing) {
  var out = { hint: "", bundledText: "", folderText: "", folderPath: "", videoFolderPath: "", rows: [], emptyText: "", truncation: "", busyText: "" }
  var gate = setupGate(record)
  if (!gate.modules) { out.hint = gate.text; return out }
  if (!mediaSupported(record)) { out.hint = MEDIA_OLD_DAEMON; return out }
  var media = isPlainObject(setup) ? setup.media : null
  out.hint = readHint(media)
  if (out.hint !== "") return out
  var n = media.bundledCount
  out.bundledText = n === 1 ? "1 bundled background" : n + " bundled backgrounds"
  var folder = mediaDir(media.userDir)
  var videoFolder = mediaDir(media.videoDir)
  if (folder !== "" && videoFolder !== "") {
    out.folderText = MEDIA_FOLDERS_NOTE_TEXT
    out.folderPath = folder
    out.videoFolderPath = videoFolder
  } else if (folder !== "" || videoFolder !== "") {
    out.folderText = MEDIA_FOLDER_NOTE_TEXT
    if (folder !== "") out.folderPath = folder
    else out.folderPath = videoFolder
  }
  var convert = convertSupported(record)
  if (importing === true) out.busyText = MEDIA_IMPORTING_TEXT
  // The first item of each path (what mediaThumb would find), indexed once.
  var byPath = {}
  for (var j = 0; j < media.items.length && j < MEDIA_ITEM_CAP; j++) {
    var e = media.items[j]
    if (isPlainObject(e) && !Object.prototype.hasOwnProperty.call(byPath, e.path)) byPath[e.path] = e
  }
  var total = 0
  for (var i = 0; i < media.items.length && i < MEDIA_ITEM_CAP; i++) {
    var it = media.items[i]
    if (it.bundled || !mediaInOwnDirs(it.path, media)) continue
    total++
    if (out.rows.length >= MEDIA_ROW_CAP) continue
    var thumb = mediaItemThumb(byPath[it.path], media.posterDir)
    out.rows.push({ path: it.path, label: it.label, sizeText: it.sizeText, source: thumb.source, video: thumb.video,
                    confirming: typeof confirming === "string" && confirming !== "" && confirming === it.path,
                    index: out.rows.length, convertCommand: convert ? it.convertCommand : "" })
  }
  if (out.rows.length === 0) out.emptyText = MEDIA_EMPTY_TEXT
  var notes = []
  var showing = showingText(out.rows.length, total, "backgrounds")
  if (showing !== "") notes.push(showing)
  if (media.truncated) notes.push("The daemon lists more backgrounds than are shown.")
  out.truncation = notes.join(". ")
  return out
}

// The daemon says which videos the CPU path cannot play and how to convert
// them: available, at VIDEO_CONVERT_REVISION or later.
function convertSupported(record) {
  return available(record) && record.interfaceRevision >= VIDEO_CONVERT_REVISION
}

// A press of Remove on the row of `path`, given the path pressed before
// (`confirming`): { confirming, remove }. The first press asks for
// confirmation; the second on the same row removes it.
function mediaRemovePress(confirming, path) {
  var p = mediaPath(path)
  if (p === "") return { confirming: "", remove: false }
  if (confirming === p) return { confirming: "", remove: true }
  return { confirming: p, remove: false }
}

// A user item of the read gallery by its path (what a Remove press may
// name), else null.
function mediaUserItem(media, path) {
  if (!isPlainObject(media) || media.ok !== true || !Array.isArray(media.items)) return null
  for (var i = 0; i < media.items.length && i < MEDIA_ITEM_CAP; i++) {
    var it = media.items[i]
    if (it.path === path && !it.bundled && mediaInOwnDirs(it.path, media)) return it
  }
  return null
}

// ---------------------------------------------------------------- the away image
//
// Interface revision PLACEHOLDER_REVISION. One image, two switches: the
// image (`effect.fallback_image`, the "Away image" path row of the read
// configuration) hides the camera when an effect cannot run
// (`effect.on_failure`; from PRIVACY_REVISION the two rows `effect.privacy`
// and `effect.privacy_mode`, with "Away image" as one of its modes) and,
// with `output.placeholder` on "Away image",
// stands in for every frame without a camera picture (off, starting, an
// error, a stall). Both switches are enum rows the setup dialog draws
// generically; the image's row is drawn as a picker: its thumbnail, its
// name, Choose... (the shell's image picker over the `away` gallery's two
// directories; the pick must be an item of the gallery just read, then
// `config set -- effect.fallback_image PATH`), Add... (the file chooser,
// then `media import away PATH --select`) and Clear (`config set --
// effect.fallback_image ""`). The panel's watch snapshot carries no config
// value, so the Effect tab's Away image row offers one Setup... button
// that opens the dialog at that row. The setup dialog draws the picker row
// directly under `output.placeholder` (CONFIG_ROW_FOLLOWS).

var AWAY_IMAGE_KEY = "effect.fallback_image"
var AWAY_ADD_TITLE = "Add an away image"
var AWAY_NONE_TEXT = "No away image"
var CHOOSE_LABEL = "Choose…"
var CLEAR_LABEL = "Clear"
var AWAY_CHOOSE_TOOLTIP = "Choose the away image from the gallery"
var AWAY_ADD_TOOLTIP = "Add an image to your away images and use it"
var AWAY_CLEAR_TOOLTIP = "Use no away image: black instead"
var AWAY_CHOOSER_MISSING_TEXT = CHOOSER_TOOL + " is not on PATH: update Omarchy to add an away image."
var AWAY_ROW_LABEL = "Away image"
var AWAY_BUTTON_LABEL = "Setup…"
var AWAY_BUTTON_TOOLTIP = "The image shown instead of the camera: choose it in the setup"
var AWAY_UNSET_TEXT = "No away image chosen: black is shown"
// The two switches that show the away image, and their value for it.
var PLACEHOLDER_KEY = "output.placeholder"
var ON_FAILURE_KEY = "effect.on_failure"
var AWAY_SWITCH_VALUE = "image"
// From PRIVACY_REVISION (obc-ipc INTERFACE_REVISION 21) `effect.on_failure`
// is replaced in the schema by a switch and its mode: `effect.privacy` (hide
// the camera when an effect cannot run) and `effect.privacy_mode` (black,
// away or freeze; greyed with a reason while the switch is off). The
// daemon still takes a write to the old key, but this plugin writes the new
// ones. A daemon below that revision has only the old key.
var PRIVACY_REVISION = 21
var PRIVACY_KEY = "effect.privacy"
var PRIVACY_MODE_KEY = "effect.privacy_mode"
var PRIVACY_AWAY_VALUE = "away"

// The daemon has the away image: available, at PLACEHOLDER_REVISION or
// later. An unknown revision counts as no.
function placeholderSupported(record) {
  return available(record) && record.interfaceRevision >= PLACEHOLDER_REVISION
}

// The away image's raw path in the read configuration (the row's rawPath),
// else "".
function awayImagePath(config) {
  var row = findConfigRow(config, AWAY_IMAGE_KEY)
  return row && row.type === "path" ? row.rawPath : ""
}

// The dialog's Away image row, exactly as drawn:
//   { visible, source, label, set, note, buttons: [{ label, enabled, tooltip, missing }] }
// visible only while the daemon is at PLACEHOLDER_REVISION and its row is
// one it takes a write for (configWidget "away"; an overridden or greyed
// row stays read-only text with its reason). `source` is the thumbnail's
// (mediaImageSource of the raw path, "" for the placeholder glyph), `label`
// the image's file stem (or the display copy's), else AWAY_NONE_TEXT;
// `set` whether an image is set; `note` AWAY_UNSET_TEXT while none is and
// a switch that shows it (`output.placeholder` is on "image"; with
// `effect.on_failure` on "image" below PRIVACY_REVISION, else `effect.privacy`
// on and `effect.privacy_mode` on "away") is on (the daemon shows black
// then), else "". Choose... is button 0, Add... 1, Clear 2;
// Choose... and Add... are disabled, the tooltip saying why, while their
// tool is not on PATH (`tools`), Clear while no image is set, and all three
// while `busy` (a flow runs or a setup write is in flight).
function awayImageView(config, record, tools, busy) {
  var out = { visible: false, source: "", label: "", set: false, note: "", buttons: [] }
  var row = placeholderSupported(record) ? findConfigRow(config, AWAY_IMAGE_KEY) : null
  if (!row || configWidget(row, true) !== "away") return out
  var t = isPlainObject(tools) ? tools : emptyTools()
  out.visible = true
  out.set = typeof row.value === "string" && row.value !== ""
  out.source = mediaImageSource(row.rawPath)
  var label = row.rawPath !== "" ? mediaStem(row.rawPath) : (out.set ? mediaStem(row.value) : "")
  out.label = label !== "" ? label : AWAY_NONE_TEXT
  if (!out.set && (awaySwitchOn(config, PLACEHOLDER_KEY) || privacyShowsAway(config, record))) out.note = AWAY_UNSET_TEXT
  var gallery = t.gallery !== ""
  var chooser = t.chooser !== ""
  out.buttons.push({ label: CHOOSE_LABEL, enabled: gallery && busy !== true,
                     tooltip: gallery || !t.known ? AWAY_CHOOSE_TOOLTIP : GALLERY_MISSING_TEXT, missing: t.known && !gallery })
  out.buttons.push({ label: ADD_LABEL, enabled: chooser && busy !== true,
                     tooltip: chooser || !t.known ? AWAY_ADD_TOOLTIP : AWAY_CHOOSER_MISSING_TEXT, missing: t.known && !chooser })
  out.buttons.push({ label: CLEAR_LABEL, enabled: out.set && busy !== true, tooltip: AWAY_CLEAR_TOOLTIP, missing: false })
  return out
}

// Whether the enum row `id` of the read configuration is on the away image.
function awaySwitchOn(config, id) {
  return awayModeIs(config, id, AWAY_SWITCH_VALUE)
}

// The daemon replaces `effect.on_failure` by `effect.privacy` and
// `effect.privacy_mode`: available, at PRIVACY_REVISION or later. An unknown
// revision counts as no (the old key).
function privacySupported(record) {
  return available(record) && record.interfaceRevision >= PRIVACY_REVISION
}

// Whether the privacy rule hides the camera behind the away image: from
// PRIVACY_REVISION `effect.privacy` is on and `effect.privacy_mode` is
// "away"; below it `effect.on_failure` is "image".
function privacyShowsAway(config, record) {
  if (!privacySupported(record)) return awaySwitchOn(config, ON_FAILURE_KEY)
  var on = findConfigRow(config, PRIVACY_KEY)
  return on !== null && on.type === "bool" && on.value === true
    && awayModeIs(config, PRIVACY_MODE_KEY, PRIVACY_AWAY_VALUE)
}

// Whether the enum row `id` of the read configuration is on `value`.
function awayModeIs(config, id, value) {
  var row = findConfigRow(config, id)
  return row !== null && row.type === "enum" && row.value === value
}

// The button of the Away image row a Left/Right press lands on, from
// `current`: the nearest enabled one that way (`direction` 0: `current`
// while enabled, else the first enabled one); -1 when there is none.
function awayButtonAfter(view, current, direction) {
  var buttons = isPlainObject(view) && Array.isArray(view.buttons) ? view.buttons : []
  var on = function(i) { return i >= 0 && i < buttons.length && isPlainObject(buttons[i]) && buttons[i].enabled === true }
  if (direction > 0 || direction < 0) {
    var step = direction > 0 ? 1 : -1
    for (var i = current + step; i >= 0 && i < buttons.length; i += step) if (on(i)) return i
    return -1
  }
  if (on(current)) return current
  for (var j = 0; j < buttons.length; j++) if (on(j)) return j
  return -1
}

// The hint under the dialog's Away image row: which tool is not on PATH,
// else "" (the dialog is hidden while a flow runs).
function awayImageHint(view) {
  if (!isPlainObject(view) || !view.visible) return ""
  var out = []
  for (var i = 0; i < view.buttons.length; i++) if (view.buttons[i].missing) out.push(view.buttons[i].tooltip)
  return out.join(" ")
}
