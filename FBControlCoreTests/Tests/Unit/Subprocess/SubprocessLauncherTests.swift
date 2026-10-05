/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Covers what the `Subprocess` entrypoints provide on top of any launcher:
/// the launcher's exit reaches the caller through the exit policy, output is
/// drained before termination is reported, and an input the launcher cannot
/// connect is rejected before anything is spawned.
struct SubprocessLauncherTests {

  private static let spec = Subprocess(executable: "/usr/bin/fake", arguments: ["--flag"])

  @Test("The launcher is handed the spec, and its exit status is what run reports")
  func exitStatusReachesTheCaller() async throws {
    let launcher = ScriptedLauncher(statLoc: 3 << 8)

    let completed = try await Self.spec.run(on: launcher, output: .closed, error: .closed, exitPolicy: .mustExit([3]))

    #expect(completed.terminationStatus == .exited(3))
    #expect(completed.processIdentifier == ScriptedLauncher.processIdentifier)
    #expect(await launcher.spawned == [Self.spec])
  }

  @Test("The launcher's exit status is subject to the exit policy")
  func exitStatusIsCheckedAgainstThePolicy() async throws {
    let launcher = ScriptedLauncher(statLoc: SIGKILL)

    await #expect(
      throws: SubprocessError.unacceptableTermination(
        status: .signalled(SIGKILL),
        policy: .mustExitZero,
        executable: Self.spec.executable,
        processIdentifier: ScriptedLauncher.processIdentifier)
    ) {
      _ = try await Self.spec.run(on: launcher, output: .closed, error: .closed)
    }
  }

  @Test("Output written just before an immediate exit is fully captured")
  func outputIsDrainedBeforeTermination() async throws {
    let payload = Data(repeating: UInt8(ascii: "x"), count: 12_000) + Data("end\n".utf8)
    let launcher = ScriptedLauncher(statLoc: 0, standardOutputPayload: payload)

    let completed = try await Self.spec.run(on: launcher, output: .data, error: .closed)

    #expect(completed.standardOutput == payload)
  }

  @Test("An input the launcher cannot connect is rejected without spawning")
  func unsupportedInputIsRejectedBeforeSpawning() async throws {
    let launcher = ScriptedLauncher(statLoc: 0, supportsStandardInput: false)

    await #expect(throws: SubprocessError.inputUnsupported(executable: Self.spec.executable)) {
      _ = try await Self.spec.run(on: launcher, output: .closed, error: .closed, input: .data(Data("in".utf8)))
    }
    #expect(await launcher.spawned.isEmpty)
  }

  @Test("A closed input is accepted by a launcher that cannot connect one")
  func closedInputIsAcceptedWithoutStandardInputSupport() async throws {
    let launcher = ScriptedLauncher(statLoc: 0, supportsStandardInput: false)

    let completed = try await Self.spec.run(on: launcher, output: .closed, error: .closed, input: .closed)

    #expect(completed.terminationStatus == .exited(0))
  }
}

/// Stands in for a process that writes its payload to stdout and exits at
/// once with `statLoc`.
private actor ScriptedLauncher: SubprocessLauncher {
  static let processIdentifier: pid_t = 4242

  nonisolated let supportsStandardInput: Bool
  private let statLoc: Int32
  private let standardOutputPayload: Data
  private(set) var spawned: [Subprocess] = []

  init(statLoc: Int32, standardOutputPayload: Data = Data(), supportsStandardInput: Bool = true) {
    self.statLoc = statLoc
    self.standardOutputPayload = standardOutputPayload
    self.supportsStandardInput = supportsStandardInput
  }

  func spawn(
    _ subprocess: Subprocess,
    standardInput: Int32?,
    standardOutput: Int32?,
    standardError: Int32?,
    logger: (any ControlCoreLogger)?
  ) async throws -> LaunchedProcess {
    spawned.append(subprocess)
    if let standardOutput {
      standardOutputPayload.withUnsafeBytes { _ = write(standardOutput, $0.baseAddress, $0.count) }
    }
    let statLoc = statLoc
    return LaunchedProcess(processIdentifier: Self.processIdentifier) { statLoc }
  }
}
