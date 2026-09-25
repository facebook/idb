/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeRuntime
import XCTest

final class AccessibilityQuiescenceMonitorTests: XCTestCase {
  private func report(_ notification: UInt32, _ info: Any?) -> FBAXQuiescenceReport? {
    var report = FBAXQuiescenceReport.runLoopIdle
    return FBAXQuiescenceReportForNotification(notification, info, &report) ? report : nil
  }

  func testUserTestingEventsClassifyByEvent() {
    XCTAssertEqual(report(4002, ["event": "RunLoopIsIdle"]), .runLoopIdle)
    XCTAssertEqual(report(4002, ["event": "AnimationsNonActive"]), .animationsInactive)
    XCTAssertEqual(report(4002, ["event": "TouchEventsCompleted"]), .touchesCompleted)
  }

  func testUnrecognisedUserTestingEventsReportNothing() {
    XCTAssertNil(report(4002, ["event": "ViewDidAppear"]))
    XCTAssertNil(report(4002, [:] as [String: Any]))
    XCTAssertNil(report(4002, nil))
    XCTAssertNil(report(4002, "RunLoopIsIdle"))
  }

  func testSuspendedStatusChangesReportAStateChangeWhateverTheStatus() {
    XCTAssertEqual(report(1021, ["pid": 42, "suspended-status": "resumed"]), .applicationStateChanged)
    XCTAssertEqual(report(1021, ["pid": 42, "suspended-status": "tentative-suspended"]), .applicationStateChanged)
  }

  func testOtherNotificationsReportNothing() {
    XCTAssertNil(report(1001, nil))
    XCTAssertNil(report(1069, ["event": "RunLoopIsIdle"]))
  }

  func testTheClientUnwrapsElementsForRequestsAndForwardsReports() throws {
    let runtime = FBAXFakeRuntime()
    let application = FBAXFakeElement.readable("UIApplication")
    runtime.applicationElements[42] = application
    let client = FBAXClient(runtime: runtime)
    var heard: [(FBAXQuiescenceReport, pid_t)] = []

    let monitor = try client.quiescenceMonitor { report, pid in heard.append((report, pid)) }
    let element = try XCTUnwrap(client.applicationElement(forProcessIdentifier: 42).value)
    let outcome = try monitor.request(.animationsInactive, fromApplication: element)

    XCTAssertEqual(outcome.status, .written)
    let fake = try XCTUnwrap(runtime.quiescenceMonitors.firstObject as? FBAXFakeQuiescenceMonitor)
    XCTAssertEqual(fake.requests.count, 1)
    let request = try XCTUnwrap(fake.requests.firstObject as? [String: Any])
    XCTAssertEqual(request["signal"] as? UInt, FBAXQuiescenceSignal.animationsInactive.rawValue)
    XCTAssertTrue(request["element"] as AnyObject === application)

    fake.deliver(.runLoopIdle, pid: 42)
    monitor.invalidate()
    fake.deliver(.animationsInactive, pid: 42)
    XCTAssertTrue(fake.isInvalidated)
    XCTAssertEqual(heard.map(\.0), [.runLoopIdle])
    XCTAssertEqual(heard.map(\.1), [42])
  }

  func testABindFailureIsAnErrorCarryingTheRuntimesReason() {
    let runtime = FBAXFakeRuntime()
    runtime.quiescenceMonitorError = "AXObserverCreate failed (-25200)"

    XCTAssertThrowsError(try FBAXClient(runtime: runtime).quiescenceMonitor { _, _ in }) { error in
      XCTAssertEqual((error as NSError).localizedDescription, "AXObserverCreate failed (-25200)")
    }
  }

  func testARaiseWhileStartingIsContained() {
    let runtime = FBAXFakeRuntime()
    runtime.raiseOnOperation = "quiescenceMonitor"

    XCTAssertThrowsError(try FBAXClient(runtime: runtime).quiescenceMonitor { _, _ in }) { error in
      XCTAssertEqual((error as NSError).domain, "FBAXRuntimeException")
    }
  }

  // Creating an observer inside an app-hosted test process traps in FrontBoardServices, so the live monitor
  // is exercised through a spawned guest instead; this pins only that its entry points are there.
  func testTheQuiescenceEntryPointsResolve() {
    XCTAssertTrue(dlopen(FBAXPathAXRuntime, RTLD_NOW) != nil, "AXRuntime could not be opened")
    for symbol in ["AXObserverCreate", "AXObserverAddNotification", "AXObserverGetRunLoopSource", "AXUIElementPerformActionWithValue"] {
      XCTAssertTrue(dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) != nil, symbol)
    }
  }
}
