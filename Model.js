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
// The largest interface revision the producer can print (a u32).
var REVISION_MAX = 4294967295

// Material Design glyphs from the bar's Nerd Font (checked by rendering them).
var GLYPH_WEBCAM = String.fromCodePoint(0xF05A0)
var GLYPH_WEBCAM_OFF = String.fromCodePoint(0xF1737)
var GLYPH_VIDEO = String.fromCodePoint(0xF0567)
var GLYPH_VIDEO_OUTLINE = String.fromCodePoint(0xF0BDC)
var GLYPH_VIDEO_OFF_OUTLINE = String.fromCodePoint(0xF0BDB)
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
    mic: null
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
  // The running daemon's interface revision, on the same lines: a new CLI may
  // still be talking to a daemon started before the upgrade.
  r.interfaceRevision = interfaceRevision(m.interface_revision)
  // No stats line arrives outside `active`; clear the figures as it is left.
  if (r.state !== "active") r.stats = null
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
// stats, mic, settings_group (a part of a set kept), settings (a set committed),
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

// state -> { glyph, colorRole: foreground | accent | urgent, dimmed }.
// starting and active share the accent and differ by glyph (outline vs
// filled); off and unavailable are both dimmed and differ by glyph. A
// non-empty `error` outside the `error` state only shows in the tooltip and
// the panel. A `warning` never changes the visual: it follows `state` only.
function visualFor(key) {
  switch (key) {
  case "off": return { key: key, glyph: GLYPH_WEBCAM_OFF, colorRole: "foreground", dimmed: true }
  case "idle": return { key: key, glyph: GLYPH_WEBCAM, colorRole: "foreground", dimmed: false }
  case "starting": return { key: key, glyph: GLYPH_VIDEO_OUTLINE, colorRole: "accent", dimmed: false }
  case "active": return { key: key, glyph: GLYPH_VIDEO, colorRole: "accent", dimmed: false }
  case "error": return { key: key, glyph: GLYPH_ALERT, colorRole: "urgent", dimmed: false }
  default: return { key: "unavailable", glyph: GLYPH_VIDEO_OFF_OUTLINE, colorRole: "foreground", dimmed: true }
  }
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
             hint: "Start it with:", commandText: "systemctl --user start omarchy-broadcastd" }
  case "unreachable":
    return { title: "omarchy-broadcastd is not answering", path: "", detail: detail,
             hint: "Retrying every 2 s. Its log:", commandText: "journalctl --user -u omarchy-broadcastd" }
  case "cli-missing":
    // The text ends on the path it searched or was given, when it names one.
    var parts = splitTrailingPath(detail !== "" ? detail : CLI_MISSING_TEXT)
    return { title: parts.text, path: parts.path, detail: "",
             hint: "Install it:\n"
               + "Arch package: /usr/bin\n"
               + "install-user.sh: ~/.local/bin\n"
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
// faded with the daemon's reason under it.
function effectModeView(record, drafts) {
  var out = { visible: false, hint: "", id: "", enabled: false, reason: "", options: [] }
  if (!available(record)) return out
  if (!moduleEffects(record)) { out.hint = DAEMON_NO_EFFECTS; return out }
  if (!settingsSupported(record)) { out.hint = settingsMissingText(record); return out }
  if (!isPlainObject(record.settings)) return out
  var row = effectModeRow(record)
  if (!row) { out.hint = NO_BACKGROUND_TEXT; return out }
  var value = shownSettingValue(row, drafts)
  out.visible = true
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
// with no image.
function effectRows(record) {
  if (!moduleEffects(record) || !hasBackgroundImage(record)) return []
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

function nextArgv(cli) {
  return cliUsable(cli) ? [cli, "camera", "next"] : null
}

function canNext(record) {
  return available(record) && record.cameras.length >= 2
}

// A control request is kept as an intent, { verb, on, id, effect, value, camera },
// and turned into an argv when it runs: with the CLI path and the availability of that moment,
// so a request queued behind a slow one never runs against a daemon that has
// gone meanwhile (`on`/`off`/`camera`/`settings`/`config`/`modules`/`order`/`mic` would D-Bus-activate it) or
// with a CLI path that has changed. null = do not run.
function intentArgv(intent, cli, record) {
  if (!intent || typeof intent !== "object") return null
  switch (intent.verb) {
  case "enable": return available(record) ? enableArgv(cli, intent.on === true) : null
  case "select": return available(record) ? selectArgv(cli, intent.id) : null
  case "next": return canNext(record) ? nextArgv(cli) : null
  case "setup": return setupIntentArgv(cli, record, intent)
  case "setting": return settingIntentArgv(cli, record, intent)
  case "mic-host": return micSupported(record) ? micHostArgv(cli, intent.on === true) : null
  case "reset-settings": return settingsSupported(record) && settingIntentBound(intent, record) ? resetSettingsArgv(cli, record.settings.camera) : null
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
var PREVIEW_IDLE_TEXT = "Camera idle; turn on Preview to start it"
var PREVIEW_OFF_TEXT = "Preview off"
var PREVIEW_CAMERA_OFF_TEXT = "Camera off"
var PREVIEW_STARTING_TEXT = "Starting preview…"
var PREVIEW_RETRY_HINT = "Reopen the panel to retry."
// A preview preference the shell did not store (no layout entry to write, or
// an entry over SETTINGS_KEY_CAP): it holds for this session only.
var PREVIEW_UNSAVED_TEXT = "Could not save the preview setting"
var PREVIEW_FPS_TOOLTIPS = { 15: "Lighter; uses less CPU", 30: "Smoother, closer to what apps see; uses more CPU" }

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

// Whether the one preview process runs. A panel is open (`held` registered
// holders), the preview can work (`supported`: daemon revision, frame path,
// CLI), and either the user's Preview switch is on, or the stream is already
// active for SOMEONE ELSE: loopback or PipeWire consumers, never preview
// leases. The lease is itself a consumer, so counting it would let a preview
// keep the camera on that only it holds, with the switch off (R1).
function shouldPreview(held, supported, switchOn, record) {
  if (!(typeof held === "number" && held > 0) || supported !== true) return false
  if (switchOn === true) return true
  return available(record) && record.state === "active" && otherConsumers(record) > 0
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
// (15 or 30) and panelTab (a word of PANEL_TABS) may be written; anything
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
  return wrote ? entry : null
}

// An entry as the bar hands settings to a widget: without its id.
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
    out.push({ value: v, label: v + " fps", tooltip: PREVIEW_FPS_TOOLTIPS[v], selected: v === current })
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
// setting, and never evaluates `enabled_when` (a condition on a setting it
// skipped, or an operator it does not know, changes nothing: `enabled` is
// the daemon's word). The daemon keeps each camera's values and applies them
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
//   other ask (select, next, enable ...)                     1
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
var SETTINGS_TITLE = "SETTINGS"
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
// (optionValueOf). Unknown fields (enabled_when, hint, ...) are not read. A
// setting
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
    return String(n) + (row.unit !== "" ? " " + row.unit : "")
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
  if (row.enabled) return value
  var parts = ["Unavailable"]
  if (value !== "") parts.push(value)
  if (typeof row.reason === "string" && row.reason !== "") parts.push(row.reason)
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

// The widget an enum gets: a row of buttons while fitsSegmented, else a
// dropdown.
function settingWidget(row) {
  if (!row) return ""
  if (row.type === "int") return "slider"
  if (row.type === "bool") return "switch"
  if (row.type === "action") return "action"
  return fitsSegmented(row.options) ? "segmented" : "dropdown"
}

// ---- the panel's view

// The group that is open: at most one at a time (an accordion, so the
// Camera tab is never taller than its tallest group). `open` is the panel's
// choice of this session (memory only): a group id (that group, while the
// set has it), "" (the user closed the open group: none), or anything else,
// a group the set does not have included (no choice): the Image group, or
// the first group on a camera that has none. "" when none is open. Only the
// camera's groups count: the global ones are never in the accordion.
function openGroupId(open, set) {
  if (!isPlainObject(set) || !Array.isArray(set.groups)) return ""
  var first = ""
  var image = false
  for (var i = 0; i < set.groups.length && i < SETTINGS_SET_GROUP_CAP; i++) {
    var g = set.groups[i]
    if (g.scope === "global") continue
    if (first === "") first = g.id
    if (open !== "" && typeof open === "string" && g.id === open) return open
    if (g.id === "image") image = true
  }
  if (first === "" || open === "") return ""
  return image ? "image" : first
}

// The settings section of a tab, exactly as it is drawn:
//   { visible, hint, note, groups, truncation, reset, rowCount, setKey,
//     title, collapsible }
// groups: { id, label, index, expanded, glyph, rows, truncation }, where the
// rows of a collapsed group are not listed; a row:
//   { id, type, widget, label, enabled, reason, value, valueText, min, max,
//     step, options, selectedIndex, optionsNote, stop }
// `stop` numbers the rows drawn, top to bottom (the keyboard's stops, see
// cursorStops). `hint` replaces everything when the settings cannot be
// shown (an old CLI or daemon, a newer schema, a camera without settings);
// `note` says whether a change applies live or at the next open. `open` is
// the panel's choice of open group (openGroupId). `setKey` names the set
// (its camera and serial): a row of another key is another camera's or
// another structure's, whatever its place (a held slider lets go).
// `collapsible` is whether the groups open and close (one at a time).
function emptySettingsView() {
  return { visible: false, hint: "", note: "", groups: [], truncation: "", reset: false, rowCount: 0, setKey: "",
           title: "", collapsible: true }
}

function viewRowOf(row, drafts, stop) {
  var value = shownSettingValue(row, drafts)
  return {
    id: row.id, type: row.type, widget: settingWidget(row), label: row.label, enabled: row.enabled,
    reason: row.reason, value: value, valueText: settingValueText(row, value), min: row.min, max: row.max,
    step: row.step, options: row.options, selectedIndex: row.type === "enum" ? optionIndex(row.options, value) : -1,
    optionsNote: showingText(row.options.length, row.optionsTotal, "choices"), stop: stop
  }
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
  var stop = 0
  for (var g = 0; g < set.groups.length && g < SETTINGS_SET_GROUP_CAP; g++) {
    var group = set.groups[g]
    if (group.scope === "global") continue
    var expanded = group.id === openId
    var rows = []
    for (var r = 0; expanded && r < group.rows.length && r < SETTINGS_PER_GROUP_CAP; r++)
      rows.push(viewRowOf(group.rows[r], drafts, stop++))
    out.groups.push({
      id: group.id, label: group.label, index: out.groups.length, expanded: expanded,
      glyph: expanded ? GLYPH_EXPANDED : GLYPH_COLLAPSED,
      rows: rows, truncation: expanded ? showingText(rows.length, group.total, "settings") : ""
    })
  }
  out.rowCount = stop
  // "Showing N of M groups": N is what is drawn (commitSettings keeps only
  // groups to draw), M counts the refused and capped ones too.
  out.truncation = showingText(out.groups.length, set.groupsTotal, "groups")
  if (out.groups.length === 0) {
    // A set of global settings only: there is no camera, and nothing to say.
    out.hint = set.camera !== "" ? SETTINGS_EMPTY_TEXT : ""
    if (set.camera === "") out.truncation = ""
    out.visible = out.hint !== ""
    return out
  }
  out.visible = true
  out.note = settingsLive(record) ? SETTINGS_LIVE_TEXT : SETTINGS_IDLE_TEXT
  out.reset = true
  return out
}

// The setting the Effect tab's dedicated choice row owns: the background
// effect. The only one this plugin names; every other global setting is
// drawn by the generic renderer.
var EFFECT_MODE_SETTING = "effect.background.mode"

// The Effect tab's generic section: every group of global settings, all open
// (no accordion, no reset: the camera's reset never reaches them), without
// the setting the dedicated row owns (a group left with nothing is not
// drawn), and without the microphone's groups (the Mic tab draws those).
// No groups (`visible` false) when the daemon publishes no other global
// setting, or predates module effects (MODULES_REVISION: the tab then says
// it needs updating).
function effectSettingsView(record, drafts) {
  var out = emptySettingsView()
  out.collapsible = false
  if (!moduleEffects(record) || !settingsSupported(record) || !isPlainObject(record.settings)) return out
  var set = record.settings
  out.setKey = JSON.stringify([set.camera, set.serial])
  var stop = 0
  var skippedGroups = 0
  for (var g = 0; g < set.groups.length && g < SETTINGS_SET_GROUP_CAP; g++) {
    var group = set.groups[g]
    if (group.scope !== "global" || group.surface === MIC_SURFACE) continue
    var rows = []
    var skipped = 0
    for (var r = 0; r < group.rows.length && r < SETTINGS_PER_GROUP_CAP; r++) {
      if (group.rows[r].id === EFFECT_MODE_SETTING) { skipped++; continue }
      rows.push(viewRowOf(group.rows[r], drafts, stop++))
    }
    if (rows.length === 0) { skippedGroups++; continue }
    out.groups.push({
      id: group.id, label: group.label, index: out.groups.length, expanded: true, glyph: "",
      rows: rows, truncation: showingText(rows.length + skipped, group.total, "settings")
    })
  }
  out.rowCount = stop
  out.truncation = showingText(out.groups.length + skippedGroups, set.globalGroupsTotal, "groups")
  out.visible = out.groups.length > 0
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

// The panel's four tabs, in order, under the preview: the words are the
// stored `panelTab` setting's values (manifest schema `options`, same order),
// and the only ones ever written. The first is the default.
var PANEL_TABS = ["effect", "camera", "mic", "status"]
var PANEL_TAB_DEFAULT = "effect"
var PANEL_TAB_LABELS = { effect: "Effect", camera: "Camera", mic: "Mic", status: "Status" }
var PANEL_TAB_DESCRIPTIONS = {
  effect: "Background effect and the video effects' settings",
  camera: "Camera choice and camera settings",
  mic: "The Omarchy Broadcast Mic: its processing, input and state",
  status: "State, consumers, outputs and live figures"
}

// The stored tab, read back: a word of PANEL_TABS exactly, else the default.
// Nothing is ever written back from here.
function panelTabValue(value) {
  return typeof value === "string" && PANEL_TABS.indexOf(value) >= 0 ? value : PANEL_TAB_DEFAULT
}

// The tab row: { value, label, description, selected }, constants only.
function panelTabOptions(tab) {
  var current = panelTabValue(tab)
  var out = []
  for (var i = 0; i < PANEL_TABS.length; i++) {
    var v = PANEL_TABS[i]
    out.push({ value: v, label: PANEL_TAB_LABELS[v], description: PANEL_TAB_DESCRIPTIONS[v], selected: v === current })
  }
  return out
}

// ---------------------------------------------------------------- status tab

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

// The Status tab's rows: { label, value }, every value a display copy. The
// daemon reports its interface revision, not a version number, so that is
// what is shown.
function statusRows(record) {
  if (!available(record)) return []
  var camera = activeCameraLabel(record)
  var rows = [
    { label: "State", value: record.state },
    { label: "Camera", value: camera !== "" ? camera : "none" },
    { label: "Consumers", value: record.consumers >= 0 ? String(record.consumers) : UNKNOWN }
  ]
  var split = consumersByKind(record)
  if (split !== "") rows.push({ label: "Used by", value: split })
  rows.push({ label: "Output", value: record.outputMode !== "" ? record.outputMode : UNKNOWN })
  rows.push({ label: "PipeWire", value: record.pipewireOutput !== "" ? record.pipewireOutput : UNKNOWN })
  rows.push({ label: "D-Bus API",
              value: record.interfaceRevision >= 0 ? "revision " + record.interfaceRevision : UNKNOWN })
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
//   { visible, hint, hostOn, rows, runsOn, error }
// `visible`: the microphone is shown (else `hint` says why: an old daemon
// or CLI). `hostOn`: the switch of the microphone itself (`mic on|off`).
// rows: { label, value }; `runsOn` the modules processing it, as the daemon
// words it ("" unless the state is active or starting, as the added delay is
// "None" unless it is); `error` the daemon's.
function micView(record) {
  var out = { visible: false, hint: "", hostOn: false, rows: [], runsOn: "", error: "" }
  if (!available(record)) return out
  if (!micSupported(record)) { out.hint = micMissingText(record); return out }
  var m = record.mic
  out.visible = true
  out.hostOn = m.state !== "off"
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
// accordion, no reset), as effectSettingsView draws the Effect tab's. `note`
// says that no audio module is installed when the daemon's own group is the
// only one; nothing while the set is still loading, or the microphone is
// not supported (micView says why).
function micSettingsView(record, drafts) {
  var out = emptySettingsView()
  out.collapsible = false
  if (!micSupported(record) || !settingsSupported(record) || !isPlainObject(record.settings)) return out
  var set = record.settings
  // The microphone's settings are global: no camera in the key, so another
  // camera never closes an open dropdown or lets go of a held slider (that
  // is all a key change does, see SettingsView's rowKey).
  out.setKey = JSON.stringify([MIC_SURFACE, set.serial])
  var stop = 0
  var modules = false
  var undrawn = 0
  for (var g = 0; g < set.groups.length && g < SETTINGS_SET_GROUP_CAP; g++) {
    var group = set.groups[g]
    if (group.surface !== MIC_SURFACE) continue
    if (group.id !== MIC_INPUT_GROUP) modules = true
    if (out.groups.length >= SETTINGS_GROUP_CAP) continue
    var rows = []
    for (var r = 0; r < group.rows.length && r < SETTINGS_PER_GROUP_CAP; r++) rows.push(viewRowOf(group.rows[r], drafts, stop++))
    if (rows.length === 0) { undrawn++; continue }
    out.groups.push({
      id: group.id, label: group.label, index: out.groups.length, expanded: true, glyph: "",
      rows: rows, truncation: showingText(rows.length, group.total, "settings")
    })
  }
  out.rowCount = stop
  // "Showing N of M groups": M counts the groups the view could draw, not
  // one it never draws (no row to show).
  var groupsTotal = typeof set.micGroupsTotal === "number" ? Math.max(0, set.micGroupsTotal - undrawn) : 0
  out.truncation = showingText(out.groups.length, groupsTotal, "groups")
  out.note = modules ? "" : (micHostOn(record) ? MIC_NO_MODULES_TEXT : MIC_NO_MODULES_OFF_TEXT)
  out.visible = out.groups.length > 0 || out.note !== ""
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

// ---------------------------------------------------------------- keyboard cursor

// The panel's keyboard stops, top to bottom, as the panel lays them out: the
// on/off switch, the Preview switch and the frame-rate choices (one stop for
// the row; only when `previewControls`, see previewControlsShown), the tab
// row (one stop; Left/Right change the tab), then only the stops of the tab
// shown (`tab`, read through panelTabValue):
//   effect  the background effect's choices (one stop for the row;
//           Left/Right walk its choices, as in the shell's button groups),
//           then the rows of `effectSettings` (effectSettingsView: the
//           daemon's other global settings, drawn generically, no group
//           header is a stop);
//   camera  one per rendered camera row (`cameraCount` is the count the
//           panel draws, so the cursor and the rows always agree), Next
//           camera when it is shown, then from `settings` (the settingsView
//           the panel draws, so collapsed groups and capped rows are no
//           stops): Reset to defaults (on the settings' title line), each
//           group header (index: its place in the view) and the rows of an
//           open group (index: the row's `stop`);
//   mic     the microphone's switch (while micView shows it), then the
//           rows of `micSettings` (micSettingsView, drawn generically);
//   status  nothing (it only shows figures).
// Nothing is a stop while the daemon is unavailable: no control is drawn. The
// effect row is no stop either while it is not drawn (effectModeView: the
// daemon predates module effects, or offers no background effect).
function cursorStops(record, cameraCount, previewControls, tab, settings, effectSettings, micSettings) {
  if (!available(record)) return []
  var stops = [{ kind: "switch", index: -1 }]
  if (previewControls === true) {
    stops.push({ kind: "preview", index: -1 })
    stops.push({ kind: "fps", index: -1 })
  }
  stops.push({ kind: "tabs", index: -1 })
  var shown = panelTabValue(tab)
  if (shown === "effect") {
    if (effectModeShown(record)) stops.push({ kind: "effect", index: -1 })
    if (effectSettingsShown(effectSettings)) {
      // The generic rows' stops number from 0 in this tab's view, as the
      // camera's do in theirs (the two are never shown together).
      for (var e = 0; e < effectSettings.groups.length && e < SETTINGS_GROUP_CAP; e++) {
        var erows = Array.isArray(effectSettings.groups[e].rows) ? effectSettings.groups[e].rows : []
        for (var q = 0; q < erows.length && q < SETTINGS_PER_GROUP_CAP; q++) stops.push({ kind: "setting", index: erows[q].stop })
      }
    }
  } else if (shown === "mic") {
    if (micSupported(record)) stops.push({ kind: "mic-host", index: -1 })
    var mgroups = micSettingsShown(micSettings) ? micSettings.groups : []
    for (var mg = 0; mg < mgroups.length && mg < SETTINGS_GROUP_CAP; mg++) {
      var mrows = Array.isArray(mgroups[mg].rows) ? mgroups[mg].rows : []
      for (var mr = 0; mr < mrows.length && mr < SETTINGS_PER_GROUP_CAP; mr++) stops.push({ kind: "setting", index: mrows[mr].stop })
    }
  } else if (shown === "camera") {
    var n = Math.max(0, Math.min(Number(cameraCount) || 0, CAMERA_CAP))
    for (var i = 0; i < n; i++) stops.push({ kind: "camera", index: i })
    if (canNext(record)) stops.push({ kind: "next", index: -1 })
    if (isPlainObject(settings) && settings.reset === true) stops.push({ kind: "reset", index: -1 })
    var groups = isPlainObject(settings) && Array.isArray(settings.groups) ? settings.groups : []
    for (var g = 0; g < groups.length && g < SETTINGS_GROUP_CAP; g++) {
      stops.push({ kind: "group", index: g })
      var rows = Array.isArray(groups[g].rows) ? groups[g].rows : []
      for (var r = 0; r < rows.length && r < SETTINGS_PER_GROUP_CAP; r++) stops.push({ kind: "setting", index: rows[r].stop })
    }
  }
  return stops
}

function clampCursor(index, length) {
  if (!(length > 0)) return 0
  var i = Math.floor(Number(index) || 0)
  return Math.max(0, Math.min(length - 1, i))
}

// Rows that are one stop each (cameras, group headers, settings) are told
// apart by index.
function stopHasIndex(kind) {
  return kind === "camera" || kind === "group" || kind === "setting"
}

function stopIndex(stops, kind, index) {
  for (var i = 0; i < stops.length; i++)
    if (stops[i].kind === kind && (!stopHasIndex(kind) || stops[i].index === index)) return i
  return -1
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

// "file:///a/b%20c/" -> "/a/b c"
function localPathFromUrl(url) {
  var s = String(url === undefined || url === null ? "" : url)
  if (s.indexOf("file://") !== 0) return ""
  var path
  try {
    path = decodeURIComponent(s.slice("file://".length))
  } catch (e) {
    return ""
  }
  return path.length > 1 ? path.replace(/\/+$/, "") : path
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
// The sections, in the order of the list on the left (keys 1 to 5).
var SETUP_SECTIONS = ["modules", "order", "backends", "daemon", "diagnostics"]
var SETUP_SECTION_LABELS = {
  modules: "Modules", order: "Order", backends: "Backends", daemon: "Daemon", diagnostics: "Diagnostics"
}
var SETUP_SECTION_DESCRIPTIONS = {
  modules: "The effect modules and whether each one is enabled",
  order: "The order the effect stages run in",
  backends: "The backend profile and the module that provides each stage",
  daemon: "The daemon's configuration",
  diagnostics: "Interface revision, errors, configuration files and module problems"
}
// The reads behind the sections, in the order they run.
var SETUP_READS = ["modules", "order", "config", "files"]
var SETUP_TITLE = "Omarchy Broadcast setup"
var SETUP_OLD_DAEMON = "The daemon needs updating for the setup dialog (omarchy-broadcastd 0.24 or newer)."
var SETUP_OLD_CONFIG = "The daemon needs updating to show its configuration here (omarchy-broadcastd 0.25 or newer)."
var SETUP_OLD_PLUGIN = "Update the plugin to show the daemon's configuration."
var SETUP_LOADING = "Loading…"
var SETUP_SAVING = "Saving…"
// Where the daemon looks by default (modules.dirs; docs/modules.md).
var MODULES_EMPTY_TEXT = "No effect modules installed. A module's manifest goes in ~/.local/share/omarchy-broadcast/modules.d (your own) or /usr/lib/omarchy-broadcast/modules.d (packaged)."
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
var CONFIG_FILE_CAP = 96
var CONFIG_DIR_CAP = 256
var STAGE_WORD_CAP = 32
// The payload a summon carries: a few keys only.
var SETUP_PAYLOAD_CAP = PATH_CAP + 256

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
var FILE_STATUSES = ["loaded", "absent", "error"]

// ---- payload and the panel it forwards to

// The overlay's open() payload -> { view, cliSetting }: "setup" only for an
// object whose `view` is "setup" (the right click's); anything else, the
// empty payload of the panel hotkey and the shell's "{}" included, is the
// bar panel ("panel"). `cliSetting` is the clicked widget's cliPath setting
// as given (a string within PATH_CAP), else null.
function setupPayload(json) {
  var p = null
  if (typeof json === "string" && json !== "" && json.length <= SETUP_PAYLOAD_CAP) {
    try { p = JSON.parse(json) } catch (e) { p = null }
  }
  if (!isPlainObject(p) || p.view !== "setup") return { view: "panel", cliSetting: null }
  var cli = p.cliPath
  return { view: "setup", cliSetting: typeof cli === "string" && cli.length <= PATH_CAP ? cli : null }
}

// The right click's payload: the view, and the widget's cliPath setting
// when it has one.
function setupPayloadJson(cliSetting) {
  var p = { view: "setup" }
  if (typeof cliSetting === "string" && cliSetting.length <= PATH_CAP) p.cliPath = cliSetting
  return JSON.stringify(p)
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
    kind: sanitize(o.kind, STAGE_WORD_CAP), enabled: o.enabled === true, status: status,
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
// overridden_by, apply, enabled and disabled_reason.
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
    enabled: enabled, reason: enabled ? "" : settingText(s.disabled_reason, CONFIG_REASON_CAP)
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
// status and first stderr line.
function setupRead(kind, lines, code, stderrText) {
  if (kind === "modules") return readModules(lines, code, stderrText)
  if (kind === "order") return readOrder(lines, code, stderrText)
  if (kind === "config") return readConfig(lines, code, stderrText)
  if (kind === "files") return readConfigFiles(lines, code, stderrText)
  return readFailed("")
}

// The reads the daemon supports now, in order: the modules and the order
// from MODULES_REVISION, the configuration and its files from
// CONFIG_REVISION; none while it is unavailable.
function setupReads(record) {
  if (!available(record) || record.interfaceRevision < MODULES_REVISION) return []
  var out = ["modules", "order"]
  if (record.interfaceRevision >= CONFIG_REVISION) out.push("config", "files")
  return out
}

// The argv of read `kind` (fixed words only), or null.
function setupReadArgv(cli, kind) {
  if (!cliUsable(cli)) return null
  if (kind === "modules") return [cli, "modules", "list", "--json"]
  if (kind === "order") return [cli, "order", "show", "--json"]
  if (kind === "config") return [cli, "config", "show", "--json"]
  if (kind === "files") return [cli, "config", "files", "--json"]
  return null
}

// Every read, not yet loaded (null): what the dialog shows as loading.
function emptySetup() {
  return { modules: null, order: null, config: null, files: null }
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

// The section shown: a word of SETUP_SECTIONS, else the first.
function setupSectionValue(value) {
  return typeof value === "string" && SETUP_SECTIONS.indexOf(value) >= 0 ? value : SETUP_SECTIONS[0]
}

// The section list: { value, label, description, number, selected }.
function setupSectionOptions(section) {
  var current = setupSectionValue(section)
  var out = []
  for (var i = 0; i < SETUP_SECTIONS.length; i++) {
    var v = SETUP_SECTIONS[i]
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
//     switchable, note, index }
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
    var stages = ids.length > 0 ? "Stages: " + ids.join(", ") + (m.stagesTruncated ? ", …" : "") : ""
    out.rows.push({
      id: m.id, title: m.name + (m.version !== "" ? " " + m.version : ""),
      statusText: statusText, kindText: kindText,
      reason: m.reason, statusLine: statusReasonText(statusText, m.reason),
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
// choices, such as output.mode), "stepper" (a bounded number: - and +), or
// "text" (the value,
// read-only): every row the daemon does not take a write for now
// (configWord's rule), and every string, path or list.
function configWidget(row) {
  if (!isPlainObject(row) || !row.editable || !row.enabled || row.overriddenBy !== "") return "text"
  if (row.type === "bool") return "switch"
  if (row.type === "enum") return fitsSegmented(row.options) ? "choices" : "dropdown"
  if ((row.type === "int" || row.type === "float") && row.bounded) return "stepper"
  return "text"
}

// A config row as drawn: { id, type, widget, label, description, value,
// valueText, options, note, applyText, greyed, stop }. `note` is "Overridden
// by <file>" for a row a later file sets, else the daemon's reason for a
// greyed one; `applyText` says when a change takes effect (not for a live
// one); `stop` is the keyboard stop of an interactive row, -1 for text.
function configRowView(row, stop) {
  var widget = configWidget(row)
  var options = []
  for (var i = 0; row.type === "enum" && i < row.options.length && i < CONFIG_OPTION_CAP; i++)
    options.push({ value: row.options[i].value, label: row.options[i].label, selected: row.options[i].value === row.value })
  var overridden = row.overriddenBy !== ""
  return {
    id: row.id, type: row.type, widget: widget, label: row.label, description: row.description, value: row.value,
    valueText: configValueText(row), options: options,
    note: overridden ? overriddenText(row.overriddenBy) : (row.enabled ? "" : row.reason),
    applyText: APPLY_TEXTS[row.apply] !== undefined && widget !== "text" ? APPLY_TEXTS[row.apply] : "",
    greyed: overridden || !row.enabled, stop: widget === "text" ? -1 : stop
  }
}

// Whether a key of the modules group is one Backends draws: the profile and
// a stage's pin.
function backendKey(id) {
  return id === "modules.profile" || id.indexOf("modules.pin.") === 0
}

// The rows of the read configuration that `pick(group, row)` keeps, as
// groups of configRowView rows numbered for the keyboard from 0.
function configGroupsView(config, pick) {
  var groups = []
  var stop = 0
  for (var g = 0; g < config.groups.length && g < CONFIG_GROUP_CAP; g++) {
    var group = config.groups[g]
    var rows = []
    for (var r = 0; r < group.rows.length && r < CONFIG_GROUP_ROW_CAP; r++) {
      if (!pick(group, group.rows[r])) continue
      var view = configRowView(group.rows[r], stop)
      if (view.stop >= 0) stop++
      rows.push(view)
    }
    if (rows.length > 0) groups.push({ id: group.id, label: group.label, rows: rows })
  }
  return { groups: groups, stops: stop }
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
  var v = configGroupsView(config, function(group) { return group.id !== "modules" })
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

// The dialog's keyboard stops, top to bottom: the five section entries,
// then the shown section's controls:
//   modules   each module whose switch can be flipped
//   order     each stage that can move (Left/Right pick Move up or Move
//             down, Enter moves; Ctrl+Up/Down moves at once), then Reset
//             order when offered
//   backends, daemon  each interactive config row (index: its `stop`)
//   diagnostics  nothing (it only shows)
// `view` is the shown section's view, as drawn.
function setupStops(section, view) {
  var stops = []
  for (var i = 0; i < SETUP_SECTIONS.length; i++) stops.push({ kind: "section", index: i })
  var shown = setupSectionValue(section)
  if (!isPlainObject(view) || view.hint !== "") return stops
  if (shown === "modules") {
    for (var m = 0; m < view.rows.length; m++) if (view.rows[m].switchable) stops.push({ kind: "module", index: m })
  } else if (shown === "order") {
    for (var o = 0; o < view.rows.length; o++) if (view.rows[o].up || view.rows[o].down) stops.push({ kind: "stage", index: o })
    if (view.reset) stops.push({ kind: "order-reset", index: -1 })
  } else if (shown === "backends" || shown === "daemon") {
    for (var s = 0; s < view.stops; s++) stops.push({ kind: "config", index: s })
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
