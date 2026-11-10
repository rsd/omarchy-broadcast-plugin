import QtQuick
import QtTest
import "../Model.js" as Model

// Unit tests for Model.js: the stream reducer, sanitising, caps, the bar's
// six visual states, tooltips, argv builders, the camera settings (the set,
// its deltas, validation, caps, the writes) and the command queue, and
// CLI-path resolution.
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
  function kindsOf(stops) { return JSON.stringify(stops.map(function(s) { return s.kind })) }

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
    compare(Model.rightClickAction(r, false), "open-panel")
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

  function test_right_click_while_busy() {
    compare(Model.rightClickAction(snap(), false), "toggle")
    compare(Model.rightClickAction(snap(), true), "ignore")
    compare(Model.rightClickAction(Model.emptyRecord("not-running"), true), "open-panel")
    compare(Model.rightClickAction(Model.emptyRecord("not-running"), false), "open-panel")
    compare(Model.rightClickAction(snap(), "true"), "toggle", "busy only for a real true")
    verify(Model.leftClickAction === undefined, "the old name is gone")
  }

  function test_bar_click_help() {
    compare(Model.barClickHelp(snap()), "Click: open the panel. Right click: turn the camera off.")
    compare(Model.barClickHelp(snap({ state: "off", enabled: false })), "Click: open the panel. Right click: turn the camera on.")
    compare(Model.barClickHelp(Model.emptyRecord("not-running")), "Click or right click: open the panel.")
    compare(Model.barClickHelp(snap({ state: "dancing" })), "Click or right click: open the panel.")
    compare(Model.barClickHelp(null), "Click or right click: open the panel.")
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
    var stops = Model.cursorStops(r, r.cameras.length, false, "camera")
    compare(JSON.stringify(stops.map(function(s) { return s.kind + s.index })),
            JSON.stringify(["switch-1", "tabs-1", "camera0", "camera1", "camera2", "next-1"]))
    compare(Model.cursorStops(r, 2, false, "camera").length, 5, "follows the rendered row count")
    var one = snap({ cameras: [cameraObjects()[0]] })
    compare(kindsOf(Model.cursorStops(one, 1, false, "camera")), JSON.stringify(["switch", "tabs", "camera"]))
    compare(kindsOf(Model.cursorStops(one, 1, false, "effect")), JSON.stringify(["switch", "tabs", "effect"]))
    compare(kindsOf(Model.cursorStops(one, 1, false, "status")), JSON.stringify(["switch", "tabs"]), "the Status tab has no control")
    compare(kindsOf(Model.cursorStops(one, 1, false)), kindsOf(Model.cursorStops(one, 1, false, "effect")), "no tab: the default")
    compare(kindsOf(Model.cursorStops(one, 1, false, "bogus")), kindsOf(Model.cursorStops(one, 1, false, "effect")), "unknown tab: the default")
    compare(kindsOf(Model.cursorStops(one, 1, false, "Camera")), kindsOf(Model.cursorStops(one, 1, false, "effect")), "exact words only")
    compare(Model.cursorStops(Model.emptyRecord("not-running"), 3, true, "camera").length, 0)
    // a CLI that predates effects: nothing on the effect row can be requested
    var noEffects = snap({ cameras: [cameraObjects()[0]], blur_strength: undefined })
    compare(kindsOf(Model.cursorStops(noEffects, 1, false, "effect")), JSON.stringify(["switch", "tabs"]))
    compare(kindsOf(Model.cursorStops(noEffects, 1, false, "camera")), JSON.stringify(["switch", "tabs", "camera"]))
    compare(Model.clampCursor(-3, 5), 0)
    compare(Model.clampCursor(9, 5), 4)
    compare(Model.clampCursor(2, 0), 0)
    compare(Model.stopIndex(stops, "camera", 2), 4)
    compare(Model.stopIndex(stops, "tabs", -1), 1)
    compare(Model.stopIndex(stops, "next", -1), 5)
    compare(Model.stopIndex(stops, "camera", 7), -1)
    compare(Model.stopIndex(stops, "effect", -1), -1, "another tab's stop")
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
      Model.CLI_MISSING_TEXT + ": /home/a b/with space/omarchy-broadcast"
    ]
    var paths = ["/nonexistent/omarchy-broadcast", "/home/a b/with space/omarchy-broadcast"]
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
                        "the cliPath setting is not text", Model.resolverMissText()]) {
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
    compare(Model.rightClickAction(snap()), "toggle")
    compare(Model.rightClickAction(Model.emptyRecord("not-running")), "open-panel")
    compare(Model.rightClickAction(Model.emptyRecord("cli-missing")), "open-panel")
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
    compare(kindsOf(Model.cursorStops(snap({ interface_revision: 1, cameras: [cameraObjects()[0]] }), 1, false, "effect")),
            JSON.stringify(["switch", "tabs"]))
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
    compare(kindsOf(Model.cursorStops(snap({ cameras: one, denoise: false }), 1, false, "effect")),
            JSON.stringify(["switch", "tabs", "effect", "denoise"]))
    compare(kindsOf(Model.cursorStops(snap({ cameras: one, denoise: true }), 1, false, "effect")),
            JSON.stringify(["switch", "tabs", "effect", "denoise"]))
    compare(kindsOf(Model.cursorStops(snap({ cameras: one }), 1, false, "effect")),
            JSON.stringify(["switch", "tabs", "effect"]), "unknown: no stop")
    // a daemon below the noise removal revision: no stop, whatever the line carries
    compare(kindsOf(Model.cursorStops(snap({ cameras: one, interface_revision: 3, denoise: false }), 1, false, "effect")),
            JSON.stringify(["switch", "tabs", "effect"]))
    compare(Model.stopIndex(Model.cursorStops(snap({ denoise: false }), 2, false, "effect"), "denoise", -1), 3)
    compare(Model.stopIndex(Model.cursorStops(snap({ denoise: false }), 2, false, "camera"), "denoise", -1), -1, "only on its own tab")
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

  function test_resolver_argv_searches_path_only() {
    var argv = Model.resolverArgv()
    compare(argv.length, 4)
    compare(argv[0], "sh")
    compare(argv[1], "-c")
    compare(argv[3], "omarchy-broadcast-resolve")
    verify(argv[2].indexOf("command -v omarchy-broadcast") !== -1)
    verify(argv[2].indexOf("target/release") === -1, "no development-build fallback")
    verify(argv[2].indexOf("readlink") === -1 && argv[2].indexOf("$1") === -1, "no plugin directory is searched")
    verify(argv[2].indexOf("nl='\n'") === 0, "newline guard")
    compare(Model.resolverMissText(), "omarchy-broadcast is not on PATH")
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

  // ---- preview -------------------------------------------------------------

  readonly property string runtimeDir: "/run/user/1000"
  readonly property string framePath: "/run/user/1000/omarchy-broadcast/preview.jpg"

  // A rev-5 record in `state` with the given loopback and PipeWire consumers.
  function previewRecord(state, loopback, pipewire, revision) {
    var r = snap({ interface_revision: revision === undefined ? 5 : revision, denoise: false,
                   loopback_consumers: loopback, pipewire_consumers: pipewire,
                   consumers: (loopback || 0) + (pipewire || 0) + 1 })
    if (state === "idle") return r
    return Model.reduce(r, line(stateObject({ state: state, interface_revision: revision === undefined ? 5 : revision, denoise: false,
                                              loopback_consumers: loopback, pipewire_consumers: pipewire,
                                              consumers: (loopback || 0) + (pipewire || 0) + 1 }))).record
  }

  function test_consumer_split_parsed() {
    var r = previewRecord("active", 2, 1)
    compare(r.loopbackConsumers, 2)
    compare(r.pipewireConsumers, 1)
    compare(Model.otherConsumers(r), 3)
    var old = snap({})
    compare(old.loopbackConsumers, -1, "absent: unknown")
    compare(Model.otherConsumers(old), -1)
    compare(snap({ loopback_consumers: -1, pipewire_consumers: 0 }).loopbackConsumers, -1)
    compare(snap({ loopback_consumers: 1.5, pipewire_consumers: 0 }).loopbackConsumers, -1)
    compare(Model.otherConsumers(snap({ loopback_consumers: "1", pipewire_consumers: 0 })), -1)
  }

  function test_should_preview_truth_table() {
    var idle = previewRecord("idle", 0, 0)
    var activeOnlyPreview = previewRecord("active", 0, 0)
    var activeLoopback = previewRecord("active", 1, 0)
    var activePipewire = previewRecord("active", 0, 1)
    var startingLoopback = previewRecord("starting", 1, 0)
    // R1: the switch off never starts or holds the camera
    compare(Model.shouldPreview(1, true, false, idle), false, "switch off, idle")
    compare(Model.shouldPreview(1, true, false, activeOnlyPreview), false, "switch off, active for preview leases only")
    compare(Model.shouldPreview(1, true, false, activeLoopback), true, "switch off, active, loopback 1")
    compare(Model.shouldPreview(1, true, false, activePipewire), true, "switch off, active, PipeWire 1")
    compare(Model.shouldPreview(1, true, false, startingLoopback), false, "switch off, starting: not active yet")
    compare(Model.shouldPreview(1, true, false, snap({ state: "active" })), false, "unknown split")
    // the switch on starts it in any state the daemon can show
    compare(Model.shouldPreview(1, true, true, idle), true, "switch on, idle")
    compare(Model.shouldPreview(2, true, true, activeOnlyPreview), true, "switch on, two panels")
    compare(Model.shouldPreview(1, true, true, snap({ state: "off", enabled: false, interface_revision: 5 })), true, "switch on, off")
    // panel closed
    compare(Model.shouldPreview(0, true, true, idle), false, "no holder, switch on")
    compare(Model.shouldPreview(0, true, false, activeLoopback), false, "no holder, active")
    compare(Model.shouldPreview(-1, true, true, idle), false)
    compare(Model.shouldPreview("1", true, true, idle), false)
    // not supported
    compare(Model.shouldPreview(1, false, true, idle), false, "unsupported, switch on")
    compare(Model.shouldPreview(1, false, false, activeLoopback), false, "unsupported, active")
    compare(Model.shouldPreview(1, "yes", true, idle), false)
    compare(Model.shouldPreview(1, true, "true", idle), false, "only a real true is on")
    // unavailable daemon, with the switch off
    compare(Model.shouldPreview(1, true, false, Model.withLink("not-running")), false)
  }

  function test_preview_supported_needs_revision_5() {
    compare(Model.previewSupported(previewRecord("idle", 0, 0, 5)), true)
    compare(Model.previewSupported(previewRecord("idle", 0, 0, 6)), true)
    compare(Model.previewSupported(previewRecord("idle", 0, 0, 4)), false, "rev 4")
    compare(Model.previewSupported(snap({ interface_revision: "5" })), false, "unknown revision")
    compare(Model.previewSupported(Model.withLink("not-running")), false)
    // so a rev-4 daemon never runs it, whatever the rest says
    var rev4 = previewRecord("active", 1, 0, 4)
    compare(Model.shouldPreview(1, Model.previewSupported(rev4), true, rev4), false)
  }

  function test_preview_argv() {
    compare(JSON.stringify(Model.previewArgv(cli, 15)), JSON.stringify([cli, "preview", "--json", "--fps", "15"]))
    compare(JSON.stringify(Model.previewArgv(cli, 30)), JSON.stringify([cli, "preview", "--json", "--fps", "30"]))
    compare(Model.previewArgv(cli, 20), null)
    compare(Model.previewArgv(cli, "30"), null)
    compare(Model.previewArgv(cli, NaN), null)
    compare(Model.previewArgv("omarchy-broadcast", 15), null, "relative CLI")
    compare(Model.previewArgv("/a\nb", 15), null)
  }

  function test_preview_path_validation() {
    compare(Model.previewPath(runtimeDir).path, framePath)
    compare(Model.previewPath(runtimeDir + "/").path, framePath, "trailing slash dropped")
    compare(Model.previewPath(runtimeDir + "///").path, framePath)
    compare(Model.previewPath("/tmp/a b/rt").path, "/tmp/a b/rt/omarchy-broadcast/preview.jpg", "a space is a path character")
    var bad = ["", "run/user/1000", "./run", "/run/user/../1000", "/run/..", "/run/user/1000\n", "/run/\u0001x",
               "/run/\u007fx", "/run/u?x", "/run/u#x", "/run/u%41", "/", "///", "/run/ x",
               "//evil.host/share", "//run/user/1000"]
    for (var i = 0; i < bad.length; i++) {
      var r = Model.previewPath(bad[i])
      compare(r.path, "", JSON.stringify(bad[i]))
      verify(r.reason !== "", "a reason for " + JSON.stringify(bad[i]))
    }
    compare(Model.previewPath(undefined).reason, "XDG_RUNTIME_DIR is not set")
    compare(Model.previewPath(null).path, "")
    compare(Model.previewPath(7).path, "")
    compare(Model.previewPath("relative").reason, "XDG_RUNTIME_DIR is not an absolute path")
    compare(Model.previewPath("//evil.host/share").reason, "XDG_RUNTIME_DIR starts with //", "no URL host in file:////host")
    compare(Model.previewPath("/run//user/1000").path, "/run//user/1000/omarchy-broadcast/preview.jpg", "an inner // is a local path")
    var long = "/"
    for (var j = 0; j < Model.PATH_CAP; j++) long += "a"
    compare(Model.previewPath(long).path, "", "over PATH_CAP")
  }

  function test_preview_source() {
    compare(Model.previewSource(framePath, 7), "file://" + framePath + "?7")
    compare(Model.previewSource(framePath, 0), "")
    compare(Model.previewSource(framePath, 1.5), "")
    compare(Model.previewSource("", 7), "")
  }

  function frameLine(seq, path, extra) {
    var m = { v: 1, type: "frame", seq: seq, path: path }
    for (var k in extra) m[k] = extra[k]
    return JSON.stringify(m)
  }

  function test_preview_frame_lines() {
    var r = Model.parsePreviewLine(frameLine(1, framePath), framePath, 0)
    compare(r.kind, "frame")
    compare(r.seq, 1)
    compare(Model.parsePreviewLine(frameLine(9, framePath), framePath, 3).seq, 9)
    // the path must be exactly the expected one
    var paths = ["/etc/passwd", framePath + "?x=1", "/run/user/1000/omarchy-broadcast/../../../etc/shadow",
                 "/run/user/1000//omarchy-broadcast/preview.jpg", framePath + "/", framePath.toUpperCase(),
                 "file://" + framePath, "", null, 7]
    for (var i = 0; i < paths.length; i++) {
      var d = Model.parsePreviewLine(frameLine(5, paths[i]), framePath, 0)
      compare(d.kind, "dropped", JSON.stringify(paths[i]))
      compare(d.reason, "path", JSON.stringify(paths[i]))
    }
    compare(Model.parsePreviewLine(frameLine(5, framePath), "", 0).kind, "dropped", "no expected path: nothing matches")
    // seq: a positive integer, increasing
    var seqs = [0, -1, 1.5, "2", NaN, null, Infinity, 9007199254740992, true]
    for (var j = 0; j < seqs.length; j++) {
      var line = frameLine(seqs[j], framePath)
      var e = Model.parsePreviewLine(line, framePath, 0)
      compare(e.kind, "dropped", String(seqs[j]))
    }
    // NaN and Infinity reach JSON as null; a literal 1e999 (Infinity) is no frame either
    verify(Model.parsePreviewLine('{"v":1,"type":"frame","seq":1e999,"path":"' + framePath + '"}', framePath, 0).kind !== "frame")
    compare(Model.previewSeq(Infinity), 0)
    compare(Model.previewSeq(NaN), 0)
    compare(Model.parsePreviewLine(frameLine(3, framePath), framePath, 3).reason, "stale", "same seq")
    compare(Model.parsePreviewLine(frameLine(2, framePath), framePath, 3).reason, "stale", "older seq")
    // the line itself
    compare(Model.parsePreviewLine(JSON.stringify({ v: 2, type: "frame", seq: 1, path: framePath }), framePath, 0).kind, "invalid", "v 2")
    compare(Model.parsePreviewLine(JSON.stringify({ v: "1", type: "frame", seq: 1, path: framePath }), framePath, 0).kind, "invalid", "v \"1\"")
    compare(Model.parsePreviewLine(JSON.stringify({ type: "frame", seq: 1, path: framePath }), framePath, 0).kind, "invalid", "no v")
    compare(Model.parsePreviewLine("not json <img src=x>", framePath, 0).kind, "invalid")
    compare(Model.parsePreviewLine("[1]", framePath, 0).kind, "invalid")
    compare(Model.parsePreviewLine("", framePath, 0).kind, "ignored")
    compare(Model.parsePreviewLine(JSON.stringify({ v: 1, type: "stats", fps: 30 }), framePath, 0).kind, "ignored", "unknown type")
    compare(Model.parsePreviewLine(JSON.stringify({ v: 1, type: "snapshot" }), framePath, 0).kind, "ignored", "a watch type")
    var pad = ""
    for (var k = 0; k < Model.LINE_CAP; k++) pad += "x"
    var over = frameLine(1, framePath, { pad: pad })
    var t0 = Date.now()
    var o = Model.parsePreviewLine(over, framePath, 0)
    compare(o.kind, "dropped")
    compare(o.reason, "too-long")
    verify(Date.now() - t0 < 100)
  }

  function test_preview_lease_and_error_lines() {
    var on = Model.parsePreviewLine(JSON.stringify({ v: 1, type: "preview", active: true, fps: 30, path: framePath }), framePath, 0)
    compare(on.kind, "preview")
    compare(on.active, true)
    compare(on.fps, 30)
    compare(on.pathMismatch, false)
    var elsewhere = Model.parsePreviewLine(JSON.stringify({ v: 1, type: "preview", active: true, fps: 15, path: "/tmp/x.jpg" }), framePath, 0)
    compare(elsewhere.pathMismatch, true)
    compare(Model.parsePreviewLine(JSON.stringify({ v: 1, type: "preview", active: true, fps: 99, path: framePath }), framePath, 0).fps, 0)
    var off = Model.parsePreviewLine(JSON.stringify({ v: 1, type: "preview", active: false }), framePath, 0)
    compare(off.kind, "preview")
    compare(off.active, false)
    compare(Model.parsePreviewLine(JSON.stringify({ v: 1, type: "preview", active: "yes" }), framePath, 0).kind, "invalid")
    var err = Model.parsePreviewLine(JSON.stringify({ v: 1, type: "error", code: "daemon-not-running", error: "x" }), framePath, 0)
    compare(err.kind, "error")
    compare(err.text, "omarchy-broadcastd is not running")
    compare(Model.parsePreviewLine(JSON.stringify({ v: 1, type: "error", code: "unsupported-daemon" }), framePath, 0).text,
            "Preview needs omarchy-broadcast 0.18 or newer")
    var hostile = "<img src='http://127.0.0.1:9/b'>\n&"
    for (var i = 0; i < 200; i++) hostile += "z"
    var h = Model.parsePreviewLine(JSON.stringify({ v: 1, type: "error", code: hostile }), framePath, 0)
    compare(h.kind, "error")
    verify(!/[<>&\n]/.test(h.text), h.text)
    verify(h.code.length <= Model.PREVIEW_CODE_CAP, h.code.length)
    compare(Model.parsePreviewLine(JSON.stringify({ v: 1, type: "error" }), framePath, 0).text, "Preview stream error: unknown")
    compare(Model.parsePreviewLine(JSON.stringify({ v: 1, type: "error", code: "dbus-error" }), framePath, 0).text, "Preview stream error: dbus-error")
  }

  function test_preview_exit_text() {
    verify(Model.previewExitText(1, false, true, false).indexOf("exited with status 1") !== -1)
    verify(Model.previewExitText(15, true, true, false).indexOf("stopped by signal 15") !== -1)
    verify(Model.previewExitText(0, false, false, false).indexOf("could not be started") !== -1)
    verify(Model.previewExitText(2, false, true, false).indexOf("needs 0.18 or newer") !== -1, "clap usage error: an old CLI")
    verify(Model.previewExitText(0, false, true, true).indexOf("longer than " + Model.LINE_CAP) !== -1)
    verify(Model.previewExitText(1, false, true, false).indexOf(Model.PREVIEW_RETRY_HINT) !== -1)
  }

  function placeholderFor(o) {
    var s = { record: previewRecord("idle", 0, 0), pathReason: "", switchOn: false, wanted: false, running: false,
              leaseActive: false, hasFrame: false, exitError: "", streamError: "", pathMismatch: false }
    for (var k in o) s[k] = o[k]
    return Model.previewPlaceholder(s)
  }

  function test_preview_placeholder_per_state() {
    compare(placeholderFor({ record: Model.withLink("not-running") }).mode, "hidden", "daemon unavailable")
    compare(placeholderFor({ record: Model.withLink("connecting") }).mode, "hidden")
    var old = placeholderFor({ record: previewRecord("idle", 0, 0, 4), switchOn: true })
    compare(old.mode, "note")
    compare(old.text, "Preview needs omarchy-broadcast 0.18 or newer")
    var badPath = placeholderFor({ pathReason: "XDG_RUNTIME_DIR is not set" })
    compare(badPath.mode, "note")
    compare(badPath.text, "Preview unavailable: XDG_RUNTIME_DIR is not set")
    var idle = placeholderFor({})
    compare(idle.mode, "note", "nothing shown or starting: one line, no empty frame area")
    compare(idle.text, "Camera idle; turn on Preview to start it")
    compare(idle.error, false)
    var activeOff = placeholderFor({ record: previewRecord("active", 0, 0) })
    compare(activeOff.text, "Preview off", "active for other previews only")
    compare(activeOff.mode, "note")
    var cameraOff = placeholderFor({ record: snap({ state: "off", enabled: false, interface_revision: 5 }) })
    compare(cameraOff.text, "Camera off", "the camera itself is off")
    compare(cameraOff.mode, "note")
    compare(placeholderFor({ record: snap({ state: "idle", enabled: false, interface_revision: 5 }) }).text, "Camera off",
            "Enabled false wins over the state")
    compare(placeholderFor({ record: snap({ state: "off", enabled: false, interface_revision: 5 }), switchOn: true, wanted: true }).mode,
            "box", "camera off, Preview on: it starts")
    var starting = placeholderFor({ switchOn: true, wanted: true })
    compare(starting.text, "Starting preview…", "armed, nothing yet")
    compare(starting.mode, "box", "the 16:9 area while it starts")
    compare(placeholderFor({ switchOn: true, wanted: true, running: true }).text, "Starting preview…", "running, no lease")
    compare(placeholderFor({ switchOn: true, wanted: true, running: true, leaseActive: true }).text, "Starting preview…", "lease, no frame")
    compare(placeholderFor({ switchOn: true, wanted: true, running: true, leaseActive: true, hasFrame: true }).mode, "image")
    compare(placeholderFor({ wanted: true, running: true, leaseActive: true, hasFrame: true,
                             record: previewRecord("active", 1, 0) }).mode, "image", "shown at once for another consumer")
    var exit = placeholderFor({ switchOn: true, wanted: true, exitError: "omarchy-broadcast preview exited with status 1. Reopen the panel to retry." })
    compare(exit.mode, "note", "an error is a line, not a box")
    compare(exit.error, true)
    verify(exit.text.indexOf("status 1") !== -1)
    var stream = placeholderFor({ switchOn: true, wanted: true, running: true, streamError: "Preview stream error: dbus-error" })
    compare(stream.text, "Preview stream error: dbus-error")
    compare(stream.error, true)
    compare(stream.mode, "note")
    var mismatch = placeholderFor({ switchOn: true, wanted: true, running: true, leaseActive: true, pathMismatch: true })
    compare(mismatch.error, true)
    compare(mismatch.mode, "note")
    verify(mismatch.text.indexOf("XDG_RUNTIME_DIR") !== -1)
    compare(Model.previewPlaceholder(null).mode, "hidden")
  }

  function test_preview_controls_and_cursor() {
    var r5 = previewRecord("idle", 0, 0)
    compare(Model.previewControlsShown(r5, ""), true)
    compare(Model.previewControlsShown(r5, "XDG_RUNTIME_DIR is not set"), false)
    compare(Model.previewControlsShown(previewRecord("idle", 0, 0, 4), ""), false)
    compare(kindsOf(Model.cursorStops(r5, 2, true, "effect")), JSON.stringify(["switch", "preview", "fps", "tabs", "effect", "denoise"]))
    compare(kindsOf(Model.cursorStops(r5, 2, true, "camera")), JSON.stringify(["switch", "preview", "fps", "tabs", "camera", "camera", "next"]))
    compare(kindsOf(Model.cursorStops(r5, 2, true, "status")), JSON.stringify(["switch", "preview", "fps", "tabs"]))
    var without = Model.cursorStops(r5, 2, false).map(function(s) { return s.kind })
    compare(without.indexOf("preview"), -1)
    compare(Model.cursorStops(r5, 2).length, without.length, "no previewControls: no preview stops")
    compare(JSON.stringify(Model.cursorStops(Model.withLink("not-running"), 2, true)), "[]")
    var fps = Model.fpsOptions(30)
    compare(JSON.stringify(fps.map(function(o) { return o.value })), "[15,30]")
    compare(fps[1].selected, true)
    compare(fps[0].label, "15 fps")
    compare(fps[1].tooltip, "Smoother, closer to what apps see; uses more CPU")
    compare(fps[0].tooltip, "Lighter; uses less CPU")
    compare(Model.fpsOptions(42)[0].selected, true, "anything else reads as 15")
  }

  function test_preview_settings_normalised() {
    compare(JSON.stringify(Model.previewSettings({})), JSON.stringify({ enabled: false, fps: 15 }))
    compare(JSON.stringify(Model.previewSettings(null)), JSON.stringify({ enabled: false, fps: 15 }))
    compare(JSON.stringify(Model.previewSettings({ previewEnabled: true, previewFps: 30 })), JSON.stringify({ enabled: true, fps: 30 }))
    var fpsValues = [0, 15, 20, 29.9, 31, 60, -30, "30", null, undefined, NaN, Infinity, [30], { v: 30 }, true]
    for (var i = 0; i < fpsValues.length; i++)
      compare(Model.previewFpsValue(fpsValues[i]), 15, String(fpsValues[i]))
    compare(Model.previewFpsValue(30), 30)
    var on = [1, "true", "on", {}, [true]]
    for (var j = 0; j < on.length; j++)
      compare(Model.previewSettings({ previewEnabled: on[j] }).enabled, false, JSON.stringify(on[j]))
  }

  function test_settings_entry_merge() {
    var settings = { cliPath: "~/bin/omarchy-broadcast", other: { nested: 1 } }
    var before = JSON.stringify(settings)
    var e = Model.settingsEntry("br.com.dias.omarchy-broadcast", settings, { previewEnabled: true })
    compare(JSON.stringify(e), JSON.stringify({ id: "br.com.dias.omarchy-broadcast", cliPath: "~/bin/omarchy-broadcast",
                                                other: { nested: 1 }, previewEnabled: true }))
    compare(JSON.stringify(settings), before, "the settings given are not modified")
    var f = Model.settingsEntry("m", { previewEnabled: true, previewFps: 15, id: "stale" }, { previewFps: 30 })
    compare(JSON.stringify(f), JSON.stringify({ id: "m", previewEnabled: true, previewFps: 30 }), "id from the module name")
    compare(JSON.stringify(Model.settingsFromEntry(f)), JSON.stringify({ previewEnabled: true, previewFps: 30 }))
    compare(JSON.stringify(Model.settingsEntry("m", undefined, { previewEnabled: false })), JSON.stringify({ id: "m", previewEnabled: false }))
    // writes nothing that is not a valid user's value
    compare(Model.settingsEntry("m", settings, {}), null, "nothing to write")
    compare(Model.settingsEntry("m", settings, { cliPath: "/x" }), null, "only preview keys")
    compare(Model.settingsEntry("m", settings, { previewEnabled: "true" }), null)
    compare(Model.settingsEntry("m", settings, { previewFps: 20 }), null)
    compare(Model.settingsEntry("m", settings, { previewFps: "30" }), null)
    compare(Model.settingsEntry("", settings, { previewEnabled: true }), null)
    compare(Model.settingsEntry("m", "junk", { previewEnabled: true }), null)
    compare(Model.settingsEntry("m", [1], { previewEnabled: true }), null)
    compare(Model.settingsEntry("m", settings, null), null)
    var huge = {}
    for (var i = 0; i <= Model.SETTINGS_KEY_CAP; i++) huge["k" + i] = i
    compare(Model.settingsEntry("m", huge, { previewEnabled: true }), null, "too many keys: not rewritten, not truncated")
    compare(Model.SETTINGS_KEY_CAP, 256)
    var atCap = {}
    for (var c = 0; c < Model.SETTINGS_KEY_CAP; c++) atCap["k" + c] = c
    verify(Model.settingsEntry("m", atCap, { previewEnabled: true }) !== null, "exactly at the cap: written")
    // reading never writes
    var read = { cliPath: "/x" }
    Model.previewSettings(read)
    Model.previewFpsValue(read.previewFps)
    compare(JSON.stringify(read), JSON.stringify({ cliPath: "/x" }), "no default written back on read")
  }

  // A widget re-injected with the same stored values never undoes a choice
  // of this session; a value the settings changed always replaces it (S8).
  function test_preview_prefs_after_injection() {
    var off15 = { enabled: false, fps: 15 }
    var on15 = { enabled: true, fps: 15 }
    compare(JSON.stringify(Model.previewPrefsAfter(on15, null, off15)), JSON.stringify(off15), "first hand-over: as given")
    compare(JSON.stringify(Model.previewPrefsAfter(null, off15, on15)), JSON.stringify(on15), "nothing in force yet")
    compare(JSON.stringify(Model.previewPrefsAfter(on15, off15, off15)), JSON.stringify(on15), "same stored values: the session's choice holds")
    compare(JSON.stringify(Model.previewPrefsAfter(on15, off15, { enabled: false, fps: 30 })), JSON.stringify({ enabled: true, fps: 30 }),
            "only the changed value replaces the one in force")
    compare(JSON.stringify(Model.previewPrefsAfter(off15, off15, on15)), JSON.stringify(on15), "a stored change wins")
    compare(JSON.stringify(Model.previewPrefsAfter({ enabled: true, fps: 30 }, { enabled: true, fps: 30 }, off15)), JSON.stringify(off15))
    compare(JSON.stringify(Model.previewPrefsAfter(off15, off15, null)), JSON.stringify(off15), "junk reads as the defaults")
    compare(Model.previewPrefsAfter(off15, off15, { enabled: "yes", fps: 1e9 }).fps, 15)
  }

  function test_preview_prefs_chosen() {
    var off15 = { enabled: false, fps: 15 }
    compare(JSON.stringify(Model.previewPrefsChosen(off15, { previewEnabled: true })), JSON.stringify({ enabled: true, fps: 15 }))
    compare(JSON.stringify(Model.previewPrefsChosen(off15, { previewFps: 30 })), JSON.stringify({ enabled: false, fps: 30 }))
    var junk = [{ previewEnabled: "true" }, { previewFps: 20 }, { previewFps: "30" }, null, "x", { cliPath: "/x" }]
    for (var i = 0; i < junk.length; i++)
      compare(JSON.stringify(Model.previewPrefsChosen(off15, junk[i])), JSON.stringify(off15), JSON.stringify(junk[i]))
  }

  // An unchanged entry is answered false by the shell, as a missing one is:
  // only the second is a choice that was not saved (S7, S8).
  function test_settings_hold_and_unsaved() {
    compare(Model.settingsHold({ previewEnabled: true, cliPath: "/x" }, { previewEnabled: true }), true)
    compare(Model.settingsHold({ previewEnabled: false }, { previewEnabled: true }), false)
    compare(Model.settingsHold({}, { previewFps: 15 }), false, "a default is not a stored value")
    compare(Model.settingsHold({ previewFps: 30 }, {}), false)
    compare(Model.settingsHold(null, { previewFps: 30 }), false)
    compare(Model.previewUnsaved({ enabled: true, fps: 15 }, { enabled: false, fps: 15 }), true)
    compare(Model.previewUnsaved({ enabled: false, fps: 30 }, { enabled: false, fps: 15 }), true)
    compare(Model.previewUnsaved({ enabled: true, fps: 30 }, { enabled: true, fps: 30 }), false)
    compare(Model.previewUnsaved({ enabled: true, fps: 30 }, null), false, "nothing handed over yet")
    compare(Model.PREVIEW_UNSAVED_TEXT, "Could not save the preview setting")
  }

  // ---- camera settings (interface revision 7) ----------------------------------

  function merged(base, o) {
    for (var k in o) base[k] = o[k]
    return base
  }
  function intS(id, label, o) {
    return merged({ id: id, label: label, type: "int", scope: "camera", stored: false, enabled: true, disabled_reason: "",
                    enabled_when: [], value: 128, "default": 128, min: 0, max: 255, step: 1, hint: "slider" }, o || {})
  }
  function boolS(id, label, o) {
    return merged({ id: id, label: label, type: "bool", scope: "camera", stored: false, enabled: true, disabled_reason: "",
                    enabled_when: [], value: true, "default": true, hint: "switch" }, o || {})
  }
  function enumS(id, label, options, o) {
    return merged({ id: id, label: label, type: "enum", scope: "camera", stored: false, enabled: true, disabled_reason: "",
                    enabled_when: [], value: options[0].value, "default": options[0].value, options: options, hint: "segmented" }, o || {})
  }
  // The MX Brio as the daemon publishes it (contract s1, section 1).
  function brioGroups() {
    return [
      { id: "image", label: "Image", settings: [
        intS("camera.image.brightness", "Brightness"), intS("camera.image.contrast", "Contrast"),
        intS("camera.image.saturation", "Saturation"), intS("camera.image.sharpness", "Sharpness"),
        intS("camera.image.backlight_compensation", "Backlight compensation", { min: 0, max: 1, value: 1, "default": 1 })] },
      { id: "white_balance", label: "White balance", settings: [
        boolS("camera.white_balance.white_balance_automatic", "Automatic white balance"),
        intS("camera.white_balance.white_balance_temperature", "Temperature", {
          min: 2000, max: 7500, value: 2975, "default": 5000, unit: "K", enabled: false,
          disabled_reason: "Turn off automatic white balance to change this",
          enabled_when: [{ id: "camera.white_balance.white_balance_automatic", op: "eq", value: false }] })] },
      { id: "exposure", label: "Exposure", settings: [
        enumS("camera.exposure.auto_exposure", "Exposure mode", [{ value: "manual", label: "Manual" }, { value: "aperture_priority", label: "Auto" }],
              { value: "aperture_priority", "default": "aperture_priority" }),
        intS("camera.exposure.exposure_time_absolute", "Exposure time", {
          min: 3, max: 2047, value: 1250, "default": 156, unit: "×100 µs", enabled: false,
          disabled_reason: "Set exposure to manual to change this",
          enabled_when: [{ id: "camera.exposure.auto_exposure", op: "in", value: ["manual", "shutter_priority"] }] }),
        intS("camera.exposure.gain", "Gain", { value: 0, "default": 0 }),
        boolS("camera.exposure.keep_framerate", "Keep 30 fps in low light", { value: false }),
        enumS("camera.exposure.power_line_frequency", "Anti-flicker", [{ value: "disabled", label: "Off" }, { value: "50hz", label: "50 Hz" },
                                                                       { value: "60hz", label: "60 Hz" }, { value: "auto", label: "Auto" }],
              { value: "60hz", "default": "60hz" })] },
      { id: "focus", label: "Focus & zoom", settings: [
        boolS("camera.focus.focus_automatic_continuous", "Continuous autofocus"),
        intS("camera.focus.focus_absolute", "Focus", { value: 40, "default": 0, enabled: false,
                                                       disabled_reason: "Turn off continuous autofocus to change this" }),
        intS("camera.focus.zoom_absolute", "Zoom", { min: 100, max: 500, value: 100, "default": 100 }),
        intS("camera.focus.pan_absolute", "Pan", { min: -36000, max: 36000, step: 3600, value: 14400, "default": 0 }),
        intS("camera.focus.tilt_absolute", "Tilt", { min: -36000, max: 36000, step: 3600, value: -14400, "default": 0 }),
        enumS("camera.focus.field_of_view", "Field of view", [{ value: "90", label: "90°" }, { value: "78", label: "78°" }, { value: "65", label: "65°" }],
              { value: "65", "default": "90" })] }
    ]
  }
  // The groups as settings_group lines: at most `per` settings a line.
  function setLines(groups, o) {
    var opt = merged({ rev: 5, serial: 2, camera: brioId, per: 4 }, o || {})
    var raw = []
    for (var g = 0; g < groups.length; g++) {
      var parts = Math.max(1, Math.ceil(groups[g].settings.length / opt.per))
      for (var p = 0; p < parts; p++)
        raw.push({ v: 1, type: "settings_group", schema: 1, rev: opt.rev, serial: opt.serial, camera: opt.camera, part: p + 1, parts: parts,
                   group: { id: groups[g].id, label: groups[g].label, settings: groups[g].settings.slice(p * opt.per, (p + 1) * opt.per) } })
    }
    for (var i = 0; i < raw.length; i++) { raw[i].index = i; raw[i].count = raw.length }
    return raw
  }
  function rev7(o) { return merged({ interface_revision: 7, settings_schema: 1, settings_revision: 5 }, o || {}) }
  function feedAll(r, lines) {
    var res = { record: r, outcome: "" }
    for (var i = 0; i < lines.length; i++) res = Model.reduce(res.record, line(lines[i]))
    return res
  }
  function brio(o) { return feedAll(snap(rev7(o)), setLines(brioGroups())).record }
  function deltaLine(changes, o) {
    return merged({ v: 1, type: "settings_delta", schema: 1, rev: 6, serial: 2, camera: brioId, changes: changes }, o || {})
  }
  function rowIds(set) {
    var out = []
    for (var g = 0; g < set.groups.length; g++) out.push(set.groups[g].id + ":" + set.groups[g].rows.length)
    return JSON.stringify(out)
  }
  function groupsOf(n, perGroup) {
    var out = []
    for (var g = 0; g < n; g++) {
      var settings = []
      for (var s = 0; s < perGroup; s++) settings.push(intS("camera.g" + g + ".s" + s, "S" + s))
      out.push({ id: "g" + g, label: "Group " + g, settings: settings })
    }
    return out
  }

  // A set is committed once every line of it has arrived, whatever their
  // order; the parts of a group are joined.
  function test_settings_set_assembled_across_lines() {
    var lines = setLines(brioGroups())
    compare(lines.length, 7, "image and exposure and focus are cut in two parts at 4 a line")
    var r = snap(rev7({}))
    compare(r.settings, null)
    for (var i = 0; i < lines.length - 1; i++) {
      var res = Model.reduce(r, line(lines[i]))
      compare(res.outcome, "settings_group", "part " + i)
      compare(res.record.settings, null, "nothing committed before the last line")
      r = res.record
    }
    var last = Model.reduce(r, line(lines[lines.length - 1]))
    compare(last.outcome, "settings")
    var set = last.record.settings
    compare(rowIds(set), JSON.stringify(["image:5", "white_balance:2", "exposure:5", "focus:6"]))
    compare(set.rev, 5)
    compare(set.serial, 2)
    compare(set.camera, brioId)
    compare(last.record.settingsAssembly, null)
    compare(set.groups[3].label, "Focus & zoom", "an & stays in a settings label")
    compare(set.groups[0].rows.map(function(e) { return e.id.split(".")[2] }).join(","),
            "brightness,contrast,saturation,sharpness,backlight_compensation", "the two parts of Image joined, in order")
  }

  function test_settings_set_order_and_fields() {
    var lines = setLines(brioGroups())
    var r = feedAll(snap(rev7({})), lines.slice().reverse()).record
    compare(rowIds(r.settings), JSON.stringify(["image:5", "white_balance:2", "exposure:5", "focus:6"]),
            "lines arriving in reverse: the order is the lines' index, not their arrival")
    compare(r.settings.groups[0].rows[4].id, "camera.image.backlight_compensation")
  }

  function test_settings_set_rows() {
    var r = brio()
    var t = Model.findSetting(r, "camera.white_balance.white_balance_temperature")
    compare(t.type, "int")
    compare(t.enabled, false)
    compare(t.reason, "Turn off automatic white balance to change this")
    compare(t.unit, "K")
    compare(t.value, 2975)
    compare(t.min + ".." + t.max + "/" + t.step, "2000..7500/1")
    var fov = Model.findSetting(r, "camera.focus.field_of_view")
    compare(JSON.stringify(fov.options), JSON.stringify([{ value: "90", label: "90°" }, { value: "78", label: "78°" }, { value: "65", label: "65°" }]))
    compare(fov.value, "65")
    compare(fov.defaultValue, "90")
    var keep = Model.findSetting(r, "camera.exposure.keep_framerate")
    compare(keep.value, false)
    compare(keep.reason, "", "no reason while enabled")
    compare(Model.findSetting(r, "camera.image.nope"), null)
    compare(Model.findSetting(r, 7), null)
    compare(Model.findSetting(snap(rev7({})), "camera.image.brightness"), null)
  }

  // A line of another rev, serial, camera or count starts a new set; the
  // half-assembled one is dropped, never committed.
  function test_settings_half_set_dropped() {
    var old = setLines(brioGroups(), { rev: 5 })
    var fresh = setLines(brioGroups(), { rev: 6 })
    var r = feedAll(snap(rev7({})), old.slice(0, 3)).record
    compare(r.settingsAssembly.received, 3)
    r = Model.reduce(r, line(fresh[0])).record
    compare(r.settingsAssembly.rev, 6, "a line of another rev starts over")
    compare(r.settingsAssembly.received, 1)
    r = feedAll(r, old.slice(3)).record
    compare(r.settings, null, "the rest of the old set never completes it")
    r = feedAll(r, fresh).record
    compare(r.settings.rev, 6)
    // another serial, another camera, another count: each starts over too
    var other = [setLines(brioGroups(), { serial: 3 })[0], setLines(brioGroups(), { camera: fhdId })[0], setLines(brioGroups(), { per: 8 })[0]]
    for (var i = 0; i < other.length; i++) {
      var a = feedAll(snap(rev7({})), old.slice(0, 2)).record
      a = Model.reduce(a, line(other[i])).record
      compare(a.settingsAssembly.received, 1, "starts over " + i)
    }
    // a repeated index is ignored, the set still completes with its own lines
    var dup = feedAll(snap(rev7({})), [old[0], old[0], old[0]])
    compare(dup.outcome, "ignored")
    compare(dup.record.settingsAssembly.received, 1)
    compare(feedAll(dup.record, old.slice(1)).record.settings.rev, 5)
    // nothing before a snapshot, nothing from another schema
    compare(Model.reduce(Model.withLink("not-running"), line(old[0])).outcome, "ignored")
    compare(Model.reduce(snap(rev7({})), line(merged(old[0], { schema: 2 }))).outcome, "ignored")
  }

  // Deltas apply to the committed set of their serial, from its rev on.
  function test_settings_delta() {
    var r = brio()
    var res = Model.reduce(r, line(deltaLine([
      { id: "camera.exposure.auto_exposure", value: "manual", stored: true, enabled: true, disabled_reason: "" },
      { id: "camera.exposure.exposure_time_absolute", value: 156, stored: false, enabled: true, disabled_reason: "" }])))
    compare(res.outcome, "settings_delta")
    var after = res.record
    compare(after.settings.rev, 6)
    compare(Model.findSetting(after, "camera.exposure.auto_exposure").value, "manual")
    compare(Model.findSetting(after, "camera.exposure.auto_exposure").stored, true)
    var t = Model.findSetting(after, "camera.exposure.exposure_time_absolute")
    compare(t.enabled, true, "the manual mode enabled it")
    compare(t.reason, "")
    compare(t.value, 156)
    compare(Model.findSetting(r, "camera.exposure.exposure_time_absolute").enabled, false, "the old record is not modified")
    // the second line of one change set (same rev) applies; an older rev does not
    var same = Model.reduce(after, line(deltaLine([{ id: "camera.image.gain", value: 1 }, { id: "camera.exposure.gain", value: 9, stored: true, enabled: true, disabled_reason: "" }])))
    compare(same.outcome, "settings_delta")
    compare(Model.findSetting(same.record, "camera.exposure.gain").value, 9)
    compare(Model.reduce(after, line(deltaLine([{ id: "camera.exposure.gain", value: 3 }], { rev: 5 }))).outcome, "ignored", "an older rev")
    compare(Model.reduce(after, line(deltaLine([{ id: "camera.exposure.gain", value: 3 }], { rev: 9, serial: 3 }))).outcome, "ignored", "another serial")
    compare(Model.reduce(after, line(deltaLine([{ id: "camera.exposure.gain", value: 3 }], { rev: 9, camera: fhdId }))).outcome, "ignored", "another camera")
    compare(Model.reduce(after, line(deltaLine([{ id: "camera.exposure.gain", value: 3 }], { rev: 9, schema: 2 }))).outcome, "ignored", "another schema")
    compare(Model.reduce(snap(rev7({})), line(deltaLine([]))).outcome, "ignored", "no set committed")
    compare(Model.reduce(after, line(deltaLine([], { rev: 0 }))).outcome, "ignored")
    // a gap in rev still applies (the CLI re-emits the set after a gap)
    compare(Model.reduce(after, line(deltaLine([], { rev: 40 }))).record.settings.rev, 40)
    // mistyped keys keep the row's value; an int is clamped; an enum outside its options reads ""
    var odd = Model.reduce(same.record, line(deltaLine([
      { id: "camera.exposure.gain", value: "9", stored: "yes", enabled: 1 },
      { id: "camera.image.brightness", value: 9999 },
      { id: "camera.focus.field_of_view", value: "120" },
      { id: "camera.focus.focus_automatic_continuous", value: false, stored: true, enabled: true },
      { id: "camera.focus.focus_absolute", enabled: true, disabled_reason: "x" },
      { id: "camera.focus.zoom_absolute", enabled: false, disabled_reason: "<b>Busy</b> & " + new Array(200).join("z") },
      "junk", null, { id: "-1", value: 1 }]))).record
    compare(Model.findSetting(odd, "camera.exposure.gain").value, 9)
    compare(Model.findSetting(odd, "camera.exposure.gain").stored, true)
    compare(Model.findSetting(odd, "camera.image.brightness").value, 255)
    compare(Model.findSetting(odd, "camera.focus.field_of_view").value, "")
    compare(Model.findSetting(odd, "camera.focus.focus_automatic_continuous").value, false)
    compare(Model.findSetting(odd, "camera.focus.focus_absolute").reason, "", "enabled: no reason")
    var z = Model.findSetting(odd, "camera.focus.zoom_absolute")
    compare(z.enabled, false)
    verify(!/[<>]/.test(z.reason) && z.reason.indexOf("bBusy/b & ") === 0 && z.reason.length <= Model.SETTING_REASON_CAP, z.reason)
  }

  // settings_clear and every new picture of the daemon drop the set.
  function test_settings_clear_and_outage() {
    var r = brio()
    var half = Model.reduce(r, line(setLines(brioGroups(), { rev: 9 })[0])).record
    var c = Model.reduce(half, line({ v: 1, type: "settings_clear", rev: 9, serial: 2 }))
    compare(c.outcome, "settings_clear")
    compare(c.record.settings, null)
    compare(c.record.settingsAssembly, null)
    compare(c.record.settingsCleared, true)
    compare(Model.settingsView(c.record, {}, {}).hint, Model.SETTINGS_EMPTY_TEXT)
    compare(Model.settingsView(Model.reduce(c.record, line(stateObject({ active_camera: "", interface_revision: 7 }))).record, {}, {}).visible,
            false, "no camera at all: the camera list says so")
    compare(Model.reduce(Model.withLink("not-running"), line({ v: 1, type: "settings_clear", rev: 1, serial: 1 })).outcome, "ignored")
    var err = Model.reduce(r, line({ v: 1, type: "error", code: "daemon-not-running", error: "" })).record
    compare(err.settings, null)
    var again = Model.reduce(half, line(snapshotObject(rev7({})))).record
    compare(again.settings, null, "a snapshot starts over: its set follows")
    compare(again.settingsAssembly, null)
    compare(again.settingsCleared, false)
    var kept = Model.reduce(r, line(stateObject({ state: "active", interface_revision: 7 }))).record
    compare(rowIds(kept.settings), rowIds(r.settings), "a state line keeps the set")
    compare(Model.reduce(r, line({ v: 1, type: "controls", camera: brioId, controls: [] })).outcome, "ignored",
            "the revision-6 controls line is ignored")
  }

  // interface_revision >= 7 and a settings_schema this plugin reads; the
  // three hints otherwise.
  function test_settings_capability_rule() {
    var ok = brio()
    verify(Model.settingsSupported(ok))
    compare(Model.settingsMissingText(ok), "")
    var cases = [
      [{}, Model.CLI_NO_SETTINGS, "absent"],
      [{ interface_revision: 7 }, Model.CLI_NO_SETTINGS, "absent behind a revision-7 daemon"],
      [{ interface_revision: 6, settings_schema: null, settings_revision: null }, Model.DAEMON_NO_SETTINGS, "null"],
      [{ interface_revision: 6, settings_schema: 1 }, Model.DAEMON_NO_SETTINGS, "a revision-6 daemon"],
      [{ interface_revision: 7, settings_schema: null }, Model.DAEMON_NO_SETTINGS, "null at 7"],
      [{ interface_revision: 7, settings_schema: "1" }, Model.DAEMON_NO_SETTINGS, "a string"],
      [{ interface_revision: 7, settings_schema: 1.5 }, Model.DAEMON_NO_SETTINGS, "not whole"],
      [{ interface_revision: 7, settings_schema: 0 }, Model.DAEMON_NO_SETTINGS, "0"],
      [{ interface_revision: 7, settings_schema: 2 }, Model.PLUGIN_OLD_SETTINGS, "newer"],
      [{ interface_revision: 8, settings_schema: 99 }, Model.PLUGIN_OLD_SETTINGS, "much newer"],
      [{ interface_revision: "7", settings_schema: 1 }, Model.DAEMON_NO_SETTINGS, "a revision that is not a number"]
    ]
    for (var i = 0; i < cases.length; i++) {
      var r = snap(cases[i][0])
      verify(!Model.settingsSupported(r), cases[i][2])
      compare(Model.settingsMissingText(r), cases[i][1], cases[i][2])
      compare(Model.settingsView(r, {}, {}).hint, cases[i][1], cases[i][2])
      compare(Model.settingsView(r, {}, {}).groups.length, 0)
    }
    verify(Model.settingsSupported(snap(rev7({ interface_revision: 9 }))), "a later revision")
    var down = Model.reduce(ok, line(stateObject({ interface_revision: 6 }))).record
    verify(!Model.settingsSupported(down), "a daemon restarted older")
    compare(Model.settingsMissingText(Model.withLink("not-running")), "")
    compare(Model.settingsView(Model.withLink("not-running"), {}, {}).visible, false)
    compare(Model.DAEMON_NO_SETTINGS, "The daemon needs updating for camera settings (omarchy-broadcastd 0.22 or newer).")
    compare(Model.PLUGIN_OLD_SETTINGS, "Update the plugin to show these camera settings.")
    verify(Model.CLI_NO_SETTINGS.indexOf("omarchy-broadcast 0.22") !== -1 && Model.CLI_NO_SETTINGS.indexOf("CLI") !== -1)
  }

  function test_setting_entry_validation() {
    var hostileIds = ["Camera.image.x", "camera", "camera.a.b.c.d", "camera.image.bright ness", "camera.image.x;rm -rf ~",
                      "-1", "--camera=x", "camera..x", "camera.image.", ".camera.x", "camera.ímage.x", "camera.image.x\n",
                      "camera.image." + new Array(40).join("a"), 5, null, ""]
    for (var i = 0; i < hostileIds.length; i++)
      compare(Model.settingEntry(intS(hostileIds[i], "X")), null, JSON.stringify(hostileIds[i]))
    var at48 = "camera.image." + new Array(36).join("a")
    compare(at48.length, 48)
    compare(Model.settingEntry(intS(at48, "X")).id, at48, "48 bytes is fine")
    compare(Model.settingEntry(intS(at48 + "a", "X")), null, "49 is not")
    compare(Model.settingEntry(merged(intS("camera.image.x", "X"), { type: "float" })), null, "an unknown type is skipped")
    compare(Model.settingEntry(merged(intS("camera.image.x", "X"), { type: "path" })), null)
    compare(Model.settingEntry(null), null)
    var badInt = [
      ["NaN", { value: NaN }], ["Infinity", { max: Infinity }], ["-Infinity", { min: -Infinity }], ["float", { value: 1.5 }],
      ["string", { value: "128" }], ["null min", { min: null }], ["max == min", { min: 5, max: 5, value: 5, "default": 5 }],
      ["max < min", { min: 10, max: 5 }], ["step 0", { step: 0 }], ["negative step", { step: -1 }],
      ["1e7 steps", { min: 0, max: 10000000, step: 1 }], ["beyond int32", { max: 4294967296 }], ["huge", { max: 1e300 }],
      ["missing default", { "default": undefined }]
    ]
    for (var j = 0; j < badInt.length; j++)
      compare(Model.settingEntry(intS("camera.image.x", "X", badInt[j][1])), null, badInt[j][0])
    compare(Model.settingEntry(intS("camera.image.x", "X", { min: 0, max: 1000000, step: 1 })).max, 1000000, "1e6 steps is fine")
    var clamped = Model.settingEntry(intS("camera.image.x", "X", { value: -1, "default": 300 }))
    compare(clamped.value, 0, "-1 under min: clamped")
    compare(clamped.defaultValue, 255)
    var neg = Model.settingEntry(intS("camera.focus.pan_absolute", "Pan", { min: -36000, max: 36000, step: 3600, value: -14400 }))
    compare(neg.value, -14400)
    compare(Model.settingEntry(boolS("camera.x.y", "Y", { value: "true" })), null, "a switch needs a real boolean")
    compare(Model.settingEntry(boolS("camera.x.y", "Y", { value: false, "default": "x" })).defaultValue, false)
    // options: values of the grammar only, no repeats, at least one
    var opts = [{ value: "-1", label: "Minus" }, { value: "A", label: "Upper" }, { value: new Array(34).join("a"), label: "Long" },
                { value: "ok", label: "<img src=x> & OK" }, { value: "ok", label: "Again" }, { value: 3, label: "Number" },
                "junk", { value: "empty", label: "<>" }]
    var e = Model.settingEntry(enumS("camera.x.mode", "Mode", opts, { value: "ok", "default": "-1" }))
    compare(JSON.stringify(e.options), JSON.stringify([{ value: "ok", label: "img src=x & OK" }, { value: "empty", label: "empty" }]),
            "markup characters < and > removed, an & kept, an empty label is the value")
    compare(e.value, "ok")
    compare(e.defaultValue, "", "a default that is no option reads as none")
    compare(Model.settingEntry(enumS("camera.x.mode", "Mode", [{ value: "A", label: "x" }])), null, "no valid option")
    compare(Model.settingEntry(enumS("camera.x.mode", "Mode", [{ value: "a", label: "A" }], { value: "zzz" })).value, "")
    // labels, reasons and units: sanitised and capped; an empty label is the id
    var long = new Array(300).join("w")
    var l = Model.settingEntry(intS("camera.image.x", "<b>" + long, { unit: "<u>" + long, enabled: "true", disabled_reason: "<i>&" + long }))
    verify(!/[<>]/.test(l.label + l.unit + l.reason))
    verify(l.label.length <= Model.SETTING_LABEL_CAP && l.unit.length <= Model.SETTING_UNIT_CAP && l.reason.length <= Model.SETTING_REASON_CAP)
    compare(l.enabled, false, "enabled only for a real true")
    compare(Model.settingEntry(intS("camera.image.x", "<>\u202e")).label, "camera.image.x")
    // enabled_when is the daemon's business: an unknown op, or a condition on a
    // skipped setting, changes nothing
    var w = Model.settingEntry(intS("camera.image.x", "X", { enabled_when: [{ id: "camera.image.skipped", op: "xor", value: 1 }] }))
    compare(w.enabled, true)
    var g = Model.settingEntry(intS("camera.image.y", "Y", { enabled: false, disabled_reason: "Why", enabled_when: "junk" }))
    compare(g.enabled + ":" + g.reason, "false:Why")
  }

  // A set with an unknown type keeps everything else; a condition pointing at
  // the skipped setting does not change what the daemon says.
  function test_settings_unknown_type_in_a_set() {
    var groups = brioGroups()
    groups[0].settings.splice(1, 0, merged(intS("camera.image.future", "Future"), { type: "colour" }))
    groups[0].settings[2].enabled_when = [{ id: "camera.image.future", op: "eq", value: true }]
    var r = feedAll(snap(rev7({})), setLines(groups)).record
    compare(rowIds(r.settings), JSON.stringify(["image:5", "white_balance:2", "exposure:5", "focus:6"]))
    compare(Model.findSetting(r, "camera.image.future"), null)
    compare(Model.findSetting(r, "camera.image.contrast").enabled, true)
    compare(Model.settingsView(r, {}, {}).groups[0].truncation, "", "a skipped type is no truncation")
  }

  function test_settings_caps() {
    // 20 groups of 2: 16 shown, said so
    var many = feedAll(snap(rev7({})), setLines(groupsOf(20, 2), { per: 2 })).record
    compare(many.settings.groups.length, 16)
    compare(many.settings.groupsTotal, 20)
    var v = Model.settingsView(many, {}, {})
    compare(v.truncation, "Showing 16 of 20 groups")
    // a group of 20 settings: 16 shown
    var big = feedAll(snap(rev7({})), setLines(groupsOf(1, 20), { per: 8 })).record
    compare(big.settings.groups[0].rows.length, 16)
    compare(Model.settingsView(big, null, {}).groups[0].truncation, "Showing 16 of 20 settings")
    compare(Model.settingsView(big, "", {}).groups[0].truncation, "", "a closed group says nothing")
    // 64 rows in all: 5 groups of 16 leave the fifth empty and the fourth full
    var all = feedAll(snap(rev7({})), setLines(groupsOf(5, 16), { per: 8 })).record
    var counts = all.settings.groups.map(function(g) { return g.rows.length })
    compare(JSON.stringify(counts), JSON.stringify([16, 16, 16, 16, 0]))
    for (var gi = 0; gi < 5; gi++) {
      var view = Model.settingsView(all, "g" + gi, {})
      compare(view.groups.length, 5, "a group cut to nothing by the row cap is drawn, to say so")
      compare(view.rowCount, gi < 4 ? 16 : 0, "one group open: its rows only")
      compare(Model.cursorStops(all, 0, false, "camera", view).filter(function(s) { return s.kind === "setting" }).length, view.rowCount,
              "the keyboard walks exactly the rows drawn")
      compare(view.groups[gi].truncation, gi < 4 ? "" : "Showing 0 of 16 settings")
    }
    // counts no v1 producer announces: never waited for
    var l = setLines(brioGroups())[0]
    var hostile = [{ count: 1e9 }, { count: 65 }, { count: 0 }, { count: -1 }, { count: 2.5 }, { index: 7, count: 7 },
                   { index: -1 }, { parts: 65 }, { part: 0 }, { part: 3, parts: 2 }, { rev: 0 }, { rev: 4294967296 },
                   { serial: "2" }, { camera: "" }, { camera: 7 }, { group: { id: "Image", label: "x", settings: [] } },
                   { group: { id: "image", label: "x", settings: "x" } }, { group: null }]
    // A bad group in a good envelope is kept as a refused group (it fills its
    // place, so the rest of the set still commits; see
    // test_settings_prototype_keys); a bad envelope is ignored.
    for (var i = 0; i < hostile.length; i++) {
      var res = Model.reduce(snap(rev7({})), line(merged(JSON.parse(JSON.stringify(l)), hostile[i])))
      // (a camera group with no camera is a refused group too)
      compare(res.outcome, hostile[i].group !== undefined || hostile[i].camera === "" ? "settings_group" : "ignored", JSON.stringify(hostile[i]))
    }
    // a huge settings or changes array: bounded work, only the first entries read
    var junk = []
    for (var k = 0; k < 200000; k++) junk.push("junk")
    junk[3] = intS("camera.image.brightness", "Brightness")
    junk[Model.SETTINGS_LINE_LOOK] = intS("camera.image.contrast", "Contrast")
    var t0 = Date.now()
    var huge = Model.applyMessage(snap(rev7({})), ({ v: 1, type: "settings_group", schema: 1, rev: 1, serial: 1, camera: brioId,
                                                   index: 0, count: 1, part: 1, parts: 1, group: { id: "image", label: "Image", settings: junk } })).record
    var changes = []
    for (var c = 0; c < 200000; c++) changes.push({ id: "camera.image.brightness", value: c })
    var d = Model.applyMessage(huge, deltaLine(changes, { rev: 1, serial: 1 })).record
    var took = Date.now() - t0
    compare(rowIds(huge.settings), JSON.stringify(["image:1"]), "the entry past the look cap is never read")
    compare(Model.findSetting(d, "camera.image.brightness").value, Model.SETTINGS_LINE_LOOK - 1, "only the first changes are applied")
    verify(took < 100, "took " + took + " ms")
    compare(Model.SETTINGS_GROUP_CAP + Model.SETTINGS_PER_GROUP_CAP + Model.SETTING_OPTION_CAP + Model.SETTINGS_ROW_CAP, 112)
    // options: 20 sent, 16 kept, said so on the row
    var twenty = []
    for (var o = 0; o < 20; o++) twenty.push({ value: "m" + o, label: "Item " + o })
    var groups = [{ id: "other", label: "Other", settings: [enumS("camera.other.menu", "Menu", twenty)] }]
    var menu = Model.settingsView(feedAll(snap(rev7({})), setLines(groups)).record, {}, {}).groups[0].rows[0]
    compare(menu.options.length, 16)
    compare(menu.optionsNote, "Showing 16 of 20 choices")
    compare(menu.widget, "dropdown")
  }

  function test_setting_values() {
    var r = brio()
    var pan = Model.findSetting(r, "camera.focus.pan_absolute")
    compare(Model.snapSetting(pan, 14000), 14400)
    compare(Model.snapSetting(pan, 40000), null, "out of range")
    compare(Model.clampSetting(pan, 40000), 36000)
    compare(Model.clampSetting(pan, -1e9), -36000)
    compare(Model.clampSetting(pan, NaN), null)
    compare(Model.clampSetting(pan, "1"), null)
    compare(Model.settingKeyStep(pan), 3600)
    compare(Model.settingKeyStep(Model.findSetting(r, "camera.image.brightness")), 13)
    compare(Model.settingNudge(pan, 14400, 1), 18000)
    compare(Model.settingNudge(pan, 36000, 1), 36000)
    compare(Model.settingNudge(pan, 14400, 0), null)
    var mode = Model.findSetting(r, "camera.exposure.auto_exposure")
    compare(Model.settingNudge(mode, "aperture_priority", -1), null, "a choice is never written by Left/Right")
    compare(Model.settingNudge(mode, "", 1), null)
    compare(Model.settingNudge(Model.findSetting(r, "camera.exposure.keep_framerate"), false, 1), null)
    compare(Model.rowValue(mode, "manual"), "manual")
    compare(Model.rowValue(mode, "shutter_priority"), null, "not an option of this camera")
    compare(Model.rowValue(Model.findSetting(r, "camera.exposure.keep_framerate"), "true"), null)
    compare(Model.rowValue(Model.findSetting(r, "camera.exposure.keep_framerate"), true), true)
    compare(Model.rowValue(pan, 13000), 14400)
    compare(Model.rowValue(null, 1), null)
    compare(Model.settingValueText(Model.findSetting(r, "camera.exposure.exposure_time_absolute"), 1250), "1250 ×100 µs")
    compare(Model.settingValueText(pan, -14400), "-14400")
    compare(Model.settingValueText(mode, "manual"), "Manual")
    compare(Model.settingValueText(mode, "x"), Model.UNKNOWN)
    compare(Model.shownSettingValue(pan, { "camera.focus.pan_absolute": 0 }), 0)
    compare(Model.shownSettingValue(pan, { "camera.focus.pan_absolute": 99999 }), 36000, "clamped")
    compare(Model.shownSettingValue(pan, { "camera.focus.pan_absolute": "x" }), 14400)
    compare(Model.shownSettingValue(mode, { "camera.exposure.auto_exposure": "manual" }), "manual")
    compare(Model.shownSettingValue(pan, null), 14400)
    // the widget: few short choices are buttons, else a dropdown
    compare(Model.settingWidget(mode), "segmented")
    compare(Model.settingWidget(Model.findSetting(r, "camera.exposure.power_line_frequency")), "segmented")
    compare(Model.settingWidget(Model.findSetting(r, "camera.focus.field_of_view")), "segmented")
    compare(Model.settingWidget(pan), "slider")
    compare(Model.settingWidget(Model.findSetting(r, "camera.exposure.keep_framerate")), "switch")
    compare(Model.settingWidget({ type: "enum", options: [{ label: "A very long first choice" }, { label: "And a second" }] }), "dropdown")
    compare(Model.settingWidget({ type: "action" }), "action")
  }

  // Every write: `--camera=` of the set's camera, then `--`, then id and value,
  // each its own argv element.
  function test_settings_argv() {
    var r = brio()
    var argv = function(id, value, camera) {
      return JSON.stringify(Model.intentArgv({ verb: "setting", id: id, value: value, camera: camera === undefined ? brioId : camera }, cli, r))
    }
    compare(argv("camera.image.brightness", 141), JSON.stringify([cli, "settings", "set", "--camera=" + brioId, "--", "camera.image.brightness", "141"]))
    compare(argv("camera.focus.pan_absolute", -14400), JSON.stringify([cli, "settings", "set", "--camera=" + brioId, "--", "camera.focus.pan_absolute", "-14400"]),
            "a negative value after --")
    compare(argv("camera.focus.pan_absolute", -14000), JSON.stringify([cli, "settings", "set", "--camera=" + brioId, "--", "camera.focus.pan_absolute", "-14400"]),
            "put on the grid")
    compare(argv("camera.focus.pan_absolute", 99999), "null", "off range")
    compare(argv("camera.exposure.keep_framerate", true), JSON.stringify([cli, "settings", "set", "--camera=" + brioId, "--", "camera.exposure.keep_framerate", "true"]))
    compare(argv("camera.exposure.keep_framerate", false), JSON.stringify([cli, "settings", "set", "--camera=" + brioId, "--", "camera.exposure.keep_framerate", "false"]))
    compare(argv("camera.exposure.keep_framerate", "true"), "null", "a string is no boolean")
    compare(argv("camera.focus.field_of_view", "78"), JSON.stringify([cli, "settings", "set", "--camera=" + brioId, "--", "camera.focus.field_of_view", "78"]))
    compare(argv("camera.focus.field_of_view", "120"), "null", "not an option of this setting")
    compare(argv("camera.exposure.auto_exposure", "shutter_priority"), "null", "an option of the catalogue, not of this camera")
    compare(argv("camera.focus.field_of_view", "--help"), "null")
    compare(argv("camera.image.brightness", NaN), "null")
    compare(argv("camera.image.brightness", 1e21), "null")
    compare(argv("camera.image.brightness", "141"), "null")
    compare(argv("camera.white_balance.white_balance_temperature", 3000), "null", "greyed: never sent")
    compare(argv("camera.image.nope", 1), "null", "not in the set")
    compare(argv("camera.image.brightness; rm -rf ~", 1), "null")
    compare(argv("camera.image.brightness", 141, fhdId), "null", "made for another camera")
    compare(argv("camera.image.brightness", 141, ""), "null", "no camera recorded")
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: "camera.image.brightness", value: 1, camera: brioId }, "omarchy-broadcast", r)), "null", "relative CLI")
    compare(JSON.stringify(Model.intentArgv({ verb: "reset-settings", camera: brioId }, cli, r)), JSON.stringify([cli, "settings", "reset", "--camera=" + brioId]))
    compare(JSON.stringify(Model.intentArgv({ verb: "reset-settings", camera: fhdId }, cli, r)), "null")
    compare(JSON.stringify(Model.intentArgv({ verb: "reset-settings" }, cli, r)), "null")
    // the set moved to another camera: what was made for the Brio never runs
    var fhd = feedAll(r, setLines(brioGroups(), { camera: fhdId, rev: 9 })).record
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: "camera.image.brightness", value: 1, camera: brioId }, cli, fhd)), "null")
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: "camera.image.brightness", value: 1, camera: fhdId }, cli, fhd)),
            JSON.stringify([cli, "settings", "set", "--camera=" + fhdId, "--", "camera.image.brightness", "1"]))
    // re-checked when they run: an old daemon, a cleared set, unavailable
    var olds = [Model.reduce(r, line(stateObject({ interface_revision: 6 }))).record,
                Model.reduce(r, line({ v: 1, type: "settings_clear", rev: 9, serial: 2 })).record, Model.withLink("not-running")]
    for (var i = 0; i < olds.length; i++) {
      compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: "camera.image.brightness", value: 1, camera: brioId }, cli, olds[i])), "null", "write " + i)
      compare(JSON.stringify(Model.intentArgv({ verb: "reset-settings", camera: brioId }, cli, olds[i])), "null", "reset " + i)
    }
    // the builders: the camera validated as selections are, the id by its
    // grammar, the value by its words
    compare(JSON.stringify(Model.settingArgv(cli, "next", "camera.image.x", "1")), JSON.stringify([cli, "settings", "set", "--camera=next", "--", "camera.image.x", "1"]),
            "a camera named next is fine in --camera=")
    compare(Model.settingArgv(cli, "", "camera.image.x", "1"), null)
    compare(Model.settingArgv(cli, "usb-cam…", "camera.image.x", "1"), null, "a clipped id")
    compare(Model.settingArgv(cli, new Array(98).join("c"), "camera.image.x", "1"), null, "over the id cap")
    compare(Model.settingArgv(cli, brioId, "-1", "1"), null)
    compare(Model.settingArgv(cli, brioId, "camera.image.x", "1.5"), null)
    compare(Model.settingArgv(cli, brioId, "camera.image.x", "1 2"), null)
    compare(Model.settingArgv(cli, brioId, "camera.image.x", "-"), null)
    compare(Model.settingArgv(cli, brioId, "camera.image.x", "--help"), null)
    compare(Model.settingArgv(cli, brioId, "camera.image.x", ""), null)
    compare(Model.settingArgv(cli, brioId, "camera.image.x", 1), null)
    compare(Model.resetSettingsArgv(cli, ""), null)
    compare(Model.resetSettingsArgv("", brioId), null)
    // an action: only true
    var act = { id: "camera.focus.pan_reset", type: "action", enabled: true }
    compare(Model.settingArgvValue(act, true), "true")
    compare(Model.settingArgvValue(act, "true"), null)
    compare(Model.settingArgvValue(act, false), null)
  }

  // A drag never queues a process per move: one queued write per setting id.
  function test_intent_queue_coalesces_settings() {
    var q = []
    var add = function(i) { q = Model.enqueueIntent(q, i) }
    var show = function() {
      return JSON.stringify(q.map(function(i) { return i.verb + (i.verb === "setting" ? ":" + i.id + "=" + i.value : "") }))
    }
    for (var v = 0; v < 100; v++) add({ verb: "setting", id: "camera.image.brightness", value: v })
    compare(show(), JSON.stringify(["setting:camera.image.brightness=99"]))
    add({ verb: "setting", id: "camera.image.contrast", value: 5 })
    add({ verb: "setting", id: "camera.image.brightness", value: 7 })
    compare(show(), JSON.stringify(["setting:camera.image.contrast=5", "setting:camera.image.brightness=7"]), "the newer write goes last")
    add({ verb: "select", id: "a" })
    add({ verb: "next" })
    compare(show(), JSON.stringify(["setting:camera.image.contrast=5", "setting:camera.image.brightness=7", "next"]), "the latest other ask wins")
    add({ verb: "reset-settings" })
    compare(show(), JSON.stringify(["next", "reset-settings"]), "a reset supersedes the queued writes")
    add({ verb: "setting", id: "camera.image.saturation", value: 4 })
    compare(show(), JSON.stringify(["next", "reset-settings", "setting:camera.image.saturation=4"]), "a write after a reset stays after it")
    var input = q
    Model.enqueueIntent(input, { verb: "enable", on: true })
    compare(input.length, 3, "the queue given is not modified")
    var many = []
    for (var i = 0; i < 1000; i++) many = Model.enqueueIntent(many, { verb: "setting", id: "camera.image.s" + i, value: 1 })
    compare(many.length, Model.SETTING_QUEUE_CAP, "the cap counts ids")
    compare(many[0].id, "camera.image.s0", "nothing queued is evicted: the later writes are refused")
    verify(Model.queuedSetting([{ verb: "setting", id: "camera.image.contrast", value: 1 }], "camera.image.contrast"))
    verify(!Model.queuedSetting([{ verb: "reset-settings" }], "camera.image.contrast"))
    verify(!Model.queuedSetting(null, "camera.image.contrast"))
    // on/off goes first and only a non-setting command holds the toggle
    var w = { verb: "setting", id: "camera.image.brightness", value: 1 }
    var o = Model.enqueueIntent([w, { verb: "setting", id: "camera.image.contrast", value: 2 }], { verb: "enable", on: false })
    compare(JSON.stringify(o.map(function(i) { return i.verb })), JSON.stringify(["enable", "setting", "setting"]))
    verify(!Model.toggleBlocked(w, [w, { verb: "reset-settings" }]), "setting writes do not hold the switch")
    verify(Model.toggleBlocked(w, [w, { verb: "enable", on: false }]))
    verify(Model.toggleBlocked({ verb: "select", id: "x" }, []))
    // a camera change drops the queued writes and resets, keeps the rest
    var d = [w, { verb: "reset-settings" }, { verb: "next" }]
    compare(JSON.stringify(Model.dropSettingIntents(d)), JSON.stringify([{ verb: "next" }]))
    compare(d.length, 3)
    compare(Model.dropSettingIntents(null).length, 0)
  }

  // A switch, a choice, an effect or noise removal does not wait behind
  // queued slider writes; the sliders' latest values stay queued and run
  // after it, and two writes of one id keep their order (one per id).
  function test_intent_queue_quick_asks_pass_sliders() {
    var order = function(q) {
      return JSON.stringify(q.map(function(i) { return i.verb + (i.verb === "setting" ? ":" + i.id + "=" + i.value : "") }))
    }
    var slider = function(id, v) { return { verb: "setting", id: id, value: v } }
    var q = [slider("camera.image.brightness", 1), slider("camera.image.contrast", 2)]
    q = Model.enqueueIntent(q, { verb: "setting", id: "camera.image.autofocus", value: true, quick: true })
    compare(order(q), JSON.stringify(["setting:camera.image.autofocus=true", "setting:camera.image.brightness=1", "setting:camera.image.contrast=2"]), "a switch goes first")
    q = Model.enqueueIntent(q, { verb: "denoise", on: true })
    compare(order(q), JSON.stringify(["setting:camera.image.autofocus=true", "denoise", "setting:camera.image.brightness=1", "setting:camera.image.contrast=2"]), "noise removal goes after the earlier quick ask, before the sliders")
    // the slider's coalesced latest value stays queued, after the quick ones
    q = Model.enqueueIntent(q, slider("camera.image.brightness", 9))
    compare(order(q), JSON.stringify(["setting:camera.image.autofocus=true", "denoise", "setting:camera.image.contrast=2", "setting:camera.image.brightness=9"]))
    // an effect replaces the other ask, passes the sliders
    var e = Model.enqueueIntent([slider("camera.image.brightness", 1)], { verb: "effect", effect: "blur" })
    compare(order(e), JSON.stringify(["effect", "setting:camera.image.brightness=1"]))
    // the same id keeps one write: a quick write replaces a queued one of its id
    var same = Model.enqueueIntent([slider("camera.image.contrast", 2), slider("camera.image.mode", "a")],
                                   { verb: "setting", id: "camera.image.mode", value: "b", quick: true })
    compare(order(same), JSON.stringify(["setting:camera.image.mode=b", "setting:camera.image.contrast=2"]))
    // never ahead of a reset queued before it
    var r = Model.enqueueIntent([{ verb: "reset-settings" }, slider("camera.image.contrast", 2)],
                                { verb: "setting", id: "camera.image.autofocus", value: false, quick: true })
    compare(order(r), JSON.stringify(["reset-settings", "setting:camera.image.autofocus=false", "setting:camera.image.contrast=2"]))
    // a quick ask with no slider queued goes last, as before
    var l = Model.enqueueIntent([{ verb: "next" }], { verb: "denoise", on: false })
    compare(order(l), JSON.stringify(["denoise"]), "the latest other ask wins")
    verify(Model.isQuickIntent({ verb: "effect", effect: "off" }))
    verify(!Model.isQuickIntent(slider("camera.image.brightness", 1)))
    verify(!Model.isQuickIntent(null))
  }

  // The daemon prints no change for a write of the value in force: such a
  // write owes no line, and its exit alone settles the draft.
  function test_setting_noop_write_owes_no_line() {
    var r = brio()
    var id = "camera.exposure.keep_framerate"
    compare(Model.findSetting(r, id).value, false)
    verify(!Model.settingNoop(r, { verb: "setting", id: id, value: false }), "shown but not stored: the write prints a line")
    Model.findSetting(r, id).stored = true
    verify(Model.settingNoop(r, { verb: "setting", id: id, value: false }), "the value already in force")
    verify(!Model.settingNoop(r, { verb: "setting", id: id, value: false }, 3, 4), "an earlier write's line is still owed: the record may be stale")
    verify(Model.settingNoop(r, { verb: "setting", id: id, value: false }, 4, 4), "no line owed")
    verify(!Model.settingNoop(r, { verb: "setting", id: id, value: true }), "a real change owes its line")
    verify(!Model.settingNoop(r, { verb: "reset-settings" }))
    verify(!Model.settingNoop(r, { verb: "setting", id: "camera.image.nope", value: 1 }))
    verify(!Model.settingNoop(snap(rev7({})), { verb: "setting", id: id, value: false }))
  }

  // A draft goes on the change its own write caused, never on an earlier
  // write's late one.
  function test_setting_line_ownership_and_drafts() {
    var b = "camera.image.brightness"
    var markN = Model.settingLineMark(0, 0)
    compare(Model.settingWriteEnd(true, 0, markN), "settle")
    var markN1 = Model.settingLineMark(0, markN + 1)
    compare(markN1, 1)
    var settling = {}
    settling[b] = { value: 200, line: markN1 + 1 }
    var drafts = {}
    drafts[b] = 200
    var after = Model.settleWritten(drafts, settling, 1)
    compare(after.drafts[b], 200, "an earlier write's change does not settle it")
    after = Model.settleWritten(after.drafts, after.settling, 2)
    compare(JSON.stringify(after.drafts), "{}", "its own change settles it, whatever it reports")
    compare(JSON.stringify(after.settling), "{}")
    compare(Model.settingWriteEnd(true, 2, markN1), "drop")
    compare(Model.settingWriteEnd(false, 0, 0), "drop")
    compare(Model.settingWriteEnd("yes", 0, 0), "drop")
    drafts[b] = 90
    after = Model.settleWritten(drafts, settling, 5)
    compare(after.drafts[b], 90, "the user moved on: the newer draft stays")
    compare(JSON.stringify(after.settling), "{}")
    compare(JSON.stringify(Model.settleWritten(null, null, 1)), JSON.stringify({ drafts: {}, settling: {} }))
    compare(Model.settingLineMark(NaN, "x"), 0)
    // drafts settle on the reported value, a row gone or greyed
    var r = brio()
    var d = {}
    d["camera.image.brightness"] = 128
    d["camera.image.contrast"] = 100
    d["camera.white_balance.white_balance_temperature"] = 3000
    d["camera.image.gone"] = 1
    compare(JSON.stringify(Model.settleDrafts(d, r)), JSON.stringify({ "camera.image.contrast": 100 }))
    compare(JSON.stringify(Model.settleDrafts(d, Model.withLink("not-running"))), "{}")
    // withSetting: ids of the grammar, at most the row cap
    compare(JSON.stringify(Model.withSetting({ "camera.image.a": 1, "junk key": 2 }, "camera.image.b", 3)), JSON.stringify({ "camera.image.a": 1, "camera.image.b": 3 }))
    compare(JSON.stringify(Model.withSetting({ "camera.image.a": 1 }, "camera.image.a", undefined)), "{}")
    compare(JSON.stringify(Model.withSetting({ "camera.image.a": 1 }, "-1", 3)), JSON.stringify({ "camera.image.a": 1 }))
    var big = {}
    for (var i = 0; i < 500; i++) big["camera.image.s" + i] = i
    compare(Object.keys(Model.withSetting(big, "", undefined)).length, Model.SETTINGS_ROW_CAP)
  }

  // What the panel draws is what the keyboard walks: collapsed groups and
  // capped rows are no stops.
  function test_settings_view_and_stops() {
    var r = brio({ cameras: [cameraObjects()[0]] })
    var v = Model.settingsView(r, {}, {})
    compare(v.visible, true)
    compare(v.hint, "")
    compare(v.note, Model.SETTINGS_IDLE_TEXT)
    compare(v.reset, true)
    compare(JSON.stringify(v.groups.map(function(g) { return g.id + ":" + g.expanded + ":" + g.rows.length })),
            JSON.stringify(["image:true:5", "white_balance:false:0", "exposure:false:0", "focus:false:0"]), "Image open, the others closed")
    compare(v.groups[0].glyph, Model.GLYPH_EXPANDED)
    compare(v.groups[1].glyph, Model.GLYPH_COLLAPSED)
    compare(v.rowCount, 5)
    var kinds = function(view) {
      return JSON.stringify(Model.cursorStops(r, 1, false, "camera", view).map(function(s) { return s.kind + s.index }))
    }
    compare(kinds(v), JSON.stringify(["switch-1", "tabs-1", "camera0", "reset-1", "group0", "setting0", "setting1", "setting2", "setting3", "setting4",
                                      "group1", "group2", "group3"]), "Reset first: it is on the settings' title line")
    var open = Model.settingsView(r, "exposure", {})
    compare(kinds(open), JSON.stringify(["switch-1", "tabs-1", "camera0", "reset-1", "group0", "group1", "group2", "setting0", "setting1", "setting2",
                                         "setting3", "setting4", "group3"]), "opening Exposure closed Image")
    var t = Model.viewRow(open, 1)
    compare(t.id, "camera.exposure.exposure_time_absolute")
    compare(t.enabled + ":" + t.reason, "false:Set exposure to manual to change this", "a greyed row is drawn, with its reason, and is a stop")
    compare(t.valueText, "1250 ×100 µs")
    compare(Model.viewRow(open, 0).widget, "segmented")
    compare(Model.viewRow(open, 3).widget, "switch")
    compare(Model.viewRow(open, 9), null)
    compare(kindsOf(Model.cursorStops(r, 1, false, "effect", v)), JSON.stringify(["switch", "tabs", "effect"]),
            "the settings are stops on the Camera tab only")
    // a draft shows until it is confirmed
    var d = {}
    d["camera.image.brightness"] = 200
    compare(Model.settingsView(r, {}, d).groups[0].rows[0].value, 200)
    compare(Model.settingsView(r, {}, d).groups[0].rows[0].valueText, "200")
    // live while the daemon has the camera open
    compare(Model.settingsView(Model.reduce(r, line(stateObject({ state: "active", consumers: 1, interface_revision: 7 }))).record, {}, {}).note,
            Model.SETTINGS_LIVE_TEXT)
    compare(Model.settingsView(Model.reduce(r, line(stateObject({ state: "starting", consumers: 1, interface_revision: 7 }))).record, {}, {}).note,
            Model.SETTINGS_LIVE_TEXT)
    // a camera without an Image group opens its first group
    var other = feedAll(snap(rev7({})), setLines([{ id: "other", label: "Other", settings: [intS("camera.other.x", "X")] },
                                                   { id: "focus", label: "Focus", settings: [intS("camera.focus.y", "Y")] }])).record
    compare(JSON.stringify(Model.settingsView(other, {}, {}).groups.map(function(g) { return g.expanded })), JSON.stringify([true, false]))
    // the hint replaces everything: no stops
    var old = snap({ cameras: [cameraObjects()[0]] })
    compare(kinds(Model.settingsView(old, {}, {})), JSON.stringify(["switch-1", "tabs-1", "camera0"]))
    compare(kinds(undefined), JSON.stringify(["switch-1", "tabs-1", "camera0"]))
    verify(Model.stopHasIndex("group") && Model.stopHasIndex("setting") && Model.stopHasIndex("camera") && !Model.stopHasIndex("reset"))
    var stops = Model.cursorStops(r, 1, true, "camera", v)
    compare(Model.stopIndex(stops, "setting", 2), 9, "after the preview's two stops, the tab row, the camera row, Reset and the header")
    compare(Model.stopIndex(stops, "group", 3), 14)
    compare(Model.openGroupId({ image: true }, r.settings), "image", "anything but a group id or \"\" reads as the default")
    compare(Model.openGroupId("nope", r.settings), "image", "a group the set does not have: the default")
    compare(Model.openGroupId("focus", r.settings), "focus")
    compare(Model.openGroupId("", r.settings), "", "the user closed it: none")
    compare(Model.openGroupId("image", null), "")
  }

  // The CLI's own bytes (crates/omarchy-broadcast/src/json.rs, the s1 sample
  // lines): a set of two lines, then a delta that also greys an action.
  readonly property var cliSetLines: [
    '{"v":1,"type":"settings_group","schema":1,"rev":12,"serial":3,"camera":"usb-046d_0944","index":0,"count":2,"part":1,"parts":1,"group":{"id":"exposure","label":"Exposure","settings":[{"id":"camera.exposure.auto_exposure","label":"Exposure mode","type":"enum","value":"aperture_priority","default":"aperture_priority","stored":false,"enabled":true,"disabled_reason":"","enabled_when":[],"options":[{"value":"manual","label":"Manual"},{"value":"aperture_priority","label":"Auto"}],"hint":"segmented"},{"id":"camera.exposure.exposure_time_absolute","label":"Exposure time","type":"int","value":1250,"default":156,"stored":false,"enabled":false,"disabled_reason":"Set exposure to manual to change this","enabled_when":[{"id":"camera.exposure.auto_exposure","op":"in","value":["manual","shutter_priority"]}],"min":3,"max":2047,"step":1,"unit":"×100 µs"},{"id":"camera.exposure.keep_framerate","label":"Keep 30 fps in low light","type":"bool","value":false,"default":true,"stored":true,"enabled":true,"disabled_reason":"","enabled_when":[],"hint":"switch"}]}}',
    '{"v":1,"type":"settings_group","schema":1,"rev":12,"serial":3,"camera":"usb-046d_0944","index":1,"count":2,"part":1,"parts":1,"group":{"id":"white_balance","label":"White balance","settings":[{"id":"camera.white_balance.do_white_balance","label":"Balance once","type":"action","stored":false,"enabled":true,"disabled_reason":"","enabled_when":[]}]}}'
  ]
  readonly property string cliDeltaLine: '{"v":1,"type":"settings_delta","schema":1,"rev":13,"serial":3,"camera":"usb-046d_0944","changes":[{"id":"camera.exposure.auto_exposure","value":"manual","stored":true,"enabled":true,"disabled_reason":""},{"id":"camera.exposure.exposure_time_absolute","value":1250,"stored":false,"enabled":true,"disabled_reason":""},{"id":"camera.white_balance.do_white_balance","stored":false,"enabled":false,"disabled_reason":"Not now"}]}'

  function test_real_cli_lines() {
    var r = Model.reduce(Model.emptyRecord("connecting"), line(snapshotObject(rev7({ active_camera: "usb-046d_0944" })))).record
    verify(Model.settingsSupported(r))
    var res = { record: r, outcome: "" }
    for (var i = 0; i < cliSetLines.length; i++) res = Model.reduce(res.record, cliSetLines[i])
    compare(res.outcome, "settings")
    compare(rowIds(res.record.settings), JSON.stringify(["exposure:3", "white_balance:1"]))
    var exp = Model.findSetting(res.record, "camera.exposure.exposure_time_absolute")
    compare(exp.unit, "×100 µs")
    compare(exp.enabled + ":" + exp.reason, "false:Set exposure to manual to change this")
    compare(Model.findSetting(res.record, "camera.white_balance.do_white_balance").type, "action")
    var d = Model.reduce(res.record, cliDeltaLine)
    compare(d.outcome, "settings_delta")
    compare(Model.findSetting(d.record, "camera.exposure.auto_exposure").value, "manual")
    compare(Model.findSetting(d.record, "camera.exposure.exposure_time_absolute").enabled, true)
    var act = Model.findSetting(d.record, "camera.white_balance.do_white_balance")
    compare(act.enabled + ":" + act.reason, "false:Not now")
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: "camera.exposure.exposure_time_absolute", value: 3, camera: "usb-046d_0944" }, cli, d.record)),
            JSON.stringify([cli, "settings", "set", "--camera=usb-046d_0944", "--", "camera.exposure.exposure_time_absolute", "3"]))
    compare(Model.intentArgv({ verb: "setting", id: "camera.white_balance.do_white_balance", value: true, camera: "usb-046d_0944" }, cli, d.record), null,
            "a greyed action does not run")
    var half = Model.reduce(Model.reduce(r, cliSetLines[0]).record, cliDeltaLine)
    compare(half.record.settings, null, "half a set: the delta has nothing to apply to")
  }

  // ---- global settings (the daemon's own: the effect, noise removal, ...)
  readonly property string modeId: "effect.background.mode"
  readonly property string strengthId: "effect.background.blur_strength"
  readonly property string denoiseId: "effect.video.denoise"
  function globalGroups(o) {
    var opt = merged({ effect: "none", denoise: true, denoiseOk: true }, o || {})
    var blur = opt.effect === "blur"
    return [
      { id: "background", label: "Background effect", settings: [
        enumS(modeId, "Effect", [{ value: "none", label: "Off" }, { value: "blur", label: "Blur" }, { value: "replace", label: "Replace" }],
              { scope: "global", value: opt.effect, "default": "none" }),
        intS(strengthId, "Blur strength", { scope: "global", min: 0, max: 100, value: 50, "default": 50, unit: "%", enabled: blur,
                                            disabled_reason: blur ? "" : "Choose Blur to change this",
                                            enabled_when: [{ id: modeId, op: "eq", value: "blur" }] })] },
      { id: "video", label: "Video", settings: [
        boolS(denoiseId, "Noise removal", { scope: "global", value: opt.denoiseOk ? opt.denoise : false, "default": false, enabled: opt.denoiseOk,
                                            disabled_reason: opt.denoiseOk ? "" : "Not installed" })] }
    ]
  }
  function rev8(o) { return merged({ interface_revision: 8, settings_schema: 1, settings_revision: 5 }, o || {}) }
  // The camera's groups, then the global ones, as the daemon publishes them.
  function withGlobals(o, g) {
    return feedAll(snap(rev8(o)), setLines(brioGroups().concat(globalGroups(g)))).record
  }
  // No camera: only global groups, with camera "".
  function globalsOnly(o, g) {
    return feedAll(snap(rev8(merged({ active_camera: "", cameras: [] }, o || {}))), setLines(globalGroups(g), { camera: "" })).record
  }

  function test_global_settings_routed_by_scope() {
    var r = withGlobals({ cameras: [cameraObjects()[0]] })
    compare(rowIds(r.settings), JSON.stringify(["image:5", "white_balance:2", "exposure:5", "focus:6", "background:2", "video:1"]),
            "the global groups come after the camera's")
    compare(r.settings.groups[4].scope, "global")
    compare(r.settings.groups[0].scope, "camera")
    compare(Model.findSetting(r, strengthId).scope, "global")
    var cam = Model.settingsView(r, {}, {})
    compare(JSON.stringify(cam.groups.map(function(g) { return g.id })), JSON.stringify(["image", "white_balance", "exposure", "focus"]),
            "the Camera tab draws no global group")
    compare(cam.reset, true)
    compare(cam.title, Model.SETTINGS_TITLE)
    compare(cam.truncation, "")
    // routed by scope, not by id: a global group named like a camera one stays global
    var same = feedAll(snap(rev8({})), setLines([{ id: "image", label: "Image", settings: [intS("camera.image.x", "X")] },
                                                  { id: "image", label: "Image fx", settings: [intS("effect.image.y", "Y", { scope: "global" })] }])).record
    compare(rowIds(same.settings), JSON.stringify(["image:1", "image:1"]), "one group a scope")
    compare(Model.settingsView(same, {}, {}).groups.length, 1)
    compare(Model.effectSettingsView(same, {}).groups.length, 1)
    // the default open group is a camera one
    compare(Model.openGroupId(null, r.settings), "image")
    var onlyGlobal = globalsOnly()
    compare(Model.openGroupId(null, onlyGlobal.settings), "", "no camera group: none to open")
    compare(Model.openGroupId("background", r.settings), "image", "a global group is never the open one")
  }

  function test_effect_view_skips_the_mode_and_shows_the_rest() {
    var r = withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "blur" })
    var v = Model.effectSettingsView(r, {})
    compare(v.visible, true)
    compare(v.collapsible, false)
    compare(v.reset, false)
    compare(v.title, "")
    compare(JSON.stringify(v.groups.map(function(g) { return g.id + ":" + g.expanded + ":" + g.rows.map(function(x) { return x.id }).join(",") })),
            JSON.stringify(["background:true:" + strengthId, "video:true:" + denoiseId]),
            "every global group open, the effect choice left to the dedicated row")
    compare(v.rowCount, 2)
    compare(v.truncation, "")
    compare(v.groups[0].truncation, "", "the skipped setting is not a truncation")
    var strength = Model.viewRow(v, 0)
    compare(strength.widget, "slider")
    compare(strength.enabled, true)
    compare(strength.valueText, "50 %")
    compare(Model.viewRow(v, 1).widget, "switch")
    compare(Model.effectSettingsShown(v), true)
    // a group that holds only the skipped setting is not drawn
    var lone = feedAll(snap(rev8({})), setLines([{ id: "background", label: "Background effect", settings: [globalGroups()[0].settings[0]] }],
                                                 { camera: "" })).record
    compare(Model.effectSettingsView(lone, {}).groups.length, 0)
    compare(Model.effectSettingsShown(Model.effectSettingsView(lone, {})), false)
    // a draft shows on a global row too
    var d = {}
    d[strengthId] = 80
    compare(Model.viewRow(Model.effectSettingsView(r, d), 0).valueText, "80 %")
  }

  function test_effect_fallback_without_global_settings() {
    var r = brio({ cameras: [cameraObjects()[0]], interface_revision: 7, effect: "blur", blur_strength: 0.5, denoise: true })
    var v = Model.effectSettingsView(r, {})
    compare(v.visible, false)
    compare(v.groups.length, 0)
    compare(Model.effectSettingsShown(v), false)
    compare(JSON.stringify(Model.effectRows(r, false)), JSON.stringify([{ label: "Strength", value: "50 %" }]), "the read-only strength stays")
    compare(kindsOf(Model.cursorStops(r, 1, false, "effect", Model.settingsView(r, {}, {}), v)), JSON.stringify(["switch", "tabs", "effect", "denoise"]),
            "the noise removal switch stays a stop")
    compare(Model.effectSettingsView(Model.withLink("not-running"), {}).visible, false)
    var cleared = Model.reduce(r, line({ v: 1, type: "settings_clear", rev: 9, serial: 2 })).record
    compare(Model.effectSettingsView(cleared, {}).visible, false)
  }

  function test_effect_generic_rows_in_the_effect_tab() {
    var r = withGlobals({ cameras: [cameraObjects()[0]], effect: "blur", blur_strength: 0.5, denoise: true }, { effect: "blur" })
    var v = Model.effectSettingsView(r, {})
    compare(JSON.stringify(Model.effectRows(r, true)), JSON.stringify([]), "no read-only strength beside the adjustable one")
    var cam = Model.settingsView(r, {}, {})
    compare(kindsOf(Model.cursorStops(r, 1, false, "effect", cam, v)), JSON.stringify(["switch", "tabs", "effect", "setting", "setting"]),
            "the generic rows replace the noise removal stop; no group header is a stop")
    var stops = Model.cursorStops(r, 1, false, "effect", cam, v)
    compare(Model.stopIndex(stops, "setting", 1), 4)
    compare(Model.stopIndex(stops, "denoise", -1), -1)
    compare(kindsOf(Model.cursorStops(r, 1, false, "camera", cam, v).filter(function(s) { return s.kind === "setting" })), JSON.stringify(["setting", "setting", "setting", "setting", "setting"]),
            "the Camera tab walks the camera's view only")
    var replace = withGlobals({ cameras: [cameraObjects()[0]], effect: "replace", background_image: "/tmp/a.png" }, { effect: "replace" })
    compare(Model.effectRows(replace, true).map(function(x) { return x.label }).join(","), "Image", "the image row stays")
  }

  function test_global_row_disabled_with_its_reason() {
    var r = withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "none", denoiseOk: false })
    var v = Model.effectSettingsView(r, {})
    var strength = Model.viewRow(v, 0)
    compare(strength.enabled + ":" + strength.reason, "false:Choose Blur to change this")
    var dn = Model.viewRow(v, 1)
    compare(dn.enabled + ":" + dn.reason + ":" + dn.value, "false:Not installed:false")
    compare(Model.settingDescription(dn), "Unavailable. Off. Not installed")
    // refused: a greyed row never runs
    var go = function(id, value) { return Model.intentArgv({ verb: "setting", id: id, value: value, camera: brioId }, cli, r) }
    compare(go(strengthId, 20), null)
    compare(go(denoiseId, true), null)
    // a delta enables it
    var d = Model.reduce(r, line(deltaLine([{ id: strengthId, value: 50, stored: false, enabled: true, disabled_reason: "" }]))).record
    compare(Model.viewRow(Model.effectSettingsView(d, {}), 0).enabled, true)
  }

  function test_global_settings_argv() {
    var r = withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "blur" })
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: strengthId, value: 70, camera: brioId }, cli, r)),
            JSON.stringify([cli, "settings", "set", "--", strengthId, "70"]), "no camera named for a global setting")
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: strengthId, value: 70, camera: "" }, cli, r)),
            JSON.stringify([cli, "settings", "set", "--", strengthId, "70"]), "bound to no camera")
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: denoiseId, value: false, camera: fhdId }, cli, r)),
            JSON.stringify([cli, "settings", "set", "--", denoiseId, "false"]))
    compare(Model.intentArgv({ verb: "setting", id: strengthId, value: 700, camera: brioId }, cli, r), null, "off range")
    compare(Model.intentArgv({ verb: "setting", id: denoiseId, value: "on", camera: brioId }, cli, r), null, "a bool only")
    compare(Model.intentArgv({ verb: "setting", id: strengthId, value: 1 }, "relative", r), null)
    // a camera row still needs its camera
    compare(Model.intentArgv({ verb: "setting", id: "camera.image.brightness", value: 1, camera: fhdId }, cli, r), null)
    // the camera reset names the camera and is no global reset
    compare(JSON.stringify(Model.intentArgv({ verb: "reset-settings", camera: brioId }, cli, r)), JSON.stringify([cli, "settings", "reset", "--camera=" + brioId]))
    // no camera: the global rows still write
    var none = globalsOnly({}, { effect: "blur" })
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: strengthId, value: 30, camera: "" }, cli, none)),
            JSON.stringify([cli, "settings", "set", "--", strengthId, "30"]))
    compare(Model.settingArgvGlobal(cli, "-1", "1"), null)
    compare(Model.settingArgvGlobal(cli, strengthId, "--help"), null)
    compare(Model.settingArgvGlobal("", strengthId, "1"), null)
  }

  function test_no_camera_with_global_groups_only() {
    var r = globalsOnly()
    compare(r.settings.camera, "", "a set with no camera")
    compare(rowIds(r.settings), JSON.stringify(["background:2", "video:1"]))
    var cam = Model.settingsView(r, {}, {})
    compare(cam.visible, false, "the Camera tab shows nothing: no camera, no hint")
    compare(cam.hint, "")
    compare(cam.reset, false)
    compare(cam.groups.length, 0)
    var v = Model.effectSettingsView(r, {})
    compare(v.visible, true)
    compare(v.groups.length, 2)
    compare(kindsOf(Model.cursorStops(r, 0, false, "camera", cam, v)), JSON.stringify(["switch", "tabs"]))
    // a camera group with no camera is not a v1 line
    // is refused, and the set commits without it
    var bad = feedAll(snap(rev8({})), setLines(brioGroups(), { camera: "" })).record
    compare(bad.settings.groups.length, 0)
    compare(bad.settings.camera, "")
    // a camera appears: a new set with the camera's groups first
    var withCam = feedAll(r, setLines(brioGroups().concat(globalGroups()), { rev: 6, serial: 3, camera: brioId })).record
    compare(Model.settingsView(withCam, {}, {}).visible, true)
    compare(Model.settingsView(withCam, {}, {}).groups.length, 4)
    // a set with a camera and no camera setting says the camera has none
    var camNone = feedAll(snap(rev8({ active_camera: brioId })), setLines(globalGroups(), { camera: brioId })).record
    compare(Model.settingsView(camNone, {}, {}).hint, Model.SETTINGS_EMPTY_TEXT)
    // nothing at all to show
    var cleared = Model.reduce(r, line({ v: 1, type: "settings_clear", rev: 9, serial: 3 })).record
    compare(Model.settingsView(cleared, {}, {}).visible, false)
    compare(Model.effectSettingsView(cleared, {}).visible, false)
  }

  function test_global_deltas_and_caps() {
    var r = withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "none" })
    var d = Model.reduce(r, line(deltaLine([{ id: modeId, value: "blur", stored: true, enabled: true, disabled_reason: "" },
                                             { id: strengthId, value: 55, stored: false, enabled: true, disabled_reason: "" }]))).record
    compare(Model.findSetting(d, strengthId).value, 55)
    compare(Model.findSetting(d, strengthId).scope, "global", "a delta keeps the scope")
    compare(d.settings.groups[4].scope, "global")
    compare(Model.effectSettingsView(d, {}).groups.length, 2)
    // the caps are a scope's own: sixteen camera groups leave the global ones
    var many = feedAll(snap(rev8({})), setLines(groupsOf(16, 1).concat(globalGroups()), { camera: brioId, per: 8 })).record
    compare(Model.settingsView(many, {}, {}).groups.length, 16)
    compare(Model.effectSettingsView(many, {}).groups.length, 2)
    compare(Model.settingsView(many, {}, {}).truncation, "")
  }

  // F1/F2: a group id, an option value or a change id that names a member
  // of Object.prototype is refused; nothing reaches the prototype, and the
  // rest of the set commits and draws.
  function test_settings_prototype_keys() {
    var probes = ["total", "rows", "label", "id", "shown", "value"]
    var clean = function(what) {
      for (var p = 0; p < probes.length; p++) {
        compare(({})[probes[p]], undefined, what + ": ({})." + probes[p])
        compare(Object[probes[p]], undefined, what + ": Object." + probes[p])
        verify(!Object.prototype.hasOwnProperty(probes[p]), what + ": Object.prototype." + probes[p])
      }
      var inherited = []
      for (var k in {}) inherited.push(k)
      compare(JSON.stringify(inherited), "[]", what + ": nothing enumerable on Object.prototype")
    }
    var bad = ["__proto__", "constructor", "prototype"]
    for (var b = 0; b < bad.length; b++) {
      var groups = brioGroups()
      groups.splice(1, 0, { id: bad[b], label: "X", settings: [intS("camera.x.a", "A")] })
      var res = feedAll(snap(rev7({})), setLines(groups))
      compare(res.outcome, "settings", bad[b] + " as a group id: the rest of the set commits")
      compare(rowIds(res.record.settings), JSON.stringify(["image:5", "white_balance:2", "exposure:5", "focus:6"]))
      compare(Model.findSetting(res.record, "camera.x.a"), null)
      compare(res.record.settings.groupsTotal, 5, "the refused group is counted, not drawn")
      var v = Model.settingsView(res.record, null, {})
      compare(v.truncation, "Showing 4 of 5 groups")
      compare(v.groups[0].rows.length, 5, "Image still drawn")
      clean(bad[b] + " group")
      // as an option value: that option is skipped, the row stays
      var g2 = brioGroups()
      g2[2].settings[0].options = [{ value: bad[b], label: "P" }].concat(g2[2].settings[0].options)
      var res2 = feedAll(snap(rev7({})), setLines(g2))
      compare(res2.outcome, "settings", bad[b] + " as an option value: no throw, the set commits")
      compare(JSON.stringify(Model.findSetting(res2.record, "camera.exposure.auto_exposure").options.map(function(o) { return o.value })),
              JSON.stringify(["manual", "aperture_priority"]))
      clean(bad[b] + " option")
      // as a change id, and as a draft key
      var d = Model.reduce(brio(), line(deltaLine([{ id: bad[b], value: 1 }, { id: "camera.image.brightness", value: 7 }])))
      compare(d.outcome, "settings_delta")
      compare(Model.findSetting(d.record, "camera.image.brightness").value, 7)
      compare(Model.settingId(bad[b]), "")
      compare(Model.optionValueOf(bad[b]), "")
      compare(Model.groupIdOf(bad[b]), "")
      compare(Model.ownValue({}, bad[b]), undefined, "an inherited member is no value")
      clean(bad[b] + " delta")
    }
    var parsed = JSON.parse('{"__proto__": {"total": 1}, "constructor": 2, "camera.image.a": 3}')
    var copy = Model.withSetting(parsed, "camera.image.b", 4)
    compare(JSON.stringify(Object.keys(copy).sort()), JSON.stringify(["camera.image.a", "camera.image.b"]))
    verify(Object.getPrototypeOf(copy) === Object.prototype, "the copy keeps its own prototype")
    compare(copy.total, undefined)
    compare(Model.ownValue(parsed, "camera.image.a"), 3)
    clean("drafts")
  }

  // F3: a full queue refuses the next setting write (its draft waits, see
  // Daemon.flushSettings); it never drops any other ask, and never evicts a
  // queued write.
  function test_intent_queue_cap_never_drops_an_ask() {
    var q = []
    for (var i = 0; i < Model.SETTING_QUEUE_CAP; i++) q = Model.enqueueIntent(q, { verb: "setting", id: "camera.image.s" + i, value: i })
    compare(q.length, Model.SETTING_QUEUE_CAP)
    var newWrite = { verb: "setting", id: "camera.image.new", value: 1 }
    verify(!Model.queueTakes(q, newWrite), "a ninth id waits")
    compare(JSON.stringify(Model.enqueueIntent(q, newWrite)), JSON.stringify(q), "refused: the queue as it was, nothing evicted")
    verify(Model.queueTakes(q, { verb: "setting", id: "camera.image.s3", value: 9 }), "a write for a queued id replaces it")
    compare(Model.enqueueIntent(q, { verb: "setting", id: "camera.image.s3", value: 9 }).length, Model.SETTING_QUEUE_CAP)
    var toggle = { verb: "setting", id: "camera.image.toggle", value: true, quick: true }
    verify(Model.queueTakes(q, toggle), "a quick ask is not refused by a full slider queue")
    var tq = Model.enqueueIntent(q, toggle)
    compare(tq.length, Model.SETTING_QUEUE_CAP + 1)
    compare(tq[0], toggle, "placed ahead of the sliders")
    var asks = [{ verb: "enable", on: false }, { verb: "select", id: fhdId }, { verb: "next" }, { verb: "effect", effect: "blur" },
                { verb: "denoise", on: true }]
    for (var a = 0; a < asks.length; a++) {
      verify(Model.queueTakes(q, asks[a]), asks[a].verb)
      var out = Model.enqueueIntent(q, asks[a])
      compare(out.length, Model.SETTING_QUEUE_CAP + 1, asks[a].verb + ": kept, and every write with it")
      compare(out.filter(function(x) { return x === asks[a] }).length, 1, asks[a].verb + " survives a full queue")
      if (asks[a].verb === "enable") compare(out[0], asks[a], "on/off goes first")
    }
    var reset = Model.enqueueIntent(q, { verb: "reset-settings", camera: brioId })
    compare(JSON.stringify(reset.map(function(x) { return x.verb })), JSON.stringify(["reset-settings"]), "a reset supersedes the writes")
    // the invariant over a long random run: at most one other ask, one reset
    // and SETTING_QUEUE_CAP writes, and the latest other ask always queued
    var seed = 7
    var rnd = function(n) { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n }
    var run = []
    var lastOther = null
    for (var step = 0; step < 3000; step++) {
      var k = rnd(10)
      var intent = k < 6 ? { verb: "setting", id: "camera.image.s" + rnd(12), value: step }
        : (k < 7 ? { verb: "reset-settings", camera: brioId }
          : (k < 8 ? { verb: "enable", on: rnd(2) === 1 } : (k < 9 ? { verb: "select", id: "x" + step } : { verb: "effect", effect: "none" })))
      run = Model.enqueueIntent(run, intent)
      if (!Model.isSettingIntent(intent)) lastOther = intent
      if (rnd(7) === 0) {
        if (run.length > 0 && run[0] === lastOther) lastOther = null
        run = run.slice(1)          // a command ran
      }
      var writes = run.filter(function(x) { return x.verb === "setting" }).length
      var resets = run.filter(function(x) { return x.verb === "reset-settings" }).length
      var others = run.filter(function(x) { return !Model.isSettingIntent(x) })
      verify(run.length <= Model.INTENT_QUEUE_CAP && writes <= Model.SETTING_QUEUE_CAP && resets <= 1 && others.length <= 1,
             "step " + step + ": " + run.length + "/" + writes + "/" + resets + "/" + others.length)
      if (lastOther !== null) verify(others.length === 1 && others[0] === lastOther, "step " + step + ": the latest other ask is queued")
    }
  }

  // The queue's own bound covers quick writes: slider writes, quick writes and
  // one other ask fill it, and the next enqueue (of any kind) never makes the
  // trim to INTENT_QUEUE_CAP cut a slider's latest value.
  function test_intent_queue_quick_writes_never_cost_a_slider_write() {
    var q = []
    for (var i = 0; i < Model.SETTING_QUEUE_CAP; i++) q = Model.enqueueIntent(q, { verb: "setting", id: "camera.image.s" + i, value: i })
    q = Model.enqueueIntent(q, { verb: "setting", id: "camera.image.q0", value: true, quick: true })
    q = Model.enqueueIntent(q, { verb: "setting", id: "camera.image.q1", value: true, quick: true })
    q = Model.enqueueIntent(q, { verb: "select", id: fhdId })
    compare(q.length, Model.SETTING_QUEUE_CAP + 3)
    var sliders = function(x) { return x.filter(function(e) { return e.verb === "setting" && e.quick !== true }) }
    var next = [{ verb: "setting", id: "camera.image.s2", value: 99 },
                { verb: "setting", id: "camera.image.new", value: 1 },
                { verb: "setting", id: "camera.image.q2", value: true, quick: true },
                { verb: "setting", id: "camera.image.q0", value: false, quick: true }]
    for (var n = 0; n < next.length; n++) {
      var out = Model.enqueueIntent(q, next[n])
      verify(out.length <= Model.INTENT_QUEUE_CAP, "within the cap: " + out.length)
      var kept = out.filter(function(e) { return e.id === next[n].id })
      var expectIn = Model.queueTakes(q, next[n])
      compare(kept.length, expectIn ? 1 : 0, next[n].id)
      compare(sliders(out).length, Model.SETTING_QUEUE_CAP, "no slider write dropped: " + next[n].id)
      for (var j = 0; j < Model.SETTING_QUEUE_CAP; j++) {
        var id = "camera.image.s" + j
        var w = sliders(out).filter(function(e) { return e.id === id })
        compare(w.length, 1, id)
        compare(w[0].value, id === next[n].id ? next[n].value : j, id + " latest value")
      }
    }
    verify(!Model.queueTakes(q, next[1]), "a ninth slider id waits (stays a draft)")
    verify(Model.queueTakes(q, next[2]) && Model.queueTakes(q, next[3]))
    // every bound full: the trim removes nothing, a same-id write replaces
    var full = q
    for (var k = 2; k < Model.QUICK_QUEUE_CAP; k++) full = Model.enqueueIntent(full, { verb: "setting", id: "camera.image.q" + k, value: true, quick: true })
    compare(full.length, Model.SETTING_QUEUE_CAP + Model.QUICK_QUEUE_CAP + 1)
    var fifth = { verb: "setting", id: "camera.image.q9", value: true, quick: true }
    verify(!Model.queueTakes(full, fifth), "a fifth quick write waits")
    compare(JSON.stringify(Model.enqueueIntent(full, fifth)), JSON.stringify(full), "refused: the queue as it was")
    var again = Model.enqueueIntent(full, { verb: "setting", id: "camera.image.q0", value: false, quick: true })
    compare(again.length, full.length, "a same-id write replaces")
    var withAsk = Model.enqueueIntent(full, { verb: "effect", effect: "blur" })
    verify(withAsk.length <= Model.INTENT_QUEUE_CAP, "an other ask fits: " + withAsk.length)
    compare(sliders(withAsk).length, Model.SETTING_QUEUE_CAP)
  }

  // A settings action has no draft: a full quick queue never refuses its press,
  // and nothing queued is dropped.
  function test_intent_queue_action_press_is_never_refused() {
    var q = []
    for (var i = 0; i < Model.SETTING_QUEUE_CAP; i++) q = Model.enqueueIntent(q, { verb: "setting", id: "camera.image.s" + i, value: i })
    for (var k = 0; k < Model.QUICK_QUEUE_CAP; k++) q = Model.enqueueIntent(q, { verb: "setting", id: "camera.image.q" + k, value: true, quick: true })
    q = Model.enqueueIntent(q, { verb: "select", id: fhdId })
    q = Model.enqueueIntent(q, { verb: "reset-settings", camera: "c" })
    // a reset supersedes the camera's writes: queue the writes after it
    for (var j = 0; j < Model.SETTING_QUEUE_CAP; j++) q = Model.enqueueIntent(q, { verb: "setting", id: "camera.image.s" + j, value: j })
    for (var m = 0; m < Model.QUICK_QUEUE_CAP; m++) q = Model.enqueueIntent(q, { verb: "setting", id: "camera.image.q" + m, value: true, quick: true })
    var act = { verb: "setting", id: "camera.image.reset_wb", value: true, quick: true, action: true }
    verify(!Model.queueTakes(q, { verb: "setting", id: "camera.image.q9", value: true, quick: true }), "quick queue is full")
    verify(Model.queueTakes(q, act), "the action press is accepted")
    var out = Model.enqueueIntent(q, act)
    compare(out.length, q.length + 1, "nothing dropped")
    verify(out.length <= Model.INTENT_QUEUE_CAP)
    compare(out.filter(function(e) { return e.id === act.id }).length, 1)
    var twice = Model.enqueueIntent(out, act)
    compare(twice.length, out.length, "one per row id")
    // every action row at once still fits
    var all = []
    for (var a = 0; a < Model.SETTINGS_ROW_CAP; a++) all = Model.enqueueIntent(all, { verb: "setting", id: "camera.image.a" + a, value: true, quick: true, action: true })
    compare(all.length, Model.SETTINGS_ROW_CAP)
    all = Model.enqueueIntent(all, { verb: "effect", effect: "blur" })
    all = Model.enqueueIntent(all, { verb: "reset-settings", camera: "c" })
    verify(all.length <= Model.INTENT_QUEUE_CAP)
  }

  // A write for a queued id is checked against the cap of its new kind.
  function test_intent_queue_same_id_changing_kind_respects_the_cap() {
    var q = []
    for (var k = 0; k < Model.QUICK_QUEUE_CAP; k++) q = Model.enqueueIntent(q, { verb: "setting", id: "camera.image.q" + k, value: true, quick: true })
    q = Model.enqueueIntent(q, { verb: "setting", id: "camera.image.x", value: 1 })
    var asQuick = { verb: "setting", id: "camera.image.x", value: true, quick: true }
    verify(!Model.queueTakes(q, asQuick), "slider -> quick with the quick queue full waits")
    compare(JSON.stringify(Model.enqueueIntent(q, asQuick)), JSON.stringify(q))
    verify(Model.queueTakes(q, { verb: "setting", id: "camera.image.q1", value: false, quick: true }), "same kind replaces")
  }

  // F5/F6: "Showing N of M" counts what is drawn; a setting of a known type
  // that cannot be drawn is counted as not shown, and said so.
  function test_settings_counts_match_what_is_drawn() {
    var groups = groupsOf(20, 2)
    groups[0].settings = [merged(intS("camera.g0.s0", "S"), { type: "colour" }), merged(intS("camera.g0.s1", "S"), { type: "colour" })]
    var r = feedAll(snap(rev7({})), setLines(groups, { per: 2 })).record
    var v = Model.settingsView(r, null, {})
    compare(v.groups.length, 16)
    compare(v.groups[0].id, "g1", "a group of unknown types only is not drawn")
    compare(v.truncation, "Showing 16 of 19 groups", "and not counted: N is what is drawn")
    var fixed = intS("camera.image.fixed", "Fixed", { min: 5, max: 5, value: 5, "default": 5 })
    var fine = intS("camera.image.fine", "Fine", { min: 0, max: 10000000, step: 1 })
    var g = [{ id: "image", label: "Image", settings: [intS("camera.image.a", "A"), fixed, fine] }]
    var w = Model.settingsView(feedAll(snap(rev7({})), setLines(g)).record, null, {})
    compare(w.rowCount, 1)
    compare(w.groups[0].truncation, "Showing 1 of 3 settings", "a fixed int and one of too many steps are not shown, and said so")
    var only = [{ id: "image", label: "Image", settings: [fixed] }, { id: "focus", label: "Focus", settings: [intS("camera.focus.f", "F")] }]
    var o = feedAll(snap(rev7({ cameras: [] })), setLines(only)).record
    var ov = Model.settingsView(o, null, {})
    compare(ov.groups.length, 2, "a group of skipped rows only is drawn, to say so")
    compare(ov.groups[0].truncation, "Showing 0 of 1 settings")
    compare(ov.truncation, "")
    compare(JSON.stringify(Model.cursorStops(o, 0, false, "camera", ov).map(function(s) { return s.kind + s.index })),
            JSON.stringify(["switch-1", "tabs-1", "reset-1", "group0", "group1"]), "nothing to walk in it")
  }

  // F7: a full set older than the committed one (same serial and camera)
  // never puts back what a delta moved on from.
  function test_settings_older_set_ignored() {
    var r = feedAll(snap(rev7({})), setLines(brioGroups(), { rev: 12 })).record
    r = Model.reduce(r, line(deltaLine([{ id: "camera.exposure.auto_exposure", value: "manual" }], { rev: 13 }))).record
    compare(r.settings.rev, 13)
    var old = feedAll(r, setLines(brioGroups(), { rev: 12 }))
    compare(old.outcome, "ignored")
    compare(old.record.settings.rev, 13)
    compare(Model.findSetting(old.record, "camera.exposure.auto_exposure").value, "manual")
    compare(old.record.settingsAssembly, null, "nothing of it kept")
    compare(feedAll(r, setLines(brioGroups(), { rev: 13 })).outcome, "settings", "the same rev again applies")
    compare(feedAll(r, setLines(brioGroups(), { rev: 14 })).record.settings.rev, 14)
    compare(feedAll(r, setLines(brioGroups(), { rev: 1, serial: 3 })).record.settings.rev, 1, "another serial is a new set")
    compare(feedAll(r, setLines(brioGroups(), { rev: 1, camera: fhdId })).record.settings.camera, fhdId, "another camera too")
  }

  // M4: one group open at a time; M1: a row of buttons is walked by a chip
  // cursor (the model's part; the panel's in the harness).
  function test_settings_accordion_and_choice_cursor() {
    var r = brio()
    var set = r.settings
    var opened = function(open) {
      return JSON.stringify(Model.settingsView(r, open, {}).groups.map(function(g) { return g.expanded }))
    }
    compare(opened(null), JSON.stringify([true, false, false, false]), "Image open by default")
    compare(Model.groupOpenAfter(null, set, "exposure", true), "exposure")
    compare(opened(Model.groupOpenAfter(null, set, "exposure", true)), JSON.stringify([false, false, true, false]), "opening one closes the other")
    compare(Model.groupOpenAfter("exposure", set, "exposure", false), "")
    compare(opened(""), JSON.stringify([false, false, false, false]))
    compare(Model.groupOpenAfter("exposure", set, "image", false), "exposure", "closing a closed group changes nothing")
    compare(Model.groupOpenAfter(null, set, "image", false), "", "closing the default one")
    var choices = [null, "", "image", "white_balance", "exposure", "focus", "nope", { image: true }, 3]
    for (var i = 0; i < choices.length; i++)
      verify(Model.settingsView(r, choices[i], {}).groups.filter(function(g) { return g.expanded }).length <= 1, JSON.stringify(choices[i]))
    var v = Model.settingsView(r, "exposure", {})
    var flicker = Model.viewRow(v, 4)
    compare(flicker.widget, "segmented")
    compare(flicker.selectedIndex, 2)
    compare(Model.choiceCursorStart(flicker), 2, "lands on the current choice")
    compare(Model.choiceCursorAfter(flicker, 2, 1), 3)
    compare(Model.choiceCursorAfter(flicker, 3, 1), 3, "no wrap")
    compare(Model.choiceCursorAfter(flicker, 0, -1), 0)
    compare(Model.choiceCursorAfter(flicker, -1, -1), 1, "a cursor on no chip starts from the selected one")
    compare(Model.choiceCursorAfter(null, 0, 1), -1)
    compare(Model.choiceCursorStart(merged(flicker, { selectedIndex: -1 })), 0)
    compare(Model.viewRow(v, 1).selectedIndex, -1, "not a choice")
    compare(v.setKey, JSON.stringify([brioId, 2]))
    var other = Model.settingsView(feedAll(snap(rev7({})), setLines(brioGroups(), { camera: fhdId })).record, "exposure", {})
    verify(other.setKey !== v.setKey, "another camera's rows have another key, whatever their place")
    // m7: a greyed row tells its value and why it is greyed
    compare(Model.settingDescription(Model.viewRow(v, 1)), "Unavailable. 1250 ×100 µs. Set exposure to manual to change this")
    compare(Model.settingDescription(Model.viewRow(v, 2)), "0")
    compare(Model.settingDescription({ enabled: false, valueText: "", reason: "Not now" }), "Unavailable. Not now")
    compare(Model.settingDescription(null), "")
  }

  // ---- the panel tabs and the Status tab ---------------------------------------

  function test_panel_tab_value() {
    compare(JSON.stringify(Model.PANEL_TABS), JSON.stringify(["effect", "camera", "status"]))
    compare(Model.PANEL_TAB_DEFAULT, "effect")
    compare(Model.panelTabValue("effect"), "effect")
    compare(Model.panelTabValue("camera"), "camera")
    compare(Model.panelTabValue("status"), "status")
    var bad = [undefined, null, "", "Camera", " camera", "camera ", "cameras", "live", 1, 0, true, ["camera"], { tab: "camera" },
               "<b>status</b>", "status\n", NaN]
    for (var i = 0; i < bad.length; i++) compare(Model.panelTabValue(bad[i]), "effect", JSON.stringify(bad[i]) + " " + i)
    // reading never writes
    var read = { cliPath: "/x" }
    Model.panelTabValue(read.panelTab)
    compare(JSON.stringify(read), JSON.stringify({ cliPath: "/x" }), "no default written back on read")
  }

  function test_panel_tab_options() {
    var o = Model.panelTabOptions("camera")
    compare(JSON.stringify(o.map(function(x) { return x.value })), JSON.stringify(Model.PANEL_TABS))
    compare(JSON.stringify(o.map(function(x) { return x.label })), JSON.stringify(["Effect", "Camera", "Status"]))
    compare(JSON.stringify(o.map(function(x) { return x.selected })), JSON.stringify([false, true, false]))
    verify(o.every(function(x) { return typeof x.description === "string" && x.description !== "" && !/[<>&]/.test(x.description) }))
    compare(Model.panelTabOptions("junk")[0].selected, true, "anything else reads as the default")
    compare(Model.panelTabOptions(undefined).filter(function(x) { return x.selected }).length, 1)
  }

  function test_settings_entry_panel_tab() {
    var settings = { cliPath: "/x", previewEnabled: true }
    compare(JSON.stringify(Model.settingsEntry("m", settings, { panelTab: "status" })),
            JSON.stringify({ id: "m", cliPath: "/x", previewEnabled: true, panelTab: "status" }))
    compare(JSON.stringify(Model.settingsEntry("m", { panelTab: "camera" }, { panelTab: "effect" })),
            JSON.stringify({ id: "m", panelTab: "effect" }), "replaces the stored tab")
    var bad = ["Camera", "", "live", 1, null, true, ["camera"], "camera "]
    for (var i = 0; i < bad.length; i++)
      compare(Model.settingsEntry("m", settings, { panelTab: bad[i] }), null, JSON.stringify(bad[i]))
    compare(Model.settingsEntry("m", settings, { panelTab: "camera", previewFps: 20 }), null, "one bad value refuses the write")
    verify(Model.settingsHold({ panelTab: "camera" }, { panelTab: "camera" }))
    verify(!Model.settingsHold({ panelTab: "camera" }, { panelTab: "status" }))
    // a tab is no preview preference: choosing one changes neither of them
    compare(JSON.stringify(Model.previewPrefsChosen({ enabled: true, fps: 30 }, { panelTab: "status" })),
            JSON.stringify({ enabled: true, fps: 30 }))
    compare(Model.previewUnsaved({ enabled: false, fps: 15 }, Model.previewSettings({ panelTab: "status" })), false)
  }

  function test_pipewire_and_preview_consumers_parsed() {
    var r = snap({ consumers: 3, loopback_consumers: 1, pipewire_consumers: 1, preview_consumers: 1, pipewire_output: "streaming" })
    compare(r.previewConsumers, 1)
    compare(r.pipewireOutput, "streaming")
    var old = snap({})
    compare(old.previewConsumers, -1, "absent: unknown")
    compare(old.pipewireOutput, "", "absent: not reported")
    compare(snap({ preview_consumers: -1 }).previewConsumers, -1)
    compare(snap({ preview_consumers: 0.5 }).previewConsumers, -1)
    compare(snap({ pipewire_output: 7 }).pipewireOutput, "")
    var hostile = snap({ pipewire_output: "<img src=x>‮ready & more and more and more text here" })
    verify(!/[<>&‮]/.test(hostile.pipewireOutput), hostile.pipewireOutput)
    verify(hostile.pipewireOutput.length <= Model.PIPEWIRE_CAP, hostile.pipewireOutput.length)
    var st = Model.reduce(r, line(stateObject({ pipewire_output: "ready", preview_consumers: 0 }))).record
    compare(st.pipewireOutput, "ready")
    compare(st.previewConsumers, 0)
  }

  function test_consumers_by_kind() {
    compare(Model.consumersByKind(snap({ loopback_consumers: 1, pipewire_consumers: 2, preview_consumers: 1, pipewire_output: "streaming" })),
            "Apps 1 · PipeWire 2 · Preview 1")
    compare(Model.consumersByKind(snap({ loopback_consumers: 1, pipewire_consumers: 0, pipewire_output: "ready" })),
            "Apps 1 · PipeWire 0", "no preview field: not named")
    compare(Model.consumersByKind(snap({ loopback_consumers: 1, pipewire_consumers: 0, preview_consumers: 1, pipewire_output: "off" })), "",
            "the PipeWire output off: no split (docs/cli-json.md)")
    compare(Model.consumersByKind(snap({ loopback_consumers: 1, pipewire_consumers: 0 })), "", "not reported: no split")
    compare(Model.consumersByKind(snap({ pipewire_consumers: 0, pipewire_output: "ready" })), "", "a part unknown: no split")
    compare(Model.consumersByKind(Model.emptyRecord("not-running")), "")
  }

  function test_status_rows() {
    var r = snap({ consumers: 2, loopback_consumers: 1, pipewire_consumers: 1, preview_consumers: 0,
                   pipewire_output: "streaming", interface_revision: 6 })
    compare(JSON.stringify(Model.statusRows(r)), JSON.stringify([
      { label: "State", value: "idle" },
      { label: "Camera", value: "Logitech MX Brio" },
      { label: "Consumers", value: "2" },
      { label: "Used by", value: "Apps 1 · PipeWire 1 · Preview 0" },
      { label: "Output", value: "NV12 1920x1080@30" },
      { label: "PipeWire", value: "streaming" },
      { label: "D-Bus API", value: "revision 6" }
    ]))
    var old = snap({ interface_revision: undefined, output_mode: "", consumers: -1, active_camera: "", active_camera_name: "" })
    compare(JSON.stringify(Model.statusRows(old).map(function(x) { return x.label + "=" + x.value })), JSON.stringify([
      "State=idle", "Camera=none", "Consumers=—", "Output=—", "PipeWire=—", "D-Bus API=—"]))
    compare(Model.statusRows(Model.emptyRecord("not-running")).length, 0)
    compare(Model.statusRows(snap({ state: "dancing" })).length, 0)
  }

  // ---- review round: scope-aware camera changes, no-camera sets, per-row fallback

  function test_queued_global_write_survives_a_camera_change_and_reset() {
    var g = { verb: "setting", id: strengthId, value: 70, scope: "global" }
    var c = { verb: "setting", id: "camera.image.contrast", value: 2, camera: brioId }
    var q = [c, g, { verb: "reset-settings", camera: brioId }, { verb: "next" }]
    compare(JSON.stringify(Model.dropSettingIntents(q)), JSON.stringify([g, { verb: "next" }]),
            "another camera: only the camera's writes and reset go")
    var after = Model.enqueueIntent([c, g], { verb: "reset-settings", camera: brioId })
    compare(JSON.stringify(after), JSON.stringify([g, { verb: "reset-settings", camera: brioId }]),
            "a camera reset supersedes the camera's writes, not the global one")
    var again = Model.enqueueIntent(after, { verb: "reset-settings", camera: brioId })
    compare(JSON.stringify(again), JSON.stringify(after), "a second reset replaces the first")
    // the drafts: kept by the scope of the row in either set
    var r = withGlobals({ cameras: [cameraObjects()[0]] })
    var drafts = {}
    drafts[strengthId] = 70
    drafts["camera.image.contrast"] = 3
    var kept = Model.keepGlobalSettings(drafts, [r])
    compare(JSON.stringify(Object.keys(kept)), JSON.stringify([strengthId]))
    // another camera's set (none of the camera's rows): the global draft stays through the old set
    var none = globalsOnly()
    compare(JSON.stringify(Object.keys(Model.keepGlobalSettings(drafts, [r, none]))), JSON.stringify([strengthId]))
    compare(Object.keys(Model.keepGlobalSettings(drafts, [none])).length, 1, "the new set alone holds the global row")
    compare(Object.keys(Model.keepGlobalSettings(drafts, [])).length, 0)
    compare(Object.keys(Model.keepGlobalSettings(null, [r])).length, 0)
  }

  function test_no_camera_set_commits_without_a_bad_line() {
    var lines = setLines(globalGroups(), { camera: "" })
    // the first line of the set is a refused group id; the next, a camera group
    var clone = function(o) { return JSON.parse(JSON.stringify(o)) }
    var bogus = merged(clone(lines[0]), { group: { id: "Bad Id!", label: "x", settings: [] } })
    var camGroup = merged(clone(lines[1]), { group: { id: "cam", label: "Cam", settings: [intS("camera.cam.x", "X")] } })
    var all = [bogus, camGroup].concat(lines)
    for (var i = 0; i < all.length; i++) { all[i] = merged(all[i], { index: i, count: all.length }) }
    var r = feedAll(snap(rev8({})), all).record
    verify(r.settings !== null, "the set committed")
    compare(r.settings.camera, "")
    compare(r.settings.groups.every(function(x) { return x.scope === "global" }), true)
    verify(Model.findSetting(r, strengthId) !== null || Model.findSetting(r, denoiseId) !== null, "the global rows are there")
    verify(Model.findSetting(r, "camera.cam.x") === null, "the camera group is left out")
  }

  function test_camera_must_be_a_string() {
    var good = setLines(globalGroups(), { camera: "" })
    for (var i = 0; i < good.length; i++) {
      var broken = [null, 5, true, {}, [], "x".repeat(Model.ID_CAP * 2 + 1)]
      for (var b = 0; b < broken.length; b++)
        compare(Model.reduce(snap(rev8({})), line(merged(good[i], { camera: broken[b] }))).record.settings, null, "camera " + JSON.stringify(broken[b]).slice(0, 12))
    }
    var r = globalsOnly()
    var d = deltaLine([], { camera: "" })
    compare(Model.settingsDelta(r.settings, d) !== null, true, "the literal empty string is the no-camera set")
    d.camera = 0
    compare(Model.settingsDelta(r.settings, d), null, "a number is not the empty camera")
    delete d.camera
    compare(Model.settingsDelta(r.settings, d), null, "an absent camera is not the empty camera")
  }

  function test_legacy_rows_fall_back_per_row() {
    var base = { cameras: [cameraObjects()[0]], effect: "blur", blur_strength: 0.5, denoise: true }
    // only the video group is published: the strength stays read-only, the switch goes
    var onlyVideo = feedAll(snap(rev8(base)), setLines(brioGroups().concat([globalGroups({ effect: "blur" })[1]]))).record
    var v1 = Model.effectSettingsView(onlyVideo, {})
    compare(Model.effectSettingShown(v1, strengthId), false)
    compare(Model.effectSettingShown(v1, denoiseId), true)
    compare(JSON.stringify(Model.effectRows(onlyVideo, Model.effectSettingShown(v1, strengthId))), JSON.stringify([{ label: "Strength", value: "50 %" }]))
    compare(kindsOf(Model.cursorStops(onlyVideo, 1, false, "effect", Model.settingsView(onlyVideo, {}, {}), v1)),
            JSON.stringify(["switch", "tabs", "effect", "setting"]), "no legacy switch stop: the setting row holds it")
    // only the background group: the strength is generic, the legacy switch stays
    var onlyBg = feedAll(snap(rev8(base)), setLines(brioGroups().concat([globalGroups({ effect: "blur" })[0]]))).record
    var v2 = Model.effectSettingsView(onlyBg, {})
    compare(Model.effectSettingShown(v2, strengthId), true)
    compare(Model.effectSettingShown(v2, denoiseId), false)
    compare(Model.effectRows(onlyBg, true).length, 0)
    compare(kindsOf(Model.cursorStops(onlyBg, 1, false, "effect", Model.settingsView(onlyBg, {}, {}), v2)),
            JSON.stringify(["switch", "tabs", "effect", "denoise", "setting"]), "the legacy switch stands, above the rows")
    compare(Model.effectSettingShown(null, strengthId), false)
  }
}
