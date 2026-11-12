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
    compare(Model.middleClickAction(r, false), "open-panel")
    compare(Model.clickAction("right", r, false), "setup", "the setup dialog opens whatever the state")
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

  function test_warning_parsing_visual_and_tooltip() {
    compare(snap({ warning: "effect blur unavailable: no module" }).warning, "effect blur unavailable: no module")
    compare(snap({}).warning, "", "absent (an older daemon)")
    compare(snap({ warning: 42 }).warning, "", "not a string")
    compare(snap({ warning: null }).warning, "")
    compare(snap({ warning: "a <b>w</b>&\nx" }).warning, "a bw/b x", "sanitised")
    compare(Model.emptyRecord("connecting").warning, "")
    var w = snap({ state: "active", consumers: 1, warning: "effect blur unavailable" })
    compare(Model.visualKey(w), "active", "a warning never makes the error visual")
    compare(Model.visualFor(Model.visualKey(w)).colorRole, "accent")
    compare(Model.visualKey(snap({ warning: "w" })), "idle")
    compare(Model.tooltipText(w), "Omarchy Broadcast: active \u00b7 Logitech MX Brio \u00b7 1 consumer \u00b7 warning: effect blur unavailable")
    var both = Model.tooltipText(snap({ state: "idle", error: "e1", warning: "w1" }))
    verify(both.indexOf("error: e1") !== -1 && both.indexOf("warning: w1") > both.indexOf("error: e1"), both)
    verify(Model.tooltipText(snap({ state: "idle", warning: "w1" })).indexOf("error") === -1)
    verify(Model.tooltipText(snap({ state: "idle", warning: new Array(200).join("w") })).length <= Model.TOOLTIP_CAP)
  }

  function test_status_reason_text() {
    compare(Model.statusReasonText("Disabled", "Disabled"), "Disabled")
    compare(Model.statusReasonText("Disabled", "disabled"), "Disabled")
    compare(Model.statusReasonText("Disabled", ""), "Disabled")
    compare(Model.statusReasonText("Disabled", "Disabled after crashing the daemon twice in a row"),
            "Disabled: Disabled after crashing the daemon twice in a row")
    compare(Model.statusReasonText("Unavailable", "Maxine SDK not found"), "Unavailable: Maxine SDK not found")
    var off = Model.modulesSectionView(Model.withSetupRead(fullSetup(), "modules", Model.readModules(moduleLines([
      moduleObj("org.example.hello", { status: "disabled", enabled: false, reason: "Disabled" })]))), setupRecord(10))
    compare(off.rows[0].statusLine, "Disabled", "no Disabled: Disabled")
    var d = Model.diagnosticsView(Model.withSetupRead(fullSetup(), "modules", Model.readModules(moduleLines([
      moduleObj("org.example.hello", { name: "Hello", status: "disabled", enabled: false, reason: "Disabled" })]))), setupRecord(10))
    compare(d.problems[0].reason, "Disabled")
  }

  function test_off_tooltip_includes_error() {
    compare(Model.tooltipText(snap({ state: "off", enabled: false, error: "config <b>rejected</b>" })),
            "Omarchy Broadcast: off \u00b7 error: config brejected/b")
    compare(Model.tooltipText(snap({ state: "off", enabled: false })), "Omarchy Broadcast: off")
  }

  function test_error_and_off_tooltips_include_warning() {
    compare(Model.tooltipText(snap({ state: "error", error: "loopback missing", warning: "w <b>1</b>" })),
            "Omarchy Broadcast: error \u00b7 loopback missing \u00b7 warning: w b1/b")
    compare(Model.tooltipText(snap({ state: "error", warning: "w1" })), "Omarchy Broadcast: error \u00b7 warning: w1")
    compare(Model.tooltipText(snap({ state: "off", enabled: false, error: "e1", warning: "w1" })),
            "Omarchy Broadcast: off \u00b7 error: e1 \u00b7 warning: w1")
    compare(Model.tooltipText(snap({ state: "off", enabled: false, warning: "w1" })), "Omarchy Broadcast: off \u00b7 warning: w1")
  }

  function test_glyph_warning_is_alert_outline() {
    compare(Model.GLYPH_WARNING.codePointAt(0), 0xF002A)
  }

  function test_diagnostics_view_shows_warning_row() {
    var d = Model.diagnosticsView(fullSetup(), snap(rev10({ error: "e1", warning: "effect blur unavailable" })))
    compare(JSON.stringify(d.rows), JSON.stringify([{ label: "D-Bus API", value: "revision 10" },
      { label: "Daemon warning", value: "effect blur unavailable" }, { label: "Daemon error", value: "e1" }]))
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

  function test_middle_click_while_busy() {
    compare(Model.middleClickAction(snap(), false), "toggle")
    compare(Model.middleClickAction(snap(), true), "ignore")
    compare(Model.middleClickAction(Model.emptyRecord("not-running"), true), "open-panel")
    compare(Model.middleClickAction(Model.emptyRecord("not-running"), false), "open-panel")
    compare(Model.middleClickAction(snap(), "true"), "toggle", "busy only for a real true")
    verify(Model.leftClickAction === undefined, "the old name is gone")
    verify(Model.rightClickAction === undefined, "the right click is the setup dialog's now")
  }

  function test_click_actions_by_button() {
    compare(Model.clickAction("left", snap(), false), "panel")
    compare(Model.clickAction("left", snap(), true), "panel", "the panel opens while a command runs")
    compare(Model.clickAction("left", Model.emptyRecord("not-running"), false), "panel")
    compare(Model.clickAction("middle", snap(), false), "toggle")
    compare(Model.clickAction("middle", snap(), true), "ignore")
    compare(Model.clickAction("middle", Model.emptyRecord("not-running"), false), "open-panel")
    compare(Model.clickAction("right", snap(), false), "setup")
    compare(Model.clickAction("right", snap(), true), "setup")
    compare(Model.clickAction("right", Model.emptyRecord("cli-missing"), false), "setup")
    compare(Model.clickAction("back", snap(), false), "panel", "any other button: the panel")
    compare(Model.clickAction(undefined, snap(), false), "panel")
  }

  function test_bar_click_help() {
    compare(Model.barClickHelp(snap()), "Click: open the panel. Middle click: turn the camera off. Right click: open the setup.")
    compare(Model.barClickHelp(snap({ state: "off", enabled: false })),
            "Click: open the panel. Middle click: turn the camera on. Right click: open the setup.")
    compare(Model.barClickHelp(Model.emptyRecord("not-running")), "Click or middle click: open the panel. Right click: open the setup.")
    compare(Model.barClickHelp(snap({ state: "dancing" })), "Click or middle click: open the panel. Right click: open the setup.")
    compare(Model.barClickHelp(null), "Click or middle click: open the panel. Right click: open the setup.")
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
    compare(kindsOf(Model.cursorStops(one, 1, false, "effect")), JSON.stringify(["switch", "tabs"]), "a daemon below revision 9: no effect row")
    compare(kindsOf(Model.cursorStops(one, 1, false, "status")), JSON.stringify(["switch", "tabs"]), "the Status tab has no control")
    compare(kindsOf(Model.cursorStops(one, 1, false)), kindsOf(Model.cursorStops(one, 1, false, "effect")), "no tab: the default")
    compare(kindsOf(Model.cursorStops(one, 1, false, "bogus")), kindsOf(Model.cursorStops(one, 1, false, "effect")), "unknown tab: the default")
    compare(kindsOf(Model.cursorStops(one, 1, false, "Camera")), kindsOf(Model.cursorStops(one, 1, false, "effect")), "exact words only")
    compare(Model.cursorStops(Model.emptyRecord("not-running"), 3, true, "camera").length, 0)
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
    compare(Model.middleClickAction(snap()), "toggle")
    compare(Model.middleClickAction(Model.emptyRecord("not-running")), "open-panel")
    compare(Model.middleClickAction(Model.emptyRecord("cli-missing")), "open-panel")
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

  // ---- the background effect (from the settings schema, interface revision 9)

  function test_no_effect_vocabulary_left() {
    verify(Model.EFFECTS === undefined, "no list of effect names")
    verify(Model.effectArgv === undefined && Model.denoiseArgv === undefined, "no `effect` or `denoise` command")
    verify(Model.effectOptions === undefined && Model.denoiseRow === undefined && Model.effectHint === undefined)
    verify(Model.LEGACY_STRENGTH_SETTING === undefined && Model.LEGACY_DENOISE_SETTING === undefined)
    var r = withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "blur" })
    compare(Model.intentArgv({ verb: "effect", effect: "blur" }, cli, r), null, "the old verbs run nothing")
    compare(Model.intentArgv({ verb: "denoise", on: true }, cli, r), null)
    var old = snap({ effect: "blur", blur_strength: 0.5, denoise: true })
    verify(old.effectKey === undefined && old.blurStrength === undefined && old.denoise === undefined && old.cliEffects === undefined,
           "the snapshot's legacy effect fields are not read")
    compare(old.effect, "blur", "the effect word stays a display copy")
  }

  function test_effect_mode_from_the_schema() {
    var r = withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "blur" })
    var v = Model.effectModeView(r, {})
    compare(v.visible, true)
    compare(v.hint, "")
    compare(v.id, modeId)
    compare(v.enabled, true)
    compare(JSON.stringify(v.options.map(function(o) { return o.value + ":" + o.label + ":" + o.selected })),
            JSON.stringify(["none:Off:false", "blur:Blur:true", "replace:Replace:false"]), "the daemon's options and labels, in its order")
    compare(v.options.filter(function(o) { return o.faded }).length, 0)
    compare(Model.effectModeSelected(v), 1)
    verify(Model.effectModeShown(r))
    // the user's unconfirmed choice is shown
    var d = {}
    d[modeId] = "replace"
    compare(Model.effectModeSelected(Model.effectModeView(r, d)), 2)
    d[modeId] = "sepia"
    compare(Model.effectModeSelected(Model.effectModeView(r, d)), 1, "a draft that is no option is not shown")
    // labels come sanitised from the schema
    var hostile = withGlobals({}, { effect: "none" })
    var g = globalGroups()
    g[0].settings[0].options = [{ value: "none", label: "<b>Off</b>" }, { value: "blur", label: "Blur & more" }]
    hostile = feedAll(snap(rev9({})), setLines(brioGroups().concat(g))).record
    compare(JSON.stringify(Model.effectModeView(hostile, {}).options.map(function(o) { return o.label })), JSON.stringify(["bOff/b", "Blur & more"]))
    // greyed by the daemon: every choice faded, its reason shown, nothing selectable
    var off = withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "none" })
    var row = Model.findSetting(off, modeId)
    var greyed = Model.reduce(off, line(deltaLine([{ id: modeId, value: "none", stored: false, enabled: false,
                                                     disabled_reason: "Loading the effect module" }]))).record
    var gv = Model.effectModeView(greyed, {})
    compare(gv.visible, true)
    compare(gv.enabled, false)
    compare(gv.reason, "Loading the effect module")
    compare(gv.options.filter(function(o) { return o.faded }).length, 3)
    compare(gv.options[1].tooltip, "Loading the effect module")
    compare(Model.intentArgv({ verb: "setting", id: modeId, value: "blur", camera: "" }, cli, greyed), null, "a greyed row never runs")
    verify(row.enabled)
  }

  function test_effect_mode_hints() {
    // below revision 9: the daemon needs updating, whatever the snapshot carries
    var old = feedAll(snap(merged(rev9({ cameras: [cameraObjects()[0]] }), { interface_revision: 8 })), setLines(brioGroups().concat(globalGroups()))).record
    var v = Model.effectModeView(old, {})
    compare(v.visible, false)
    compare(v.hint, Model.DAEMON_NO_EFFECTS)
    compare(Model.effectSettingsView(old, {}).visible, false, "no generic rows either")
    compare(Model.effectModeView(snap({ effect: "blur" }), {}).hint, Model.DAEMON_NO_EFFECTS, "revision 4")
    compare(Model.effectModeView(snap({ interface_revision: undefined }), {}).hint, Model.DAEMON_NO_EFFECTS, "unknown revision")
    // a CLI that predates the settings, a plugin that predates the schema
    compare(Model.effectModeView(snap({ interface_revision: 9 }), {}).hint, Model.CLI_NO_SETTINGS)
    compare(Model.effectModeView(snap(rev9({ settings_schema: 2 })), {}).hint, Model.PLUGIN_OLD_SETTINGS)
    // loading: nothing yet, and no hint
    var loading = snap(rev9({}))
    compare(Model.effectModeView(loading, {}).visible, false)
    compare(Model.effectModeView(loading, {}).hint, "")
    // no module offers the background effect: only the video group is published
    var noBg = feedAll(snap(rev9({ cameras: [cameraObjects()[0]] })), setLines(brioGroups().concat([globalGroups()[1]]))).record
    compare(Model.effectModeView(noBg, {}).visible, false)
    compare(Model.effectModeView(noBg, {}).hint, Model.NO_BACKGROUND_TEXT)
    compare(Model.effectSettingsView(noBg, {}).visible, true, "the other global settings still draw")
    // a mode row of the camera's scope is not the effect
    var g = globalGroups()
    g[0].settings[0].scope = "camera"
    var wrong = feedAll(snap(rev9({})), setLines(brioGroups().concat(g))).record
    compare(Model.effectModeView(wrong, {}).hint, Model.NO_BACKGROUND_TEXT)
    // unavailable: nothing at all
    compare(Model.effectModeView(Model.emptyRecord("not-running"), {}).hint, "")
    compare(Model.effectModeView(null, {}).visible, false)
  }

  function test_effect_choice_is_a_setting_write() {
    var r = withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "none" })
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: modeId, value: "replace", camera: "" }, cli, r)),
            JSON.stringify([cli, "settings", "set", "--", modeId, "replace"]))
    compare(Model.intentArgv({ verb: "setting", id: modeId, value: "sepia", camera: "" }, cli, r), null, "only one of the row's options")
    compare(Model.intentArgv({ verb: "setting", id: modeId, value: "blur; rm", camera: "" }, cli, r), null)
    compare(Model.rowValue(Model.findSetting(r, modeId), "blur"), "blur")
  }

  function test_effect_in_tooltip() {
    var base = "Omarchy Broadcast: idle \u00b7 Logitech MX Brio \u00b7 0 consumers"
    compare(Model.tooltipText(withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "blur" })), base + " \u00b7 background: Blur")
    compare(Model.tooltipText(withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "replace" })), base + " \u00b7 background: Replace")
    compare(Model.tooltipText(withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "none" })), base, "the default says nothing")
    compare(Model.tooltipText(snap({ effect: "blur" })), base, "a daemon below revision 9: no schema, no phrase")
    compare(Model.effectSummary(null), "")
    compare(Model.tooltipText(merged(withGlobals({ cameras: [cameraObjects()[0]] }, { effect: "blur" }), {})).indexOf("Blur") > 0, true)
  }

  function test_background_image_row() {
    var r = snap(rev9({ background_image: image }))
    compare(JSON.stringify(Model.effectRows(r)), JSON.stringify([{ label: "Background image", value: "\u2066" + image + "\u2069" }]),
            "inside a left-to-right isolate")
    compare(Model.effectRows(snap(rev9({ background_image: "" }))).length, 0)
    compare(Model.effectRows(snap({ background_image: image })).length, 0, "below revision 9: no Effect tab rows")
    var heb = "/\u05d0\u05d1\u05d2/c.png"
    compare(Model.effectRows(snap(rev9({ background_image: heb })))[0].value, "\u2066" + heb + "\u2069", "LRI, not first-strong")
    var hostile = snap(rev9({ background_image: "/tmp/<img src='http://x/y'>&\n\u202epic.png" }))
    verify(!/[<>&\n\u202e]/.test(hostile.backgroundImage), hostile.backgroundImage)
    verify(hostile.backgroundImage.indexOf("/tmp/") === 0, hostile.backgroundImage)
    var long = "/"
    for (var i = 0; i < 5000; i++) long += "d"
    var capped = snap(rev9({ background_image: long }))
    compare(capped.backgroundImage.length, Model.IMAGE_PATH_CAP)
    compare(capped.backgroundImage.charAt(capped.backgroundImage.length - 1), "\u2026", "ellipsised")
    var odd = [42, null, true, ["/a"], { p: "/a" }]
    for (var o = 0; o < odd.length; o++)
      compare(snap(rev9({ background_image: odd[o] })).backgroundImage, "", JSON.stringify(odd[o]))
    // the raw field decides: a path that sanitises to nothing is still held
    var blank = snap(rev9({ background_image: "<>&" }))
    verify(Model.hasBackgroundImage(blank))
    compare(Model.effectRows(blank)[0].value, Model.UNKNOWN)
  }

  function test_effect_tab_stops() {
    var one = [cameraObjects()[0]]
    var r = withGlobals({ cameras: one }, { effect: "blur" })
    var cam = Model.settingsView(r, {}, {})
    var fx = Model.effectSettingsView(r, {})
    compare(kindsOf(Model.cursorStops(r, 1, false, "effect", cam, fx)), JSON.stringify(["switch", "tabs", "effect", "setting", "setting"]))
    var noBg = feedAll(snap(rev9({ cameras: one })), setLines(brioGroups().concat([globalGroups()[1]]))).record
    compare(kindsOf(Model.cursorStops(noBg, 1, false, "effect", Model.settingsView(noBg, {}, {}), Model.effectSettingsView(noBg, {}))),
            JSON.stringify(["switch", "tabs", "setting"]), "no effect row without a background effect")
    compare(kindsOf(Model.cursorStops(snap({ cameras: one, denoise: true }), 1, false, "effect")), JSON.stringify(["switch", "tabs"]),
            "below revision 9: no effect stops, no noise removal switch")
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
    compare(kindsOf(Model.cursorStops(r5, 2, true, "effect")), JSON.stringify(["switch", "preview", "fps", "tabs"]))
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
      for (var p = 0; p < parts; p++) {
        var group = { id: groups[g].id, label: groups[g].label, settings: groups[g].settings.slice(p * opt.per, (p + 1) * opt.per) }
        if (groups[g].surface !== undefined) group.surface = groups[g].surface
        raw.push({ v: 1, type: "settings_group", schema: 1, rev: opt.rev, serial: opt.serial, camera: opt.camera, part: p + 1, parts: parts,
                   group: group })
      }
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
    q = Model.enqueueIntent(q, { verb: "setting", id: "effect.video.denoise", value: true, quick: true })
    compare(order(q), JSON.stringify(["setting:camera.image.autofocus=true", "setting:effect.video.denoise=true", "setting:camera.image.brightness=1",
                                      "setting:camera.image.contrast=2"]), "a later quick ask goes after the earlier one, before the sliders")
    // the slider's coalesced latest value stays queued, after the quick ones
    q = Model.enqueueIntent(q, slider("camera.image.brightness", 9))
    compare(order(q), JSON.stringify(["setting:camera.image.autofocus=true", "setting:effect.video.denoise=true", "setting:camera.image.contrast=2",
                                      "setting:camera.image.brightness=9"]))
    // an other ask goes last, behind the sliders
    var e = Model.enqueueIntent([slider("camera.image.brightness", 1)], { verb: "next" })
    compare(order(e), JSON.stringify(["setting:camera.image.brightness=1", "next"]))
    // the same id keeps one write: a quick write replaces a queued one of its id
    var same = Model.enqueueIntent([slider("camera.image.contrast", 2), slider("camera.image.mode", "a")],
                                   { verb: "setting", id: "camera.image.mode", value: "b", quick: true })
    compare(order(same), JSON.stringify(["setting:camera.image.mode=b", "setting:camera.image.contrast=2"]))
    // never ahead of a reset queued before it
    var r = Model.enqueueIntent([{ verb: "reset-settings" }, slider("camera.image.contrast", 2)],
                                { verb: "setting", id: "camera.image.autofocus", value: false, quick: true })
    compare(order(r), JSON.stringify(["reset-settings", "setting:camera.image.autofocus=false", "setting:camera.image.contrast=2"]))
    // a quick ask with no slider queued goes last, as before
    var l = Model.enqueueIntent([{ verb: "next" }], { verb: "select", id: fhdId })
    compare(order(l), JSON.stringify(["select"]), "the latest other ask wins")
    verify(!Model.isQuickIntent({ verb: "effect", effect: "off" }), "the old effect verb is no quick ask")
    verify(Model.isQuickIntent({ verb: "setting", id: "effect.video.denoise", value: true, quick: true }))
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
    compare(kindsOf(Model.cursorStops(r, 1, false, "effect", v)), JSON.stringify(["switch", "tabs"]),
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
  // Interface revision 9: the effects come from modules and are drawn only from the schema.
  function rev9(o) { return merged({ interface_revision: 9, settings_schema: 1, settings_revision: 5 }, o || {}) }
  // The camera's groups, then the global ones, as the daemon publishes them.
  function withGlobals(o, g) {
    return feedAll(snap(rev9(o)), setLines(brioGroups().concat(globalGroups(g)))).record
  }
  // No camera: only global groups, with camera "".
  function globalsOnly(o, g) {
    return feedAll(snap(rev9(merged({ active_camera: "", cameras: [] }, o || {}))), setLines(globalGroups(g), { camera: "" })).record
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
    var same = feedAll(snap(rev9({})), setLines([{ id: "image", label: "Image", settings: [intS("camera.image.x", "X")] },
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
    var lone = feedAll(snap(rev9({})), setLines([{ id: "background", label: "Background effect", settings: [globalGroups()[0].settings[0]] }],
                                                 { camera: "" })).record
    compare(Model.effectSettingsView(lone, {}).groups.length, 0)
    compare(Model.effectSettingsShown(Model.effectSettingsView(lone, {})), false)
    // a draft shows on a global row too
    var d = {}
    d[strengthId] = 80
    compare(Model.viewRow(Model.effectSettingsView(r, d), 0).valueText, "80 %")
  }

  function test_effect_rows_need_revision_9() {
    // a revision-7 daemon with the camera's settings only: no effect rows, no stops
    var r = brio({ cameras: [cameraObjects()[0]], interface_revision: 7, effect: "blur", blur_strength: 0.5, denoise: true })
    var v = Model.effectSettingsView(r, {})
    compare(v.visible, false)
    compare(v.groups.length, 0)
    compare(Model.effectSettingsShown(v), false)
    compare(Model.effectRows(r).length, 0)
    compare(Model.effectModeView(r, {}).hint, Model.DAEMON_NO_EFFECTS)
    compare(kindsOf(Model.cursorStops(r, 1, false, "effect", Model.settingsView(r, {}, {}), v)), JSON.stringify(["switch", "tabs"]))
    compare(Model.effectSettingsView(Model.withLink("not-running"), {}).visible, false)
    var cleared = Model.reduce(r, line({ v: 1, type: "settings_clear", rev: 9, serial: 2 })).record
    compare(Model.effectSettingsView(cleared, {}).visible, false)
  }

  function test_effect_generic_rows_in_the_effect_tab() {
    var r = withGlobals({ cameras: [cameraObjects()[0]], effect: "blur", blur_strength: 0.5, denoise: true }, { effect: "blur" })
    var v = Model.effectSettingsView(r, {})
    compare(JSON.stringify(Model.effectRows(r)), JSON.stringify([]), "no read-only strength beside the adjustable one")
    var cam = Model.settingsView(r, {}, {})
    compare(kindsOf(Model.cursorStops(r, 1, false, "effect", cam, v)), JSON.stringify(["switch", "tabs", "effect", "setting", "setting"]),
            "the choice row, then the generic rows; no group header is a stop")
    var stops = Model.cursorStops(r, 1, false, "effect", cam, v)
    compare(Model.stopIndex(stops, "setting", 1), 4)
    compare(Model.stopIndex(stops, "denoise", -1), -1)
    compare(kindsOf(Model.cursorStops(r, 1, false, "camera", cam, v).filter(function(s) { return s.kind === "setting" })), JSON.stringify(["setting", "setting", "setting", "setting", "setting"]),
            "the Camera tab walks the camera's view only")
    var replace = withGlobals({ cameras: [cameraObjects()[0]], effect: "replace", background_image: "/tmp/a.png" }, { effect: "replace" })
    compare(Model.effectRows(replace).map(function(x) { return x.label }).join(","), "Background image", "the image row stays")
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
    var bad = feedAll(snap(rev9({})), setLines(brioGroups(), { camera: "" })).record
    compare(bad.settings.groups.length, 0)
    compare(bad.settings.camera, "")
    // a camera appears: a new set with the camera's groups first
    var withCam = feedAll(r, setLines(brioGroups().concat(globalGroups()), { rev: 6, serial: 3, camera: brioId })).record
    compare(Model.settingsView(withCam, {}, {}).visible, true)
    compare(Model.settingsView(withCam, {}, {}).groups.length, 4)
    // a set with a camera and no camera setting says the camera has none
    var camNone = feedAll(snap(rev9({ active_camera: brioId })), setLines(globalGroups(), { camera: brioId })).record
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
    var many = feedAll(snap(rev9({})), setLines(groupsOf(16, 1).concat(globalGroups()), { camera: brioId, per: 8 })).record
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
    compare(JSON.stringify(Model.PANEL_TABS), JSON.stringify(["effect", "camera", "mic", "status"]))
    compare(Model.PANEL_TAB_DEFAULT, "effect")
    compare(Model.panelTabValue("effect"), "effect")
    compare(Model.panelTabValue("camera"), "camera")
    compare(Model.panelTabValue("mic"), "mic")
    compare(Model.panelTabValue("status"), "status")
    var bad = [undefined, null, "", "Camera", " camera", "camera ", "cameras", "live", "Mic", "microphone", 1, 0, true, ["camera"], { tab: "camera" },
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
    compare(JSON.stringify(o.map(function(x) { return x.label })), JSON.stringify(["Effect", "Camera", "Mic", "Status"]))
    compare(JSON.stringify(o.map(function(x) { return x.selected })), JSON.stringify([false, true, false, false]))
    compare(Model.panelTabOptions("mic")[2].selected, true)
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
    var r = feedAll(snap(rev9({})), all).record
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
        compare(Model.reduce(snap(rev9({})), line(merged(good[i], { camera: broken[b] }))).record.settings, null, "camera " + JSON.stringify(broken[b]).slice(0, 12))
    }
    var r = globalsOnly()
    var d = deltaLine([], { camera: "" })
    compare(Model.settingsDelta(r.settings, d) !== null, true, "the literal empty string is the no-camera set")
    d.camera = 0
    compare(Model.settingsDelta(r.settings, d), null, "a number is not the empty camera")
    delete d.camera
    compare(Model.settingsDelta(r.settings, d), null, "an absent camera is not the empty camera")
  }

  // ---- the setup dialog (interface revisions 9 and 10) ---------------------------

  function rev10(o) { return merged({ interface_revision: 10, settings_schema: 1, settings_revision: 5, config_serial: 3, modules_serial: 2 }, o || {}) }
  function setupRecord(revision) { return snap(rev10({ interface_revision: revision === undefined ? 10 : revision })) }
  function lines(objs) { return objs.map(function(o) { return typeof o === "string" ? o : JSON.stringify(o) }) }
  function moduleObj(id, o) {
    return merged({ id: id, name: "Module " + id, version: "1.0.0", licence: "MIT", description: "", kind: "video-stage",
                    library: "/usr/lib/x.so", manifest: "/usr/lib/x.toml", enabled: true, status: "available", reason: "",
                    stages: [{ id: "background", slot: "matte", rank: 300, device: "nvidia-gpu", available: true, reason: "", selected: true }],
                    stages_truncated: false, overridden_by: "" }, o || {})
  }
  function moduleLines(mods, o) {
    var opt = merged({ serial: 2, profile: "quality", profile_overridden_by: "" }, o || {})
    var out = [{ v: 1, type: "modules", serial: opt.serial, profile: opt.profile, count: mods.length, profile_overridden_by: opt.profile_overridden_by }]
    for (var i = 0; i < mods.length; i++) out.push({ v: 1, type: "module", serial: opt.serial, index: i, count: mods.length, module: mods[i] })
    return lines(out)
  }
  function orderLines(ids, o) {
    var opt = merged({ overridden_by: "", order_truncated: false }, o || {})
    var stages = []
    for (var i = 0; i < ids.length; i++) stages.push({ id: ids[i], slot: "pre-matte", up: i > 0, down: i < ids.length - 1 })
    if (opt.stages !== undefined) stages = opt.stages
    return lines([{ v: 1, type: "order", order: ids, order_truncated: opt.order_truncated, stages: stages, overridden_by: opt.overridden_by }])
  }
  function cfgRow(id, type, o) {
    return merged({ id: id, label: id, description: "", type: type, editable: true, source: "", overridden_by: "", apply: "live",
                    enabled: true, disabled_reason: "" }, o || {})
  }
  function cfgGroups() {
    return [
      { id: "output", label: "Output", settings: [
        cfgRow("output.format", "enum", { label: "Format", value: "nv12", "default": "nv12", apply: "reload",
               options: [{ value: "nv12", label: "NV12" }, { value: "yuyv", label: "YUYV" }] }),
        cfgRow("output.hold_timeout_s", "float", { label: "Hold timeout", value: 2.5, "default": 2.5, min: 0, max: 10, step: 0.5, unit: "s", apply: "reload" }),
        cfgRow("output.mode", "string", { label: "Mode", value: "1920x1080@30", editable: false, description: "The output's size and rate" })] },
      { id: "lifecycle", label: "Lifecycle", settings: [
        cfgRow("lifecycle.idle_grace_s", "int", { label: "Idle grace", value: 5, "default": 5, min: 0, max: 60, step: 1, unit: "s" }),
        cfgRow("lifecycle.start_debounce_ms", "int", { label: "Start debounce", value: 200, "default": 200, min: 0, max: 5000, step: 10,
               source: "config.d/90-local.toml", overridden_by: "config.d/90-local.toml", enabled: false,
               disabled_reason: "Overridden by config.d/90-local.toml" })] },
      { id: "pipewire", label: "PipeWire", settings: [
        cfgRow("pipewire.enabled", "bool", { label: "PipeWire output", value: false, "default": false, apply: "reload", source: "config.d/50-panel.toml" })] },
      { id: "effect", label: "Effect", settings: [
        cfgRow("effect.maxine_root", "path", { label: "Maxine root", value: "/opt/maxine", editable: false, apply: "restart" })] },
      { id: "modules", label: "Modules", settings: [
        cfgRow("modules.profile", "enum", { label: "Backend profile", value: "quality", "default": "quality", apply: "reload",
               options: [{ value: "quality", label: "Quality" }, { value: "battery", label: "Battery" }] }),
        cfgRow("modules.pin.background", "enum", { label: "Background", value: "", "default": "", apply: "reload",
               options: [{ value: "", label: "Automatic" }, { value: "br.com.dias.maxine-vfx", label: "NVIDIA Maxine" }] }),
        cfgRow("modules.enabled.br.com.dias.maxine-vfx", "bool", { label: "NVIDIA Maxine", value: true }),
        cfgRow("modules.dirs", "list", { label: "Module directories", value: ["/a", "/b"], editable: false }),
        cfgRow("modules.order", "list", { label: "Stage order", value: [], editable: false })] }
    ]
  }
  function configLines(groups, o) {
    var opt = merged({ serial: 7, per: 2, schema: 1 }, o || {})
    var raw = []
    for (var g = 0; g < groups.length; g++) {
      var parts = Math.max(1, Math.ceil(groups[g].settings.length / opt.per))
      for (var p = 0; p < parts; p++)
        raw.push({ v: 1, type: "config_group", schema: opt.schema, serial: opt.serial, part: p + 1, parts: parts,
                   group: { id: groups[g].id, label: groups[g].label, settings: groups[g].settings.slice(p * opt.per, (p + 1) * opt.per) } })
    }
    for (var i = 0; i < raw.length; i++) { raw[i].index = i; raw[i].count = raw.length }
    return lines(raw)
  }
  function filesLines(o) {
    return lines([merged({ v: 1, type: "config_files", serial: 7, dir: "/home/u/.config/omarchy-broadcast", files: [
      { path: "config.toml", status: "loaded", managed: false, reason: "" },
      { path: "config.d/50-panel.toml", status: "absent", managed: true, reason: "" },
      { path: "config.d/90-local.toml", status: "error", managed: false, reason: "line 3: unknown field `foo`" }],
      files_truncated: false }, o || {})])
  }
  function fullSetup() {
    var setup = Model.emptySetup()
    setup = Model.withSetupRead(setup, "modules", Model.readModules(moduleLines([moduleObj("br.com.dias.maxine-vfx"),
      moduleObj("org.example.hello", { name: "Hello tint", version: "0.1.0", enabled: false, status: "disabled",
                                       reason: "Disabled after crashing the daemon twice in a row",
                                       stages: [{ id: "hello", slot: "post-composite", rank: 100, device: "cpu", available: false, reason: "Disabled", selected: false }] })]), 0, ""))
    setup = Model.withSetupRead(setup, "order", Model.readOrder(orderLines(["enhance", "denoise", "background"]), 0, ""))
    setup = Model.withSetupRead(setup, "config", Model.readConfig(configLines(cfgGroups()), 0, ""))
    setup = Model.withSetupRead(setup, "files", Model.readConfigFiles(filesLines(), 0, ""))
    return setup
  }

  function test_setup_lines_in_the_watch() {
    var r = snap(rev10({}))
    compare(r.configSerial, 3)
    compare(r.modulesSerial, 2)
    compare(snap().configSerial, 0, "a CLI that predates them: 0")
    compare(snap({ config_serial: -1, modules_serial: "2" }).configSerial, 0)
    var c = Model.reduce(r, line({ v: 1, type: "config_changed", serial: 4 }))
    compare(c.outcome, "config_changed")
    compare(c.record.configSerial, 4)
    compare(r.configSerial, 3, "the old record is not mutated")
    var m = Model.reduce(c.record, line({ v: 1, type: "modules_changed", serial: 9 }))
    compare(m.outcome, "modules_changed")
    compare(m.record.modulesSerial, 9)
    compare(m.record.configSerial, 4)
    var bad = [0, -1, 1.5, "4", null, undefined, 4294967296]
    for (var i = 0; i < bad.length; i++)
      compare(Model.reduce(r, line({ v: 1, type: "config_changed", serial: bad[i] })).outcome, "ignored", JSON.stringify(bad[i]))
    compare(Model.reduce(Model.emptyRecord("not-running"), line({ v: 1, type: "modules_changed", serial: 3 })).outcome, "ignored",
            "only between a snapshot and an outage")
  }

  function test_setup_payload() {
    compare(JSON.stringify(Model.setupPayload("")), JSON.stringify({ view: "panel", cliSetting: null }), "the panel hotkey")
    compare(Model.setupPayload("{}").view, "panel", "the shell's togglePanelAt")
    compare(Model.setupPayload(undefined).view, "panel")
    compare(Model.setupPayload("not json").view, "panel")
    compare(Model.setupPayload("[\"setup\"]").view, "panel")
    compare(Model.setupPayload('{"view":"panel"}').view, "panel")
    compare(Model.setupPayload('{"view":"Setup"}').view, "panel", "exact word only")
    var p = Model.setupPayload(Model.setupPayloadJson("/opt/bin/omarchy-broadcast"))
    compare(p.view, "setup")
    compare(p.cliSetting, "/opt/bin/omarchy-broadcast")
    compare(Model.setupPayload(Model.setupPayloadJson(null)).cliSetting, null, "no setting: none passed")
    compare(Model.setupPayloadJson(null), '{"view":"setup"}')
    compare(Model.setupPayload('{"view":"setup","cliPath":5}').cliSetting, null)
    var long = "/"
    for (var i = 0; i < Model.PATH_CAP + 10; i++) long += "x"
    compare(Model.setupPayload('{"view":"setup","cliPath":"' + long + '"}').cliSetting, null, "a path over PATH_CAP is no setting")
    for (var j = 0; j < 300; j++) long += "y"
    compare(Model.setupPayload('{"view":"setup","cliPath":"' + long + '"}').view, "panel", "an over-cap payload is not read")
  }

  function test_pick_panel_owner() {
    var c = [{ screenName: "DP-1", visible: true }, { screenName: "HDMI-A-1", visible: true }]
    compare(Model.pickPanelOwner(c, "HDMI-A-1"), 1, "the focused screen's")
    compare(Model.pickPanelOwner(c, "DP-1"), 0)
    compare(Model.pickPanelOwner(c, ""), 0, "no focused screen: the first")
    compare(Model.pickPanelOwner(c, "eDP-1"), 0, "a screen without the widget: the first")
    // As the shell's BarModel.pickPanelSlot: the focused screen first, then a drawn one
    compare(Model.pickPanelOwner([{ screenName: "DP-1", visible: false }, { screenName: "HDMI-A-1", visible: true }], "DP-1"), 0,
            "the focused screen's, drawn or not")
    compare(Model.pickPanelOwner([{ screenName: "DP-1", visible: false }, { screenName: "HDMI-A-1", visible: true }], "eDP-1"), 1,
            "no copy on the focused screen: a drawn one before one that is not")
    compare(Model.pickPanelOwner([{ screenName: "DP-1", visible: false }, { screenName: "DP-1", visible: true }], "DP-1"), 1,
            "on the focused screen, the drawn one")
    compare(Model.pickPanelOwner([{ screenName: "DP-1", visible: false }, { screenName: "HDMI-A-1", visible: true }], ""), 1,
            "no focused screen: a drawn one")
    compare(Model.pickPanelOwner([{ screenName: "DP-1", visible: false }], "DP-1"), 0, "none drawn: still one")
    compare(Model.pickPanelOwner([], "DP-1"), -1)
    compare(Model.pickPanelOwner(null, "DP-1"), -1)
  }

  function test_read_modules() {
    var r = Model.readModules(moduleLines([moduleObj("br.com.dias.maxine-vfx", { name: "NVIDIA <b>Maxine</b>" }),
                                           moduleObj("org.example.hello", { status: "disabled", enabled: false, reason: "Disabled", overridden_by: "config.d/90-x.toml" })],
                                          { profile_overridden_by: "config.d/90-x.toml" }), 0, "")
    compare(r.ok, true)
    compare(r.serial, 2)
    compare(r.profile, "quality")
    compare(r.profileOverriddenBy, "config.d/90-x.toml")
    compare(r.modules.length, 2)
    compare(r.modules[0].name, "NVIDIA bMaxine/b", "sanitised")
    compare(r.modules[0].stages[0].id, "background")
    compare(r.modules[1].overriddenBy, "config.d/90-x.toml")
    compare(r.modules[1].reason, "Disabled")
    compare(r.modules[0].reason, "", "an available module has no reason")
    // an empty list is a list
    var none = Model.readModules(moduleLines([]), 0, "")
    compare(none.ok, true)
    compare(none.modules.length, 0)
    // incomplete, repeated or foreign lines
    var some = moduleLines([moduleObj("a.b"), moduleObj("c.d")])
    compare(Model.readModules(some.slice(0, 2), 0, "").ok, false, "a module line missing")
    compare(Model.readModules([some[0], some[1], some[1]], 0, "").error, "The module list arrived incomplete", "a repeated index is one line")
    compare(Model.readModules(some.slice(1), 0, "").ok, false, "no header")
    // ids not of the grammar are left out; an unknown status reads unavailable
    var odd = Model.readModules(moduleLines([moduleObj("Bad Id"), moduleObj("a.b", { status: "weird" }), moduleObj("a.b"), moduleObj("x")]), 0, "")
    compare(odd.ok, true)
    compare(JSON.stringify(odd.modules.map(function(m) { return m.id + ":" + m.status })), JSON.stringify(["a.b:unavailable"]), "bad ids dropped, a repeat kept once")
    // the CLI's error line, or its exit status
    var err = Model.readModules(lines([{ v: 1, type: "error", code: "unsupported-daemon", error: "the daemon does not support modules" }]), 1, "")
    compare(err.ok, false)
    compare(err.error, "the daemon does not support modules")
    compare(Model.readModules([], 3, "").error, "omarchy-broadcastd is not running")
    compare(Model.readModules(["garbage"], 0, "").error, "omarchy-broadcast printed no module list")
    compare(Model.readModules(lines([{ v: 2, type: "modules" }]), 0, "").error.indexOf("schema v2") >= 0, true)
    // a count over the cap is never waited for
    compare(Model.readModules(lines([{ v: 1, type: "modules", serial: 1, profile: "", count: Model.MODULE_LINES_CAP + 1 }]), 0, "").ok, false)
  }

  function test_read_order_and_moves() {
    var o = Model.readOrder(orderLines(["enhance", "denoise", "background", "relight"]), 0, "")
    compare(o.ok, true)
    compare(JSON.stringify(o.order), JSON.stringify(["enhance", "denoise", "background", "relight"]))
    compare(JSON.stringify(o.stages.map(function(s) { return s.up + "/" + s.down })), JSON.stringify(["false/true", "true/true", "true/true", "true/false"]))
    compare(JSON.stringify(Model.orderAfterMove(o, 1, -1)), JSON.stringify(["denoise", "enhance", "background", "relight"]))
    compare(JSON.stringify(Model.orderAfterMove(o, 1, 1)), JSON.stringify(["enhance", "background", "denoise", "relight"]))
    compare(Model.orderAfterMove(o, 0, -1), null, "the first cannot go up")
    compare(Model.orderAfterMove(o, 3, 1), null)
    compare(Model.orderAfterMove(o, 9, 1), null)
    compare(Model.orderAfterMove(o, 1, 2), null, "one place at a time")
    // the daemon's word decides: a move it would refuse is not offered
    var strict = Model.readOrder(orderLines(["denoise", "background"], { stages: [
      { id: "denoise", slot: "pre-matte", up: false, down: false }, { id: "background", slot: "matte", up: false, down: false }] }), 0, "")
    compare(Model.orderAfterMove(strict, 0, 1), null)
    compare(Model.orderAfterMove(strict, 1, -1), null)
    // no stages (a revision-9 CLI): nothing moves
    var bare = Model.readOrder(lines([{ v: 1, type: "order", order: ["a", "b"], order_truncated: false }]), 0, "")
    compare(bare.ok, true)
    compare(bare.stages.every(function(s) { return !s.up && !s.down }), true)
    // overridden or truncated: nothing moves, and the view says why
    var over = Model.readOrder(orderLines(["a", "b"], { overridden_by: "config.d/90-x.toml" }), 0, "")
    compare(Model.orderAfterMove(over, 0, 1), null)
    var trunc = Model.readOrder(orderLines(["a", "b"], { order_truncated: true }), 0, "")
    compare(trunc.truncated, true)
    compare(Model.orderAfterMove(trunc, 0, 1), null)
    // ids not of the stage grammar (or repeated) make it truncated: never written back
    var hostile = Model.readOrder(orderLines(["a", "--flag", "a"]), 0, "")
    compare(JSON.stringify(hostile.order), JSON.stringify(["a"]))
    compare(hostile.truncated, true)
    compare(Model.readOrder(["{}"], 0, "").ok, false)
    compare(Model.orderAfterMove(null, 0, 1), null)
  }

  function test_read_config_rows() {
    var c = Model.readConfig(configLines(cfgGroups()), 0, "")
    compare(c.ok, true)
    compare(c.serial, 7)
    compare(JSON.stringify(c.groups.map(function(g) { return g.id + ":" + g.rows.length })),
            JSON.stringify(["output:3", "lifecycle:2", "pipewire:1", "effect:1", "modules:5"]), "the parts of a group joined, in order")
    var fmt = Model.findConfigRow(c, "output.format")
    compare(fmt.type + ":" + fmt.value + ":" + fmt.apply, "enum:nv12:reload")
    var hold = Model.findConfigRow(c, "output.hold_timeout_s")
    compare(hold.bounded, true)
    compare(hold.decimals, 1)
    var deb = Model.findConfigRow(c, "lifecycle.start_debounce_ms")
    compare(deb.overriddenBy, "config.d/90-local.toml")
    compare(deb.enabled, false)
    var en = Model.findConfigRow(c, "modules.enabled.br.com.dias.maxine-vfx")
    verify(en !== null, "a key whose last parts are a module id")
    compare(JSON.stringify(Model.findConfigRow(c, "modules.dirs").value), JSON.stringify(["/a", "/b"]))
    compare(Model.findConfigRow(c, "modules.pin.background").value, "", "Automatic is the empty option")
    // incomplete, another serial, a newer schema
    var all = configLines(cfgGroups())
    compare(Model.readConfig(all.slice(1), 0, "").ok, false)
    compare(Model.readConfig(configLines(cfgGroups(), { schema: 2 }), 0, "").error, Model.SETUP_OLD_PLUGIN)
    var mixed = all.slice()
    mixed[2] = JSON.stringify(merged(JSON.parse(mixed[2]), { serial: 8 }))
    compare(Model.readConfig(mixed, 0, "").ok, false, "a line of another serial does not complete the set")
    compare(Model.readConfig(lines([{ v: 1, type: "error", code: "unsupported-daemon", error: "the daemon does not support the configuration" }]), 1, "").error,
            "the daemon does not support the configuration")
  }

  function test_config_entry_validation() {
    var e = function(o) { return Model.configEntry(o) }
    compare(e(cfgRow("output.format", "enum", { value: "x", options: [] })), null, "an enum with no option")
    compare(e(cfgRow("output.x", "color", { value: "red" })), null, "an unknown type is skipped")
    compare(e(cfgRow("Output.X", "bool", { value: true })), null, "not of the key grammar")
    compare(e(cfgRow("output", "bool", { value: true })), null, "a key has a dot")
    // module ids are reverse-DNS with any number of parts (the daemon's valid_module_id, 64 bytes)
    var longId = "a.b.c.d.e.f.g.h.i.j.k.l"
    compare(e(cfgRow("modules.enabled." + longId, "bool", { value: true })).id, "modules.enabled." + longId, "a module id of many parts")
    var maxId = "a"
    while (maxId.length < 63) maxId += ".b"
    maxId = maxId.slice(0, 64)
    compare(Model.moduleIdOf(maxId), maxId, "64 bytes of parts")
    compare(Model.configKeyOf("modules.enabled." + maxId), "modules.enabled." + maxId)
    compare(Model.configKeyOf("modules.enabled.a..b"), "", "no empty part")
    compare(Model.configKeyOf("modules.enabled.a.b."), "", "no empty last part")
    compare(e(cfgRow("output.__proto__", "bool", { value: true })) !== null, true, "a dotted key is never a bare reserved word")
    compare(e(cfgRow("output.x", "bool", { value: "true" })), null, "a bool is a boolean")
    compare(e(cfgRow("output.x", "int", { value: 1.5 })), null, "an int is whole")
    compare(e(cfgRow("output.x", "int", { value: 5, min: 0, max: 10, step: 1 })).bounded, true)
    compare(e(cfgRow("output.x", "int", { value: 50, min: 0, max: 10, step: 1 })).value, 10, "clamped into range")
    compare(e(cfgRow("output.x", "int", { value: 5 })).bounded, false, "no range: shown, not stepped")
    compare(e(cfgRow("output.x", "int", { value: 5, min: 10, max: 0, step: 1 })).bounded, false)
    compare(e(cfgRow("output.x", "float", { value: 0.25, min: 0, max: 1, step: 0.05 })).decimals, 2)
    compare(e(cfgRow("output.x", "float", { value: 1e300 })), null)
    compare(e(cfgRow("output.x", "string", { value: 7 })), null)
    compare(e(cfgRow("output.x", "list", { value: "a,b" })), null)
    var hostile = e(cfgRow("output.x", "string", { label: "<img src=x>", description: "a\nb<b>", value: "<script>",
                                                   overridden_by: "config.d/<x>.toml", disabled_reason: "r" }))
    verify(!/[<>]/.test(hostile.label + hostile.description + hostile.value + hostile.overriddenBy), JSON.stringify(hostile))
    compare(hostile.reason, "", "no reason while enabled")
    compare(e(cfgRow("output.x", "bool", { value: true, apply: "sometimes" })).apply, "live", "an unknown apply reads live")
    var list = []
    for (var i = 0; i < 40; i++) list.push("/d" + i)
    var many = e(cfgRow("modules.dirs", "list", { value: list }))
    compare(many.value.length, Model.CONFIG_LIST_CAP)
    compare(many.itemsTotal, 40)
    var opts = []
    for (var o = 0; o < 30; o++) opts.push({ value: "o" + o, label: "O" + o })
    opts.push({ value: "--flag", label: "bad" })
    compare(e(cfgRow("output.x", "enum", { value: "o1", options: opts })).options.length, Model.CONFIG_OPTION_CAP)
    compare(Model.configOptions([{ value: "--flag", label: "x" }, { value: "a b", label: "y" }, { value: "", label: "" }]).options.length, 1,
            "only option values of the grammar")
  }

  function test_config_words_and_widgets() {
    var c = Model.readConfig(configLines(cfgGroups()), 0, "")
    var row = function(id) { return Model.findConfigRow(c, id) }
    compare(Model.configWord(row("output.format"), "yuyv"), "yuyv")
    compare(Model.configWord(row("output.format"), "rgb"), null, "only the row's options")
    compare(Model.configWord(row("pipewire.enabled"), true), "true")
    compare(Model.configWord(row("pipewire.enabled"), "true"), null, "a strict boolean")
    compare(Model.configWord(row("lifecycle.idle_grace_s"), 7.4), "7", "on the grid")
    compare(Model.configWord(row("lifecycle.idle_grace_s"), 900), "60", "within range")
    compare(Model.configWord(row("output.hold_timeout_s"), 3.3), "3.5")
    compare(Model.configWord(row("output.hold_timeout_s"), NaN), null)
    compare(Model.configWord(row("modules.pin.background"), ""), "", "Automatic")
    compare(Model.configWord(row("modules.pin.background"), "br.com.dias.maxine-vfx"), "br.com.dias.maxine-vfx")
    compare(Model.configWord(row("lifecycle.start_debounce_ms"), 300), null, "overridden by a later file: refused")
    compare(Model.configWord(row("output.mode"), "x"), null, "not editable")
    compare(Model.configWord(row("modules.dirs"), ["/x"]), null, "a list is never written here")
    compare(Model.configNudge(row("lifecycle.idle_grace_s"), 1), 8, "a twentieth of the range")
    compare(Model.configNudge(row("lifecycle.idle_grace_s"), -1), 2)
    compare(Model.configNudge(row("output.hold_timeout_s"), 1), 3)
    compare(Model.configNudge(row("output.hold_timeout_s"), 0), null)
    // the widgets
    compare(Model.configWidget(row("pipewire.enabled")), "switch")
    compare(Model.configWidget(row("output.format")), "choices")
    compare(Model.configWidget(row("lifecycle.idle_grace_s")), "stepper")
    compare(Model.configWidget(row("lifecycle.start_debounce_ms")), "text", "overridden: read-only")
    compare(Model.configWidget(row("output.mode")), "text")
    compare(Model.configWidget(row("effect.maxine_root")), "text")
    compare(Model.configWidget(Model.configEntry(cfgRow("output.x", "int", { value: 5 }))), "text", "an unbounded number is shown")
    // the drawn row
    var v = Model.configRowView(row("lifecycle.start_debounce_ms"), 4)
    compare(v.note, "Overridden by config.d/90-local.toml")
    compare(v.greyed, true)
    compare(v.stop, -1)
    compare(v.applyText, "")
    var f = Model.configRowView(row("output.format"), 0)
    compare(f.applyText, "Applies at next camera start")
    compare(Model.configSelected(f), 0)
    compare(Model.configRowView(row("output.hold_timeout_s"), 1).valueText, "2.5 s")
    compare(Model.configRowView(row("modules.dirs"), 0).valueText, "/a, /b")
    compare(Model.configRowView(row("modules.order"), 0).valueText, "None")
    // argv
    compare(JSON.stringify(Model.configSetArgv(cli, "output.format", "yuyv")), JSON.stringify([cli, "config", "set", "--", "output.format", "yuyv"]))
    compare(JSON.stringify(Model.configSetArgv(cli, "modules.pin.background", "")), JSON.stringify([cli, "config", "set", "--", "modules.pin.background", ""]))
    compare(Model.configSetArgv(cli, "output.format", "--help"), null)
    compare(Model.configSetArgv(cli, "output.format", "a b"), null)
    compare(Model.configSetArgv(cli, "-x", "1"), null)
    compare(Model.configSetArgv("", "output.format", "nv12"), null)
  }

  // output.mode of interface revision 12: an editable enum of up to 16 options
  // the daemon computes ("WxH@FPS" values, labels with a dot).
  function outputModeOptions(n) {
    var sizes = ["3840x2160", "2560x1440", "1920x1080", "1280x720"]
    var rates = [15, 24, 30, 60]
    var out = []
    for (var i = 0; i < n; i++) {
      var size = sizes[Math.floor(i / 4) % 4], rate = rates[i % 4]
      out.push({ value: size + "@" + rate, label: size + " \u00b7 " + rate + " fps" + (rate === 60 ? " (generated)" : "") })
    }
    return out
  }
  function modeRow(options, o) {
    return Model.configEntry(cfgRow("output.mode", "enum", merged({ label: "Output size and rate", value: "1920x1080@30", "default": "1920x1080@30",
                                                                    apply: "reload", options: options }, o || {})))
  }

  function test_config_enum_dropdown_for_many_or_long_choices() {
    // many choices: a dropdown, as the panel draws a long setting
    var mode = modeRow(outputModeOptions(16))
    compare(mode.options.length, 16)
    compare(Model.configWidget(mode), "dropdown")
    var v = Model.configRowView(mode, 3)
    compare(v.widget, "dropdown")
    compare(v.options.length, 16)
    compare(v.stop, 3, "a dropdown is a keyboard stop")
    compare(Model.configSelected(v), 10)
    compare(v.options[10].selected, true)
    compare(v.options[15].label, "1280x720 \u00b7 60 fps (generated)", "a label keeps its generated note")
    compare(v.valueText, "1920x1080 \u00b7 30 fps")
    compare(v.applyText, "Applies at next camera start", "the apply note stays")
    // few and short: the row of buttons stays
    var short4 = modeRow([{ value: "a", label: "A" }, { value: "b", label: "B" }, { value: "c", label: "C" }, { value: "d", label: "D" }], { value: "a", "default": "a" })
    compare(Model.configWidget(short4), "choices")
    compare(Model.configRowView(short4, 0).widget, "choices")
    compare(Model.configRowView(short4, 0).applyText, "Applies at next camera start")
    var fmt = Model.configEntry(cfgRow("output.format", "enum", { value: "nv12", options: [{ value: "nv12", label: "NV12" }, { value: "i420", label: "I420" }] }))
    compare(Model.configWidget(fmt), "choices", "two short choices")
    // the same limits as the panel's settings (Model.SEGMENTED_MAX_OPTIONS and _CHARS)
    var five = modeRow([{ value: "a", label: "A" }, { value: "b", label: "B" }, { value: "c", label: "C" }, { value: "d", label: "D" },
                        { value: "e", label: "E" }], { value: "a", "default": "a" })
    compare(Model.configWidget(five), "dropdown", "five short choices")
    compare(Model.SEGMENTED_MAX_OPTIONS, 4)
    var longLabels = modeRow([{ value: "a", label: "A fairly long first choice" }, { value: "b", label: "Second" }], { value: "a", "default": "a" })
    compare(Model.configWidget(longLabels), "dropdown", "labels together over " + Model.SEGMENTED_MAX_CHARS + " characters")
    var edge = modeRow([{ value: "a", label: new Array(Model.SEGMENTED_MAX_CHARS).join("x") + "y" }], { value: "a", "default": "a" })
    compare(edge.options[0].label.length, Model.SEGMENTED_MAX_CHARS)
    compare(Model.configWidget(edge), "choices", "exactly the limit still fits")
    compare(Model.fitsSegmented([{ label: "A" }, { label: "B" }]), true)
    compare(Model.fitsSegmented([]), true)
    compare(Model.fitsSegmented(null), true)
    compare(Model.fitsSegmented(outputModeOptions(3)), false)
    // a settings row and a config row of the same options get the same widget
    var setting = { type: "enum", options: outputModeOptions(16) }
    compare(Model.settingWidget(setting), Model.configWidget(mode))
    // the options a dropdown shows are the daemon's, at most 16, labels up to a config label's 48
    var many = modeRow(outputModeOptions(16).concat([{ value: "800x600@30", label: "800x600 \u00b7 30 fps" }]))
    compare(many.options.length, 16, "at most 16 are looked at")
    var wide = modeRow([{ value: "a", label: new Array(48).join("w") + "xyz" }], { value: "a", "default": "a" })
    compare(wide.options[0].label.length, 48, "a config option label is kept up to 48 characters")
    // an older daemon: output.mode is read-only text, never a dropdown
    var old = Model.configEntry(cfgRow("output.mode", "string", { label: "Mode", value: "1920x1080@30", editable: false }))
    compare(Model.configWidget(old), "text")
    compare(Model.configRowView(old, 3).stop, -1)
    // an enum the daemon marks read-only, greyed, or overridden is text too
    compare(Model.configWidget(modeRow(outputModeOptions(16), { editable: false })), "text")
    compare(Model.configWidget(modeRow(outputModeOptions(16), { enabled: false, disabled_reason: "No camera" })), "text")
    compare(Model.configWidget(modeRow(outputModeOptions(16), { overridden_by: "config.d/90-local.toml", enabled: false })), "text")
  }

  function test_config_dropdown_value_is_written_by_config_set() {
    var c = Model.readConfig(configLines([{ id: "output", label: "Output", settings: [
      cfgRow("output.mode", "enum", { label: "Output size and rate", value: "1920x1080@30", "default": "1920x1080@30", apply: "reload",
              options: outputModeOptions(16) })] }]), 0, "")
    var row = Model.findConfigRow(c, "output.mode")
    compare(row.options.length, 16)
    // the word is the option's value, checked against the row's options
    compare(Model.configWord(row, "1920x1080@60"), "1920x1080@60")
    compare(Model.configWord(row, "2560x1440@24"), "2560x1440@24")
    compare(Model.configWord(row, "800x600@30"), null, "only the row's options")
    compare(Model.configWord(row, "1920x1080 \u00b7 60 fps"), null, "a label is not a value")
    compare(Model.configWord(row, 60), null)
    compare(JSON.stringify(Model.configSetArgv(cli, "output.mode", "1920x1080@60")),
            JSON.stringify([cli, "config", "set", "--", "output.mode", "1920x1080@60"]), "after `--`, one element")
    compare(JSON.stringify(Model.configSetArgv(cli, "output.mode", "1920x1080@30000/1001")),
            JSON.stringify([cli, "config", "set", "--", "output.mode", "1920x1080@30000/1001"]), "a fractional rate")
    compare(Model.configSetArgv(cli, "output.mode", "1920x1080 @60"), null, "no space")
    compare(Model.configSetArgv(cli, "output.mode", "@60"), null, "starts with a letter or digit")
    compare(Model.configSetArgv(cli, "output.mode", "-1920x1080@60"), null)
    compare(Model.configSetArgv(cli, "output.mode", "1920x1080;60"), null)
    // the write is an intent of the setup queue, from revision 10 (the row itself arrives from 12)
    var go = function(word, r) { return JSON.stringify(Model.intentArgv({ verb: "setup", op: "config", id: "output.mode", word: word }, cli, r)) }
    compare(go("1920x1080@60", setupRecord(12)), JSON.stringify([cli, "config", "set", "--", "output.mode", "1920x1080@60"]))
    compare(go("1920x1080@60", setupRecord(9)), "null", "config writes need revision 10")
    // a refused value (the dialog asks chooseConfigValue first) never reaches argv
    compare(Model.configOptionIndex(Model.configRowView(row, 0).options, "1920x1080@60"), 11)
    compare(Model.configOptionIndex(Model.configRowView(row, 0).options, "800x600@30"), -1)
  }

  function test_capture_mode_setting_is_a_dropdown_and_written_by_settings_set() {
    var modes = ["3840x2160@30", "3840x2160@24", "2560x1440@30", "1920x1200@30", "1920x1080@60", "1920x1080@30", "1920x1080@24",
                 "1600x900@30", "1280x960@30", "1280x720@60", "1280x720@30", "1024x576@30", "960x540@30", "640x360@30"]
    var options = [{ value: "auto", label: "Automatic" }]
    for (var i = 0; i < modes.length; i++) {
      var parts = modes[i].split("@")
      options.push({ value: modes[i], label: parts[0] + " \u00b7 " + parts[1] + " fps" })
    }
    options.push({ value: "4096x2160@30", label: "4096x2160 \u00b7 30 fps (gone)" })
    compare(options.length, 16)
    var groups = [{ id: "capture", label: "Capture", settings: [
      enumS("camera.capture.mode", "Capture mode", options, { value: "3840x2160@30", "default": "auto", stored: true, hint: "dropdown" })] }].concat(brioGroups())
    var r = feedAll(snap(rev7({ interface_revision: 12 })), setLines(groups, { rev: 12 })).record
    var mode = Model.findSetting(r, "camera.capture.mode")
    verify(mode !== null, "the row is kept: values with @ are valid")
    compare(mode.options.length, 16)
    compare(mode.options[1].value, "3840x2160@30")
    compare(mode.options[15].label, "4096x2160 \u00b7 30 fps (gone)", "the whole label, within 32 characters")
    compare(Model.settingWidget(mode), "dropdown")
    compare(r.settings.groups[0].id, "capture", "the first group")
    compare(Model.settingValueText(mode, "3840x2160@30"), "3840x2160 \u00b7 30 fps")
    var v = Model.settingsView(r, {}, {})
    compare(v.groups[0].id, "capture")
    compare(v.groups[0].expanded, false, "Image stays the group open by default")
    compare(v.groups[1].expanded, true)
    v = Model.settingsView(r, "capture", {})
    compare(v.groups[0].expanded, true, "opened by the user")
    compare(v.groups[0].rows[0].widget, "dropdown")
    compare(v.groups[0].rows[0].options.length, 16)
    // the write
    var argv = function(value) {
      return JSON.stringify(Model.intentArgv({ verb: "setting", id: "camera.capture.mode", value: value, camera: brioId }, cli, r))
    }
    compare(argv("1920x1080@60"), JSON.stringify([cli, "settings", "set", "--camera=" + brioId, "--", "camera.capture.mode", "1920x1080@60"]))
    compare(argv("auto"), JSON.stringify([cli, "settings", "set", "--camera=" + brioId, "--", "camera.capture.mode", "auto"]))
    compare(argv("800x600@30"), "null", "not one of the row's options")
    compare(Model.settingArgv(cli, brioId, "camera.capture.mode", "1920x1080@30000/1001") !== null, true, "a fractional rate")
    compare(Model.settingArgv(cli, brioId, "camera.capture.mode", "1920x1080 60"), null)
    // an older daemon never publishes it: no capture group, nothing to draw
    var old = feedAll(snap(rev7({ interface_revision: 7 })), setLines(brioGroups())).record
    compare(Model.findSetting(old, "camera.capture.mode"), null)
    compare(old.settings.groups[0].id, "image")
  }

  function test_setup_intents() {
    var r10 = setupRecord(10)
    var r9 = setupRecord(9)
    var go = function(intent, r) { return JSON.stringify(Model.intentArgv(merged({ verb: "setup" }, intent), cli, r)) }
    compare(go({ op: "module", id: "org.example.hello", on: true }, r9), JSON.stringify([cli, "modules", "enable", "org.example.hello"]))
    compare(go({ op: "module", id: "org.example.hello", on: false }, r9), JSON.stringify([cli, "modules", "disable", "org.example.hello"]))
    compare(go({ op: "module", id: "--all", on: false }, r9), "null")
    compare(go({ op: "module", id: "org.example.hello", on: "yes" }, r9), "null")
    compare(go({ op: "order", order: ["denoise", "enhance"] }, r9), JSON.stringify([cli, "order", "set", "denoise,enhance"]))
    compare(go({ op: "order", order: ["denoise", "denoise"] }, r9), "null", "each stage once")
    compare(go({ op: "order", order: ["a,b"] }, r9), "null")
    compare(go({ op: "order", order: [] }, r9), "null")
    compare(go({ op: "order-reset" }, r9), JSON.stringify([cli, "order", "reset"]))
    compare(go({ op: "config", id: "output.format", word: "yuyv" }, r10), JSON.stringify([cli, "config", "set", "--", "output.format", "yuyv"]))
    compare(go({ op: "config", id: "output.format", word: "yuyv" }, r9), "null", "config writes need revision 10")
    compare(go({ op: "module", id: "a.b", on: true }, setupRecord(8)), "null", "modules need revision 9")
    compare(go({ op: "module", id: "a.b", on: true }, Model.emptyRecord("not-running")), "null", "never D-Bus-activates a stopped daemon")
    compare(go({ op: "rm" }, r10), "null")
    // the queue: one setup write at a time, never replaced by another ask
    verify(!Model.setupWriteBusy(null, []))
    var q = Model.enqueueIntent([], { verb: "setup", op: "order-reset" })
    verify(Model.setupWriteBusy(null, q))
    verify(Model.setupWriteBusy({ verb: "setup", op: "order-reset" }, []))
    compare(Model.queueTakes(q, { verb: "setup", op: "module", id: "a.b", on: true }), false, "a second one is refused")
    var mixed = Model.enqueueIntent(q, { verb: "next" })
    compare(JSON.stringify(mixed.map(function(i) { return i.verb })), JSON.stringify(["setup", "next"]), "another ask leaves it queued")
    mixed = Model.enqueueIntent(mixed, { verb: "select", id: fhdId })
    compare(JSON.stringify(mixed.map(function(i) { return i.verb })), JSON.stringify(["setup", "select"]), "the latest other ask still wins")
    compare(Model.dropSettingIntents(mixed).length, 2, "a camera change keeps it")
    // Q5: a setup write is a settings-type write; it never holds the on/off
    verify(!Model.toggleBlocked(null, q), "the middle click does not wait for a queued setup write")
    verify(!Model.toggleBlocked({ verb: "setup", op: "config", id: "output.format", word: "yuyv" }, []), "nor for a running one")
    verify(Model.toggleBlocked({ verb: "setup", op: "order-reset" }, [{ verb: "enable", on: true }]), "an on/off behind it still does")
    verify(Model.toggleBlocked(null, mixed), "nor does a camera change queued with it")
    verify(Model.isSetupIntent(q[0]))
    verify(!Model.isSettingIntent(q[0]))
  }

  function test_setup_gate_and_reads() {
    compare(JSON.stringify(Model.setupReads(setupRecord(10))), JSON.stringify(["modules", "order", "config", "files"]))
    compare(JSON.stringify(Model.setupReads(setupRecord(9))), JSON.stringify(["modules", "order"]))
    compare(Model.setupReads(setupRecord(8)).length, 0)
    compare(Model.setupReads(Model.emptyRecord("not-running")).length, 0)
    compare(JSON.stringify(Model.setupReadArgv(cli, "config")), JSON.stringify([cli, "config", "show", "--json"]))
    compare(JSON.stringify(Model.setupReadArgv(cli, "files")), JSON.stringify([cli, "config", "files", "--json"]))
    compare(JSON.stringify(Model.setupReadArgv(cli, "modules")), JSON.stringify([cli, "modules", "list", "--json"]))
    compare(JSON.stringify(Model.setupReadArgv(cli, "order")), JSON.stringify([cli, "order", "show", "--json"]))
    compare(Model.setupReadArgv(cli, "rm"), null)
    compare(Model.setupReadArgv("relative", "order"), null)
    var g8 = Model.setupGate(setupRecord(8))
    compare(g8.modules + ":" + g8.config + ":" + g8.text, "false:false:" + Model.SETUP_OLD_DAEMON)
    var g9 = Model.setupGate(setupRecord(9))
    compare(g9.modules + ":" + g9.config + ":" + g9.text, "true:false:")
    var gone = Model.setupGate(Model.emptyRecord("not-running"))
    compare(gone.text, "omarchy-broadcastd is not running")
    compare(gone.commandText, "systemctl --user start omarchy-broadcastd")
    var s = Model.withSetupRead(Model.emptySetup(), "order", { ok: true })
    compare(s.order.ok, true)
    compare(s.modules, null)
    compare(Model.withSetupRead(s, "bogus", {}).order.ok, true, "an unknown kind changes nothing")
    // a daemon whose revision drops: the reads it no longer supports are cleared
    var all = { modules: { ok: true }, order: { ok: true }, config: { ok: true }, files: { ok: true } }
    var kept = Model.setupForReads(all, Model.setupReads(setupRecord(9)))
    compare(kept.modules.ok + ":" + kept.order.ok + ":" + kept.config + ":" + kept.files, "true:true:null:null", "revision 9 keeps the modules reads")
    var none = Model.setupForReads(all, Model.setupReads(setupRecord(8)))
    compare(JSON.stringify(none), JSON.stringify(Model.emptySetup()), "revision 8 keeps nothing")
    compare(Model.setupForReads(all, Model.setupReads(setupRecord(10))).files.ok, true, "revision 10 keeps all")
    compare(JSON.stringify(Model.setupForReads(null, ["modules"])), JSON.stringify(Model.emptySetup()))
  }

  function test_setup_section_views() {
    var setup = fullSetup()
    var r = setupRecord(10)
    var mods = Model.modulesSectionView(setup, r)
    compare(mods.hint, "")
    compare(JSON.stringify(mods.rows.map(function(m) { return m.title + "|" + m.statusText + "|" + m.checked + "|" + m.switchable })),
            JSON.stringify(["Module br.com.dias.maxine-vfx 1.0.0|Available|true|true", "Hello tint 0.1.0|Disabled|false|true"]))
    compare(mods.rows[1].reason, "Disabled after crashing the daemon twice in a row", "a crash-ledger disable says so")
    compare(mods.rows[0].stagesText, "Camera effect \u00b7 Stages: background", "the kind leads")
    compare(mods.rows[0].kindText, "Camera effect")
    var order = Model.orderSectionView(setup, r)
    compare(JSON.stringify(order.rows.map(function(x) { return x.position + x.id + x.up + x.down })),
            JSON.stringify(["1enhancefalsetrue", "2denoisetruetrue", "3backgroundtruefalse"]))
    compare(order.reset, true)
    var back = Model.backendsSectionView(setup, r)
    compare(JSON.stringify(back.groups[0].rows.map(function(x) { return x.id + ":" + x.widget })),
            JSON.stringify(["modules.profile:choices", "modules.pin.background:choices"]), "the profile and the pins only")
    compare(back.stops, 2)
    var dmn = Model.daemonSectionView(setup, r)
    compare(JSON.stringify(dmn.groups.map(function(g) { return g.id })), JSON.stringify(["output", "lifecycle", "pipewire", "effect"]), "no modules group")
    compare(JSON.stringify(dmn.groups[0].rows.map(function(x) { return x.widget + ":" + x.stop })), JSON.stringify(["choices:0", "stepper:1", "text:-1"]))
    compare(dmn.stops, 4, "the interactive rows only")
    compare(Model.configViewRow(dmn, 3).id, "pipewire.enabled")
    compare(Model.configViewRow(dmn, 9), null)
    compare(dmn.groups[3].rows[0].applyText, "", "a read-only row says nothing about applying")
    // a revision-9 daemon: Modules and Order work, the config sections say why not
    var r9 = setupRecord(9)
    compare(Model.modulesSectionView(setup, r9).hint, "")
    compare(Model.backendsSectionView(setup, r9).hint, Model.SETUP_OLD_CONFIG)
    compare(Model.daemonSectionView(setup, r9).hint, Model.SETUP_OLD_CONFIG)
    // revision 8: every section says the daemon needs updating
    var r8 = setupRecord(8)
    compare(Model.modulesSectionView(setup, r8).hint, Model.SETUP_OLD_DAEMON)
    compare(Model.orderSectionView(setup, r8).hint, Model.SETUP_OLD_DAEMON)
    // loading and failures
    compare(Model.modulesSectionView(Model.emptySetup(), r).hint, Model.SETUP_LOADING)
    compare(Model.daemonSectionView(Model.withSetupRead(Model.emptySetup(), "config", Model.readFailed("boom")), r).hint, "boom")
    compare(Model.modulesSectionView(Model.withSetupRead(setup, "modules", Model.readModules(moduleLines([]), 0, "")), r).hint, Model.MODULES_EMPTY_TEXT)
    compare(Model.orderSectionView(Model.withSetupRead(setup, "order", Model.readOrder(orderLines([]), 0, "")), r).hint, Model.ORDER_EMPTY_TEXT)
    // overridden: the switch and the moves are not offered
    var overSetup = Model.withSetupRead(setup, "modules", Model.readModules(moduleLines([moduleObj("a.b", { overridden_by: "config.d/90-x.toml" })]), 0, ""))
    var ov = Model.modulesSectionView(overSetup, r)
    compare(ov.rows[0].switchable, false)
    compare(ov.rows[0].note, "Overridden by config.d/90-x.toml")
    var overOrder = Model.withSetupRead(setup, "order", Model.readOrder(orderLines(["a", "b"], { overridden_by: "config.d/90-x.toml" }), 0, ""))
    var oo = Model.orderSectionView(overOrder, r)
    compare(oo.rows.every(function(x) { return !x.up && !x.down }), true)
    compare(oo.reset, false)
    compare(oo.note, "Overridden by config.d/90-x.toml")
  }

  function test_setup_stops() {
    var setup = fullSetup()
    var r = setupRecord(10)
    var kinds = function(section, view) { return JSON.stringify(Model.setupStops(section, view).map(function(x) { return x.kind + x.index })) }
    var sections = ["section0", "section1", "section2", "section3", "section4"]
    compare(kinds("modules", Model.modulesSectionView(setup, r)), JSON.stringify(sections.concat(["module0", "module1"])))
    compare(kinds("order", Model.orderSectionView(setup, r)), JSON.stringify(sections.concat(["stage0", "stage1", "stage2", "order-reset-1"])))
    compare(kinds("backends", Model.backendsSectionView(setup, r)), JSON.stringify(sections.concat(["config0", "config1"])))
    compare(kinds("daemon", Model.daemonSectionView(setup, r)), JSON.stringify(sections.concat(["config0", "config1", "config2", "config3"])))
    compare(kinds("diagnostics", Model.diagnosticsView(setup, r)), JSON.stringify(sections), "Diagnostics only shows")
    compare(kinds("modules", Model.modulesSectionView(Model.emptySetup(), r)), JSON.stringify(sections), "loading: the list only")
    compare(kinds("bogus", null), JSON.stringify(sections))
    // a stage that cannot move is no stop
    var strict = Model.withSetupRead(setup, "order", Model.readOrder(orderLines(["a", "b"], { stages: [
      { id: "a", up: false, down: false }, { id: "b", up: false, down: false }] }), 0, ""))
    compare(kinds("order", Model.orderSectionView(strict, r)), JSON.stringify(sections.concat(["order-reset-1"])))
    // the buttons a stage row's Left/Right land on
    compare(Model.stageButtonAfter({ up: true, down: true }, 0, 1), 1)
    compare(Model.stageButtonAfter({ up: true, down: true }, 1, -1), 0)
    compare(Model.stageButtonAfter({ up: false, down: true }, 0, 0), 1, "lands on the one offered")
    compare(Model.stageButtonAfter({ up: false, down: true }, 1, -1), 1, "never on one not offered")
    compare(Model.stageButtonAfter({ up: true, down: false }, 1, 0), 0)
    compare(Model.stageButtonAfter({ up: false, down: false }, 0, 1), -1)
    compare(Model.setupSectionValue("order"), "order")
    compare(Model.setupSectionValue("Order"), "modules")
    compare(JSON.stringify(Model.setupSectionOptions("daemon").map(function(x) { return x.number + x.label + x.selected })),
            JSON.stringify(["1Modulesfalse", "2Orderfalse", "3Backendsfalse", "4Daemontrue", "5Diagnosticsfalse"]))
  }

  function test_setup_scroll() {
    // contentY after a scroll of `delta` (clamped to the content)
    compare(Model.scrollTarget(0, 1000, 400, 40), 40)
    compare(Model.scrollTarget(580, 1000, 400, 40), 600, "stops at the bottom")
    compare(Model.scrollTarget(20, 1000, 400, -40), 0, "stops at the top")
    compare(Model.scrollTarget(0, 300, 400, 40), 0, "content that fits does not scroll")
    compare(Model.scrollTarget(NaN, 1000, 400, 40), 40, "a bad position reads as the top")
  }

  function test_diagnostics_view() {
    var setup = fullSetup()
    var r = snap(rev10({ error: "Maxine could not load" }))
    var d = Model.diagnosticsView(setup, r)
    compare(JSON.stringify(d.rows), JSON.stringify([{ label: "D-Bus API", value: "revision 10" }, { label: "Daemon error", value: "Maxine could not load" }]))
    compare(d.dir, "/home/u/.config/omarchy-broadcast")
    compare(JSON.stringify(d.files.map(function(f) { return f.path + "|" + f.statusText + "|" + f.reason + "|" + f.note })),
            JSON.stringify(["config.toml|Loaded||", "config.d/50-panel.toml|Not present||" + Model.MANAGED_FILE_TEXT,
                            "config.d/90-local.toml|Error|line 3: unknown field `foo`|"]), "in load order, the managed one marked")
    compare(JSON.stringify(d.problems.map(function(p) { return p.title + "|" + p.reason })),
            JSON.stringify(["Hello tint|Disabled: Disabled after crashing the daemon twice in a row"]))
    compare(JSON.stringify(d.commands), JSON.stringify(["omarchy-broadcast modules", "journalctl --user -u omarchy-broadcastd"]))
    // an unavailable stage of an available module is a problem too
    var stageOff = Model.withSetupRead(setup, "modules", Model.readModules(moduleLines([moduleObj("a.b", { stages: [
      { id: "relight", slot: "post-matte", rank: 1, device: "gpu", available: false, reason: "Not installed", selected: false }] })]), 0, ""))
    compare(Model.diagnosticsView(stageOff, r).problems[0].title, "Module a.b, stage relight")
    compare(Model.diagnosticsView(stageOff, r).problems[0].reason, "Not installed")
    var fine = Model.withSetupRead(setup, "modules", Model.readModules(moduleLines([moduleObj("a.b")]), 0, ""))
    compare(Model.diagnosticsView(fine, r).problemsHint, "No module problems")
    // revision 9: the files need 10; unavailable: the panel's words
    compare(Model.diagnosticsView(setup, setupRecord(9)).filesHint, Model.SETUP_OLD_CONFIG)
    var gone = Model.diagnosticsView(setup, Model.emptyRecord("not-running"))
    compare(gone.rows[0].value, Model.UNKNOWN)
    compare(gone.rows[1].value, "omarchy-broadcastd is not running")
    compare(gone.files.length, 0)
    var trunc = Model.readConfigFiles(filesLines({ files_truncated: true }), 0, "")
    compare(trunc.truncated, true)
    compare(Model.readConfigFiles(filesLines({ files: [{ path: "x.toml", status: "odd", managed: 1, reason: "<b>" }] }), 0, "").files[0].status, "error")
  }

  // ---- the microphone (interface revision 13) -------------------------------

  readonly property string micDevice: "alsa_input.usb-C-Media-00.mono"
  function micObj(o) {
    return merged({ state: "active", consumers: 2, provider: "mic-denoise: NVIDIA Maxine AFX (GPU)", latency_ms: 20, error: "" }, o || {})
  }
  function micLine(o) { return merged({ v: 1, type: "mic" }, micObj(o)) }
  function rev13(o) { return merged({ interface_revision: 13, settings_schema: 1, settings_revision: 5, mic: micObj() }, o || {}) }
  // The microphone's groups as the daemon publishes them: its own, then the
  // audio modules' (surface "mic", scope global).
  function micGroups(o) {
    var opt = merged({ voice: false, modules: true, surface: "mic" }, o || {})
    var g = function(id, label, settings) {
      var out = { id: id, label: label, settings: settings }
      if (opt.surface !== undefined) out.surface = opt.surface
      return out
    }
    var glob = { scope: "global" }
    var groups = [g("input", "Microphone", [
      boolS("mic.input.enabled", "Noise and echo processing", glob),
      enumS("mic.input.device", "Input device", [{ value: "default", label: "System default" }, { value: micDevice, label: "USB PnP Sound Device" },
                                                 { value: "alsa_input.pci-0000_00_1f.3.analog-ste…", label: "Built-in" }], glob),
      merged({ id: "mic.input.make_default", label: "Use as default microphone", type: "action", scope: "global", stored: false, enabled: true,
               disabled_reason: "", enabled_when: [] }, {}),
      merged({ id: "mic.input.restore_default", label: "Use the previous default microphone", type: "action", scope: "global", stored: false,
               enabled: false, disabled_reason: "The Omarchy Broadcast Mic was not made the default here", enabled_when: [] }, {})])]
    if (!opt.modules) return groups
    var off = opt.voice ? { enabled: false, disabled_reason: "Studio voice already removes noise and echo" } : {}
    groups.push(g("noise", "Noise removal", [boolS("mic.noise.enabled", "Noise removal", merged({ scope: "global" }, off)),
                                             intS("mic.noise.strength", "Strength", merged({ scope: "global", min: 0, max: 100, value: 100, "default": 100, unit: "%" }, off))]))
    groups.push(g("voice", "Studio voice", [boolS("mic.voice.enabled", "Studio voice (adds noticeable delay)", { scope: "global", value: opt.voice }),
                                            enumS("mic.voice.profile", "Mic profile", [{ value: "passthrough", label: "None" }, { value: "bright", label: "Bright" }],
                                                  { scope: "global" })]))
    return groups
  }
  function micRecord(o, g, setOpt) {
    return feedAll(snap(rev13(o)), setLines(brioGroups().concat(globalGroups()).concat(micGroups(g)), setOpt)).record
  }

  function test_mic_snapshot_and_lines() {
    var r = snap(rev13({}))
    compare(r.micField, "object")
    compare(JSON.stringify(r.mic), JSON.stringify({ state: "active", rawState: "active", consumers: 2, provider: "mic-denoise: NVIDIA Maxine AFX (GPU)",
                                                    latencyMs: 20, error: "" }))
    var res = Model.reduce(r, line(micLine({ state: "passthrough", consumers: 0, provider: "", latency_ms: 0 })))
    compare(res.outcome, "mic")
    compare(res.record.mic.state, "passthrough")
    compare(res.record.mic.consumers, 0)
    compare(r.mic.state, "active", "records are never mutated")
    // a state line keeps the microphone; a snapshot replaces it
    compare(Model.reduce(res.record, line(stateObject({ interface_revision: 13 }))).record.mic.state, "passthrough")
    compare(Model.reduce(res.record, line(snapshotObject(rev13({ mic: micObj({ state: "off" }) })))).record.mic.state, "off")
    // a daemon below revision 13 (null) and a CLI that predates it (absent)
    var old = snap(rev9({ mic: null }))
    compare(old.micField, "null")
    compare(old.mic, null)
    compare(snap(rev9({})).micField, "absent")
    // not linked: ignored
    compare(Model.reduce(Model.emptyRecord("not-running"), line(micLine())).outcome, "ignored")
    compare(Model.reduce(Model.emptyRecord("connecting"), line(micLine())).record.mic, null)
    // hostile fields
    var h = Model.reduce(r, line(micLine({ state: "<b>dancing</b>", consumers: -3, provider: "<img src=x>‮GPU", latency_ms: "20", error: 7 }))).record.mic
    compare(h.state, "unknown")
    compare(h.rawState, "bdancing/b")
    compare(h.consumers, -1)
    compare(h.provider, "img src=xGPU")
    compare(h.latencyMs, null)
    compare(h.error, "")
    compare(Model.reduce(r, line(micLine({ latency_ms: 1e9 }))).record.mic.latencyMs, null, "past STAT_MAX: unknown")
  }

  function test_mic_supported_and_hints() {
    compare(Model.micSupported(snap(rev13({}))), true)
    compare(Model.micMissingText(snap(rev13({}))), "")
    compare(Model.micSupported(snap(rev9({ mic: null }))), false)
    compare(Model.micMissingText(snap(rev9({ mic: null }))), Model.DAEMON_NO_MIC)
    compare(Model.micMissingText(snap(rev9({}))), Model.DAEMON_NO_MIC, "an old daemon, whatever the CLI")
    var noField = snapshotObject(rev13({}))
    delete noField.mic
    compare(Model.micMissingText(Model.reduce(Model.emptyRecord("connecting"), line(noField)).record), Model.CLI_NO_MIC)
    compare(Model.micMissingText(snap(rev13({ mic: null }))), Model.DAEMON_NO_MIC)
    compare(Model.micMissingText(snap(rev13({ interface_revision: "13" }))), Model.DAEMON_NO_MIC, "an unknown revision counts as no")
    compare(Model.micMissingText(Model.emptyRecord("not-running")), "", "unavailable: the panel says why")
    var v = Model.micView(snap(rev9({})))
    compare(v.visible, false)
    compare(v.hint, Model.DAEMON_NO_MIC)
    compare(Model.micSettingsView(snap(rev9({})), {}).visible, false)
    compare(Model.micIndicator(snap(rev9({}))).visible, false)
  }

  function test_mic_view_rows() {
    var v = Model.micView(snap(rev13({})))
    compare(v.visible, true)
    compare(v.hostOn, true)
    compare(JSON.stringify(v.rows), JSON.stringify([{ label: "State", value: "Processing" }, { label: "Consumers", value: "2 apps" },
                                                    { label: "Added delay", value: "20.0 ms" }]))
    compare(v.runsOn, "Runs on: mic-denoise: NVIDIA Maxine AFX (GPU)")
    compare(v.error, "")
    var pass = Model.micView(snap(rev13({ mic: micObj({ state: "passthrough", consumers: 1, provider: "", latency_ms: 0 }) })))
    compare(JSON.stringify(pass.rows.map(function(x) { return x.value })), JSON.stringify(["On, not processed", "1 app", "None"]))
    compare(pass.runsOn, "", "nothing processes it")
    // the delay and the module are shown only while processing or starting
    var passStale = Model.micView(snap(rev13({ mic: micObj({ state: "passthrough", consumers: 1, provider: "stale", latency_ms: 20 }) })))
    compare(passStale.rows[2].value, "None", "not processed: no added delay")
    compare(passStale.runsOn, "", "and no module")
    var starting = Model.micView(snap(rev13({ mic: micObj({ state: "starting", latency_ms: 20 }) })))
    compare(starting.rows[2].value, "20.0 ms")
    compare(starting.runsOn, "Runs on: mic-denoise: NVIDIA Maxine AFX (GPU)")
    var off = Model.micView(snap(rev13({ mic: micObj({ state: "off", consumers: 0, provider: "x", latency_ms: 12 }) })))
    compare(off.hostOn, false)
    compare(JSON.stringify(off.rows.map(function(x) { return x.value })), JSON.stringify(["Off", "None", "None"]))
    compare(off.runsOn, "")
    var err = Model.micView(snap(rev13({ mic: micObj({ state: "error", error: "The audio worker is not installed" }) })))
    compare(err.rows[0].value, "Error")
    compare(err.rows[2].value, "None", "an error: no added delay")
    compare(err.runsOn, "", "and no module")
    compare(err.error, "The audio worker is not installed")
    compare(Model.micView(snap(rev13({ mic: micObj({ state: "warming" }) }))).rows[0].value, "warming", "a later state as the daemon words it")
    compare(Model.micView(snap(rev13({ mic: micObj({ consumers: -1, latency_ms: -1 }) }))).rows[1].value, Model.UNKNOWN)
    compare(Model.micView(Model.emptyRecord("not-running")).visible, false)
    compare(Model.micView(Model.emptyRecord("not-running")).hint, "")
  }

  function test_mic_settings_routed_by_surface() {
    var r = micRecord({ cameras: [cameraObjects()[0]] })
    var ids = function(v) { return JSON.stringify(v.groups.map(function(g) { return g.id })) }
    compare(ids(Model.micSettingsView(r, {})), JSON.stringify(["input", "noise", "voice"]), "the Mic tab draws the mic groups")
    compare(ids(Model.effectSettingsView(r, {})), JSON.stringify(["background", "video"]), "the Effect tab does not")
    compare(ids(Model.settingsView(r, {}, {})), JSON.stringify(["image", "white_balance", "exposure", "focus"]), "nor the Camera tab")
    var v = Model.micSettingsView(r, {})
    compare(v.visible, true)
    compare(v.collapsible, false)
    compare(v.reset, false)
    compare(v.title, "")
    compare(v.note, "")
    compare(v.truncation, "")
    compare(JSON.stringify(v.groups[0].rows.map(function(x) { return x.widget })), JSON.stringify(["switch", "dropdown", "action", "action"]))
    compare(v.rowCount, 8)
    // the device's choices: node names, but never a clipped one
    var device = Model.viewRow(v, 1)
    compare(JSON.stringify(device.options.map(function(o) { return o.value })), JSON.stringify(["default", micDevice]))
    compare(device.optionsNote, "")
    // the restore action greyed with the daemon's reason
    compare(Model.viewRow(v, 3).enabled, false)
    compare(Model.viewRow(v, 3).reason, "The Omarchy Broadcast Mic was not made the default here")
    // studio voice on: noise removal greyed with the daemon's reason, its label says what it costs
    var sv = Model.micSettingsView(micRecord({}, { voice: true }), {})
    compare(Model.viewRow(sv, 4).enabled, false)
    compare(Model.viewRow(sv, 4).reason, "Studio voice already removes noise and echo")
    compare(Model.viewRow(sv, 6).label, "Studio voice (adds noticeable delay)")
    // no audio module: only the daemon's own group, and the note
    var none = Model.micSettingsView(micRecord({}, { modules: false }), {})
    compare(ids(none), JSON.stringify(["input"]))
    compare(none.note, Model.MIC_NO_MODULES_TEXT)
    compare(Model.micSettingsView(micRecord({ mic: micObj({ state: "off" }) }, { modules: false }), {}).note, Model.MIC_NO_MODULES_OFF_TEXT,
            "the switch is off: only that none is installed")
    compare(Model.MIC_NO_MODULES_OFF_TEXT, "No microphone modules installed")
    // no mic group at all (the worker never answered): the note alone
    var empty = Model.micSettingsView(withGlobals(rev13({})), {})
    compare(empty.groups.length, 0)
    compare(empty.note, Model.MIC_NO_MODULES_TEXT)
    compare(empty.visible, true)
    compare(Model.micSettingsShown(empty), false)
    // still loading: nothing said
    compare(Model.micSettingsView(snap(rev13({})), {}).visible, false)
    // an older daemon gives no surface: the groups stay where they were drawn (the Effect tab)
    var plain = micRecord({}, { surface: undefined })
    compare(ids(Model.effectSettingsView(plain, {})), JSON.stringify(["background", "video", "input", "noise", "voice"]))
    compare(Model.micSettingsView(plain, {}).groups.length, 0)
    // without the mic surface a node name is no option value
    compare(JSON.stringify(Model.findSetting(plain, "mic.input.device").options.map(function(o) { return o.value })), JSON.stringify(["default"]))
    // an unknown surface, or the mic surface on camera settings: drawn by scope
    var odd = feedAll(snap(rev13({})), setLines([{ id: "x", label: "X", surface: "captions", settings: [boolS("effect.x.on", "On", { scope: "global" })] },
                                                  { id: "y", label: "Y", surface: "mic", settings: [boolS("camera.y.on", "On")] }])).record
    compare(ids(Model.effectSettingsView(odd, {})), JSON.stringify(["x"]))
    compare(ids(Model.settingsView(odd, {}, {})), JSON.stringify(["y"]))
    compare(Model.micSettingsView(odd, {}).groups.length, 0)
    // a group id may repeat across places: told apart by surface
    var twin = feedAll(snap(rev13({})), setLines([{ id: "noise", label: "Video noise", settings: [boolS("effect.noise.on", "On", { scope: "global" })] },
                                                  { id: "noise", label: "Noise removal", surface: "mic", settings: [boolS("mic.noise.enabled", "On", { scope: "global" })] }])).record
    compare(rowIds(twin.settings), JSON.stringify(["noise:1", "noise:1"]))
    compare(Model.effectSettingsView(twin, {}).groups[0].label, "Video noise")
    compare(Model.micSettingsView(twin, {}).groups[0].label, "Noise removal")
  }

  function test_mic_settings_caps_and_deltas() {
    // the mic groups have caps of their own: the effects' never crowd them out
    var many = []
    for (var i = 0; i < 18; i++) many.push({ id: "fx" + i, label: "Fx " + i, settings: [boolS("effect.fx" + i + ".on", "On", { scope: "global" })] })
    for (var j = 0; j < 17; j++) many.push({ id: "m" + j, label: "M " + j, surface: "mic", settings: [boolS("mic.m" + j + ".on", "On", { scope: "global" })] })
    var r = feedAll(snap(rev13({ active_camera: "", cameras: [] })), setLines(many, { camera: "", per: 1 })).record
    compare(Model.effectSettingsView(r, {}).groups.length, Model.SETTINGS_GROUP_CAP)
    var v = Model.micSettingsView(r, {})
    compare(v.groups.length, Model.SETTINGS_GROUP_CAP)
    compare(v.truncation, "Showing 16 of 17 groups")
    compare(r.settings.micGroupsTotal, 17)
    compare(r.settings.globalGroupsTotal, 18)
    // "Showing N of M groups": M counts only the groups the view can draw (the
    // fifth is past the set's 64 rows: no row to show, so never drawn)
    var wide = []
    for (var w = 0; w < 5; w++) {
      var ws = []
      for (var x = 0; x < 16; x++) ws.push(boolS("mic.w" + w + ".s" + x, "S" + x, { scope: "global" }))
      wide.push({ id: "w" + w, label: "W " + w, surface: "mic", settings: ws })
    }
    var rw = feedAll(snap(rev13({ active_camera: "", cameras: [] })), setLines(wide, { camera: "", per: 16 })).record
    compare(rw.settings.micGroupsTotal, 5)
    var vw = Model.micSettingsView(rw, {})
    compare(vw.groups.length, 4)
    compare(vw.truncation, "", "the undrawn group is not counted")
    // a delta keeps the surface, and moves a mic row
    var m = micRecord({})
    var d = Model.reduce(m, line(deltaLine([{ id: "mic.noise.enabled", value: false, stored: true }]))).record
    compare(d.settings.micGroupsTotal, 3)
    compare(Model.findSetting(d, "mic.noise.enabled").value, false)
    compare(Model.micSettingsView(d, {}).groups.length, 3, "still the Mic tab's")
    // a draft shows on a mic row
    var drafts = {}
    drafts["mic.input.device"] = micDevice
    compare(Model.viewRow(Model.micSettingsView(m, drafts), 1).valueText, "USB PnP Sound Device")
  }

  function test_mic_setting_argv() {
    var r = micRecord({})
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: "mic.input.device", value: micDevice, camera: brioId, scope: "global" }, cli, r)),
            JSON.stringify([cli, "settings", "set", "--", "mic.input.device", micDevice]), "a node name, no camera named")
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: "mic.input.make_default", value: true, camera: "", quick: true }, cli, r)),
            JSON.stringify([cli, "settings", "set", "--", "mic.input.make_default", "true"]), "an action, bound to no camera")
    compare(Model.intentArgv({ verb: "setting", id: "mic.input.restore_default", value: true, camera: "" }, cli, r), null, "greyed: not run")
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: "mic.noise.strength", value: 42, camera: "" }, cli, r)),
            JSON.stringify([cli, "settings", "set", "--", "mic.noise.strength", "42"]))
    compare(Model.intentArgv({ verb: "setting", id: "mic.input.device", value: "alsa_input.other", camera: "" }, cli, r), null, "not one of its options")
    // the wider word grammar is the mic's only
    compare(Model.settingArgvGlobal(cli, "effect.x.y", micDevice), null)
    compare(JSON.stringify(Model.settingArgvMic(cli, "mic.input.device", micDevice)), JSON.stringify([cli, "settings", "set", "--", "mic.input.device", micDevice]))
    var bad = ["", "-rf", "a b", "a\nb", "x…", "a;b", "$(x)", "a".repeat(129), "_x"]
    for (var i = 0; i < bad.length; i++) compare(Model.settingArgvMic(cli, "mic.input.device", bad[i]), null, JSON.stringify(bad[i]))
    compare(Model.settingArgvMic("relative", "mic.input.device", micDevice), null)
    compare(Model.settingArgvMic(cli, "Mic.Input", micDevice), null)
    // an old daemon: nothing is written to a mic row it never sent
    compare(Model.intentArgv({ verb: "setting", id: "mic.input.device", value: micDevice, camera: "" }, cli, withGlobals({})), null)
  }

  function test_mic_host_argv_and_queue() {
    var r = snap(rev13({}))
    compare(JSON.stringify(Model.micHostArgv(cli, true)), JSON.stringify([cli, "mic", "on"]))
    compare(JSON.stringify(Model.micHostArgv(cli, false)), JSON.stringify([cli, "mic", "off"]))
    compare(Model.micHostArgv(cli, "on"), null)
    compare(Model.micHostArgv("", true), null)
    compare(JSON.stringify(Model.intentArgv({ verb: "mic-host", on: false }, cli, r)), JSON.stringify([cli, "mic", "off"]))
    compare(Model.intentArgv({ verb: "mic-host", on: true }, cli, snap(rev9({}))), null, "an old daemon: never run")
    compare(Model.intentArgv({ verb: "mic-host", on: true }, cli, Model.emptyRecord("not-running")), null, "never D-Bus-activates a stopped daemon")
    // the queue: the latest mic ask wins, goes first, and leaves the camera's asks alone
    var sel = { verb: "select", id: fhdId }
    var slider = { verb: "setting", id: "mic.noise.strength", value: 40, camera: "", scope: "global" }
    var q = Model.enqueueIntent([], sel)
    q = Model.enqueueIntent(q, slider)
    q = Model.enqueueIntent(q, { verb: "mic-host", on: true })
    q = Model.enqueueIntent(q, { verb: "mic-host", on: false })
    compare(JSON.stringify(q.map(function(x) { return x.verb + (x.on === undefined ? "" : ":" + x.on) })), JSON.stringify(["mic-host:false", "select", "setting"]))
    q = Model.enqueueIntent(q, { verb: "next" })
    compare(JSON.stringify(q.map(function(x) { return x.verb })), JSON.stringify(["mic-host", "setting", "next"]), "another ask replaces the select, not the mic")
    q = Model.enqueueIntent(q, { verb: "enable", on: false })
    compare(JSON.stringify(q.map(function(x) { return x.verb })), JSON.stringify(["enable", "mic-host", "setting"]),
            "turning the camera off still goes first, and replaces the other ask only")
    // the mic's on/off never holds the camera's switch, and holds its own
    compare(Model.toggleBlocked({ verb: "mic-host", on: true }, []), false)
    compare(Model.toggleBlocked(null, [{ verb: "mic-host", on: true }]), false)
    compare(Model.micBlocked({ verb: "mic-host", on: true }, []), true)
    compare(Model.micBlocked(null, [sel, { verb: "mic-host", on: true }]), true)
    compare(Model.micBlocked({ verb: "enable", on: true }, [sel]), false)
    compare(Model.queueTakes([], { verb: "mic-host", on: true }), true)
    compare(Model.INTENT_QUEUE_CAP, Model.SETTING_QUEUE_CAP + Model.QUICK_QUEUE_CAP + Model.ACTION_QUEUE_CAP + Model.SETUP_QUEUE_CAP + Model.MIC_QUEUE_CAP + 2)
  }

  function test_mic_indicator() {
    var on = Model.micIndicator(snap(rev13({})))
    compare(on.visible, true)
    compare(on.glyph, String.fromCodePoint(0xF036C))
    compare(on.tooltip, "Omarchy Broadcast Mic: processing · 2 apps recording")
    compare(on.urgent, false)
    compare(Model.micIndicator(snap(rev13({ mic: micObj({ consumers: 1, state: "passthrough" }) }))).tooltip,
            "Omarchy Broadcast Mic: on, not processed · 1 app recording")
    var err = Model.micIndicator(snap(rev13({ mic: micObj({ state: "error", error: "The worker crashed" }) })))
    compare(err.urgent, true)
    compare(err.tooltip, "Omarchy Broadcast Mic: error · 2 apps recording · error: The worker crashed")
    compare(Model.micIndicator(snap(rev13({ mic: micObj({ consumers: 0 }) }))).visible, false, "nobody records")
    compare(Model.micIndicator(snap(rev13({ mic: micObj({ consumers: -1 }) }))).visible, false, "unknown")
    compare(Model.micIndicator(snap(rev13({ mic: micObj({ state: "off", consumers: 3 }) }))).visible, false, "the host is off")
    compare(Model.micIndicator(Model.emptyRecord("not-running")).visible, false)
    compare(Model.micIndicator(snap(rev13({ state: "off", enabled: false }))).visible, true, "whatever the camera does")
    // the line moves it, nothing polls
    var r = Model.reduce(snap(rev13({ mic: micObj({ consumers: 0 }) })), line(micLine({ consumers: 1 }))).record
    compare(Model.micIndicator(r).visible, true)
    compare(Model.micClickAction("left", false), "open-mic", "the panel opens on the Mic tab")
    compare(Model.micClickAction("left", true), "close", "an open panel closes")
    compare(Model.micClickAction("left"), "open-mic")
    compare(Model.micClickAction("right", true), "setup")
    compare(Model.micClickAction("right", false), "setup")
    compare(Model.micClickAction("middle", true), "ignore")
    compare(Model.micClickAction("middle", false), "ignore")
  }

  // Device names to 128 characters, as the daemon and the CLI carry them.
  function test_mic_long_node_names() {
    var k66 = "alsa_input.usb-K66_K66_20190805V001-00.analog-stereo"
    verify(k66.length > 32 && k66.length < 128)
    compare(Model.optionValueOf(k66, Model.MIC_SURFACE), k66)
    compare(Model.optionValueOf("a".repeat(128), Model.MIC_SURFACE), "a".repeat(128))
    compare(Model.optionValueOf("a".repeat(129), Model.MIC_SURFACE), "", "past 128")
    compare(Model.optionValueOf(k66, ""), "", "never another surface's")
    compare(JSON.stringify(Model.settingArgvMic(cli, "mic.input.device", k66)), JSON.stringify([cli, "settings", "set", "--", "mic.input.device", k66]))
    compare(Model.settingArgvMic(cli, "mic.input.device", "a".repeat(129)), null)
    var groups = micGroups({})
    groups[0].settings[1] = enumS("mic.input.device", "Input device", [{ value: "default", label: "System default" }, { value: k66, label: "K66" }],
                                  { scope: "global" })
    var r = feedAll(snap(rev13({})), setLines(brioGroups().concat(globalGroups()).concat(groups), {})).record
    var device = Model.viewRow(Model.micSettingsView(r, {}), 1)
    compare(JSON.stringify(device.options.map(function(o) { return o.value })), JSON.stringify(["default", k66]), "offered, not clipped")
    compare(JSON.stringify(Model.intentArgv({ verb: "setting", id: "mic.input.device", value: k66, camera: "", scope: "global" }, cli, r)),
            JSON.stringify([cli, "settings", "set", "--", "mic.input.device", k66]))
  }

  function test_mic_set_key_ignores_the_camera() {
    var a = micRecord({ cameras: [cameraObjects()[0]] })
    var v = Model.micSettingsView(a, {})
    verify(v.setKey.indexOf(String(a.settings.camera)) < 0 || a.settings.camera === "", "no camera in the key")
    compare(v.setKey, JSON.stringify(["mic", a.settings.serial]))
  }

  function test_mic_tab_stops() {
    var r = micRecord({ cameras: [cameraObjects()[0]] })
    var mv = Model.micSettingsView(r, {})
    var stops = Model.cursorStops(r, 1, false, "mic", Model.settingsView(r, {}, {}), Model.effectSettingsView(r, {}), mv)
    compare(kindsOf(stops), JSON.stringify(["switch", "tabs", "mic-host", "setting", "setting", "setting", "setting", "setting", "setting", "setting", "setting"]))
    compare(JSON.stringify(stops.slice(3).map(function(s) { return s.index })), JSON.stringify([0, 1, 2, 3, 4, 5, 6, 7]))
    compare(Model.stopIndex(stops, "mic-host", -1), 2)
    compare(kindsOf(Model.cursorStops(snap(rev9({})), 1, false, "mic")), JSON.stringify(["switch", "tabs"]), "an old daemon: no control")
    compare(kindsOf(Model.cursorStops(r, 1, false, "status")), JSON.stringify(["switch", "tabs"]))
    compare(Model.stopIndex(Model.cursorStops(r, 1, false, "camera"), "mic-host", -1), -1, "another tab's stop")
  }

  function test_module_kind_and_mic_pins() {
    var list = Model.readModules(moduleLines([moduleObj("br.com.dias.maxine-afx", { kind: "audio-filter", stages: [
      { id: "mic-denoise", slot: "clean", rank: 300, device: "nvidia-gpu", available: true, reason: "", selected: true }] }),
      moduleObj("org.example.odd", { kind: "<b>sensor</b>" }), moduleObj("org.example.old", { kind: undefined, stages: [] })]), 0, "")
    compare(JSON.stringify(list.modules.map(function(m) { return m.kind })), JSON.stringify(["audio-filter", "bsensor/b", ""]))
    var setup = Model.withSetupRead(fullSetup(), "modules", list)
    var rows = Model.modulesSectionView(setup, setupRecord(13)).rows
    compare(JSON.stringify(rows.map(function(x) { return x.stagesText })),
            JSON.stringify(["Microphone effect · Stages: mic-denoise", "bsensor/b · Stages: background", ""]), "an older daemon: no kind")
    compare(Model.moduleKindText("analyser"), "Analyser")
    compare(Model.moduleKindText("constructor"), "constructor", "never an inherited member")
    // the Backends section shows the mic stages' pins as any other
    var groups = cfgGroups()
    groups[4].settings.push(cfgRow("modules.pin.mic-denoise", "enum", { label: "Module for mic-denoise", value: "", "default": "", apply: "reload",
      options: [{ value: "", label: "Automatic" }, { value: "br.com.dias.maxine-afx", label: "NVIDIA Maxine AFX" }, { value: "br.com.dias.voice-cpu", label: "DeepFilterNet" }] }))
    var back = Model.backendsSectionView(Model.withSetupRead(setup, "config", Model.readConfig(configLines(groups), 0, "")), setupRecord(13))
    compare(JSON.stringify(back.groups[0].rows.map(function(x) { return x.id })),
            JSON.stringify(["modules.profile", "modules.pin.background", "modules.pin.mic-denoise"]))
  }

  function test_module_stage_resolution_refusals() {
    var long = new Array(300).join("x")
    var list = Model.readModules(moduleLines([moduleObj("a.res", { stages: [
      { id: "denoise-x", slot: "a", rank: 1, device: "cpu", available: false, reason: "Needs denoise", selected: false },
      { id: "matte-y", slot: "b", rank: 1, device: "cpu", available: false, reason: "Needs the cut-out of the module that provides it", selected: false },
      { id: "long", slot: "c", rank: 1, device: "cpu", available: false, reason: long, selected: false }] })]), 0, "")
    var n = Model.modulesSectionView(Model.withSetupRead(fullSetup(), "modules", list), setupRecord(13)).rows[0].stageNotes.split("\n")
    compare(n[0], "denoise-x: Needs denoise")
    compare(n[1], "matte-y: Needs the cut-out of the module that provides it")
    verify(n[2].length <= 64 + 2 + 96, "a long reason is clipped")
  }

  function test_module_forced_and_stage_notes() {
    var refused = { id: "cutout", slot: "matte", rank: 1, device: "cpu", available: false, reason: "Cannot run together with noise removal", selected: false }
    var list = Model.readModules(moduleLines([
      moduleObj("a.forced", { forced: true }), moduleObj("a.plain", { forced: false }), moduleObj("a.garbage", { forced: "true" }),
      moduleObj("a.older", { forced: undefined }),
      moduleObj("a.refused", { stages: [refused, { id: "bare", slot: "x", rank: 1, device: "cpu", available: false }] }),
      moduleObj("a.off", { status: "disabled", enabled: false, reason: "Disabled", stages: [refused] }),
      moduleObj("a.unavail", { status: "unavailable", reason: "Needs the module x.y", stages: [refused] })]), 0, "")
    compare(JSON.stringify(list.modules.map(function(m) { return m.forced })), JSON.stringify([true, false, false, false, false, false, false]))
    compare(list.modules[4].stages[0].available, false)
    compare(list.modules[4].stages[0].reason, "Cannot run together with noise removal")
    var rows = Model.modulesSectionView(Model.withSetupRead(fullSetup(), "modules", list), setupRecord(13)).rows
    compare(rows[0].statusLine, "Available")
    compare(rows[0].forcedText, "Forced: conflicts are not enforced (debug override)")
    compare(rows[0].forcedText, Model.MODULE_FORCED_TEXT)
    compare(rows[0].forced, true)
    compare(rows[1].statusLine, "Available")
    compare(rows[1].forcedText, "")
    compare(rows[2].forced, false, "only a strict true")
    compare(rows[3].statusLine, "Available", "an older daemon")
    compare(rows[3].forcedText, "")
    compare(rows[0].stageNotes, "")
    compare(rows[4].stageNotes, "cutout: Cannot run together with noise removal\nbare: unavailable")
    compare(rows[5].stageNotes, "", "a disabled module: its own reason says why")
    compare(rows[6].stageNotes, "", "an unavailable module too")
  }
}
