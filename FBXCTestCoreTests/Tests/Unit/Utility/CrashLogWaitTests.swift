/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBXCTestCore
import XCTest

final class CrashLogWaitTests: XCTestCase {

  private struct TimedOut: Error {}

  func testACrashLogThatAppearsInTimeIsReturned() async throws {
    let crash = CrashLogInfo(
      crashPath: "/tmp/sh.crash",
      executablePath: "/bin/sh",
      identifier: "sh",
      processName: "sh",
      processIdentifier: 42,
      parentProcessName: "idb",
      parentProcessIdentifier: 1,
      date: Date(),
      processType: .system,
      exceptionDescription: nil,
      crashedThreadDescription: nil)

    let found = try await StubCrashLogCommands { crash }.notifyOfCrash(matching: CrashLogInfo.predicateForCrashLogs(withProcessID: 42), within: 30, orThrow: TimedOut())

    XCTAssertEqual(found.processIdentifier, 42)
  }

  func testNoCrashLogWithinTheTimeoutFailsWithTheTimeoutError() async throws {
    let start = Date()
    do {
      _ = try await StubCrashLogCommands {
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
        throw CancellationError()
      }.notifyOfCrash(matching: NSPredicate(value: true), within: 0.1, orThrow: TimedOut())
      XCTFail("Expected the wait to time out")
    } catch is TimedOut {
      XCTAssertLessThan(Date().timeIntervalSince(start), 10, "The lookup is cancelled rather than waited out")
    }
  }
}
