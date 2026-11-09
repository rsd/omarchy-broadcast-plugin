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

// The video effects the daemon accepts (docs/adr/0012), in panel order. The
// only words ever passed to `omarchy-broadcast effect`.
var EFFECTS = ["none", "blur", "replace"]
var EFFECT_LABELS = { none: "None", blur: "Blur", replace: "Replace" }
// Said instead of offering effects when the CLI predates them (it prints no
// blur_strength and has no `effect` command).
var CLI_NO_EFFECTS = "The omarchy-broadcast CLI needs updating for effects"
// Said instead when the CLI knows effects but the running daemon does not (an
// interface revision below EFFECTS_REVISION, or none readable): the CLI would
// refuse every `effect` request.
var DAEMON_NO_EFFECTS = "The daemon needs updating for effects"
// Video noise removal: a stage that runs before the effect, or alone with
// `none`, switched by `omarchy-broadcast denoise on|off`. It is not an effect
// and hides nothing, so it is a separate switch, not a choice of EFFECTS. When
// it cannot run the stream goes on without it and the daemon's error text
// says why. The only words ever passed to `omarchy-broadcast denoise`.
var DENOISE_WORDS = { on: "on", off: "off" }
var DENOISE_LABEL = "Noise removal"
// The daemon interface revision that added effects (obc-ipc INTERFACE_REVISION
// 2; the CLI's bus::require_effects checks the same).
var EFFECTS_REVISION = 2
// The daemon interface revision that added noise removal (obc-ipc
// INTERFACE_REVISION 4; the CLI prints `denoise` only from a daemon at or
// above it, and null below).
var DENOISE_REVISION = 4
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

// Whether noise removal is on: a boolean exactly, else null (unknown).
function denoiseFlag(value) {
  return typeof value === "boolean" ? value : null
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
    // The split of `consumers` (docs/cli-json.md): processes holding the
    // loopback and links to the PipeWire node; -1 when unknown. A preview
    // lease (interface revision 5) is in `consumers` but in neither of these.
    loopbackConsumers: -1,
    pipewireConsumers: -1,
    outputMode: "",
    effect: "",
    effectKey: "",
    blurStrength: null,
    backgroundImage: "",
    backgroundImageSet: false,
    // true or false as the daemon reports it; null when the line has no
    // boolean `denoise` (a CLI or a daemon that predates noise removal).
    denoise: null,
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
  r.loopbackConsumers = count(m.loopback_consumers)
  r.pipewireConsumers = count(m.pipewire_consumers)
  r.outputMode = sanitize(m.output_mode, MODE_CAP)
  r.effect = sanitize(m.effect, EFFECT_CAP)
  r.effectKey = effectKey(m.effect)
  r.blurStrength = blurStrength(m.blur_strength)
  r.backgroundImage = sanitize(m.background_image, IMAGE_PATH_CAP)
  // Whether the daemon holds an image, from the raw field: the display copy
  // above may sanitise to "" and must not decide what can be chosen.
  r.backgroundImageSet = typeof m.background_image === "string" && m.background_image !== ""
  // A CLI and daemon that know noise removal print `denoise` on every
  // snapshot and state line; one that predates it prints no such field.
  r.denoise = denoiseFlag(m.denoise)
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
// stats, error, ignored (an unknown type, or a line that cannot apply in the
// current link state), dropped, invalid, unsupported.
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

// The tooltip's effect phrase: the effect ("" for none or an unknown one),
// then noise removal when it is on, joined by a comma.
function effectSummary(record) {
  if (!record) return ""
  var parts = []
  if (record.effectKey === "blur") parts.push("background blurred")
  else if (record.effectKey === "replace") parts.push("background replaced")
  if (record.denoise === true) parts.push("noise removal on")
  return parts.join(", ")
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
// without one; the image is set with `omarchy-broadcast effect replace --image
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
    return { text: "omarchy-broadcastd reports an effect this plugin does not know"
               + (record.effect !== "" ? ": " + record.effect : "") + ". Update the plugin.",
             commandText: "" }
  if (!hasBackgroundImage(record))
    return { text: "Replace needs an image:", commandText: "omarchy-broadcast effect replace --image PATH" }
  return { text: "", commandText: "" }
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

// ---------------------------------------------------------------- noise removal

// Whether noise removal can be switched: an available daemon whose interface
// revision is at least DENOISE_REVISION and whose line reports `denoise` as a
// boolean. A CLI or a daemon that predates it omits the field (or reports an
// older revision), and the panel then shows no switch (an off switch would
// claim a state nobody reported). An unknown revision counts as no.
function denoiseSupported(record) {
  return available(record) && typeof record.denoise === "boolean"
    && typeof record.interfaceRevision === "number"
    && record.interfaceRevision >= DENOISE_REVISION
}

// The panel's noise removal row: { visible, checked, label, tooltip }, the
// tooltip worded as the on/off switch's is.
function denoiseRow(record) {
  var shown = denoiseSupported(record)
  var checked = shown && record.denoise === true
  return {
    visible: shown,
    label: DENOISE_LABEL,
    checked: checked,
    tooltip: checked ? "Turn noise removal off" : "Turn noise removal on"
  }
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

// Only `on` or `off` is ever sent, from a strict boolean.
function denoiseArgv(cli, on) {
  if (!cliUsable(cli) || typeof on !== "boolean") return null
  return [cli, "denoise", on ? DENOISE_WORDS.on : DENOISE_WORDS.off]
}

// A control request is kept as an intent, { verb, on, id, effect }, and turned into an
// argv when it runs: with the CLI path and the availability of that moment,
// so a request queued behind a slow one never runs against a daemon that has
// gone meanwhile (`on`/`off`/`camera`/`effect`/`denoise` would D-Bus-activate it) or
// with a CLI path that has changed. null = do not run.
function intentArgv(intent, cli, record) {
  if (!intent || typeof intent !== "object") return null
  switch (intent.verb) {
  case "enable": return available(record) ? enableArgv(cli, intent.on === true) : null
  case "select": return available(record) ? selectArgv(cli, intent.id) : null
  case "next": return canNext(record) ? nextArgv(cli) : null
  case "effect": return effectSelectable(record, intent.effect) ? effectArgv(cli, intent.effect) : null
  case "denoise": return denoiseSupported(record) ? denoiseArgv(cli, intent.on) : null
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
// bar gave them, ...values }. Only previewEnabled (a boolean) and previewFps
// (15 or 30) may be written; anything else, or nothing to write, is null.
// The settings given are not modified.
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

// ---------------------------------------------------------------- keyboard cursor

// The panel's keyboard stops, top to bottom: the on/off switch, the Preview
// switch and the frame-rate choices (one stop for the row, as the effect row;
// only when `previewControls`, see previewControlsShown), the effect
// choices (one stop for the row; Left/Right walk its choices, as in the
// shell's button groups), the noise removal switch, one per rendered camera
// row (`cameraCount` is the count the panel draws, so the cursor and the rows
// always agree), then Next camera when it is shown. Nothing is a stop while
// the daemon is unavailable: no control is drawn. The effect row is no stop
// either when the CLI or the daemon predates effects (none of its choices can
// be requested), nor the noise removal switch when the daemon does not
// report it (it is not drawn).
function cursorStops(record, cameraCount, previewControls) {
  if (!available(record)) return []
  var stops = [{ kind: "switch", index: -1 }]
  if (previewControls === true) {
    stops.push({ kind: "preview", index: -1 })
    stops.push({ kind: "fps", index: -1 })
  }
  if (effectsSupported(record)) stops.push({ kind: "effect", index: -1 })
  if (denoiseSupported(record)) stops.push({ kind: "denoise", index: -1 })
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

// The resolver: (1) `omarchy-broadcast` on PATH, else (2) the repository's release
// build, found from the plugin's real directory (the plugin dir is meant to be
// a symlink into the repo). The plugin dir is a positional argument, never
// interpolated into the script; an empty one skips (2). A path holding a
// newline is never printed (it would read as two answers).
var RESOLVER_SCRIPT = ""
  + "nl='\n'; "
  + "p=$(command -v omarchy-broadcast 2>/dev/null) && case $p in *\"$nl\"*) ;; /*) printf '%s\\n' \"$p\"; exit 0;; esac; "
  + "[ -n \"$1\" ] || exit 1; "
  + "d=$(readlink -f -- \"$1\" 2>/dev/null) || exit 1; "
  + "c=$(readlink -f -- \"$d/../../../target/release/omarchy-broadcast\" 2>/dev/null) || exit 1; "
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
  return ["sh", "-c", RESOLVER_SCRIPT, "omarchy-broadcast-resolve", dir]
}

// What the resolver searched, for the panel when it found nothing.
function resolverMissText(pluginDir) {
  if (!resolverDirUsable(pluginDir))
    return "omarchy-broadcast is not on PATH (no development build was searched: the plugin directory is not a usable local path)"
  return "omarchy-broadcast is not on PATH, and there is no development build at "
    + pluginDir + "/../../../target/release/omarchy-broadcast"
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
