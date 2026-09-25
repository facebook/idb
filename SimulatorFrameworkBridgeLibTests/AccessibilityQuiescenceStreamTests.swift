/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation
@_implementationOnly import SimulatorFrameworkBridgeProtocol
@_implementationOnly import SimulatorFrameworkBridgeRuntime
@_implementationOnly import SimulatorFrameworkBridgeSupport
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
    sendData(data: try frame(command: .accessibility(payload)), to: client)
    return client
  }

  /// The accessibility envelope a streamed frame carries.
  private func readEvent(fd: Int32) -> NSDictionary? {
    ((readResponse(fd: fd)?["result"] as? NSDictionary)?["values"] as? [Any])?.first as? NSDictionary
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
    let status = FBAccessibilityService.handleAction("quiet", arguments: ["--pid", String(Self.exitedPid)]) { data in
      lines.append((try? JSONSerialization.jsonObject(with: data)) as? NSDictionary ?? [:])
      return true
    }
    XCTAssertEqual(status, 0)
    XCTAssertEqual(lines, [["ok": true, "event": "target_exited", "pid": Self.exitedPid]])

    let lostOutputStatus = FBAccessibilityService.handleAction("quiet", arguments: ["--pid", String(Self.exitedPid)]) { _ in false }
    XCTAssertEqual(lostOutputStatus, 1, "output that could not be written fails the command")
  }

  func testQuietIsRefusedOutsideAStream() {
    XCTAssertEqual(FBAccessibilityService.handleRequest(["verb": "quiet"])["error_kind"] as? String, "bad_request")
  }

  func testTheTunablesParseFromArgv() {
    let request = FBAXBridgeArguments.request(action: "quiet", arguments: ["--busy-threshold-ms", "5", "--quiet-window-ms", "7", "--pid", "9"])
    XCTAssertEqual(request as NSDictionary, ["verb": "quiet", "busyThresholdMs": 5, "quietWindowMs": 7, "pid": 9])
  }
}
