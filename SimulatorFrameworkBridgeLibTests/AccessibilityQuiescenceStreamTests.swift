/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import FBSimulatorBridgeProtocol
import Foundation
@_implementationOnly import SimulatorFrameworkBridgeRuntime
@_implementationOnly import SimulatorFrameworkBridgeSupport
import UIKit
import XCTest

// Drives `quiet` through a real serve socket against the fake runtime. Thresholds are either generous or
// the thing under test, so scheduling jitter cannot flip an answer.
extension BridgeServerSocketTests {
  private func useRuntime(_ runtime: FBAXFakeRuntime) {
    FBAXClientProvider.setRuntimeForTesting(runtime)
    addTeardownBlock { FBAXClientProvider.setRuntimeForTesting(nil) }
  }

  private func openQuietStream(_ runtime: FBAXFakeRuntime, _ request: [String: BridgeJSONValue]) throws -> Int32 {
    useRuntime(runtime)
    startServerExclusive(exclusive: true)
    let client = connectClient()
    var payload = request
    payload["verb"] = .string("quiet")
    sendData(data: try frame(accessibility: payload), to: client)
    return client
  }

  /// The accessibility envelope a streamed frame carries.
  private func readEvent(fd: Int32) -> NSDictionary? {
    (readResponse(fd: fd)?["result"] as? NSDictionary)?["accessibility"] as? NSDictionary
  }

  // The exclusive server exits once the client hangs up, and must be waited for inside the test body.
  private func closeQuietStream(_ client: Int32) {
    close(client)
    finishServer()
  }

  private func eventually<T>(_ description: String, _ probe: () -> T?) throws -> T {
    let deadline = Date(timeIntervalSinceNow: 5)
    while deadline.timeIntervalSinceNow > 0 {
      if let value = probe() {
        return value
      }
      usleep(1000)
    }
    throw NSError(domain: "AccessibilityQuiescenceStreamTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "timed out waiting for \(description)"])
  }

  private func monitor(of runtime: FBAXFakeRuntime, requests: Int) throws -> FBAXFakeQuiescenceMonitor {
    try eventually("\(requests) quiescence requests") {
      guard let monitor = runtime.quiescenceMonitors.lastObject as? FBAXFakeQuiescenceMonitor, monitor.requests.count >= requests else { return nil }
      return monitor
    }
  }

  private func runtimeWithApplications(_ pids: [pid_t]) -> FBAXFakeRuntime {
    let runtime = FBAXFakeRuntime()
    runtime.automationMode = true
    for pid in pids {
      runtime.applicationElements[NSNumber(value: pid)] = FBAXFakeElement.readable("UIApplication")
    }
    return runtime
  }

  // Above the kernel's highest pid, so certain not to be running.
  private static let exitedPid: pid_t = 99999

  private func state(_ state: String, pid: pid_t, signals: [String]? = nil) -> NSDictionary {
    var event: [String: Any] = ["ok": true, "event": "state", "state": state, "pid": pid]
    event["signals"] = signals
    return event as NSDictionary
  }

  func testANamedApplicationGoesQuietOnceBothSignalsAnswer() throws {
    let pid = getpid()
    let runtime = runtimeWithApplications([pid])
    let client = try openQuietStream(runtime, ["pid": .integer(Int64(pid)), "busyThresholdMs": .integer(5000), "quietWindowMs": .integer(0)])

    let monitor = try monitor(of: runtime, requests: 2)
    let requests = try XCTUnwrap(monitor.requests.copy() as? [[String: Any]])
    let application = runtime.applicationElements[NSNumber(value: pid)] as AnyObject
    XCTAssertEqual(Set(requests.compactMap { ($0["signal"] as? NSNumber)?.uintValue }), [FBAXQuiescenceSignal.runLoopIdle.rawValue, FBAXQuiescenceSignal.animationsInactive.rawValue])
    XCTAssertTrue(requests.allSatisfy { ($0["element"] as AnyObject) === application })
    monitor.deliver(.runLoopIdle, pid: pid)
    monitor.deliver(.animationsInactive, pid: pid)
    XCTAssertEqual(readEvent(fd: client), state("quiet", pid: pid))

    _ = try self.monitor(of: runtime, requests: 4)
    monitor.deliver(.touchesCompleted, pid: pid)
    XCTAssertEqual(readEvent(fd: client), ["ok": true, "event": "touches_completed", "pid": pid])
    closeQuietStream(client)
    XCTAssertTrue(monitor.isInvalidated)
  }

  func testASignalUnansweredPastTheThresholdIsBusyUntilItAnswers() throws {
    let pid = getpid()
    let runtime = runtimeWithApplications([pid])
    let client = try openQuietStream(runtime, ["pid": .integer(Int64(pid)), "busyThresholdMs": .integer(20), "quietWindowMs": .integer(0)])
    defer { closeQuietStream(client) }

    let monitor = try monitor(of: runtime, requests: 2)
    monitor.deliver(.animationsInactive, pid: pid + 1)
    monitor.deliver(.runLoopIdle, pid: pid)
    XCTAssertEqual(readEvent(fd: client), state("busy", pid: pid, signals: ["animations_inactive"]), "an answer for another application is not this one's")
    monitor.deliver(.animationsInactive, pid: pid)
    XCTAssertEqual(readEvent(fd: client), state("quiet", pid: pid))
  }

  // Every client's monitor hears every answer, so a second answer here stands in for another client's.
  func testAnAnswerToAnotherClientsRequestIsNotReArmed() throws {
    let pid = getpid()
    let runtime = runtimeWithApplications([pid])
    let client = try openQuietStream(runtime, ["pid": .integer(Int64(pid)), "busyThresholdMs": .integer(5000), "quietWindowMs": .integer(0)])
    defer { closeQuietStream(client) }

    let monitor = try monitor(of: runtime, requests: 2)
    monitor.deliver(.runLoopIdle, pid: pid)
    monitor.deliver(.runLoopIdle, pid: pid)
    _ = try self.monitor(of: runtime, requests: 3)
    usleep(200_000)
    XCTAssertEqual(monitor.requests.count, 3)
  }

  // Automation mode goes off when another accessibility client exits, and applications drop the requests
  // they are sent while it is off.
  func testAutomationModeTurnedOffMidStreamIsTurnedBackOnAndTheUnansweredSignalsAskedAgain() throws {
    let pid = getpid()
    let runtime = runtimeWithApplications([pid])
    let client = try openQuietStream(runtime, ["pid": .integer(Int64(pid)), "busyThresholdMs": .integer(5000), "quietWindowMs": .integer(0)])
    defer { closeQuietStream(client) }

    _ = try monitor(of: runtime, requests: 2)
    runtime.automationMode = false
    _ = try monitor(of: runtime, requests: 4)
    XCTAssertEqual(runtime.automationModeWrites, [true])
  }

  // Whichever client notices automation mode off turns it back on, so this stream may never see it off.
  func testASignalUnansweredForAHeartbeatIsAskedAgainThoughAutomationModeLooksOn() throws {
    let pid = getpid()
    let runtime = runtimeWithApplications([pid])
    let client = try openQuietStream(runtime, ["pid": .integer(Int64(pid)), "busyThresholdMs": .integer(5000), "quietWindowMs": .integer(0)])
    defer { closeQuietStream(client) }

    _ = try monitor(of: runtime, requests: 4)
    XCTAssertEqual(runtime.automationModeWrites, [])
  }

  func testTheDefaultWindowSettlesBeforeGoingQuiet() throws {
    let pid = getpid()
    let runtime = runtimeWithApplications([pid])
    let client = try openQuietStream(runtime, ["pid": .integer(Int64(pid)), "busyThresholdMs": .integer(5000)])
    defer { closeQuietStream(client) }

    let monitor = try monitor(of: runtime, requests: 2)
    monitor.deliver(.runLoopIdle, pid: pid)
    monitor.deliver(.animationsInactive, pid: pid)
    XCTAssertEqual(readEvent(fd: client), state("settling", pid: pid))
    XCTAssertEqual(readEvent(fd: client), state("quiet", pid: pid))
  }

  func testFollowingTheFrontmostApplicationMovesToTheNextOne() throws {
    let (first, second) = (getpid(), getppid())
    let runtime = runtimeWithApplications([first, second])
    runtime.windowServerOutcome = .resolved(first)
    let client = try openQuietStream(runtime, ["busyThresholdMs": .integer(5000), "quietWindowMs": .integer(0)])
    defer { closeQuietStream(client) }

    let monitor = try monitor(of: runtime, requests: 2)
    monitor.deliver(.runLoopIdle, pid: first)
    monitor.deliver(.animationsInactive, pid: first)
    XCTAssertEqual(readEvent(fd: client), state("quiet", pid: first))

    runtime.windowServerOutcome = .resolved(second)
    let before = monitor.requests.count
    monitor.deliver(.applicationStateChanged, pid: second)
    XCTAssertEqual(readEvent(fd: client), ["ok": true, "event": "target_changed", "pid": second])
    _ = try self.monitor(of: runtime, requests: before + 2)
    monitor.deliver(.runLoopIdle, pid: second)
    monitor.deliver(.animationsInactive, pid: second)
    XCTAssertEqual(readEvent(fd: client), state("quiet", pid: second))
  }

  func testFollowingTheFrontmostApplicationOnANamedDisplayAsksThatDisplay() throws {
    let (first, second) = (getpid(), getppid())
    let runtime = runtimeWithApplications([first, second])
    runtime.windowServerOutcome = .resolved(first)
    let client = try openQuietStream(runtime, ["displayID": .integer(42), "busyThresholdMs": .integer(5000), "quietWindowMs": .integer(0)])
    defer { closeQuietStream(client) }

    let monitor = try monitor(of: runtime, requests: 2)
    XCTAssertEqual(runtime.lastFrontmostDisplayIdentifier, NSNumber(value: 42))

    runtime.windowServerOutcome = .resolved(second)
    monitor.deliver(.applicationStateChanged, pid: second)
    XCTAssertEqual(readEvent(fd: client), ["ok": true, "event": "target_changed", "pid": second])
    XCTAssertEqual(runtime.lastFrontmostDisplayIdentifier, NSNumber(value: 42), "retargeting stays on the named display")
  }

  func testAMalformedDisplayIsRefusedWithoutStreaming() throws {
    let client = try openQuietStream(runtimeWithApplications([]), ["displayID": .integer(0)])
    defer { closeQuietStream(client) }
    XCTAssertEqual(readEvent(fd: client), ["ok": false, "error": "displayID must be a positive 32-bit integer", "error_kind": "bad_request"])
  }

  func testANamedApplicationThatHasExitedEndsTheStream() throws {
    let pid = Self.exitedPid
    let client = try openQuietStream(runtimeWithApplications([]), ["pid": .integer(Int64(pid))])
    defer { closeQuietStream(client) }
    XCTAssertEqual(readEvent(fd: client), ["ok": true, "event": "target_exited", "pid": pid])
    assertEOF(fd: client)
  }

  func testARunningApplicationWithoutAnElementYetIsArmedOnceItHasOne() throws {
    let pid = getpid()
    let runtime = runtimeWithApplications([])
    let client = try openQuietStream(runtime, ["pid": .integer(Int64(pid)), "busyThresholdMs": .integer(5000), "quietWindowMs": .integer(0)])
    defer { closeQuietStream(client) }

    _ = try eventually("the monitor") { runtime.quiescenceMonitors.lastObject as? FBAXFakeQuiescenceMonitor }
    runtime.applicationElements[NSNumber(value: pid)] = FBAXFakeElement.readable("UIApplication")
    let monitor = try monitor(of: runtime, requests: 2)
    monitor.deliver(.runLoopIdle, pid: pid)
    monitor.deliver(.animationsInactive, pid: pid)
    XCTAssertEqual(readEvent(fd: client), state("quiet", pid: pid))
  }

  func testAutomationModeIsTurnedOnAndAFailureToIsAnError() throws {
    let runtime = runtimeWithApplications([getpid()])
    runtime.automationMode = false
    runtime.automationModeWriteFails = true
    let client = try openQuietStream(runtime, ["pid": .integer(Int64(getpid()))])
    defer { closeQuietStream(client) }
    let response = try XCTUnwrap(readEvent(fd: client))
    XCTAssertEqual(response["ok"] as? Bool, false)
    XCTAssertEqual(response["error_kind"] as? String, "reader_unavailable")
    assertEOF(fd: client)
    XCTAssertEqual(runtime.automationModeWrites, [true])
  }

  func testAMonitorThatCannotBindIsAnError() throws {
    let runtime = runtimeWithApplications([getpid()])
    runtime.quiescenceMonitorError = "AXObserverCreate failed (-25200)"
    let client = try openQuietStream(runtime, ["pid": .integer(Int64(getpid()))])
    defer { closeQuietStream(client) }
    XCTAssertEqual(readEvent(fd: client), ["ok": false, "error": "AXObserverCreate failed (-25200)", "error_kind": "reader_unavailable"])
    assertEOF(fd: client)
  }

  func testANegativeTunableIsRefusedWithoutStreaming() throws {
    let client = try openQuietStream(runtimeWithApplications([]), ["quietWindowMs": .integer(-1)])
    defer { closeQuietStream(client) }
    let response = try XCTUnwrap(readEvent(fd: client))
    XCTAssertEqual(response["error_kind"] as? String, "bad_request")
    sendData(data: try frame(command: .ping), to: client)
    XCTAssertEqual(exitCode(of: readResponse(fd: client)), 0, "a refused stream leaves the connection serving")
  }

  func testTheOneShotCommandStreamsUntilTheStreamEnds() throws {
    useRuntime(runtimeWithApplications([]))
    var lines: [NSDictionary] = []
    let status = AccessibilityService.handleAction("quiet", arguments: ["--pid", String(Self.exitedPid)]) { data in
      lines.append((try? JSONSerialization.jsonObject(with: data)) as? NSDictionary ?? [:])
      return true
    }
    XCTAssertEqual(status, 0)
    XCTAssertEqual(lines, [["ok": true, "event": "target_exited", "pid": Self.exitedPid]])

    let lostOutputStatus = AccessibilityService.handleAction("quiet", arguments: ["--pid", String(Self.exitedPid)]) { _ in false }
    XCTAssertEqual(lostOutputStatus, 1, "output that could not be written fails the command")
  }

  func testQuietIsRefusedOutsideAStream() {
    XCTAssertEqual(AccessibilityService.handleRequest(["verb": "quiet"])["error_kind"] as? String, "bad_request")
  }

  private func openSettingsStream(_ runtime: FBAXFakeRuntime, setting: String = "reduce-motion") throws -> Int32 {
    useRuntime(runtime)
    startServerExclusive(exclusive: true)
    let client = connectClient()
    sendData(
      data: try frame(command: .accessibility(.deviceSettingChanges(setting))),
      to: client)
    return client
  }

  func testASettingsObserverIsRegisteredBeforeTheInitialReadAndRereadsAuthoritatively() throws {
    let runtime = FBAXFakeRuntime()
    let setting = NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue)
    runtime.deviceSettings[setting] = false
    runtime.deviceSettingReadHandler = {
      runtime.deviceSettingReadHandler = nil
      runtime.deviceSettings[setting] = true
      runtime.deviceSettingMonitor?.deliver()
    }
    let client = try openSettingsStream(runtime)
    defer { closeQuietStream(client) }

    XCTAssertEqual(readEvent(fd: client), ["ok": true, "event": "snapshot", "setting": "reduce-motion", "enabled": false])
    XCTAssertEqual(readEvent(fd: client), ["ok": true, "event": "snapshot", "setting": "reduce-motion", "enabled": true])
    XCTAssertEqual(runtime.operations.compactMap { $0 as? String }.filter { $0 == "settingRead" }.count, 2)
  }

  func testSettingsNotificationBurstsCoalesceIntoOneAuthoritativeReread() throws {
    let runtime = FBAXFakeRuntime()
    let setting = NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue)
    runtime.deviceSettings[setting] = false
    let client = try openSettingsStream(runtime)
    defer { closeQuietStream(client) }
    XCTAssertEqual(readEvent(fd: client)?["enabled"] as? Bool, false)

    runtime.deviceSettings[setting] = true
    for _ in 0..<3 {
      runtime.deviceSettingMonitor?.deliver()
    }
    XCTAssertEqual(readEvent(fd: client)?["enabled"] as? Bool, true)
    XCTAssertEqual(runtime.operations.compactMap { $0 as? String }.filter { $0 == "settingRead" }.count, 2)
  }

  func testAnUnavailableSettingIsTypedAndEndsTheStream() throws {
    let client = try openSettingsStream(FBAXFakeRuntime())
    defer { closeQuietStream(client) }
    XCTAssertEqual(
      readEvent(fd: client),
      ["ok": false, "error": "setting unavailable", "error_kind": "capability_unavailable"])
    assertEOF(fd: client)
  }

  func testOnlyReduceMotionPublishesChanges() throws {
    let client = try openSettingsStream(FBAXFakeRuntime(), setting: "reduce-transparency")
    defer { closeQuietStream(client) }
    XCTAssertEqual(readEvent(fd: client)?["error_kind"] as? String, "capability_unavailable")
    sendData(data: try frame(command: .ping), to: client)
    XCTAssertEqual(exitCode(of: readResponse(fd: client)), 0, "a refused stream leaves the connection serving")
  }

  func testUnavailableNativeSettingObservationIsTyped() throws {
    let runtime = FBAXFakeRuntime()
    runtime.deviceSettingMonitorOutcome = .unavailable("notification unavailable")
    let client = try openSettingsStream(runtime)
    defer { closeQuietStream(client) }
    XCTAssertEqual(readEvent(fd: client), ["ok": false, "error": "notification unavailable", "error_kind": "capability_unavailable"])
    assertEOF(fd: client)
    XCTAssertFalse(runtime.operations.contains { ($0 as? String) == "settingRead" })
  }

  func testSettingObservationIsInvalidatedAfterOutputFailure() {
    let runtime = FBAXFakeRuntime()
    runtime.deviceSettings[NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue)] = false
    useRuntime(runtime)
    let status = AccessibilityService.handleAction("settings-observe", arguments: ["--setting", "reduce-motion"]) { _ in false }
    XCTAssertEqual(status, 1)
    XCTAssertEqual(runtime.deviceSettingMonitor?.isInvalidated, true)
  }

  func testCombinedSettingsPublishCompleteValuesAndObserveOtherDomains() throws {
    let runtime = FBAXFakeRuntime()
    for setting in [FBAXDeviceSetting.reduceMotion, .reduceTransparency, .buttonShapes, .increaseContrast] {
      runtime.deviceSettings[NSNumber(value: setting.rawValue)] = false
    }
    let client = try openSettingsStream(runtime, setting: "state-settings")
    defer { closeQuietStream(client) }
    let initial = try XCTUnwrap(readEvent(fd: client))
    XCTAssertEqual(
      Set(runtime.deviceSettingMonitoredSettings ?? []),
      Set(
        [
          FBAXDeviceSetting.reduceMotion, .reduceTransparency, .buttonShapes, .increaseContrast,
        ].map { NSNumber(value: $0.rawValue) }))
    XCTAssertEqual(initial["enabled"] as? Bool, false)
    let initialSettings = try XCTUnwrap(initial["settings"] as? [String: NSDictionary])
    XCTAssertEqual(Set(initialSettings.keys), ["button-shapes", "reduce-transparency", "increase-contrast"])
    XCTAssertTrue(initialSettings.values.allSatisfy { ($0["enabled"] as? Bool) == false })
    runtime.deviceSettings[NSNumber(value: FBAXDeviceSetting.buttonShapes.rawValue)] = true
    (runtime.deviceSettingMonitors[NSNumber(value: FBAXDeviceSetting.buttonShapes.rawValue)] as? FBAXFakeDeviceSettingMonitor)?.deliver()
    let changed = try XCTUnwrap(readEvent(fd: client)?["settings"] as? [String: NSDictionary])
    XCTAssertEqual(changed["button-shapes"]?["enabled"] as? Bool, true)
    XCTAssertEqual(changed["reduce-transparency"]?["enabled"] as? Bool, false)
  }

  func testCombinedSettingsPreservePerSettingReadFailure() throws {
    let runtime = FBAXFakeRuntime()
    runtime.deviceSettings[NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue)] = false
    let client = try openSettingsStream(runtime, setting: "state-settings")
    defer { closeQuietStream(client) }
    let settings = try XCTUnwrap(readEvent(fd: client)?["settings"] as? [String: NSDictionary])
    XCTAssertEqual(settings["button-shapes"]?["error_kind"] as? String, "capability_unavailable")
    runtime.deviceSettings[NSNumber(value: FBAXDeviceSetting.buttonShapes.rawValue)] = true
    runtime.deviceSettingMonitor?.deliver()
    let recovered = try XCTUnwrap(readEvent(fd: client)?["settings"] as? [String: NSDictionary])
    XCTAssertEqual(recovered["button-shapes"]?["enabled"] as? Bool, true)
  }

  func testCombinedSettingsPreservePartialObservationFailures() throws {
    for (outcome, kind) in [
      (FBAXDeviceSettingMonitorOutcome.unavailable("notification missing"), "capability_unavailable"),
      (FBAXDeviceSettingMonitorOutcome.failed("registration failed"), "reader_unavailable"),
    ] {
      let runtime = FBAXFakeRuntime()
      let motion = NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue)
      let shapes = NSNumber(value: FBAXDeviceSetting.buttonShapes.rawValue)
      let contrast = NSNumber(value: FBAXDeviceSetting.increaseContrast.rawValue)
      for setting in [FBAXDeviceSetting.reduceMotion, .reduceTransparency, .buttonShapes, .increaseContrast] {
        runtime.deviceSettings[NSNumber(value: setting.rawValue)] = false
      }
      runtime.deviceSettingMonitorOutcomes[contrast] = outcome
      var initialReads = 0
      runtime.deviceSettingReadHandler = {
        initialReads += 1
        guard initialReads == 3 else { return }
        runtime.deviceSettingReadHandler = nil
        // Deliver the burst on the stream's thread after all initial values were captured.
        runtime.deviceSettings[motion] = true
        runtime.deviceSettings[shapes] = true
        (runtime.deviceSettingMonitors[motion] as? FBAXFakeDeviceSettingMonitor)?.deliver()
        (runtime.deviceSettingMonitors[shapes] as? FBAXFakeDeviceSettingMonitor)?.deliver()
        (runtime.deviceSettingMonitors[shapes] as? FBAXFakeDeviceSettingMonitor)?.deliver()
      }
      let client = try openSettingsStream(runtime, setting: "state-settings")
      defer {
        closeQuietStream(client)
        XCTAssertTrue(runtime.deviceSettingMonitors.allValues.compactMap { $0 as? FBAXFakeDeviceSettingMonitor }.allSatisfy { $0.isInvalidated })
      }
      let initial = try XCTUnwrap(readEvent(fd: client))
      XCTAssertEqual(initial["enabled"] as? Bool, false)
      let settings = try XCTUnwrap(initial["settings"] as? [String: NSDictionary])
      XCTAssertEqual(Set(settings.keys), ["reduce-transparency", "button-shapes", "increase-contrast"])
      XCTAssertEqual(settings["increase-contrast"]?["error_kind"] as? String, kind)
      XCTAssertEqual(settings["increase-contrast"]?["error"] as? String, outcome.failureReason)
      XCTAssertNil(settings["increase-contrast"]?["enabled"])
      XCTAssertEqual(settings["button-shapes"]?["enabled"] as? Bool, false)
      XCTAssertEqual(settings["reduce-transparency"]?["enabled"] as? Bool, false)
      XCTAssertEqual(runtime.deviceSettingMonitors.count, 3)

      let changed = try XCTUnwrap(readEvent(fd: client))
      XCTAssertEqual(changed["enabled"] as? Bool, true)
      let changedSettings = try XCTUnwrap(changed["settings"] as? [String: NSDictionary])
      XCTAssertEqual(changedSettings["button-shapes"]?["enabled"] as? Bool, true)
      XCTAssertEqual(changedSettings["increase-contrast"]?["error_kind"] as? String, kind)
      XCTAssertNil(changedSettings["increase-contrast"]?["enabled"])
      let operations = runtime.operations.compactMap { $0 as? String }.filter { $0 == "settingMonitor" || $0 == "settingRead" }
      XCTAssertEqual(Array(operations.prefix(4)), Array(repeating: "settingMonitor", count: 4))
      XCTAssertEqual(operations.filter { $0 == "settingRead" }.count, 6)
    }
  }

  func testCombinedSettingsRequireReduceMotionObservation() throws {
    for (outcome, kind) in [
      (FBAXDeviceSettingMonitorOutcome.unavailable("notification missing"), "capability_unavailable"),
      (FBAXDeviceSettingMonitorOutcome.failed("registration failed"), "reader_unavailable"),
    ] {
      let runtime = FBAXFakeRuntime()
      let motion = NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue)
      runtime.deviceSettingMonitorOutcomes[motion] = outcome
      let client = try openSettingsStream(runtime, setting: "state-settings")
      defer { closeQuietStream(client) }
      let failure = try XCTUnwrap(readEvent(fd: client))
      XCTAssertEqual(failure["ok"] as? Bool, false)
      XCTAssertEqual(failure["error_kind"] as? String, kind)
      assertEOF(fd: client)
      XCTAssertEqual(runtime.deviceSettingMonitoredSettings, [motion])
      XCTAssertEqual(runtime.deviceSettingMonitors.count, 0)
      XCTAssertFalse(runtime.operations.contains { ($0 as? String) == "settingRead" })
    }
  }

  func testCombinedSettingsInvalidateAllMonitorsOnSourceOrOutputFailure() {
    for sourceFailure in [false, true] {
      let runtime = FBAXFakeRuntime()
      for setting in [FBAXDeviceSetting.reduceMotion, .reduceTransparency, .buttonShapes, .increaseContrast] {
        runtime.deviceSettings[NSNumber(value: setting.rawValue)] = false
      }
      if sourceFailure { runtime.deviceSettingReadOutcome = .failed("read failed") }
      useRuntime(runtime)
      let status = AccessibilityService.handleAction("settings-observe", arguments: ["--setting", "state-settings"]) { _ in sourceFailure }
      XCTAssertEqual(status, 1)
      XCTAssertEqual(runtime.deviceSettingMonitors.count, 4)
      XCTAssertTrue(runtime.deviceSettingMonitors.allValues.compactMap { $0 as? FBAXFakeDeviceSettingMonitor }.allSatisfy { $0.isInvalidated })
    }
  }

  func testSettingsObserveIsRefusedOutsideAStream() {
    XCTAssertEqual(
      AccessibilityService.handleRequest(["verb": "settings-observe", "setting": "reduce-motion"])["error_kind"] as? String,
      "bad_request")
  }

  func testSettingsCLIReportsSourceFailureEvenWhenOutputSucceeds() throws {
    for (outcome, kind) in [
      (FBAXDeviceSettingOutcome.unavailable("setting unavailable"), "capability_unavailable"),
      (FBAXDeviceSettingOutcome.failed("read failed"), "reader_unavailable"),
    ] {
      let runtime = FBAXFakeRuntime()
      runtime.deviceSettingReadOutcome = outcome
      useRuntime(runtime)
      var lines: [NSDictionary] = []
      let status = AccessibilityService.handleAction("settings-observe", arguments: ["--setting", "reduce-motion"]) { data in
        if let line = try? JSONSerialization.jsonObject(with: data) as? NSDictionary { lines.append(line) }
        return true
      }
      XCTAssertEqual(status, 1, "the stream's failed state must reach the CLI exit status")
      XCTAssertEqual(lines.count, 1)
      XCTAssertEqual(lines.first?["error_kind"] as? String, kind)
    }
  }

  func testSettingsCLIOutputFailureStopsTheStream() {
    let runtime = FBAXFakeRuntime()
    runtime.deviceSettings[NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue)] = false
    useRuntime(runtime)
    let status = AccessibilityService.handleAction("settings-observe", arguments: ["--setting", "reduce-motion"]) { _ in false }
    XCTAssertEqual(status, 1)
  }

  func testTheTunablesParseFromArgv() {
    let request = AXBridgeArguments.request(action: "quiet", arguments: ["--busy-threshold-ms", "5", "--quiet-window-ms", "7", "--pid", "9"])
    XCTAssertEqual(request as NSDictionary, ["verb": "quiet", "busyThresholdMs": 5, "quietWindowMs": 7, "pid": 9])
  }
}
