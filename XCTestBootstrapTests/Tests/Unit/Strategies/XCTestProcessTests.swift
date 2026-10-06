/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest
@testable import XCTestBootstrap

final class XCTestProcessTests: XCTestCase {

  private struct NoCrashLog: Error {}

  private func awaitExitCodeOfAProcessKilledBySignal(crashLogCommands: (pid_t) -> (any CrashLogCommands)?) async throws -> Int32 {
    let process = try await Subprocess(executable: "/bin/sh", arguments: ["-c", "kill -KILL $$"]).launch(output: .closed, error: .closed)
    return try await XCTestProcess.awaitExitCode(of: process, processName: "sh", completesWithin: 30, crashLogCommands: crashLogCommands(process.processIdentifier), logger: ControlCoreGlobalConfiguration.defaultLogger)
  }

  func testASignalledProcessWithoutCrashLogCommandsFailsWithTheSignal() async throws {
    do {
      _ = try await awaitExitCodeOfAProcessKilledBySignal { _ in nil }
      XCTFail("Expected the wait to fail")
    } catch let ProcessTerminationError.exitedWithSignal(_, processName, signal) {
      XCTAssertEqual(processName, "sh")
      XCTAssertEqual(signal, SIGKILL)
    }
  }

  func testASignalledProcessWithACrashLogFailsWithTheCrash() async throws {
    let crashPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(UUID().uuidString).crash")
    try "raw crash log".write(toFile: crashPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: crashPath) }
    var crash: CrashLogInfo?

    do {
      _ = try await awaitExitCodeOfAProcessKilledBySignal { processIdentifier in
        let crashOfTheProcess = CrashLogInfo(
          crashPath: crashPath,
          executablePath: "/bin/sh",
          identifier: "sh",
          processName: "sh",
          processIdentifier: processIdentifier,
          parentProcessName: "idb",
          parentProcessIdentifier: 1,
          date: Date(),
          processType: .system,
          exceptionDescription: nil,
          crashedThreadDescription: nil)
        crash = crashOfTheProcess
        return StubCrashLogCommands { crashOfTheProcess }
      }
      XCTFail("Expected the wait to fail")
    } catch let XCTestProcessError.crashed(info, rawLog) {
      XCTAssertEqual(info, String(describing: try XCTUnwrap(crash)))
      XCTAssertEqual(rawLog, "raw crash log")
    }
  }

  func testASignalledProcessWithoutACrashLogPointsAtTheDiagnosticReports() async throws {
    do {
      _ = try await awaitExitCodeOfAProcessKilledBySignal { _ in StubCrashLogCommands { throw NoCrashLog() } }
      XCTFail("Expected the wait to fail")
    } catch {
      let description = (error as NSError).localizedDescription
      XCTAssertTrue(description.hasPrefix("xctest process ("), description)
      XCTAssertTrue(description.hasSuffix(") exited abnormally with no crash log, to check for yourself look in ~/Library/Logs/DiagnosticReports"), description)
      let cause = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
      XCTAssertEqual(cause?.domain, (NoCrashLog() as NSError).domain, "The lookup's failure is the cause")
    }
  }

  func testAStalledProcessWhoseStackshotCannotBeSampledIsTerminated() async throws {
    struct SamplingFailed: Error {}
    let process = try await Subprocess(executable: "/bin/sh", arguments: ["-c", "sleep 60"]).launch(output: .closed, error: .closed)
    do {
      _ = try await XCTestProcess.awaitExitCode(of: process, processName: "sh", completesWithin: 0.5, crashLogCommands: nil, logger: ControlCoreGlobalConfiguration.defaultLogger) { _ in
        throw SamplingFailed()
      }
      XCTFail("Expected the wait to fail")
    } catch let XCTestProcessError.stalled(timeout, processIdentifier, stackshot) {
      XCTAssertEqual(timeout, 0.5)
      XCTAssertEqual(processIdentifier, process.processIdentifier)
      XCTAssertTrue(stackshot.hasPrefix("stackshot unavailable: "), stackshot)
    }
    XCTAssertNotEqual(kill(process.processIdentifier, 0), 0, "The stalled process is terminated")
  }
}

/// Answers with `crash` only if it matches the lookup's predicate, so a predicate that misses
/// the crash of the process being waited on fails the lookup.
private struct StubCrashLogCommands: CrashLogCommands {

  private struct CrashDoesNotMatch: Error {}

  let crash: @Sendable () throws -> CrashLogInfo

  func notifyOfCrash(matching predicate: NSPredicate) async throws -> CrashLogInfo {
    let crash = try crash()
    guard predicate.evaluate(with: crash) else {
      throw CrashDoesNotMatch()
    }
    return crash
  }

  func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [CrashLogInfo] {
    fatalError("Not used by XCTestProcess")
  }

  func prune(matching predicate: NSPredicate) async throws -> [CrashLogInfo] {
    fatalError("Not used by XCTestProcess")
  }

  func withFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    fatalError("Not used by XCTestProcess")
  }
}
