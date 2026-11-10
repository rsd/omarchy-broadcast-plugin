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
    // Preview leases (interface revision 5), in `consumers` too; -1 unknown.
    previewConsumers: -1,
    // The PipeWire output's state word, display copy; "" when not reported.
    pipewireOutput: "",
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
    settingsCleared: false
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
// controls, the right click and the panel all treat it so.
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
  r.previewConsumers = count(m.preview_consumers)
  r.pipewireOutput = sanitize(m.pipewire_output, PIPEWIRE_CAP)
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
// stats, settings_group (a part of a set kept), settings (a set committed),
// settings_delta, settings_clear, error, ignored (an unknown type, such as
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

// Read-only rows under the choices: the blur strength while blurring (unless
// `strengthShown`: the Effect tab draws the daemon's strength setting, an
// adjustable one, instead), the background image while replacing. Empty when unavailable or when the CLI
// or the daemon predates effects.
function effectRows(record, strengthShown) {
  if (!effectsSupported(record)) return []
  // The daemon's own strength setting is drawn (adjustable) instead.
  if (record.effectKey === "blur" && strengthShown !== true) {
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

// Right click: flips the persisted switch, only when the daemon's state is
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

// A control request is kept as an intent, { verb, on, id, effect, value, camera },
// and turned into an argv when it runs: with the CLI path and the availability of that moment,
// so a request queued behind a slow one never runs against a daemon that has
// gone meanwhile (`on`/`off`/`camera`/`effect`/`denoise`/`settings` would D-Bus-activate it) or
// with a CLI path that has changed. null = do not run.
function intentArgv(intent, cli, record) {
  if (!intent || typeof intent !== "object") return null
  switch (intent.verb) {
  case "enable": return available(record) ? enableArgv(cli, intent.on === true) : null
  case "select": return available(record) ? selectArgv(cli, intent.id) : null
  case "next": return canNext(record) ? nextArgv(cli) : null
  case "effect": return effectSelectable(record, intent.effect) ? effectArgv(cli, intent.effect) : null
  case "denoise": return denoiseSupported(record) ? denoiseArgv(cli, intent.on) : null
  case "setting": return settingIntentArgv(cli, record, intent)
  case "reset-settings": return settingsSupported(record) && settingIntentBound(intent, record) ? resetSettingsArgv(cli, record.settings.camera) : null
  default: return null
  }
}

// Right click on the bar icon: "toggle", "open-panel" (unavailable: never
// flip a state the user cannot see) or "ignore" (`busy`: a command other
// than a camera setting write is in flight or queued, see toggleBlocked; its
// result has not arrived, so the target of a toggle is unknown; the panel
// switch follows the same rule through its `busy`). Any other click opens
// and closes the panel.
function rightClickAction(record, busy) {
  if (!available(record)) return "open-panel"
  return busy === true ? "ignore" : "toggle"
}

// What the bar icon's clicks do, for its accessible description: constants
// only, worded for the state the right click would act on.
function barClickHelp(record) {
  if (!available(record)) return "Click or right click: open the panel."
  return "Click: open the panel. Right click: " + (record.enabled ? "turn the camera off." : "turn the camera on.")
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
var OPTION_VALUE_RE = /^[a-z0-9_]{1,32}$/
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
// A set holds the groups of both scopes, each up to SETTINGS_GROUP_CAP.
var SETTINGS_SET_GROUP_CAP = 2 * SETTINGS_GROUP_CAP
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
// Commands waiting behind a running one (see enqueueIntent): at most one
// other ask, one reset and SETTING_QUEUE_CAP setting writes (one per id), so
// never more than INTENT_QUEUE_CAP.
var SETTING_QUEUE_CAP = 8
var INTENT_QUEUE_CAP = SETTING_QUEUE_CAP + 2
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

function optionValueOf(value) {
  return typeof value === "string" && OPTION_VALUE_RE.test(value) && !reservedKey(value) ? value : ""
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
// new value each, with a label (its value when the label sanitises to
// nothing). `total` counts the valid ones and those past the cap.
function settingOptions(value) {
  var src = Array.isArray(value) ? value : []
  var n = Math.min(src.length, SETTING_OPTION_CAP)
  var out = []
  var seen = Object.create(null)
  for (var i = 0; i < n; i++) {
    var o = src[i]
    if (!isPlainObject(o)) continue
    var v = optionValueOf(o.value)
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
// global ones.
function settingScope(s) {
  return isPlainObject(s) && s.scope === "global" ? "global" : "camera"
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
// `scope` is read as settingScope reads it. Unknown fields (enabled_when,
// hint, ...) are not read. A setting
// of a known type that is skipped (a fixed int, max == min; too many steps;
// a field missing) still counts in its group's total (settingKnown), so the
// group says that not all are shown; one of an unknown type does not.
function settingEntry(s) {
  if (!isPlainObject(s)) return null
  var id = settingId(s.id)
  if (id === "" || typeof s.type !== "string" || SETTING_TYPES.indexOf(s.type) < 0) return null
  var label = settingText(s.label, SETTING_LABEL_CAP)
  var enabled = s.enabled === true
  var e = {
    id: id, type: s.type, label: label !== "" ? label : id, scope: settingScope(s), stored: s.stored === true, enabled: enabled,
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
    var opts = settingOptions(s.options)
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
  var n = Math.min(src.length, SETTINGS_LINE_LOOK)
  var rows = []
  var skipped = 0
  for (var i = 0; i < n; i++) {
    var e = settingEntry(src[i])
    if (e) rows.push(e)
    else if (settingKnown(src[i])) skipped++
  }
  var label = settingText(g.label, SETTING_LABEL_CAP)
  envelope.group = { refused: false, id: gid, scope: scope, label: label !== "" ? label : gid, rows: rows,
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
    // A group is told apart by its scope as well as its id: a camera group
    // and a global one may share an id.
    var key = line.group.scope + ":" + line.group.id
    var g = byId[key]
    if (g === undefined) {
      g = { id: line.group.id, scope: line.group.scope, label: line.group.label, rows: [], total: 0 }
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
  // The caps apply to each scope on its own, so that camera groups never
  // crowd the global ones out (a refused group counts with the camera's).
  var out = []
  var counted = { camera: refusedCount, global: 0 }
  var shown = { camera: 0, global: 0 }
  var rows = { camera: 0, global: 0 }
  for (var k = 0; k < all.length; k++) {
    var total = Math.max(all[k].rows.length, all[k].total)
    if (total === 0) continue
    var sc = all[k].scope
    counted[sc]++
    if (shown[sc] >= SETTINGS_GROUP_CAP) continue
    var kept = all[k].rows.slice(0, Math.max(0, SETTINGS_ROW_CAP - rows[sc]))
    rows[sc] += kept.length
    shown[sc]++
    out.push({ id: all[k].id, scope: sc, label: all[k].label, rows: kept, total: total })
  }
  return { rev: a.rev, serial: a.serial, camera: a.camera, groups: out, groupsTotal: counted.camera, globalGroupsTotal: counted.global }
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
    groups.push({ id: set.groups[g].id, scope: set.groups[g].scope, label: set.groups[g].label, rows: set.groups[g].rows.slice(), total: set.groups[g].total })
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
  return { rev: rev, serial: set.serial, camera: set.camera, groups: groups, groupsTotal: set.groupsTotal, globalGroupsTotal: set.globalGroupsTotal }
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

// The widget an enum gets: a row of buttons while it has at most
// SEGMENTED_MAX_OPTIONS choices whose labels fit SEGMENTED_MAX_CHARS, else a
// dropdown.
function settingWidget(row) {
  if (!row) return ""
  if (row.type === "int") return "slider"
  if (row.type === "bool") return "switch"
  if (row.type === "action") return "action"
  var chars = 0
  for (var i = 0; i < row.options.length; i++) chars += row.options[i].label.length
  return row.options.length <= SEGMENTED_MAX_OPTIONS && chars <= SEGMENTED_MAX_CHARS ? "segmented" : "dropdown"
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
// drawn). No groups (`visible` false) when the daemon publishes no global
// setting at all, and the panel then keeps its own rows.
function effectSettingsView(record, drafts) {
  var out = emptySettingsView()
  out.collapsible = false
  if (!available(record) || !settingsSupported(record) || !isPlainObject(record.settings)) return out
  var set = record.settings
  out.setKey = JSON.stringify([set.camera, set.serial])
  var stop = 0
  var skippedGroups = 0
  for (var g = 0; g < set.groups.length && g < SETTINGS_SET_GROUP_CAP; g++) {
    var group = set.groups[g]
    if (group.scope !== "global") continue
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

// The two settings that replace a legacy row of the Effect tab. Named only
// to hide that row once its setting is drawn (effectSettingShown); the
// generic renderer names no setting.
var LEGACY_STRENGTH_SETTING = "effect.background.blur_strength"
var LEGACY_DENOISE_SETTING = "effect.video.denoise"

// Whether the Effect tab's generic view draws setting `id` as a row.
function effectSettingShown(view, id) {
  if (!isPlainObject(view) || !Array.isArray(view.groups)) return false
  for (var g = 0; g < view.groups.length && g < SETTINGS_GROUP_CAP; g++) {
    var rows = Array.isArray(view.groups[g].rows) ? view.groups[g].rows : []
    for (var r = 0; r < rows.length && r < SETTINGS_PER_GROUP_CAP; r++) if (rows[r].id === id) return true
  }
  return false
}

// Whether the Effect tab draws the daemon's global settings (a daemon that
// publishes some) in place of its own read-only strength and noise removal
// rows.
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
var SETTING_VALUE_RE = /^(-?[0-9]{1,10}|true|false|[a-z0-9_]{1,32})$/

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
  return row.scope === "global" ? settingArgvGlobal(cli, row.id, word) : settingArgv(cli, record.settings.camera, row.id, word)
}

function isSettingIntent(intent) {
  return isPlainObject(intent) && (intent.verb === "setting" || intent.verb === "reset-settings")
}

// Whether the queue takes `intent`: anything but a setting write always; a
// write when one for the same id is queued (it replaces that one) or fewer
// than SETTING_QUEUE_CAP writes are. A write the queue does not take is not
// lost: the Daemon keeps its draft unsent and writes it once a queued
// command has run (Daemon.flushSettings). Nothing is ever evicted to make
// room, so no other ask is dropped and no draft is left waiting on a write
// that will never run.
function queueTakes(queue, intent) {
  if (!isPlainObject(intent) || intent.verb !== "setting") return true
  var q = Array.isArray(queue) ? queue : []
  var writes = 0
  for (var i = 0; i < q.length && i < INTENT_QUEUE_CAP; i++) {
    if (!isPlainObject(q[i]) || q[i].verb !== "setting") continue
    if (q[i].id === intent.id) return true
    writes++
  }
  return writes < SETTING_QUEUE_CAP
}

// The command queue behind a running command, as a pure step: `intent`
// added to `queue` (a new array; neither is modified). A queued write for
// the same setting id is replaced by the newer one, and a reset replaces
// every queued write and reset (it supersedes them), so a slider drag never
// queues more than one command per setting. Any other ask replaces the
// other ask queued before it (the latest wins). The new intent goes last, so
// the order of what the user did is kept, except an on/off ask: it goes
// first, so turning the camera off never waits behind slider writes. A
// write queueTakes refuses leaves the queue as it was. So the queue holds at
// most one other ask, one reset and SETTING_QUEUE_CAP writes: the input is
// cut to INTENT_QUEUE_CAP as a backstop only, and nothing is ever cut from a
// queue this function made.
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
    } else if (!isSettingIntent(p)) {
      continue
    }
    out.push(p)
  }
  if (intent.verb === "enable") out.unshift(intent)
  else out.push(intent)
  return out
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
// write is running or queued, so its result (and with it the target of the
// toggle) has not arrived. Setting writes never hold the switch.
function toggleBlocked(running, queue) {
  if (isPlainObject(running) && !isSettingIntent(running)) return true
  var q = Array.isArray(queue) ? queue : []
  for (var i = 0; i < q.length && i < INTENT_QUEUE_CAP; i++)
    if (isPlainObject(q[i]) && !isSettingIntent(q[i])) return true
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

// The panel's three tabs, in order, under the preview: the words are the
// stored `panelTab` setting's values (manifest schema `options`, same order),
// and the only ones ever written. The first is the default.
var PANEL_TABS = ["effect", "camera", "status"]
var PANEL_TAB_DEFAULT = "effect"
var PANEL_TAB_LABELS = { effect: "Effect", camera: "Camera", status: "Status" }
var PANEL_TAB_DESCRIPTIONS = {
  effect: "Background effect and noise removal",
  camera: "Camera choice and camera settings",
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

// ---------------------------------------------------------------- keyboard cursor

// The panel's keyboard stops, top to bottom, as the panel lays them out: the
// on/off switch, the Preview switch and the frame-rate choices (one stop for
// the row; only when `previewControls`, see previewControlsShown), the tab
// row (one stop; Left/Right change the tab), then only the stops of the tab
// shown (`tab`, read through panelTabValue):
//   effect  the effect choices (one stop for the row; Left/Right walk its
//           choices, as in the shell's button groups), then the rows of
//           the noise removal switch unless the generic rows hold it, then
//           the rows of `effectSettings` (effectSettingsView: the daemon's
//           global settings, drawn generically, no group header is a stop);
//   camera  one per rendered camera row (`cameraCount` is the count the
//           panel draws, so the cursor and the rows always agree), Next
//           camera when it is shown, then from `settings` (the settingsView
//           the panel draws, so collapsed groups and capped rows are no
//           stops): Reset to defaults (on the settings' title line), each
//           group header (index: its place in the view) and the rows of an
//           open group (index: the row's `stop`);
//   status  nothing (it only shows figures).
// Nothing is a stop while the daemon is unavailable: no control is drawn. The
// effect row is no stop either when the CLI or the daemon predates effects
// (none of its choices can be requested), nor the noise removal switch when
// the daemon does not report it (it is not drawn).
function cursorStops(record, cameraCount, previewControls, tab, settings, effectSettings) {
  if (!available(record)) return []
  var stops = [{ kind: "switch", index: -1 }]
  if (previewControls === true) {
    stops.push({ kind: "preview", index: -1 })
    stops.push({ kind: "fps", index: -1 })
  }
  stops.push({ kind: "tabs", index: -1 })
  var shown = panelTabValue(tab)
  if (shown === "effect") {
    if (effectsSupported(record)) stops.push({ kind: "effect", index: -1 })
    // The legacy switch stands only where its setting is not drawn; it sits
    // above the generic rows.
    if (denoiseSupported(record) && !effectSettingShown(effectSettings, LEGACY_DENOISE_SETTING))
      stops.push({ kind: "denoise", index: -1 })
    if (effectSettingsShown(effectSettings)) {
      // The generic rows' stops number from 0 in this tab's view, as the
      // camera's do in theirs (the two are never shown together).
      for (var e = 0; e < effectSettings.groups.length && e < SETTINGS_GROUP_CAP; e++) {
        var erows = Array.isArray(effectSettings.groups[e].rows) ? effectSettings.groups[e].rows : []
        for (var q = 0; q < erows.length && q < SETTINGS_PER_GROUP_CAP; q++) stops.push({ kind: "setting", index: erows[q].stop })
      }
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
