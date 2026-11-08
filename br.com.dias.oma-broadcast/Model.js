.pragma library

// Everything the bar widget decides, as pure functions over plain values, so
// tests/tst_model.qml can reach all of it without a shell, a daemon or a CLI.
//
// The input is the NDJSON stream of `oma-broadcast watch --json`, specified in
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
var PRODUCT = "OMA Broadcast"

// Ingestion caps. The first cap is the producer's: the CLI writes no line
// longer than 4096 bytes (crates/oma-broadcast/src/json.rs, MAX_LINE_BYTES,
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
var EFFECT_CAP = 32
// The background image path, display only; it is never sent back as an
// argument. The producer clips it to 256 bytes and keeps the end of the path
// (the file name) behind a leading ellipsis (crates/oma-broadcast/src/json.rs,
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
var CLI_MISSING_TEXT = "oma-broadcast CLI not found"
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

// The video effects the daemon accepts (docs/adr/0012), in panel order. The
// only words ever passed to `oma-broadcast effect`.
var EFFECTS = ["none", "blur", "replace"]
var EFFECT_LABELS = { none: "None", blur: "Blur", replace: "Replace" }
// Said instead of offering effects when the CLI predates them (it prints no
// blur_strength and has no `effect` command).
var CLI_NO_EFFECTS = "The oma-broadcast CLI needs updating for effects"
// Said instead when the CLI knows effects but the running daemon does not (an
// interface revision below EFFECTS_REVISION, or none readable): the CLI would
// refuse every `effect` request.
var DAEMON_NO_EFFECTS = "The daemon needs updating for effects"
// The daemon interface revision that added effects (obc-ipc INTERFACE_REVISION
// 2; the CLI's bus::require_effects checks the same).
var EFFECTS_REVISION = 2
// The largest interface revision the producer can print (a u32).
var REVISION_MAX = 4294967295

// Material Design glyphs from the bar's Nerd Font (checked by rendering them).
var GLYPH_WEBCAM = String.fromCodePoint(0xF05A0)
var GLYPH_WEBCAM_OFF = String.fromCodePoint(0xF1737)
var GLYPH_VIDEO = String.fromCodePoint(0xF0567)
var GLYPH_VIDEO_OUTLINE = String.fromCodePoint(0xF0BDC)
var GLYPH_VIDEO_OFF_OUTLINE = String.fromCodePoint(0xF0BDB)
var GLYPH_ALERT = String.fromCodePoint(0xF0028)
var GLYPH_RADIO_ON = String.fromCodePoint(0xF043E)
var GLYPH_RADIO_OFF = String.fromCodePoint(0xF043D)
var GLYPH_NEXT = String.fromCodePoint(0xF04AD)

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
// ellipsis, however little of it is left.
function sanitize(value, cap) {
  if (typeof value !== "string") return ""
  var limit = Math.max(1, Math.floor(Number(cap) || 1))
  var precut = value.length > limit * 4
  var s = precut ? value.slice(0, limit * 4) : value
  s = s.replace(/[<>&\u061c\u200b\u200e\u200f\u202a-\u202e\u2060-\u206f\ufeff]/g, "")
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

// An effect name from the daemon: one of EFFECTS exactly, else "" (unknown;
// never selected in the panel and never sent back).
function effectKey(value) {
  return typeof value === "string" && EFFECTS.indexOf(value) >= 0 ? value : ""
}

// The blur strength: a finite number in 0..1, else null (unknown).
function blurStrength(value) {
  return typeof value === "number" && isFinite(value) && value >= 0 && value <= 1 ? value : null
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
    activeCamera: "",
    activeCameraName: "",
    consumers: -1,
    outputMode: "",
    effect: "",
    effectKey: "",
    blurStrength: null,
    backgroundImage: "",
    backgroundImageSet: false,
    cliEffects: false,
    interfaceRevision: -1,
    cameras: [],
    camerasTotal: 0,
    camerasTruncated: false,
    camerasCapped: false,
    stats: null
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
// controls, the left click and the panel all treat it so.
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
  r.activeCamera = rawId(m.active_camera)
  r.activeCameraName = sanitize(m.active_camera_name, NAME_CAP)
  r.consumers = count(m.consumers)
  r.outputMode = sanitize(m.output_mode, MODE_CAP)
  r.effect = sanitize(m.effect, EFFECT_CAP)
  r.effectKey = effectKey(m.effect)
  r.blurStrength = blurStrength(m.blur_strength)
  r.backgroundImage = sanitize(m.background_image, IMAGE_PATH_CAP)
  // Whether the daemon holds an image, from the raw field: the display copy
  // above may sanitise to "" and must not decide what can be chosen.
  r.backgroundImageSet = typeof m.background_image === "string" && m.background_image !== ""
  // A CLI that knows video effects prints blur_strength as a number on every
  // snapshot and state line. One that predates them prints no such field (and
  // "effect":"none"), and has no `effect` command to run.
  r.cliEffects = typeof m.blur_strength === "number"
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
// `--` (crates/oma-broadcast/src/main.rs), so a camera whose id is literally
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
// stats, error, ignored (an unknown type, or a line that cannot apply in the
// current link state), dropped, invalid, unsupported.
function reduce(record, text) {
  var base = record || emptyRecord("connecting")
  var p = parseLine(text)
  if (p.kind === "unsupported") {
    if (base.link === "unsupported") return { record: base, outcome: "unsupported" }
    return {
      record: emptyRecord("unsupported", "oma-broadcast prints output schema v" + p.version
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
// the panel.
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
  case "cli-failed": return "oma-broadcast watch stopped"
  case "unsupported": return "unsupported oma-broadcast version"
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
  } else if (record.state === "off") {
    text = prefix + "off" + (record.error !== "" ? " \u00b7 error: " + sanitize(record.error, 60) : "")
  } else {
    var camera = activeCameraLabel(record)
    var parts = [prefix + record.state]
    parts.push(camera !== "" ? camera : "no camera")
    if (record.consumers >= 0) parts.push(consumersText(record.consumers))
    var effect = effectSummary(record)
    if (effect !== "") parts.push(effect)
    if (record.error !== "") parts.push("error: " + sanitize(record.error, 60))
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
    return { title: "oma-broadcastd reports a state this plugin does not know"
               + (record.rawState !== "" ? ": " + record.rawState : ""),
             path: "", detail: "", hint: "Update the plugin.", commandText: "" }
  }
  switch (link) {
  case "ok":
    return { title: "", path: "", detail: "", hint: "", commandText: "" }
  case "not-running":
    return { title: "oma-broadcastd is not running", path: "", detail: "",
             hint: "Start it with:", commandText: "systemctl --user start oma-broadcastd" }
  case "unreachable":
    return { title: "oma-broadcastd is not answering", path: "", detail: detail,
             hint: "Retrying every 2 s. Its log:", commandText: "journalctl --user -u oma-broadcastd" }
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
    return { title: "oma-broadcast watch stopped", path: "", detail: detail, hint: "", commandText: "" }
  case "unsupported":
    return { title: "Unsupported oma-broadcast version", path: "", detail: detail, hint: "", commandText: "" }
  default:
    return { title: "Connecting to oma-broadcastd\u2026", path: "", detail: "", hint: "", commandText: "" }
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

// The tooltip's effect phrase: "" for none or an unknown effect.
function effectSummary(record) {
  if (!record) return ""
  if (record.effectKey === "blur") return "background blurred"
  if (record.effectKey === "replace") return "background replaced"
  return ""
}

// Whether the daemon holds a background image. Read from the raw field
// (backgroundImageSet), never from the sanitised display copy, so what can be
// chosen and what the panel says about it always agree.
function hasBackgroundImage(record) {
  return !!record && record.backgroundImageSet === true
}

// Whether the running daemon knows effects: its interface revision is at
// least EFFECTS_REVISION. An unknown revision counts as no.
function daemonEffects(record) {
  return !!record && typeof record.interfaceRevision === "number"
    && record.interfaceRevision >= EFFECTS_REVISION
}

// Whether effects can be set at all: an available daemon whose interface
// knows them, through a CLI that knows them. False for a CLI that predates
// effects, and for a new CLI still talking to an older daemon.
function effectsSupported(record) {
  return available(record) && record.cliEffects === true && daemonEffects(record)
}

// Why effects cannot be set while the daemon is available: the CLI line, or
// the daemon line once the CLI knows effects. "" when they can be set (or
// the daemon is unavailable, where the panel shows no effect row).
function effectsMissingText(record) {
  if (!available(record) || effectsSupported(record)) return ""
  return record.cliEffects === true ? DAEMON_NO_EFFECTS : CLI_NO_EFFECTS
}

// Whether `effect` may be requested now: a known effect, a daemon that can
// be controlled through a CLI that knows `effect`, and for `replace` a
// background image the daemon already holds (the daemon refuses `replace`
// without one; the image is set with `oma-broadcast effect replace --image
// PATH` or in its configuration).
function effectSelectable(record, effect) {
  if (!effectsSupported(record) || effectKey(effect) === "") return false
  return effect !== "replace" || hasBackgroundImage(record)
}

// The panel's effect choices, in EFFECTS order: { value, label, selected,
// selectable, faded, tooltip }. `selectable` is false for the current effect
// (there is nothing to change) and for an effect that cannot be requested.
// `faded` marks a choice drawn dimmed: one that cannot be requested and is
// not the current one, or every choice when the CLI or the daemon predates
// effects. An
// unknown effect from the daemon selects no choice.
function effectOptions(record) {
  var out = []
  var supported = effectsSupported(record)
  for (var i = 0; i < EFFECTS.length; i++) {
    var value = EFFECTS[i]
    var selected = !!record && record.effectKey === value
    var selectable = !selected && effectSelectable(record, value)
    var missing = effectsMissingText(record)
    var tooltip = missing !== "" ? missing
      : (value === "none" ? "The camera image, unchanged"
        : (value === "blur" ? "Blur the background"
          : (hasBackgroundImage(record) ? "Replace the background with the background image"
            : "Needs a background image: background_image under [effect] in the daemon's configuration, or --image")))
    out.push({
      value: value,
      label: EFFECT_LABELS[value],
      selected: selected,
      selectable: selectable,
      faded: !selectable && !(selected && supported),
      tooltip: tooltip
    })
  }
  return out
}

function effectIndex(value) {
  return EFFECTS.indexOf(effectKey(value))
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

// Read-only rows under the choices: the blur strength while blurring, the
// background image while replacing. Empty when unavailable or when the CLI
// or the daemon predates effects.
function effectRows(record) {
  if (!effectsSupported(record)) return []
  if (record.effectKey === "blur") {
    var s = record.blurStrength
    return [{ label: "Strength", value: s === null ? UNKNOWN : Math.round(s * 100) + " %" }]
  }
  if (record.effectKey === "replace")
    return [{ label: "Image", value: imagePathText(record) }]
  return []
}

// The line under the effect choices, { text, commandText }: that the CLI or
// the daemon predates effects, that the daemon reports an effect this plugin does not
// know, or, while the daemon has no background image, how to give it one.
// `commandText` is shown to copy, never run.
function effectHint(record) {
  if (!available(record)) return { text: "", commandText: "" }
  if (!effectsSupported(record)) return { text: effectsMissingText(record) + ".", commandText: "" }
  if (record.effectKey === "")
    return { text: "oma-broadcastd reports an effect this plugin does not know"
               + (record.effect !== "" ? ": " + record.effect : "") + ". Update the plugin.",
             commandText: "" }
  if (!hasBackgroundImage(record))
    return { text: "Replace needs an image:", commandText: "oma-broadcast effect replace --image PATH" }
  return { text: "", commandText: "" }
}

// Exit status of a control command -> a short, capped message for the panel.
// `code` -1 means the command could not be started at all.
function commandFailureText(code, stderrLine, cliPath) {
  var detail = typeof stderrLine === "string" ? stderrLine.slice(0, STDERR_CAP).replace(/^oma-broadcast:\s*/, "") : ""
  detail = sanitize(detail, DETAIL_CAP)
  var text
  switch (code) {
  case -1: text = CLI_MISSING_TEXT + ": " + (typeof cliPath === "string" ? cliPath : ""); break
  case 1: text = "The daemon refused the request" + (detail !== "" ? ": " + detail : ""); break
  case 2: text = "Invalid command line (a plugin bug)" + (detail !== "" ? ": " + detail : ""); break
  case 3: text = "oma-broadcastd is not running"; break
  case 4: text = "D-Bus failure" + (detail !== "" ? ": " + detail : ""); break
  default: text = "Command failed with status " + code + (detail !== "" ? ": " + detail : "")
  }
  return sanitize(text, DETAIL_CAP + 60)
}

// The watch's exit, for the panel. `crashed` is Quickshell's exitStatus
// (1 = killed by a signal, whose number is then the exit code).
function watchExitText(code, crashed, delayMs) {
  var how = crashed ? "stopped by signal " + code : "exited with status " + code
  return "oma-broadcast watch " + how + "; restarting in " + Math.round(delayMs / 1000) + " s"
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

// Left click: flips the persisted switch, only when the daemon's state is
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

// Only a word of EFFECTS is ever sent, as its own argv element: nothing from
// the daemon or the panel reaches the command line otherwise.
function effectArgv(cli, effect) {
  if (!cliUsable(cli) || effectKey(effect) === "") return null
  return [cli, "effect", effect]
}

// A control request is kept as an intent, { verb, on, id, effect }, and turned into an
// argv when it runs: with the CLI path and the availability of that moment,
// so a request queued behind a slow one never runs against a daemon that has
// gone meanwhile (`on`/`off`/`camera`/`effect` would D-Bus-activate it) or with a CLI
// path that has changed. null = do not run.
function intentArgv(intent, cli, record) {
  if (!intent || typeof intent !== "object") return null
  switch (intent.verb) {
  case "enable": return available(record) ? enableArgv(cli, intent.on === true) : null
  case "select": return available(record) ? selectArgv(cli, intent.id) : null
  case "next": return canNext(record) ? nextArgv(cli) : null
  case "effect": return effectSelectable(record, intent.effect) ? effectArgv(cli, intent.effect) : null
  default: return null
  }
}

// Left click on the bar icon: "toggle", "open-panel" (unavailable: never
// flip a state the user cannot see) or "ignore" (a command is in flight or
// queued: its result has not arrived, so the target of a toggle is unknown;
// the panel switch follows the same rule through its `busy`).
function leftClickAction(record, busy) {
  if (!available(record)) return "open-panel"
  return busy === true ? "ignore" : "toggle"
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

// ---------------------------------------------------------------- keyboard cursor

// The panel's keyboard stops, top to bottom: the on/off switch, the effect
// choices (one stop for the row; Left/Right walk its choices, as in the
// shell's button groups), one per rendered camera row (`cameraCount` is the
// count the panel draws, so the cursor and the rows always agree), then Next
// camera when it is shown. Nothing is a stop while the daemon is
// unavailable: no control is drawn. The effect row is no stop either when the
// CLI or the daemon predates effects: none of its choices can be requested.
function cursorStops(record, cameraCount) {
  if (!available(record)) return []
  var stops = [{ kind: "switch", index: -1 }]
  if (effectsSupported(record)) stops.push({ kind: "effect", index: -1 })
  var n = Math.max(0, Math.min(Number(cameraCount) || 0, CAMERA_CAP))
  for (var i = 0; i < n; i++) stops.push({ kind: "camera", index: i })
  if (canNext(record)) stops.push({ kind: "next", index: -1 })
  return stops
}

function clampCursor(index, length) {
  if (!(length > 0)) return 0
  var i = Math.floor(Number(index) || 0)
  return Math.max(0, Math.min(length - 1, i))
}

function stopIndex(stops, kind, index) {
  for (var i = 0; i < stops.length; i++)
    if (stops[i].kind === kind && (kind !== "camera" || stops[i].index === index)) return i
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

// The resolver: (1) `oma-broadcast` on PATH, else (2) the repository's release
// build, found from the plugin's real directory (the plugin dir is meant to be
// a symlink into the repo). The plugin dir is a positional argument, never
// interpolated into the script; an empty one skips (2). A path holding a
// newline is never printed (it would read as two answers).
var RESOLVER_SCRIPT = ""
  + "nl='\n'; "
  + "p=$(command -v oma-broadcast 2>/dev/null) && case $p in *\"$nl\"*) ;; /*) printf '%s\\n' \"$p\"; exit 0;; esac; "
  + "[ -n \"$1\" ] || exit 1; "
  + "d=$(readlink -f -- \"$1\" 2>/dev/null) || exit 1; "
  + "c=$(readlink -f -- \"$d/../../../target/release/oma-broadcast\" 2>/dev/null) || exit 1; "
  + "case $c in *\"$nl\"*) exit 1;; esac; "
  + "[ -f \"$c\" ] && [ -x \"$c\" ] && { printf '%s\\n' \"$c\"; exit 0; }; "
  + "exit 1"

// A plugin directory the development-build search may use: a local absolute
// path without control characters (a newline would make the answer ambiguous).
function resolverDirUsable(pluginDir) {
  return typeof pluginDir === "string" && pluginDir.charAt(0) === "/" && pluginDir.length <= PATH_CAP
    && !hasControl(pluginDir)
}

// Always an argv: PATH is searched even when the plugin directory is unusable
// (it is then passed as "", which skips the development-build search).
function resolverArgv(pluginDir) {
  var dir = resolverDirUsable(pluginDir) ? pluginDir : ""
  return ["sh", "-c", RESOLVER_SCRIPT, "oma-broadcast-resolve", dir]
}

// What the resolver searched, for the panel when it found nothing.
function resolverMissText(pluginDir) {
  if (!resolverDirUsable(pluginDir))
    return "oma-broadcast is not on PATH (no development build was searched: the plugin directory is not a usable local path)"
  return "oma-broadcast is not on PATH, and there is no development build at "
    + pluginDir + "/../../../target/release/oma-broadcast"
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
