/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBXCTestCore
import Foundation
import Testing

@Suite(.serialized)
struct XCTestProcessTests {

  private struct NoCrashLog: Error {}

  private func awaitExitCodeOfAProcessKilledBySignal(crashLogCommands: (pid_t) -> (any CrashLogCommands)?) async throws -> Int32 {
    let process = try await Subprocess(executable: "/bin/sh", arguments: ["-c", "kill -KILL $$"]).launch(output: .closed, error: .closed)
    return try await XCTestProcess.awaitExitCode(of: process, processName: "sh", completesWithin: 30, crashLogCommands: crashLogCommands(process.processIdentifier), logger: ControlCoreGlobalConfiguration.defaultLogger)
  }

  @Test
  func aSignalledProcessWithoutCrashLogCommandsFailsWithTheSignal() async throws {
    do {
      _ = try await awaitExitCodeOfAProcessKilledBySignal { _ in nil }
      Issue.record("Expected the wait to fail")
    } catch let ProcessTerminationError.exitedWithSignal(_, processName, signal) {
      #expect(processName == "sh")
      #expect(signal == SIGKILL)
    }
  }

  @Test
  func aSignalledProcessWithACrashLogFailsWithTheCrash() async throws {
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
      Issue.record("Expected the wait to fail")
    } catch let XCTestProcessError.crashed(info, rawLog) {
      let recordedCrash = try #require(crash)
      #expect(info == String(describing: recordedCrash))
      #expect(rawLog == "raw crash log")
    }
  }

  @Test
  func aSignalledProcessWithoutACrashLogPointsAtTheDiagnosticReports() async throws {
    do {
      _ = try await awaitExitCodeOfAProcessKilledBySignal { _ in StubCrashLogCommands { throw NoCrashLog() } }
      Issue.record("Expected the wait to fail")
    } catch {
      let description = (error as NSError).localizedDescription
      #expect(description.hasPrefix("xctest process ("), "\(description)")
      #expect(description.hasSuffix(") exited abnormally with no crash log, to check for yourself look in ~/Library/Logs/DiagnosticReports"), "\(description)")
      let cause = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
      #expect(cause?.domain == (NoCrashLog() as NSError).domain, "The lookup's failure is the cause")
    }
  }

  @Test
  func aStalledProcessWhoseStackshotCannotBeSampledIsTerminated() async throws {
    struct SamplingFailed: Error {}
    let process = try await Subprocess(executable: "/bin/sh", arguments: ["-c", "sleep 60"]).launch(output: .closed, error: .closed)
    do {
      _ = try await XCTestProcess.awaitExitCode(of: process, processName: "sh", completesWithin: 0.5, crashLogCommands: nil, logger: ControlCoreGlobalConfiguration.defaultLogger) { _ in
        throw SamplingFailed()
      }
      Issue.record("Expected the wait to fail")
    } catch let XCTestProcessError.stalled(timeout, processIdentifier, stackshot) {
      #expect(timeout == 0.5)
      #expect(processIdentifier == process.processIdentifier)
      #expect(stackshot.hasPrefix("stackshot unavailable: "), "\(stackshot)")
    }
    #expect(kill(process.processIdentifier, 0) != 0, "The stalled process is terminated")
  }
}
