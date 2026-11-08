import QtQuick
import QtTest
import "../Model.js" as Model

// Unit tests for Model.js: the stream reducer, sanitising, caps, the bar's
// six visual states, tooltips, argv builders and CLI-path resolution.
//
// Run (headless):
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_model.qml
TestCase {
  name: "OmaBroadcastModel"

  readonly property string cli: "/opt/bin/oma-broadcast"
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
      output_mode: "NV12 1920x1080@30", effect: "none", interface_revision: 1,
      cameras: cameraObjects(), cameras_truncated: false
    }
    for (var k in overrides) m[k] = overrides[k]
    return m
  }

  function stateObject(overrides) {
    var m = {
      v: 1, type: "state", changed: ["state"], state: "idle", enabled: true, error: "",
      active_camera: brioId, active_camera_name: "Logitech MX Brio", consumers: 0,
      output_mode: "NV12 1920x1080@30", effect: "none", interface_revision: 1
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
    var res = Model.reduce(r, '{"v":1,"type":"error","code":"daemon-not-running","error":"oma-broadcastd is not running"}')
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
    compare(Model.tooltipText(a), "OMA Broadcast: daemon unreachable")
    compare(Model.tooltipText(Model.emptyRecord("not-running")), "OMA Broadcast: daemon not running")
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
    compare(Model.tooltipText(r), "OMA Broadcast: unsupported state")
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
            "OMA Broadcast: off \u00b7 error: config brejected/b")
    compare(Model.tooltipText(snap({ state: "off", enabled: false })), "OMA Broadcast: off")
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
    compare(Model.watchExitText(15, true, 2000), "oma-broadcast watch stopped by signal 15; restarting in 2 s")
    compare(Model.watchExitText(1, false, 1000), "oma-broadcast watch exited with status 1; restarting in 1 s")
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
    st = Model.firstLineFeed(st, "oma-broadcast: no camera ")
    compare(st.done, false)
    st = Model.firstLineFeed(st, "matches\nsecond line\n")
    compare(st.done, true)
    compare(st.text, "oma-broadcast: no camera matches")
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
    compare(JSON.stringify(Model.intentArgv({ verb: "enable", on: true }, "/new/oma-broadcast", r)),
            JSON.stringify(["/new/oma-broadcast", "on"]), "the CLI path of the moment")
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
            JSON.stringify(["switch-1", "camera0", "camera1", "camera2", "next-1"]))
    compare(Model.cursorStops(r, 2).length, 4, "follows the rendered row count")
    var one = snap({ cameras: [cameraObjects()[0]] })
    compare(JSON.stringify(Model.cursorStops(one, 1).map(function(s) { return s.kind })), JSON.stringify(["switch", "camera"]))
    compare(Model.cursorStops(Model.emptyRecord("not-running"), 3).length, 0)
    compare(Model.clampCursor(-3, 5), 0)
    compare(Model.clampCursor(9, 5), 4)
    compare(Model.clampCursor(2, 0), 0)
    compare(Model.stopIndex(stops, "camera", 2), 3)
    compare(Model.stopIndex(stops, "next", -1), 4)
    compare(Model.stopIndex(stops, "camera", 7), -1)
  }

  function test_hero_meta_has_no_command_names() {
    compare(Model.heroMeta(snap()), "idle")
    compare(Model.heroMeta(snap({ state: "off", enabled: false })), "off")
    compare(Model.heroMeta(Model.emptyRecord("connecting")), "connecting\u2026")
    var links = ["not-running", "unreachable", "cli-missing", "cli-failed", "unsupported"]
    for (var i = 0; i < links.length; i++) {
      var rec = Model.withLink(links[i], "oma-broadcast CLI not found: /x")
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
    compare(Model.tooltipText(r), "OMA Broadcast: active \u00b7 Logitech MX Brio \u00b7 2 consumers")
    compare(Model.tooltipText(snap({ state: "off", enabled: false })), "OMA Broadcast: off")
    compare(Model.tooltipText(snap({ state: "idle", consumers: 1 })), "OMA Broadcast: idle \u00b7 Logitech MX Brio \u00b7 1 consumer")
    compare(Model.tooltipText(snap({ active_camera: "", active_camera_name: "" })), "OMA Broadcast: idle \u00b7 no camera \u00b7 0 consumers")
    compare(Model.tooltipText(snap({ state: "error", error: "loopback missing" })), "OMA Broadcast: error \u00b7 loopback missing")
    verify(Model.tooltipText(snap({ error: "bad config" })).indexOf("error: bad config") !== -1)
    compare(Model.tooltipText(Model.emptyRecord("cli-missing")), "OMA Broadcast: oma-broadcast CLI not found")
    compare(Model.tooltipText(Model.emptyRecord("connecting")), "OMA Broadcast: connecting\u2026")
    var hostile = snap({ active_camera_name: "<img src='http://x/y'>" })
    verify(!/[<>&]/.test(Model.tooltipText(hostile)))
  }

  function test_unavailable_messages() {
    var m = Model.unavailableMessage(Model.emptyRecord("not-running"))
    compare(m.title, "oma-broadcastd is not running")
    compare(m.commandText, "systemctl --user start oma-broadcastd")
    compare(Model.unavailableMessage(snap()).title, "")
    var c = Model.unavailableMessage(Model.withLink("cli-missing", "oma-broadcast CLI not found: /nope"))
    compare(c.title, "oma-broadcast CLI not found: /nope")
    compare(Model.unavailableMessage(Model.emptyRecord("cli-missing")).title, "oma-broadcast CLI not found")
    verify(Model.unavailableMessage(Model.emptyRecord("unreachable")).title !== m.title, "unreachable reads differently")
  }

  function test_command_failure_text() {
    compare(Model.commandFailureText(3, "", cli), "oma-broadcastd is not running")
    var t = Model.commandFailureText(1, "oma-broadcast: no camera matches <img src=x>\n", cli)
    verify(t.indexOf("The daemon refused the request: no camera matches") === 0, t)
    verify(!/[<>&\n]/.test(t))
    verify(Model.commandFailureText(-1, "", "/nope/oma-broadcast").indexOf("/nope/oma-broadcast") !== -1)
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

  // ---- CLI resolution ------------------------------------------------------

  function test_cli_plan() {
    compare(Model.cliPlan("", "/home/u").mode, "search")
    compare(Model.cliPlan("   ", "/home/u").mode, "search")
    compare(Model.cliPlan(null, "/home/u").mode, "search")
    compare(Model.cliPlan(undefined, "/home/u").mode, "search")
    var p = Model.cliPlan(" /x/y/oma-broadcast ", "/home/u")
    compare(p.mode, "setting")
    compare(p.path, "/x/y/oma-broadcast")
    compare(Model.cliPlan("~/bin/oma-broadcast", "/home/u/").path, "/home/u/bin/oma-broadcast")
    // absolute only: a bare name or a relative path never runs
    var refused = ["oma-broadcast", "rm", "bin/x", "./oma-broadcast", "~", "~user/x", "/"]
    for (var r = 0; r < refused.length; r++) {
      var plan = Model.cliPlan(refused[r], "/home/u")
      compare(plan.mode, "invalid", refused[r])
      compare(plan.reason, "cliPath must be an absolute path", refused[r])
    }
    compare(Model.cliUsable("rm"), false)
    compare(Model.enableArgv("rm", false), null)
    compare(Model.watchArgv("bin/oma-broadcast"), null)
    compare(Model.selectArgv("oma-broadcast", brioId), null)
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
    var dir = "/home/u/plugins/br.com.dias.oma-broadcast; rm -rf ~ $(id)"
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
    var miss = Model.resolverMissText("/p/br.com.dias.oma-broadcast")
    verify(miss.indexOf("not on PATH") !== -1 && miss.indexOf("/p/br.com.dias.oma-broadcast/../../../target/release/oma-broadcast") !== -1, miss)
    compare(Model.resolverAnswer("/usr/bin/oma-broadcast", 1), "/usr/bin/oma-broadcast")
    compare(Model.resolverAnswer("/x/nl", 2), "", "two lines are no answer")
    compare(Model.resolverAnswer("", 0), "")
    compare(Model.parseResolverLine("/usr/bin/oma-broadcast\n"), "/usr/bin/oma-broadcast")
    compare(Model.parseResolverLine("oma-broadcast"), "")
    compare(Model.parseResolverLine(""), "")
    compare(Model.parseResolverLine(7), "")
    compare(Model.localPathFromUrl("file:///a/b%20c/"), "/a/b c")
    compare(Model.localPathFromUrl("qrc:/x"), "")
  }
}
