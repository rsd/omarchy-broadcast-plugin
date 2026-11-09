import QtQuick
import QtTest
import "../Model.js" as Model

// Unit tests for Model.js: the stream reducer, sanitising, caps, the bar's
// six visual states, tooltips, argv builders and CLI-path resolution.
//
// Run (headless):
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_model.qml
TestCase {
  name: "OmarchyBroadcastModel"

  readonly property string cli: "/opt/bin/omarchy-broadcast"
  readonly property string brioId: "usb-046d_0944-video-index0"
  readonly property string fhdId: "pci-0000:00:14.0-usb-0:5:1.0-video-index0"

  function cameraObjects() {
    return [
      { id: brioId, name: "Logitech MX Brio", usb: "046d:0944", active: true },
      { id: fhdId, name: "FHD Camera", usb: "5986:1193", active: false }
    ]
  }

  function snapshotObject(overrides) {
    var m = {
      v: 1, type: "snapshot", state: "idle", enabled: true, error: "",
      active_camera: brioId, active_camera_name: "Logitech MX Brio", consumers: 0,
      output_mode: "NV12 1920x1080@30", effect: "none", blur_strength: 0.5, background_image: "",
      interface_revision: 4, cameras: cameraObjects(), cameras_truncated: false
    }
    for (var k in overrides) m[k] = overrides[k]
    return m
  }

  function stateObject(overrides) {
    var m = {
      v: 1, type: "state", changed: ["state"], state: "idle", enabled: true, error: "",
      active_camera: brioId, active_camera_name: "Logitech MX Brio", consumers: 0,
      output_mode: "NV12 1920x1080@30", effect: "none", blur_strength: 0.5, background_image: "",
      interface_revision: 4
    }
    for (var k in overrides) m[k] = overrides[k]
    return m
  }

  function line(obj) { return JSON.stringify(obj) }

  function snap(overrides) {
    return Model.reduce(Model.emptyRecord("connecting"), line(snapshotObject(overrides || {}))).record
  }

  function active() {
    var r = snap({ consumers: 1 })
    r = Model.reduce(r, line(stateObject({ state: "starting", consumers: 1 }))).record
    return Model.reduce(r, line(stateObject({ state: "active", consumers: 1 }))).record
  }

  // ---- line types ----------------------------------------------------------

  function test_snapshot_replaces_everything() {
    var stale = Model.emptyRecord("not-running", "gone")
    var res = Model.reduce(stale, line(snapshotObject({})))
    compare(res.outcome, "snapshot")
    var r = res.record
    compare(r.link, "ok")
    compare(r.linkText, "")
    compare(r.state, "idle")
    compare(r.enabled, true)
    compare(r.activeCamera, brioId)
    compare(r.activeCameraName, "Logitech MX Brio")
    compare(r.consumers, 0)
    compare(r.outputMode, "NV12 1920x1080@30")
    compare(r.cameras.length, 2)
    compare(r.cameras[0].label, "Logitech MX Brio")
    compare(r.cameras[0].usb, "046d:0944")
    compare(r.cameras[1].selectId, fhdId)
    compare(r.camerasTruncated, false)
    compare(r.stats, null)
    verify(Model.isActiveCamera(r, r.cameras[0]))
    verify(!Model.isActiveCamera(r, r.cameras[1]))
    verify(stale.link === "not-running", "the old record is not mutated")
  }

  function test_state_replaces_scalars_and_keeps_cameras() {
    var r = snap()
    var res = Model.reduce(r, line(stateObject({ state: "starting", consumers: 2, active_camera: fhdId,
                                                 active_camera_name: "FHD Camera", changed: ["state", "consumers"] })))
    compare(res.outcome, "state")
    compare(res.record.state, "starting")
    compare(res.record.consumers, 2)
    compare(res.record.activeCamera, fhdId)
    compare(res.record.cameras.length, 2)
    verify(Model.isActiveCamera(res.record, res.record.cameras[1]), "active marking follows active_camera")
    compare(r.state, "idle", "previous record untouched")
  }

  function test_cameras_line_replaces_list_and_active() {
    var r = snap()
    var res = Model.reduce(r, line({ v: 1, type: "cameras", active_camera: fhdId,
                                     cameras: [{ id: fhdId, name: "FHD Camera", usb: "5986:1193", active: true }],
                                     cameras_truncated: true }))
    compare(res.outcome, "cameras")
    compare(res.record.cameras.length, 1)
    compare(res.record.activeCamera, fhdId)
    compare(res.record.camerasTruncated, true)
    compare(res.record.camerasCapped, false)
    compare(res.record.state, "idle", "scalars untouched")
  }

  function test_stats_while_active_with_unknown_values() {
    var r = active()
    var res = Model.reduce(r, '{"v":1,"type":"stats","fps":30.0,"latency_p50_ms":41.2,"cpu_percent":6.5,"gpu_percent":-1.0}')
    compare(res.outcome, "stats")
    compare(res.record.stats.fps, 30)
    compare(res.record.stats.latencyMs, 41.2)
    compare(res.record.stats.gpuPercent, null)
    var rows = Model.statsRows(res.record)
    compare(rows.length, 4)
    compare(rows[0].value, "30.0 fps")
    compare(rows[1].value, "41.2 ms")
    compare(rows[2].value, "6.5 %")
    compare(rows[3].value, Model.UNKNOWN, "-1 shows as unknown")
    verify(rows[3].value.indexOf("0") === -1, "never zero")
  }

  function test_stats_hostile_numbers_are_unknown() {
    var res = Model.reduce(active(), '{"v":1,"type":"stats","fps":true,"latency_p50_ms":"40","cpu_percent":null,"gpu_percent":-0.5}')
    compare(res.outcome, "stats")
    compare(res.record.stats.fps, null)
    compare(res.record.stats.latencyMs, null)
    compare(res.record.stats.cpuPercent, null)
    compare(res.record.stats.gpuPercent, null)
  }

  function test_stats_before_first_line_read_unknown() {
    var rows = Model.statsRows(active())
    compare(rows.length, 4)
    for (var i = 0; i < rows.length; i++) compare(rows[i].value, Model.UNKNOWN)
  }

  function test_stats_ignored_outside_active() {
    var r = snap()
    var res = Model.reduce(r, '{"v":1,"type":"stats","fps":30.0,"latency_p50_ms":1,"cpu_percent":1,"gpu_percent":1}')
    compare(res.outcome, "ignored")
    verify(res.record === r)
    compare(Model.statsRows(r).length, 0)
  }

  function test_stats_cleared_when_leaving_active() {
    var r = Model.reduce(active(), '{"v":1,"type":"stats","fps":30.0,"latency_p50_ms":1,"cpu_percent":1,"gpu_percent":1}').record
    verify(r.stats !== null)
    r = Model.reduce(r, line(stateObject({ state: "idle", consumers: 0 }))).record
    compare(r.stats, null)
    compare(Model.statsRows(r).length, 0)
  }

  function test_error_daemon_not_running_until_next_snapshot() {
    var r = active()
    var res = Model.reduce(r, '{"v":1,"type":"error","code":"daemon-not-running","error":"omarchy-broadcastd is not running"}')
    compare(res.outcome, "error")
    r = res.record
    compare(r.link, "not-running")
    compare(r.cameras.length, 0)
    compare(r.stats, null)
    compare(Model.visualKey(r), "unavailable")
    verify(!Model.available(r))
    // state and cameras lines do not revive it; only a snapshot does
    compare(Model.reduce(r, line(stateObject({ state: "idle" }))).outcome, "ignored")
    compare(Model.reduce(r, line({ v: 1, type: "cameras", active_camera: "", cameras: [], cameras_truncated: false })).outcome, "ignored")
    r = Model.reduce(r, line(snapshotObject({}))).record
    compare(r.link, "ok")
    compare(Model.visualKey(r), "idle")
  }

  function test_error_dbus_and_unknown_codes_are_unreachable() {
    var a = Model.reduce(snap(), '{"v":1,"type":"error","code":"dbus-error","error":"timeout"}').record
    compare(a.link, "unreachable")
    compare(a.linkText, "timeout")
    var b = Model.reduce(snap(), '{"v":1,"type":"error","code":"brand-new-code","error":"x"}').record
    compare(b.link, "unreachable")
    var c = Model.reduce(snap(), '{"v":1,"type":"error"}').record
    compare(c.link, "unreachable")
    compare(Model.tooltipText(a), "Omarchy Broadcast: daemon unreachable")
    compare(Model.tooltipText(Model.emptyRecord("not-running")), "Omarchy Broadcast: daemon not running")
  }

  function test_unknown_types_and_fields_are_ignored() {
    var r = snap()
    var res = Model.reduce(r, '{"v":1,"type":"telemetry","x":1}')
    compare(res.outcome, "ignored")
    verify(res.record === r)
    var withExtra = snapshotObject({ brand_new_field: { nested: [1, 2] }, cameras: [{ id: brioId, name: "Brio", usb: "", active: true, extra: 7 }] })
    var s = Model.reduce(r, line(withExtra)).record
    compare(s.link, "ok")
    compare(s.cameras.length, 1)
    compare(s.cameras[0].name, "Brio")
  }

  function test_schema_version() {
    var r = snap()
    var newer = Model.reduce(r, '{"v":2,"type":"snapshot","state":"idle"}')
    compare(newer.outcome, "unsupported")
    compare(newer.record.link, "unsupported")
    verify(newer.record.linkText.indexOf("v2") !== -1)
    compare(Model.visualKey(newer.record), "unavailable")
    var cases = ['{"v":"1","type":"snapshot"}', '{"type":"snapshot"}', '{"v":1.5,"type":"snapshot"}',
                 '{"v":0,"type":"snapshot"}', '{"v":1,"type":7}', '{"v":1}']
    for (var i = 0; i < cases.length; i++) {
      var res = Model.reduce(r, cases[i])
      compare(res.outcome, "invalid", cases[i])
      verify(res.record === r, cases[i])
    }
    // a v1 snapshot recovers from unsupported
    compare(Model.reduce(newer.record, line(snapshotObject({}))).record.link, "ok")
  }

  // An unknown state string is unavailable everywhere: icon, controls, left
  // click, cursor and panel copy agree; a known state line revives it.
  function test_unknown_state_string() {
    var r = snap({ state: "dancing" })
    compare(r.state, "unknown")
    compare(r.rawState, "dancing")
    verify(Model.linked(r), "the stream is still connected")
    verify(!Model.available(r), "but nothing can be controlled")
    compare(Model.visualKey(r), "unavailable")
    compare(Model.leftClickAction(r, false), "open-panel")
    compare(Model.toggleArgv(cli, r), null)
    compare(Model.intentArgv({ verb: "enable", on: true }, cli, r), null)
    compare(Model.intentArgv({ verb: "select", id: fhdId }, cli, r), null)
    verify(!Model.canNext(r))
    compare(Model.cursorStops(r, 2).length, 0)
    compare(Model.statsRows(r).length, 0)
    compare(Model.stateLabel(r), "unsupported state")
    compare(Model.tooltipText(r), "Omarchy Broadcast: unsupported state")
    compare(Model.heroMeta(r), "unavailable")
    verify(Model.unavailableMessage(r).title.indexOf("dancing") !== -1, Model.unavailableMessage(r).title)
    var back = Model.reduce(r, line(stateObject({ state: "idle" })))
    compare(back.outcome, "state")
    verify(Model.available(back.record))
  }

  function test_snapshot_replaces_a_populated_record() {
    var r = Model.reduce(active(), '{"v":1,"type":"stats","fps":30.0,"latency_p50_ms":1,"cpu_percent":1,"gpu_percent":1}').record
    r = Model.reduce(r, line(stateObject({ state: "active", consumers: 3, error: "boom", active_camera: fhdId,
                                           active_camera_name: "FHD Camera", effect: "blur" }))).record
    r = Model.reduce(r, line({ v: 1, type: "cameras", active_camera: fhdId, cameras: cameraObjects(), cameras_truncated: true })).record
    verify(r.stats !== null && r.error === "boom" && r.camerasTruncated && r.consumers === 3)
    var only = [{ id: "usb-1", name: "Only One", usb: "1111:2222", active: true }]
    var res = Model.reduce(r, line(snapshotObject({ state: "idle", consumers: 0, error: "", active_camera: "usb-1",
                                                    active_camera_name: "Only One", effect: "none",
                                                    cameras: only, cameras_truncated: false })))
    compare(res.outcome, "snapshot")
    var s = res.record
    compare(s.stats, null, "stats replaced")
    compare(s.error, "")
    compare(s.consumers, 0)
    compare(s.effect, "none")
    compare(s.activeCamera, "usb-1")
    compare(s.cameras.length, 1, "camera list replaced, not merged")
    compare(s.cameras[0].label, "Only One")
    compare(s.camerasTruncated, false)
    compare(s.camerasTotal, 1)
    // a snapshot in `active` over a record holding stats starts unknown
    var again = Model.reduce(r, line(snapshotObject({ state: "active", consumers: 1 }))).record
    compare(again.stats, null)
    for (var i = 0; i < 4; i++) compare(Model.statsRows(again)[i].value, Model.UNKNOWN)
    verify(r.stats !== null, "the old record is not mutated")
  }

  function test_off_tooltip_includes_error() {
    compare(Model.tooltipText(snap({ state: "off", enabled: false, error: "config <b>rejected</b>" })),
            "Omarchy Broadcast: off \u00b7 error: config brejected/b")
    compare(Model.tooltipText(snap({ state: "off", enabled: false })), "Omarchy Broadcast: off")
  }

  function test_active_camera_not_in_list() {
    var lost = snap({ active_camera: "usb-gone-<x>-video-index0", active_camera_name: "" })
    compare(Model.activeCameraLabel(lost), "usb-gone-x-video-index0", "sanitised id, not none")
    verify(Model.tooltipText(lost).indexOf("usb-gone-x-video-index0") !== -1, Model.tooltipText(lost))
    compare(Model.activeCameraLabel(snap({ active_camera: fhdId, active_camera_name: "" })), "FHD Camera", "row label")
    compare(Model.activeCameraLabel(snap({})), "Logitech MX Brio")
    compare(Model.activeCameraLabel(snap({ active_camera: "", active_camera_name: "" })), "")
    // a cameras line moves the active camera before a state line renames it
    var moved = Model.reduce(snap(), line({ v: 1, type: "cameras", active_camera: fhdId, cameras: cameraObjects(), cameras_truncated: false })).record
    compare(moved.activeCameraName, "Logitech MX Brio", "stale until the next state line")
    compare(Model.activeCameraLabel(moved), "FHD Camera", "the row of the active camera wins")
    compare(Model.activeCameraLabel(snap({ active_camera: "usb-gone", active_camera_name: "Gone Cam" })), "Gone Cam")
  }

  function test_watch_exit_text() {
    compare(Model.watchExitText(15, true, 2000), "omarchy-broadcast watch stopped by signal 15; restarting in 2 s")
    compare(Model.watchExitText(1, false, 1000), "omarchy-broadcast watch exited with status 1; restarting in 1 s")
  }

  // The CLI reads `next` as NextCamera even after `--`.
  function test_camera_with_id_next() {
    var unique = snap({ cameras: [{ id: "next", name: "Odd", usb: "046d:0944", active: false },
                                  { id: fhdId, name: "FHD Camera", usb: "5986:1193", active: false }] })
    compare(unique.cameras[0].selectId, "046d:0944", "selected by its unique vid:pid")
    compare(unique.cameras[0].selectNote, "")
    compare(JSON.stringify(Model.selectArgv(cli, unique.cameras[0].selectId)), JSON.stringify([cli, "camera", "--", "046d:0944"]))
    var shared = snap({ cameras: [{ id: "next", name: "Odd", usb: "5986:1193", active: false },
                                  { id: fhdId, name: "FHD Camera", usb: "5986:1193", active: false }] })
    compare(shared.cameras[0].selectId, "", "a vid:pid two cameras share is ambiguous")
    verify(shared.cameras[0].selectNote !== "")
    compare(shared.cameras[1].selectId, fhdId)
    var bare = snap({ cameras: [{ id: "next", name: "Odd", usb: "", active: false }] })
    compare(bare.cameras[0].selectId, "")
    verify(bare.cameras[0].selectNote.indexOf("next") !== -1)
    var hostileUsb = snap({ cameras: [{ id: "next", name: "Odd", usb: "<b>:x", active: false }] })
    compare(hostileUsb.cameras[0].selectId, "")
    compare(Model.selectArgv(cli, "next"), null, "never camera -- next")
    compare(Model.intentArgv({ verb: "select", id: "next" }, cli, snap()), null)
  }

  function test_upper_clamps() {
    compare(snap({ consumers: 1000000 }).consumers, 1000000)
    compare(snap({ consumers: 1000001 }).consumers, -1)
    compare(snap({ consumers: 1e300 }).consumers, -1)
    verify(Model.tooltipText(snap({ consumers: 1e300 })).indexOf("e+") === -1)
    var res = Model.reduce(active(), '{"v":1,"type":"stats","fps":1e300,"latency_p50_ms":2000000,"cpu_percent":1000000,"gpu_percent":5}')
    compare(res.record.stats.fps, null)
    compare(res.record.stats.latencyMs, null)
    compare(res.record.stats.cpuPercent, 1000000)
    var rows = Model.statsRows(res.record)
    compare(rows[0].value, Model.UNKNOWN)
    compare(rows[1].value, Model.UNKNOWN)
    compare(Model.formatStat(2e6, 1, " fps"), Model.UNKNOWN)
  }

  function test_truncation_text() {
    compare(Model.truncationText(snap()), "")
    var many = []
    for (var i = 0; i < 290; i++) many.push({ id: "cam-" + i, name: "Camera " + i, usb: "", active: false })
    var capped = Model.applyMessage(Model.emptyRecord("connecting"), snapshotObject({ cameras: many })).record
    compare(Model.truncationText(capped), "Showing 64 of 290 cameras")
    compare(Model.truncationText(snap({ cameras_truncated: true })), "More cameras are connected; they are not shown")
  }

  function test_stderr_first_line() {
    var st = Model.firstLineStart()
    st = Model.firstLineFeed(st, "omarchy-broadcast: no camera ")
    compare(st.done, false)
    st = Model.firstLineFeed(st, "matches\nsecond line\n")
    compare(st.done, true)
    compare(st.text, "omarchy-broadcast: no camera matches")
    verify(Model.firstLineFeed(st, "more") === st, "ignored once done")
    // blank first lines are skipped
    var b = Model.firstLineFeed(Model.firstLineStart(), "\n  \nreal\n")
    compare(b.text, "real")
    // a huge line without a newline stops at the cap, chunk by chunk
    var chunk = ""
    for (var i = 0; i < 65536; i++) chunk += "e"
    var h = Model.firstLineStart()
    var t0 = Date.now()
    for (var j = 0; j < 16 && !h.done; j++) h = Model.firstLineFeed(h, chunk)
    verify(Date.now() - t0 < 100)
    compare(h.done, true)
    compare(h.text.length, Model.STDERR_CAP)
    compare(j, 1, "done after the first chunk")
    verify(Model.commandFailureText(1, h.text, cli).length <= Model.DETAIL_CAP + 60)
  }

  function test_intents_are_rechecked_when_they_run() {
    var r = snap()
    compare(JSON.stringify(Model.intentArgv({ verb: "enable", on: false }, cli, r)), JSON.stringify([cli, "off"]))
    compare(JSON.stringify(Model.intentArgv({ verb: "select", id: fhdId }, cli, r)), JSON.stringify([cli, "camera", "--", fhdId]))
    compare(JSON.stringify(Model.intentArgv({ verb: "next" }, cli, r)), JSON.stringify([cli, "camera", "next"]))
    compare(JSON.stringify(Model.intentArgv({ verb: "enable", on: true }, "/new/omarchy-broadcast", r)),
            JSON.stringify(["/new/omarchy-broadcast", "on"]), "the CLI path of the moment")
    var gone = Model.emptyRecord("not-running")
    compare(Model.intentArgv({ verb: "enable", on: true }, cli, gone), null, "never D-Bus-activates a stopped daemon")
    compare(Model.intentArgv({ verb: "select", id: fhdId }, cli, gone), null)
    compare(Model.intentArgv({ verb: "next" }, cli, gone), null)
    compare(Model.intentArgv({ verb: "next" }, cli, snap({ cameras: [cameraObjects()[0]] })), null)
    compare(Model.intentArgv({ verb: "enable", on: true }, "", r), null)
    compare(Model.intentArgv({ verb: "rm" }, cli, r), null)
    compare(Model.intentArgv(null, cli, r), null)
  }

  function test_left_click_while_busy() {
    compare(Model.leftClickAction(snap(), false), "toggle")
    compare(Model.leftClickAction(snap(), true), "ignore")
    compare(Model.leftClickAction(Model.emptyRecord("not-running"), true), "open-panel")
  }

  function test_backoff_resets_only_after_uptime() {
    compare(Model.backoffAfterExit(8000, 100), 8000)
    compare(Model.backoffAfterExit(8000, Model.BACKOFF_RESET_UPTIME_MS - 1), 8000)
    compare(Model.backoffAfterExit(8000, Model.BACKOFF_RESET_UPTIME_MS), Model.BACKOFF_MIN_MS)
    compare(Model.backoffAfterExit(NaN, 0), Model.BACKOFF_MIN_MS)
    compare(Model.backoffAfterExit(999999, 0), Model.BACKOFF_MAX_MS)
    // a watch that prints its snapshot and dies after 100 ms, seven times
    var due = Model.BACKOFF_MIN_MS
    var delays = []
    for (var i = 0; i < 7; i++) {
      var d = Model.backoffAfterExit(due, 100)
      delays.push(d)
      due = Model.nextBackoff(d)
    }
    compare(JSON.stringify(delays), JSON.stringify([1000, 2000, 4000, 8000, 16000, 30000, 30000]))
  }

  function test_cursor_stops() {
    var r = Model.reduce(snap(), line({ v: 1, type: "cameras", active_camera: brioId,
      cameras: cameraObjects().concat([{ id: "third", name: "Third", usb: "", active: false }]), cameras_truncated: false })).record
    var stops = Model.cursorStops(r, r.cameras.length)
    compare(JSON.stringify(stops.map(function(s) { return s.kind + s.index })),
            JSON.stringify(["switch-1", "effect-1", "camera0", "camera1", "camera2", "next-1"]))
    compare(Model.cursorStops(r, 2).length, 5, "follows the rendered row count")
    var one = snap({ cameras: [cameraObjects()[0]] })
    compare(JSON.stringify(Model.cursorStops(one, 1).map(function(s) { return s.kind })), JSON.stringify(["switch", "effect", "camera"]))
    compare(Model.cursorStops(Model.emptyRecord("not-running"), 3).length, 0)
    // a CLI that predates effects: nothing on the effect row can be requested
    compare(JSON.stringify(Model.cursorStops(snap({ cameras: [cameraObjects()[0]], blur_strength: undefined }), 1)
                           .map(function(s) { return s.kind })), JSON.stringify(["switch", "camera"]))
    compare(Model.clampCursor(-3, 5), 0)
    compare(Model.clampCursor(9, 5), 4)
    compare(Model.clampCursor(2, 0), 0)
    compare(Model.stopIndex(stops, "camera", 2), 4)
    compare(Model.stopIndex(stops, "effect", -1), 1)
    compare(Model.stopIndex(stops, "next", -1), 5)
    compare(Model.stopIndex(stops, "camera", 7), -1)
  }

  function test_hero_meta_has_no_command_names() {
    compare(Model.heroMeta(snap()), "idle")
    compare(Model.heroMeta(snap({ state: "off", enabled: false })), "off")
    compare(Model.heroMeta(Model.emptyRecord("connecting")), "connecting\u2026")
    var links = ["not-running", "unreachable", "cli-missing", "cli-failed", "unsupported"]
    for (var i = 0; i < links.length; i++) {
      var rec = Model.withLink(links[i], "omarchy-broadcast CLI not found: /x")
      var meta = Model.heroMeta(rec)
      compare(meta, "unavailable", links[i])
      verify(Model.unavailableMessage(rec).title.toLowerCase() !== meta, "body does not repeat the status line")
    }
  }

  function test_malformed_lines_leave_the_record() {
    var r = snap()
    var cases = ["{", "[]", "null", "42", "\"text\"", "{\"v\":1,\"type\":\"snapshot\"", "garbage <img src=x>"]
    for (var i = 0; i < cases.length; i++) {
      var res = Model.reduce(r, cases[i])
      compare(res.outcome, "invalid", cases[i])
      verify(res.record === r)
    }
    compare(Model.reduce(r, "").outcome, "ignored")
    compare(Model.reduce(r, "   ").outcome, "ignored")
    compare(Model.reduce(r, undefined).outcome, "invalid")
  }

  function test_overlong_line_dropped_before_parse() {
    var r = snap()
    var big = line(snapshotObject({ state: "off" }))
    while (big.length <= Model.LINE_CAP) big = big + " "
    var res = Model.reduce(r, big)
    compare(res.outcome, "dropped")
    verify(res.record === r)
    // exactly at the cap still parses
    var atCap = line(snapshotObject({ state: "off" }))
    while (atCap.length < Model.LINE_CAP) atCap = atCap + " "
    compare(atCap.length, Model.LINE_CAP)
    compare(Model.reduce(r, atCap).record.state, "off")
  }

  // ---- sanitising and caps -------------------------------------------------

  function test_sanitize_hostile_names() {
    var s = Model.sanitize("<img src='http://x/y'>", 64)
    verify(s.indexOf("<") === -1 && s.indexOf(">") === -1, s)
    compare(Model.sanitize("a&b", 64), "ab")
    compare(Model.sanitize("line1\nline2\r\tend", 64), "line1 line2 end")
    compare(Model.sanitize("\u202eevil", 64), "evil")
    // bidi marks and zero-width characters, mid-string as well as at the ends
    compare(Model.sanitize("/h/\u202egnp.exe\u2066\u061c\u200b\ufeff", 64), "/h/gnp.exe")
    compare(Model.sanitize("a\u061cb\u200bc\ufeffd\u200ee\u200ff\u2068g\u2069h", 64), "abcdefgh")
    verify(!/[\u061c\u200b\u200e\u200f\u202a-\u202e\u2060-\u206f\ufeff]/.test(
             Model.sanitize("\u061c\u200b\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2060\u2061\u2064\u2066\u2067\u2068\u2069\u206a\u206f\ufeffx", 64)))
    compare(Model.sanitize("\u2060\u2061\u2062\u2063\u2064\u206a\u206fx", 64), "x", "invisible formatting block")
    compare(Model.sanitize(42, 64), "")
    compare(Model.sanitize(null, 64), "")
    var r = snap({ cameras: [{ id: "<b>id</b>", name: "<img src='http://x/y'>", usb: "<u>", active: false }],
                   active_camera_name: "a&b\n<i>x</i>", error: "<a href='x'>e</a>", output_mode: "<b>NV12</b>" })
    var texts = [r.cameras[0].name, r.cameras[0].displayId, r.cameras[0].usb, r.cameras[0].label,
                 r.activeCameraName, r.error, r.outputMode, Model.tooltipText(r)]
    for (var i = 0; i < texts.length; i++) {
      verify(!/[<>&\n]/.test(texts[i]), "sanitised: " + texts[i])
    }
    compare(r.cameras[0].id, "<b>id</b>", "the raw id is kept for argv")
  }

  // The joiners are kept: emoji sequences and Persian or Arabic words need them.
  function test_sanitize_keeps_joiners() {
    // family: man ZWJ woman ZWJ girl
    var family = "\ud83d\udc68\u200d\ud83d\udc69\u200d\ud83d\udc67"
    compare(Model.sanitize(family, 64), family, "emoji ZWJ sequence")
    compare(Model.sanitize("Cam " + family + " HD", 64), "Cam " + family + " HD")
    // woman technologist with a variation selector: ZWJ and VS16 survive
    var tech = "\ud83d\udc69\ud83c\udfff\u200d\ud83d\udcbb\ufe0f"
    compare(Model.sanitize(tech, 64), tech, "skin tone, ZWJ, variation selector")
    // Persian "mi-khaham" (I want): ZWNJ between the prefix and the stem
    var persian = "\u0645\u06cc\u200c\u062e\u0648\u0627\u0647\u0645"
    compare(Model.sanitize(persian, 64), persian, "Persian name with ZWNJ")
    compare(Model.sanitize("\u0648\u0628\u200c\u06a9\u0645 USB", 64), "\u0648\u0628\u200c\u06a9\u0645 USB")
    // in a record: the camera name and the active camera name
    var r = snap({ cameras: [{ id: "a", name: persian, usb: "1234:abcd", active: true },
                             { id: "b", name: family, usb: "1234:abce", active: false }],
                   active_camera: "a", active_camera_name: persian })
    compare(r.cameras[0].name, persian)
    compare(r.cameras[1].name, family)
    compare(r.activeCameraName, persian)
  }

  function test_sanitize_strips_bidi_overrides_around_joiners() {
    var persian = "\u0645\u06cc\u200c\u062e\u0648\u0627\u0647\u0645"
    var family = "\ud83d\udc68\u200d\ud83d\udc69\u200d\ud83d\udc67"
    // an override and isolates are removed, the joiners next to them stay
    compare(Model.sanitize("\u202e" + persian, 64), persian, "RLO stripped")
    compare(Model.sanitize("\u202a" + family + "\u202c\u2066\u2067\u2068\u2069", 64), family)
    compare(Model.sanitize("Cam \u202egnp.exe", 64), "Cam gnp.exe")
    compare(Model.sanitize("a\u202eb\u200dc\u2067d\u200ce\u2069f", 64), "ab\u200dcd\u200cef")
    // markup and control characters still go
    compare(Model.sanitize("<b>" + persian + "&\n</b>", 64), "b" + persian + " /b")
  }

  function test_sanitize_marks_a_precut_even_when_little_is_left() {
    var junk = ""
    for (var i = 0; i < 2100; i++) junk += "<"
    var s = Model.sanitize("/" + junk + "tail.png", 512)
    compare(s, "/\u2026", "the cut shows")
    compare(Model.sanitize(junk, 64), "\u2026")
    // a string that fits is not marked
    compare(Model.sanitize("<<<ok>>>", 64), "ok")
  }

  function test_sanitize_long_strings_capped() {
    var huge = ""
    for (var i = 0; i < 10240; i++) huge += "x"
    var t0 = Date.now()
    var s = Model.sanitize(huge, Model.NAME_CAP)
    verify(Date.now() - t0 < 100)
    compare(s.length, Model.NAME_CAP)
    compare(s.charAt(s.length - 1), "\u2026")
    // Applied as an object: as a line this would exceed LINE_CAP and be dropped.
    var r = Model.applyMessage(Model.emptyRecord("connecting"),
      snapshotObject({ cameras: [{ id: brioId, name: huge, usb: huge, active: true }], error: huge + huge, output_mode: huge })).record
    compare(r.cameras[0].name.length, Model.NAME_CAP)
    compare(r.cameras[0].usb.length, Model.USB_CAP)
    compare(r.error.length, Model.ERROR_CAP)
    compare(r.outputMode.length, Model.MODE_CAP)
    // no lone surrogate at a cut
    var emoji = ""
    for (var j = 0; j < 40; j++) emoji += "😀"
    var e = Model.sanitize(emoji, 10)
    var last = e.charCodeAt(e.length - 2)
    verify(!(last >= 0xd800 && last <= 0xdbff), "no dangling high surrogate")
  }

  function test_camera_cap_1000() {
    var many = []
    for (var i = 0; i < 1000; i++) many.push({ id: "cam-" + i, name: "Camera " + i, usb: "", active: false })
    var t0 = Date.now()
    var res = Model.applyMessage(Model.emptyRecord("connecting"), snapshotObject({ cameras: many }))
    verify(Date.now() - t0 < 100, "1000 cameras in < 100 ms")
    compare(res.record.cameras.length, Model.CAMERA_CAP)
    compare(res.record.camerasCapped, true)
    compare(res.record.camerasTruncated, true)
    // at the cap: not capped
    var exact = many.slice(0, Model.CAMERA_CAP)
    var e = Model.applyMessage(Model.emptyRecord("connecting"), snapshotObject({ cameras: exact })).record
    compare(e.cameras.length, Model.CAMERA_CAP)
    compare(e.camerasCapped, false)
    compare(e.camerasTruncated, false)
    // junk entries are skipped, not fatal
    var junk = Model.applyMessage(Model.emptyRecord("connecting"), snapshotObject({ cameras: [null, 7, "x", [], { id: 5 }] })).record
    compare(junk.cameras.length, 1)
    compare(junk.cameras[0].selectId, "")
    compare(Model.applyMessage(Model.emptyRecord("connecting"), snapshotObject({ cameras: "nope" })).record.cameras.length, 0)
  }

  function test_numbers() {
    compare(snap({ consumers: -1 }).consumers, -1)
    compare(snap({ consumers: 1.5 }).consumers, -1)
    compare(snap({ consumers: "3" }).consumers, -1)
    // 1e400 is Infinity once parsed (or the line is rejected): unknown either way.
    var inf = Model.reduce(snap({ consumers: 5 }), '{"v":1,"type":"snapshot","state":"idle","consumers":1e400}')
    verify(inf.outcome === "invalid" || inf.outcome === "snapshot", inf.outcome)
    if (inf.outcome === "snapshot") compare(inf.record.consumers, -1)
    compare(Model.statNumber(Infinity), null)
    compare(Model.statNumber(NaN), null)
    compare(Model.count(Infinity), -1)
    compare(Model.count(NaN), -1)
    compare(snap({ consumers: 3 }).consumers, 3)
    compare(Model.consumersText(1), "1 consumer")
    compare(Model.consumersText(2), "2 consumers")
    compare(Model.consumersText(-1), "unknown")
  }

  function test_selectable_ids() {
    compare(Model.selectableId(brioId), brioId)
    compare(Model.selectableId(""), "")
    compare(Model.selectableId(7), "")
    compare(Model.selectableId("clipped\u2026"), "")
    var long = ""
    for (var i = 0; i < 97; i++) long += "a"
    compare(Model.selectableId(long), "")
    compare(Model.selectableId(long.slice(1)), long.slice(1))
  }

  // ---- visuals and text ----------------------------------------------------

  function test_six_visual_states_are_distinct() {
    var seen = {}
    var glyphs = {}
    for (var i = 0; i < Model.VISUAL_KEYS.length; i++) {
      var key = Model.VISUAL_KEYS[i]
      var v = Model.visualFor(key)
      compare(v.key, key)
      verify(v.glyph.length > 0)
      var cp = v.glyph.codePointAt(0)
      verify(cp >= 0xf0000 && cp <= 0xffffd, "a Material Design Nerd Font glyph: " + key)
      verify(["foreground", "accent", "urgent"].indexOf(v.colorRole) !== -1)
      var tuple = v.glyph + "|" + v.colorRole + "|" + v.dimmed
      verify(!seen[tuple], "distinct: " + key)
      seen[tuple] = true
      glyphs[v.glyph] = true
    }
    compare(Object.keys(glyphs).length, 6, "every state has its own glyph")
    compare(Model.visualFor("off").dimmed, true)
    compare(Model.visualFor("unavailable").dimmed, true)
    compare(Model.visualFor("idle").colorRole, "foreground")
    compare(Model.visualFor("active").colorRole, "accent")
    compare(Model.visualFor("starting").colorRole, "accent")
    compare(Model.visualFor("error").colorRole, "urgent")
    compare(Model.visualFor("whatever").key, "unavailable")
  }

  function test_visual_key_from_record() {
    compare(Model.visualKey(null), "unavailable")
    compare(Model.visualKey(Model.emptyRecord("connecting")), "unavailable")
    compare(Model.visualKey(Model.emptyRecord("cli-missing")), "unavailable")
    compare(Model.visualKey(snap({ state: "off", enabled: false })), "off")
    compare(Model.visualKey(snap({ state: "error", error: "boom" })), "error")
    compare(Model.visualKey(active()), "active")
    // a non-empty error outside the error state does not make the icon urgent
    compare(Model.visualKey(snap({ error: "config rejected" })), "idle")
  }

  function test_tooltips() {
    var r = Model.reduce(active(), line(stateObject({ state: "active", consumers: 2 }))).record
    compare(Model.tooltipText(r), "Omarchy Broadcast: active \u00b7 Logitech MX Brio \u00b7 2 consumers")
    compare(Model.tooltipText(snap({ state: "off", enabled: false })), "Omarchy Broadcast: off")
    compare(Model.tooltipText(snap({ state: "idle", consumers: 1 })), "Omarchy Broadcast: idle \u00b7 Logitech MX Brio \u00b7 1 consumer")
    compare(Model.tooltipText(snap({ active_camera: "", active_camera_name: "" })), "Omarchy Broadcast: idle \u00b7 no camera \u00b7 0 consumers")
    compare(Model.tooltipText(snap({ state: "error", error: "loopback missing" })), "Omarchy Broadcast: error \u00b7 loopback missing")
    verify(Model.tooltipText(snap({ error: "bad config" })).indexOf("error: bad config") !== -1)
    compare(Model.tooltipText(Model.emptyRecord("cli-missing")), "Omarchy Broadcast: omarchy-broadcast CLI not found")
    compare(Model.tooltipText(Model.emptyRecord("connecting")), "Omarchy Broadcast: connecting\u2026")
    var hostile = snap({ active_camera_name: "<img src='http://x/y'>" })
    verify(!/[<>&]/.test(Model.tooltipText(hostile)))
  }

  function test_unavailable_messages() {
    var m = Model.unavailableMessage(Model.emptyRecord("not-running"))
    compare(m.title, "omarchy-broadcastd is not running")
    compare(m.commandText, "systemctl --user start omarchy-broadcastd")
    compare(Model.unavailableMessage(snap()).title, "")
    var c = Model.unavailableMessage(Model.withLink("cli-missing", "omarchy-broadcast CLI not found: /nope"))
    compare(c.title, "omarchy-broadcast CLI not found:")
    compare(c.path, "/nope")
    var none = Model.unavailableMessage(Model.emptyRecord("cli-missing"))
    compare(none.title, "omarchy-broadcast CLI not found")
    compare(none.path, "")
    verify(Model.unavailableMessage(Model.emptyRecord("unreachable")).title !== m.title, "unreachable reads differently")
  }

  // A path is never left inside a wrapping title: it is split off to a line of
  // its own, drawn with wrapping at any character. Every message that can carry
  // one is covered: the configured cliPath, the resolver's miss, the command failure.
  function test_paths_leave_the_title() {
    var cases = [
      Model.CLI_MISSING_TEXT + ": /nonexistent/omarchy-broadcast",
      Model.CLI_MISSING_TEXT + ": /home/a b/with space/omarchy-broadcast",
      Model.resolverMissText("/p/br.com.dias.omarchy-broadcast")
    ]
    var paths = ["/nonexistent/omarchy-broadcast", "/home/a b/with space/omarchy-broadcast",
                 "/p/br.com.dias.omarchy-broadcast/../../../target/release/omarchy-broadcast"]
    for (var i = 0; i < cases.length; i++) {
      var m = Model.unavailableMessage(Model.withLink("cli-missing", cases[i]))
      compare(m.path, paths[i], cases[i])
      verify(m.title.indexOf("/") === -1, "no slash left in the title: " + m.title)
      compare(m.title + " " + m.path, cases[i], "nothing lost")
      compare(m.detail, "")
      verify(m.hint.indexOf("\n") !== -1 && m.hint.split("\n").every(function(l) { return l.length <= 32 }),
             "short hint lines")
    }
    // No path in the text: the title is the whole text, the path empty.
    for (var reason of ["cliPath must be an absolute path", "HOME is not set",
                        "the cliPath setting is not text", Model.resolverMissText("")]) {
      var r = Model.unavailableMessage(Model.withLink("cli-missing", reason))
      compare(r.path, "", reason)
      compare(r.title, reason)
    }
    // The other links carry no path of their own: path is always present and empty.
    var links = ["connecting", "ok", "not-running", "unreachable", "cli-failed", "unsupported"]
    for (var k = 0; k < links.length; k++)
      compare(Model.unavailableMessage(Model.withLink(links[k], "text")).path, "", links[k])
    compare(Model.unavailableMessage(snap({ state: "dancing" })).path, "")
    // The command failure: only the CLI-missing text is split.
    var f = Model.commandErrorParts(Model.commandFailureText(-1, "", "/nope/omarchy-broadcast"))
    compare(f.text, "omarchy-broadcast CLI not found:")
    compare(f.path, "/nope/omarchy-broadcast")
    var g = Model.commandErrorParts(Model.commandFailureText(1, "omarchy-broadcast: no camera matches /dev/video3 now", cli))
    compare(g.path, "", "the CLI's own words are shown whole")
    compare(g.text, "The daemon refused the request: no camera matches /dev/video3 now")
    // A path that itself holds " /": everything after the first one is the path.
    var sp = Model.commandErrorParts(Model.CLI_MISSING_TEXT + ": /a /b/c")
    compare(sp.text, Model.CLI_MISSING_TEXT + ":")
    compare(sp.path, "/a /b/c")
    var sm = Model.unavailableMessage(Model.withLink("cli-missing", Model.CLI_MISSING_TEXT + ": /a /b/c"))
    compare(sm.path, "/a /b/c")
    // No cliPath: the whole text, an empty path.
    var np = Model.commandErrorParts(Model.commandFailureText(-1, "", ""))
    compare(np.text, Model.CLI_MISSING_TEXT + ":", "the text is trimmed, nothing to split")
    compare(np.path, "")
    compare(Model.commandErrorParts("").text, "")
    compare(Model.commandErrorParts("").path, "")
    compare(Model.commandErrorParts(undefined).text, "")
    // Hostile text stays plain: the split never adds markup, the sanitising is the record's.
    var h = Model.unavailableMessage(Model.withLink("cli-missing", "x <img src=\"http://a/b\"> /p/<b>q&r"))
    verify(!/[<>&]/.test(h.title + h.path), h.title + "|" + h.path)
  }

  function test_command_failure_text() {
    compare(Model.commandFailureText(3, "", cli), "omarchy-broadcastd is not running")
    var t = Model.commandFailureText(1, "omarchy-broadcast: no camera matches <img src=x>\n", cli)
    verify(t.indexOf("The daemon refused the request: no camera matches") === 0, t)
    verify(!/[<>&\n]/.test(t))
    verify(Model.commandFailureText(-1, "", "/nope/omarchy-broadcast").indexOf("/nope/omarchy-broadcast") !== -1)
    verify(Model.commandFailureText(4, "timeout", cli).indexOf("D-Bus failure") === 0)
    verify(Model.commandFailureText(2, "", cli).indexOf("Invalid command line") === 0)
    verify(Model.commandFailureText(137, "", cli).indexOf("status 137") !== -1)
    var long = ""
    for (var i = 0; i < 5000; i++) long += "e"
    verify(Model.commandFailureText(1, long, cli).length <= Model.DETAIL_CAP + 60)
  }

  // ---- commands ------------------------------------------------------------

  function test_toggle_argv() {
    compare(JSON.stringify(Model.toggleArgv(cli, snap({ enabled: true }))), JSON.stringify([cli, "off"]))
    compare(JSON.stringify(Model.toggleArgv(cli, snap({ state: "off", enabled: false }))), JSON.stringify([cli, "on"]))
    compare(Model.toggleArgv(cli, Model.emptyRecord("not-running")), null, "privacy fails closed")
    compare(Model.toggleArgv(cli, Model.emptyRecord("connecting")), null)
    compare(Model.toggleArgv("", snap()), null)
    compare(Model.leftClickAction(snap()), "toggle")
    compare(Model.leftClickAction(Model.emptyRecord("not-running")), "open-panel")
    compare(Model.leftClickAction(Model.emptyRecord("cli-missing")), "open-panel")
  }

  function test_select_argv_hostile_ids_stay_one_element() {
    var ids = ["--flag", "$(id)", "; rm -rf ~", "`id`", "a b", "-", "'quoted'", brioId]
    for (var i = 0; i < ids.length; i++) {
      var argv = Model.selectArgv(cli, ids[i])
      compare(argv.length, 4, ids[i])
      compare(argv[0], cli)
      compare(argv[1], "camera")
      compare(argv[2], "--", "the id comes after --")
      compare(argv[3], ids[i], "exact value, one element")
    }
    compare(Model.selectArgv(cli, ""), null)
    compare(Model.selectArgv(cli, 42), null)
    compare(Model.selectArgv(cli, "clipped\u2026"), null)
    compare(Model.selectArgv("", brioId), null)
  }

  function test_next_and_watch_argv() {
    compare(JSON.stringify(Model.nextArgv(cli)), JSON.stringify([cli, "camera", "next"]))
    compare(JSON.stringify(Model.watchArgv(cli)), JSON.stringify([cli, "watch", "--json"]))
    compare(JSON.stringify(Model.enableArgv(cli, true)), JSON.stringify([cli, "on"]))
    compare(Model.watchArgv(""), null)
    verify(Model.canNext(snap()))
    verify(!Model.canNext(snap({ cameras: [cameraObjects()[0]] })))
    verify(!Model.canNext(Model.emptyRecord("not-running")))
  }

  function test_watch_gate_and_backoff() {
    verify(Model.shouldWatch(1, cli, false))
    verify(Model.shouldWatch(2, cli, false))
    verify(!Model.shouldWatch(0, cli, false), "no readers, no watch")
    verify(!Model.shouldWatch(1, cli, true), "waiting out a backoff")
    verify(!Model.shouldWatch(1, "", false), "no CLI")
    var ms = Model.BACKOFF_MIN_MS
    var seen = [ms]
    for (var i = 0; i < 8; i++) { ms = Model.nextBackoff(ms); seen.push(ms) }
    compare(JSON.stringify(seen.slice(0, 6)), JSON.stringify([1000, 2000, 4000, 8000, 16000, 30000]))
    compare(ms, Model.BACKOFF_MAX_MS)
    compare(Model.nextBackoff(NaN), 2000)
  }

  // ---- effects -------------------------------------------------------------

  readonly property string image: "/home/u/Pictures/office.jpg"

  function test_effect_argv_whitelist() {
    for (var i = 0; i < Model.EFFECTS.length; i++)
      compare(JSON.stringify(Model.effectArgv(cli, Model.EFFECTS[i])), JSON.stringify([cli, "effect", Model.EFFECTS[i]]))
    compare(JSON.stringify(Model.EFFECTS), JSON.stringify(["none", "blur", "replace"]))
    var refused = ["", "blur; rm -rf ~", "--image", "--image=/etc/passwd", "-h", "Blur", " blur", "blur ",
                   "blur\n", "none\u0000", "$(id)", "`id`", "replace --image /x", "unknown", "constructor",
                   "toString", "__proto__", "0", "next"]
    for (var r = 0; r < refused.length; r++)
      compare(Model.effectArgv(cli, refused[r]), null, JSON.stringify(refused[r]))
    var odd = [null, undefined, 0, 1, true, ["blur"], { effect: "blur" }, new String("blur")]
    for (var o = 0; o < odd.length; o++) compare(Model.effectArgv(cli, odd[o]), null, String(odd[o]))
    compare(Model.effectArgv("", "blur"), null, "no CLI")
    compare(Model.effectArgv("omarchy-broadcast", "blur"), null, "a bare name is not a CLI path")
    compare(Model.effectArgv("/a/b\nc", "blur"), null)
  }

  function test_effect_fields_parsed() {
    var r = snap({ effect: "blur", blur_strength: 0.5, background_image: image })
    compare(r.effect, "blur")
    compare(r.effectKey, "blur")
    compare(r.blurStrength, 0.5)
    compare(r.backgroundImage, image)
    verify(r.cliEffects)
    verify(r.backgroundImageSet)
    // absent fields (an older producer; JSON drops undefined) read unknown / empty
    var old = snap({ blur_strength: undefined, background_image: undefined })
    compare(old.effectKey, "none")
    compare(old.blurStrength, null)
    compare(old.backgroundImage, "")
    compare(old.backgroundImageSet, false)
    compare(old.cliEffects, false)
    // a state line replaces them, as every scalar
    var s = Model.reduce(r, line(stateObject({ changed: ["effect", "blur_strength"], effect: "replace",
                                               blur_strength: 0.25, background_image: image }))).record
    compare(s.effectKey, "replace")
    compare(s.blurStrength, 0.25)
    compare(r.effectKey, "blur", "the old record is not mutated")
    var cleared = Model.reduce(s, line(stateObject({ changed: ["background_image"], effect: "none", background_image: "",
                                                     blur_strength: undefined }))).record
    compare(cleared.backgroundImage, "")
    compare(cleared.backgroundImageSet, false)
    compare(cleared.blurStrength, null)
    compare(cleared.cliEffects, false, "a state line decides the capability as a snapshot does")
    compare(Model.emptyRecord("not-running").effectKey, "")
    compare(Model.emptyRecord("not-running").cliEffects, false)
    compare(Model.emptyRecord("not-running").backgroundImageSet, false)
  }

  function test_blur_strength_bounds() {
    var good = [0, 1, 0.5, 0.001]
    for (var i = 0; i < good.length; i++) compare(snap({ blur_strength: good[i] }).blurStrength, good[i])
    // JSON cannot carry NaN or Infinity; the reducer sees them only through
    // Model.blurStrength itself.
    var bad = [NaN, Infinity, -Infinity, -0.01, -1, 1.0001, 2, 1e300]
    for (var b = 0; b < bad.length; b++) compare(Model.blurStrength(bad[b]), null, String(bad[b]))
    var wire = [-0.5, 1.5, 1e300, "0.5", "", null, true, [0.5], { v: 0.5 }]
    for (var w = 0; w < wire.length; w++)
      compare(snap({ blur_strength: wire[w] }).blurStrength, null, JSON.stringify(wire[w]))
    var r = snap({ effect: "blur", blur_strength: 0.456 })
    compare(JSON.stringify(Model.effectRows(r)), JSON.stringify([{ label: "Strength", value: "46 %" }]))
    compare(Model.effectRows(snap({ effect: "blur", blur_strength: 1.5 }))[0].value, Model.UNKNOWN)
    compare(Model.effectRows(snap({ effect: "blur", blur_strength: "0.5" })).length, 0, "a string: a CLI without effects")
    compare(Model.effectRows(snap({ effect: "none", blur_strength: 0.5 })).length, 0, "only while blurring")
  }

  function test_background_image_sanitised_and_capped() {
    var hostile = snap({ effect: "replace", background_image: "/tmp/<img src='http://x/y'>&\n\u202epic.png" })
    verify(!/[<>&\n\u202e]/.test(hostile.backgroundImage), hostile.backgroundImage)
    verify(hostile.backgroundImage.indexOf("/tmp/") === 0, hostile.backgroundImage)
    var long = "/"
    for (var i = 0; i < 5000; i++) long += "d"
    var r = snap({ effect: "replace", background_image: long })
    compare(r.backgroundImage.length, Model.IMAGE_PATH_CAP)
    compare(r.backgroundImage.charAt(r.backgroundImage.length - 1), "\u2026", "ellipsised")
    var odd = [42, null, true, ["/a"], { p: "/a" }]
    for (var o = 0; o < odd.length; o++)
      compare(snap({ background_image: odd[o] }).backgroundImage, "", JSON.stringify(odd[o]))
    compare(JSON.stringify(Model.effectRows(snap({ effect: "replace", background_image: image }))),
            JSON.stringify([{ label: "Image", value: "\u2066" + image + "\u2069" }]), "inside a left-to-right isolate")
    // a path whose first letter is right-to-left still sits in an LTR isolate
    var heb = "/\u05d0\u05d1\u05d2/c.png"
    compare(Model.effectRows(snap({ effect: "replace", background_image: heb }))[0].value,
            "\u2066" + heb + "\u2069", "LRI, not first-strong")
    compare(Model.effectRows(snap({ effect: "replace", background_image: "" }))[0].value, Model.UNKNOWN)
  }

  function test_unknown_effect_is_never_selected() {
    var r = snap({ effect: "sepia<b>", background_image: image })
    compare(r.effectKey, "")
    compare(r.effect, "sepiab", "display copy only, sanitised")
    var opts = Model.effectOptions(r)
    compare(opts.filter(function(o) { return o.selected }).length, 0)
    compare(JSON.stringify(opts.map(function(o) { return o.value })), JSON.stringify(Model.EFFECTS),
            "the choices are the whitelist, never the daemon's word")
    var hint = Model.effectHint(r)
    verify(hint.text.indexOf("does not know: sepiab") !== -1, hint.text)
    compare(hint.commandText, "")
    compare(Model.effectSummary(r), "")
    compare(Model.effectRows(r).length, 0)
    compare(Model.effectIndex(r.effectKey), -1)
    // one that differs only in case or spacing is unknown too
    compare(snap({ effect: "Blur" }).effectKey, "")
    compare(snap({ effect: " blur" }).effectKey, "")
    compare(snap({ effect: 7 }).effectKey, "")
  }

  function test_replace_needs_a_background_image() {
    var none = snap({ effect: "none", background_image: "" })
    verify(Model.effectSelectable(none, "none"))
    verify(Model.effectSelectable(none, "blur"))
    verify(!Model.effectSelectable(none, "replace"), "no image: Replace is not offered")
    var opts = Model.effectOptions(none)
    compare(JSON.stringify(opts.map(function(o) { return o.label })), JSON.stringify(["None", "Blur", "Replace"]))
    compare(JSON.stringify(opts.map(function(o) { return o.selected })), JSON.stringify([true, false, false]))
    compare(JSON.stringify(opts.map(function(o) { return o.selectable })), JSON.stringify([false, true, false]),
            "the current effect and Replace without an image cannot be chosen")
    compare(JSON.stringify(opts.map(function(o) { return o.faded })), JSON.stringify([false, false, true]),
            "only Replace is faded; the current effect never is")
    var hint = Model.effectHint(none)
    compare(hint.text, "Replace needs an image:")
    compare(hint.commandText, "omarchy-broadcast effect replace --image PATH")
    verify(opts[2].tooltip.indexOf("under [effect]") !== -1, opts[2].tooltip)
    compare(opts[0].tooltip, "The camera image, unchanged")
    compare(Model.intentArgv({ verb: "effect", effect: "replace" }, cli, none), null)
    // an image the daemon holds makes it selectable, and the hint goes
    var withImage = snap({ effect: "blur", blur_strength: 0.5, background_image: image })
    verify(Model.effectSelectable(withImage, "replace"))
    compare(JSON.stringify(Model.effectOptions(withImage).map(function(o) { return o.selectable })),
            JSON.stringify([true, false, true]))
    compare(Model.effectHint(withImage).text, "")
    compare(Model.effectHint(withImage).commandText, "")
    compare(Model.effectOptions(withImage)[2].tooltip, "Replace the background with the background image")
    verify(Model.effectOptions(withImage)[2].tooltip.indexOf("configured") === -1)
    compare(JSON.stringify(Model.intentArgv({ verb: "effect", effect: "replace" }, cli, withImage)),
            JSON.stringify([cli, "effect", "replace"]))
    // the gate reads the raw field, not the display copy: a path that sanitises
    // to nothing is still an image the daemon holds, and the hint agrees
    var blank = snap({ effect: "replace", background_image: "<>&" })
    compare(blank.backgroundImage, "")
    verify(blank.backgroundImageSet)
    verify(Model.effectSelectable(snap({ background_image: "<>&" }), "replace"))
    compare(Model.effectHint(blank).text, "", "no 'needs an image' hint while one is set")
    compare(Model.effectRows(blank)[0].value, Model.UNKNOWN)
    verify(Model.effectSelectable(snap({ background_image: "\n\n\t" }), "replace"))
  }

  function test_cli_without_effects_offers_none() {
    // The committed CLI before effects: "effect":"none", no blur_strength, no
    // background_image, and no `effect` command (clap exits 2).
    var old = snap({ blur_strength: undefined, background_image: undefined })
    verify(Model.available(old))
    compare(old.cliEffects, false)
    var opts = Model.effectOptions(old)
    compare(opts.filter(function(o) { return o.selectable }).length, 0, "no choice is offered")
    compare(opts.filter(function(o) { return o.faded }).length, 3, "the whole row is faded, None included")
    for (var i = 0; i < opts.length; i++) {
      compare(opts[i].tooltip, Model.CLI_NO_EFFECTS)
      compare(Model.effectSelectable(old, Model.EFFECTS[i]), false)
      compare(Model.intentArgv({ verb: "effect", effect: Model.EFFECTS[i] }, cli, old), null, Model.EFFECTS[i])
    }
    var hint = Model.effectHint(old)
    compare(hint.text, "The omarchy-broadcast CLI needs updating for effects.")
    compare(hint.commandText, "")
    verify(hint.text.indexOf("plugin") === -1, "never blamed on the plugin")
    compare(Model.effectRows(old).length, 0)
    // even with a background image field but no blur_strength
    compare(Model.effectSelectable(snap({ blur_strength: undefined, background_image: image }), "replace"), false)
    // a blur_strength that is a number but out of range still means the CLI knows effects
    var odd = snap({ blur_strength: 7 })
    verify(odd.cliEffects)
    compare(odd.blurStrength, null)
    // a string is not the new producer's number
    compare(snap({ blur_strength: "0.5" }).cliEffects, false)
    // the other controls are untouched
    verify(Model.intentArgv({ verb: "enable", on: false }, cli, old) !== null)
  }

  function test_daemon_without_effects_offers_none() {
    // A new CLI (blur_strength a number) still talking to a daemon started
    // before the upgrade: interface revision 1. The CLI would refuse every
    // `effect` request ("the daemon does not support effects").
    var old = snap({ interface_revision: 1 })
    verify(Model.available(old))
    verify(old.cliEffects, "the CLI knows effects")
    compare(old.interfaceRevision, 1)
    verify(!Model.effectsSupported(old))
    var opts = Model.effectOptions(old)
    compare(opts.filter(function(o) { return o.selectable }).length, 0, "no choice is offered")
    compare(opts.filter(function(o) { return o.faded }).length, 3, "the whole row is faded, None included")
    for (var i = 0; i < opts.length; i++) {
      compare(opts[i].tooltip, Model.DAEMON_NO_EFFECTS)
      compare(Model.effectSelectable(old, Model.EFFECTS[i]), false)
      compare(Model.intentArgv({ verb: "effect", effect: Model.EFFECTS[i] }, cli, old), null, Model.EFFECTS[i])
    }
    var hint = Model.effectHint(old)
    compare(hint.text, "The daemon needs updating for effects.")
    compare(hint.commandText, "")
    verify(hint.text !== Model.CLI_NO_EFFECTS + ".", "distinct from the CLI line")
    compare(Model.effectRows(snap({ interface_revision: 1, effect: "blur" })).length, 0)
    compare(Model.effectSelectable(snap({ interface_revision: 1, background_image: image }), "replace"), false)
    compare(JSON.stringify(Model.cursorStops(snap({ interface_revision: 1, cameras: [cameraObjects()[0]] }), 1)
                           .map(function(s) { return s.kind })), JSON.stringify(["switch", "camera"]))
    verify(Model.intentArgv({ verb: "enable", on: false }, cli, old) !== null, "the other controls are untouched")
    // an old CLI with an old daemon names the CLI first: it is what to update first
    var both = snap({ interface_revision: 1, blur_strength: undefined })
    compare(Model.effectHint(both).text, "The omarchy-broadcast CLI needs updating for effects.")
    compare(Model.effectOptions(both)[0].tooltip, Model.CLI_NO_EFFECTS)
    // a state line from the restarted daemon brings effects back
    var back = Model.reduce(old, line(stateObject({ changed: ["interface_revision"], interface_revision: 2 }))).record
    compare(back.interfaceRevision, 2)
    verify(Model.effectsSupported(back))
    compare(Model.effectHint(back).text, "Replace needs an image:")
    compare(JSON.stringify(Model.intentArgv({ verb: "effect", effect: "blur" }, cli, back)), JSON.stringify([cli, "effect", "blur"]))
    // and one from a daemon downgraded again takes them away
    var down = Model.reduce(back, line(stateObject({ changed: ["interface_revision"], interface_revision: 1 }))).record
    verify(!Model.effectsSupported(down))
    compare(Model.emptyRecord("not-running").interfaceRevision, -1)
  }

  function test_daemon_revision_bounds() {
    // revision 2 and anything later (up to the producer's u32) offers effects
    var good = [2, 3, 1000, 4294967295]
    for (var i = 0; i < good.length; i++) {
      var r = snap({ interface_revision: good[i] })
      compare(r.interfaceRevision, good[i])
      verify(Model.effectsSupported(r), String(good[i]))
      verify(Model.effectSelectable(r, "blur"), String(good[i]))
      compare(Model.effectHint(r).text, "Replace needs an image:", String(good[i]))
    }
    // below 2, or unreadable: unknown, read as a daemon without effects
    var bad = [undefined, null, 0, 1, -1, -2, 1.5, 2.5, NaN, Infinity, -Infinity, 4294967296, 1e300,
               "2", "", true, [2], { v: 2 }]
    for (var b = 0; b < bad.length; b++) {
      var name = typeof bad[b] + " " + String(bad[b])
      var o = snap({ interface_revision: bad[b] })
      verify(Model.available(o), name)
      compare(o.interfaceRevision, bad[b] === 0 || bad[b] === 1 ? bad[b] : -1, name)
      verify(!Model.effectsSupported(o), name)
      compare(Model.effectOptions(o).filter(function(x) { return x.selectable }).length, 0, name)
      compare(Model.intentArgv({ verb: "effect", effect: "blur" }, cli, o), null, name)
      compare(Model.effectHint(o).text, "The daemon needs updating for effects.", name)
      compare(Model.cursorStops(o, 0).filter(function(s) { return s.kind === "effect" }).length, 0, name)
    }
    // JSON carries NaN and Infinity as null; the reader itself refuses them too
    compare(Model.interfaceRevision(NaN), -1)
    compare(Model.interfaceRevision(Infinity), -1)
    compare(Model.interfaceRevision(-0.5), -1)
    // a number too large for a double: Qt's JSON.parse refuses the line (an
    // engine that reads it as Infinity gets -1); never effects either way
    var text = line(snapshotObject({})).replace('"interface_revision":4', '"interface_revision":1e999')
    verify(text.indexOf("1e999") > 0)
    var huge = Model.reduce(Model.emptyRecord("connecting"), text)
    if (huge.outcome === "snapshot") compare(huge.record.interfaceRevision, -1)
    else compare(huge.outcome, "invalid")
    verify(!Model.effectsSupported(huge.record))
  }

  function test_effect_intents_are_rechecked_when_they_run() {
    var r = snap()
    compare(JSON.stringify(Model.intentArgv({ verb: "effect", effect: "blur" }, cli, r)), JSON.stringify([cli, "effect", "blur"]))
    compare(JSON.stringify(Model.intentArgv({ verb: "effect", effect: "none" }, cli, r)), JSON.stringify([cli, "effect", "none"]))
    compare(Model.intentArgv({ verb: "effect", effect: "blur" }, cli, Model.emptyRecord("not-running")), null,
            "never D-Bus-activates a stopped daemon")
    compare(Model.intentArgv({ verb: "effect", effect: "blur" }, cli, snap({ state: "dancing" })), null)
    compare(Model.intentArgv({ verb: "effect", effect: "blur; rm" }, cli, r), null)
    compare(Model.intentArgv({ verb: "effect", effect: "--image" }, cli, r), null)
    compare(Model.intentArgv({ verb: "effect" }, cli, r), null)
    compare(Model.intentArgv({ verb: "effect", effect: "blur" }, "", r), null)
    verify(!Model.effectSelectable(null, "blur"))
    compare(Model.effectOptions(Model.emptyRecord("not-running")).filter(function(o) { return o.selectable }).length, 0)
    compare(Model.effectHint(Model.emptyRecord("not-running")).text, "")
    compare(Model.effectRows(Model.emptyRecord("not-running")).length, 0)
  }

  function test_effect_in_tooltip() {
    compare(Model.tooltipText(snap({ effect: "blur" })), "Omarchy Broadcast: idle \u00b7 Logitech MX Brio \u00b7 0 consumers \u00b7 background blurred")
    compare(Model.tooltipText(snap({ effect: "replace", background_image: image })),
            "Omarchy Broadcast: idle \u00b7 Logitech MX Brio \u00b7 0 consumers \u00b7 background replaced")
    compare(Model.tooltipText(snap({ effect: "none" })), "Omarchy Broadcast: idle \u00b7 Logitech MX Brio \u00b7 0 consumers")
    compare(Model.tooltipText(snap({ effect: "sepia" })), "Omarchy Broadcast: idle \u00b7 Logitech MX Brio \u00b7 0 consumers")
    compare(Model.tooltipText(snap({ state: "off", enabled: false, effect: "blur" })), "Omarchy Broadcast: off")
  }

  // ---- noise removal ---------------------------------------------------------

  function test_denoise_parsed() {
    compare(snap({ denoise: true }).denoise, true)
    compare(snap({ denoise: false }).denoise, false)
    // missing: a CLI or a daemon that predates noise removal
    compare(snap().denoise, null)
    compare(snap({ denoise: undefined }).denoise, null)
    // anything but a boolean is unknown, never coerced
    var odd = [null, 0, 1, "true", "false", "on", "", [true], { on: true }, NaN]
    for (var i = 0; i < odd.length; i++) {
      var r = snap({ denoise: odd[i] })
      compare(r.denoise, null, typeof odd[i] + " " + String(odd[i]))
      verify(!Model.denoiseSupported(r), typeof odd[i] + " " + String(odd[i]))
      verify(Model.available(r), "the rest of the record still applies")
    }
    compare(Model.emptyRecord("connecting").denoise, null)
    compare(Model.emptyRecord("not-running").denoise, null)
    // a state line carries it too, and the old record is not mutated
    var on = snap({ denoise: true })
    var off = Model.reduce(on, line(stateObject({ changed: ["denoise"], denoise: false }))).record
    compare(off.denoise, false)
    compare(on.denoise, true, "the old record is not mutated")
    // a state line without it (an old producer) makes it unknown again
    var gone = Model.reduce(on, line(stateObject({ changed: ["state"] }))).record
    compare(gone.denoise, null)
    // an error line forgets it with everything else
    compare(Model.reduce(on, line({ v: 1, type: "error", code: "daemon-not-running", error: "gone" })).record.denoise, null)
  }

  function test_denoise_row() {
    var on = Model.denoiseRow(snap({ denoise: true }))
    compare(on.visible, true)
    compare(on.checked, true)
    compare(on.label, "Noise removal")
    compare(on.tooltip, "Turn noise removal off")
    var off = Model.denoiseRow(snap({ denoise: false }))
    compare(off.visible, true)
    compare(off.checked, false)
    compare(off.tooltip, "Turn noise removal on")
    // unknown: no switch at all, rather than an off one
    var unknown = Model.denoiseRow(snap())
    compare(unknown.visible, false)
    compare(unknown.checked, false)
    compare(Model.denoiseRow(Model.emptyRecord("not-running")).visible, false)
    compare(Model.denoiseRow(snap({ state: "dancing", denoise: true })).visible, false, "an unknown state is unavailable")
    compare(Model.denoiseRow(null).visible, false)
    // offered in every known state, as the effect choices are
    var states = ["off", "idle", "starting", "error"]
    for (var i = 0; i < states.length; i++)
      compare(Model.denoiseRow(snap({ state: states[i], denoise: false })).visible, true, states[i])
    compare(Model.denoiseRow(Model.reduce(active(), line(stateObject({ state: "active", denoise: true }))).record).checked, true)
    // gated on the daemon's interface revision, as effects are: a revision-3
    // line that carries `denoise` still shows no switch, and none can be armed
    var rev3 = snap({ interface_revision: 3, denoise: false })
    compare(Model.denoiseRow(rev3).visible, false)
    verify(!Model.denoiseSupported(rev3))
    compare(Model.intentArgv({ verb: "denoise", on: true }, cli, rev3), null)
    compare(Model.intentArgv({ verb: "denoise", on: false }, cli, rev3), null)
    compare(Model.denoiseRow(snap({ interface_revision: 4, denoise: false })).visible, true)
    compare(Model.denoiseRow(snap({ interface_revision: 5, denoise: true })).visible, true)
    compare(Model.denoiseRow(snap({ interface_revision: 3, denoise: true })).visible, false)
    compare(Model.denoiseRow(snap({ interface_revision: undefined, denoise: false })).visible, false, "unknown revision")
    // independent of effects: effects without noise removal leave the switch hidden
    verify(Model.effectsSupported(rev3))
  }

  function test_denoise_argv() {
    compare(JSON.stringify(Model.denoiseArgv(cli, true)), JSON.stringify([cli, "denoise", "on"]))
    compare(JSON.stringify(Model.denoiseArgv(cli, false)), JSON.stringify([cli, "denoise", "off"]))
    // a strict boolean only: nothing else becomes a word on the command line
    var odd = [null, undefined, 0, 1, "on", "off", "true", "", [true], { on: true }, new Boolean(true)]
    for (var i = 0; i < odd.length; i++) compare(Model.denoiseArgv(cli, odd[i]), null, typeof odd[i] + " " + String(odd[i]))
    compare(Model.denoiseArgv("", true), null, "no CLI")
    compare(Model.denoiseArgv("omarchy-broadcast", true), null, "a bare name is not a CLI path")
    compare(Model.denoiseArgv("/a/b\nc", true), null)
  }

  function test_denoise_intents_are_rechecked_when_they_run() {
    var r = snap({ denoise: false })
    compare(JSON.stringify(Model.intentArgv({ verb: "denoise", on: true }, cli, r)), JSON.stringify([cli, "denoise", "on"]))
    compare(JSON.stringify(Model.intentArgv({ verb: "denoise", on: false }, cli, snap({ denoise: true }))),
            JSON.stringify([cli, "denoise", "off"]))
    compare(JSON.stringify(Model.intentArgv({ verb: "denoise", on: true }, "/new/omarchy-broadcast", r)),
            JSON.stringify(["/new/omarchy-broadcast", "denoise", "on"]), "the CLI path of the moment")
    compare(Model.intentArgv({ verb: "denoise", on: true }, cli, Model.emptyRecord("not-running")), null,
            "never D-Bus-activates a stopped daemon")
    compare(Model.intentArgv({ verb: "denoise", on: true }, cli, snap({ state: "dancing", denoise: false })), null)
    compare(Model.intentArgv({ verb: "denoise", on: true }, cli, snap()), null,
            "a CLI or daemon that does not report it has no `denoise` to run")
    compare(Model.intentArgv({ verb: "denoise", on: "on" }, cli, r), null)
    compare(Model.intentArgv({ verb: "denoise" }, cli, r), null)
    compare(Model.intentArgv({ verb: "denoise", on: true }, "", r), null)
    // a daemon that loses it meanwhile (a downgrade) drops a queued ask
    var lost = Model.reduce(r, line(stateObject({ changed: ["state"] }))).record
    compare(Model.intentArgv({ verb: "denoise", on: true }, cli, lost), null)
  }

  function test_denoise_cursor_stop() {
    var one = [cameraObjects()[0]]
    compare(JSON.stringify(Model.cursorStops(snap({ cameras: one, denoise: false }), 1).map(function(s) { return s.kind })),
            JSON.stringify(["switch", "effect", "denoise", "camera"]))
    compare(JSON.stringify(Model.cursorStops(snap({ cameras: one, denoise: true }), 1).map(function(s) { return s.kind })),
            JSON.stringify(["switch", "effect", "denoise", "camera"]))
    compare(JSON.stringify(Model.cursorStops(snap({ cameras: one }), 1).map(function(s) { return s.kind })),
            JSON.stringify(["switch", "effect", "camera"]), "unknown: no stop")
    // a daemon below the noise removal revision: no stop, whatever the line carries
    compare(JSON.stringify(Model.cursorStops(snap({ cameras: one, interface_revision: 3, denoise: false }), 1)
                           .map(function(s) { return s.kind })), JSON.stringify(["switch", "effect", "camera"]))
    compare(Model.stopIndex(Model.cursorStops(snap({ denoise: false }), 2), "denoise", -1), 2)
    compare(Model.cursorStops(Model.emptyRecord("not-running"), 2).length, 0)
  }

  function test_denoise_in_tooltip() {
    var base = "Omarchy Broadcast: idle \u00b7 Logitech MX Brio \u00b7 0 consumers"
    compare(Model.tooltipText(snap({ effect: "blur", denoise: true })), base + " \u00b7 background blurred, noise removal on")
    compare(Model.tooltipText(snap({ effect: "replace", background_image: image, denoise: true })),
            base + " \u00b7 background replaced, noise removal on")
    compare(Model.tooltipText(snap({ effect: "none", denoise: true })), base + " \u00b7 noise removal on")
    compare(Model.tooltipText(snap({ effect: "sepia", denoise: true })), base + " \u00b7 noise removal on")
    compare(Model.tooltipText(snap({ effect: "blur", denoise: false })), base + " \u00b7 background blurred")
    compare(Model.tooltipText(snap({ effect: "none", denoise: false })), base)
    compare(Model.tooltipText(snap({ effect: "none" })), base, "unknown says nothing")
    compare(Model.tooltipText(snap({ effect: "none", denoise: "true" })), base)
    compare(Model.tooltipText(snap({ state: "off", enabled: false, denoise: true })), "Omarchy Broadcast: off")
    compare(Model.effectSummary(snap({ effect: "blur", denoise: true })), "background blurred, noise removal on")
    compare(Model.effectSummary(null), "")
    // a daemon error about noise removal (it could not run) still shows
    verify(Model.tooltipText(snap({ denoise: true, error: "noise removal unavailable" }))
             .indexOf("noise removal on \u00b7 error: noise removal unavailable") !== -1)
  }

  // ---- CLI resolution ------------------------------------------------------

  function test_cli_plan() {
    compare(Model.cliPlan("", "/home/u").mode, "search")
    compare(Model.cliPlan("   ", "/home/u").mode, "search")
    compare(Model.cliPlan(null, "/home/u").mode, "search")
    compare(Model.cliPlan(undefined, "/home/u").mode, "search")
    var p = Model.cliPlan(" /x/y/omarchy-broadcast ", "/home/u")
    compare(p.mode, "setting")
    compare(p.path, "/x/y/omarchy-broadcast")
    compare(Model.cliPlan("~/bin/omarchy-broadcast", "/home/u/").path, "/home/u/bin/omarchy-broadcast")
    // absolute only: a bare name or a relative path never runs
    var refused = ["omarchy-broadcast", "rm", "bin/x", "./omarchy-broadcast", "~", "~user/x", "/"]
    for (var r = 0; r < refused.length; r++) {
      var plan = Model.cliPlan(refused[r], "/home/u")
      compare(plan.mode, "invalid", refused[r])
      compare(plan.reason, "cliPath must be an absolute path", refused[r])
    }
    compare(Model.cliUsable("rm"), false)
    compare(Model.enableArgv("rm", false), null)
    compare(Model.watchArgv("bin/omarchy-broadcast"), null)
    compare(Model.selectArgv("omarchy-broadcast", brioId), null)
    compare(Model.cliPlan("a\nb", "/home/u").mode, "invalid")
    compare(Model.cliPlan(42, "/home/u").mode, "invalid")
    compare(Model.cliPlan("~/x", "").mode, "invalid")
    var long = "/"
    for (var i = 0; i < 5000; i++) long += "a"
    compare(Model.cliPlan(long, "/home/u").mode, "invalid")
    compare(Model.settingValue({ cliPath: "/a" }, "cliPath"), "/a")
    compare(Model.settingValue({}, "cliPath"), null)
    compare(Model.settingValue(null, "cliPath"), null)
  }

  function test_resolver_argv_passes_dir_positionally() {
    var dir = "/home/u/plugins/br.com.dias.omarchy-broadcast; rm -rf ~ $(id)"
    var argv = Model.resolverArgv(dir)
    compare(argv.length, 5)
    compare(argv[0], "sh")
    compare(argv[1], "-c")
    compare(argv[4], dir)
    verify(argv[2].indexOf(dir) === -1, "never interpolated")
    verify(argv[2].indexOf("\"$1\"") !== -1)
    // PATH is searched even without a usable plugin dir: it is passed as ""
    compare(Model.resolverArgv("")[4], "")
    compare(Model.resolverArgv("relative/dir")[4], "")
    compare(Model.resolverArgv("/a/b\nc")[4], "", "a newline in the dir is refused")
    verify(argv[2].indexOf("[ -n \"$1\" ] || exit 1") !== -1, "an empty dir skips the development search")
    verify(argv[2].indexOf("nl='\n'") === 0, "newline guard")
    verify(Model.resolverMissText("").indexOf("no development build was searched") !== -1)
    var miss = Model.resolverMissText("/p/br.com.dias.omarchy-broadcast")
    verify(miss.indexOf("not on PATH") !== -1 && miss.indexOf("/p/br.com.dias.omarchy-broadcast/../../../target/release/omarchy-broadcast") !== -1, miss)
    compare(Model.resolverAnswer("/usr/bin/omarchy-broadcast", 1), "/usr/bin/omarchy-broadcast")
    compare(Model.resolverAnswer("/x/nl", 2), "", "two lines are no answer")
    compare(Model.resolverAnswer("", 0), "")
    compare(Model.parseResolverLine("/usr/bin/omarchy-broadcast\n"), "/usr/bin/omarchy-broadcast")
    compare(Model.parseResolverLine("omarchy-broadcast"), "")
    compare(Model.parseResolverLine(""), "")
    compare(Model.parseResolverLine(7), "")
    compare(Model.localPathFromUrl("file:///a/b%20c/"), "/a/b c")
    compare(Model.localPathFromUrl("qrc:/x"), "")
  }
}
