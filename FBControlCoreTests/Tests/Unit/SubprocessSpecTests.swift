/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct SubprocessSpecTests {

  @Test("Mutating a copy of a spec leaves the original untouched")
  func specCopiesDoNotAlias() {
    let base = Subprocess(executable: "/usr/bin/true")
    var copy = base
    copy.arguments += ["--flag"]
    copy.environment = .inherit

    #expect(base.arguments.isEmpty)
    #expect(base.environment == .idbDefault)
    #expect(copy.arguments == ["--flag"])
  }

  private static let parent = [
    "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
    "HOME": "/Users/someone",
    "PATH": "/usr/bin:/bin",
    "SECRET_TOKEN": "hunter2",
  ]

  @Test("The default environment passes through only DEVELOPER_DIR, HOME and PATH")
  func idbDefaultFiltersTheParentEnvironment() {
    let resolved = Subprocess.Environment.idbDefault.resolved(against: Self.parent)

    #expect(
      resolved == [
        "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
        "HOME": "/Users/someone",
        "PATH": "/usr/bin:/bin",
      ])
  }

  @Test("An allowlisted variable that is unset in the parent stays unset")
  func idbDefaultDoesNotInventUnsetVariables() {
    let resolved = Subprocess.Environment.idbDefault.resolved(against: ["HOME": "/Users/someone"])

    #expect(resolved == ["HOME": "/Users/someone"])
  }

  @Test("Inheriting passes the parent environment through whole")
  func inheritPassesEverything() {
    let resolved = Subprocess.Environment.inherit.resolved(against: Self.parent)

    #expect(resolved == Self.parent)
  }

  @Test("An exact environment is used verbatim, ignoring the parent")
  func exactIgnoresTheParent() {
    let resolved = Subprocess.Environment.exact(["ONLY": "this"]).resolved(against: Self.parent)

    #expect(resolved == ["ONLY": "this"])
  }

  @Test("Additions overlay the filtered default, winning on conflict")
  func additionsOverlayTheFilteredDefault() {
    let resolved = Subprocess.Environment
      .additions(["EXTRA": "value", "PATH": "/override"])
      .resolved(against: Self.parent)

    #expect(
      resolved == [
        "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
        "HOME": "/Users/someone",
        "PATH": "/override",
        "EXTRA": "value",
      ])
  }
}

/// Pins `TerminationStatus.init(statLoc:)` to the decode in
/// `FBProcessSpawnCommandHelpers`, which `FBSubprocessTerminationTests` pins
/// against real processes.
@Suite
struct TerminationStatusTests {

  @Test(
    "An exit code is decoded from the high byte of the status word",
    arguments: [Int32(0), Int32(1), Int32(3), Int32(149), Int32(255)])
  func exitCodeDecodesFromTheHighByte(code: Int32) {
    #expect(TerminationStatus(statLoc: code << 8) == .exited(code))
  }

  @Test(
    "A termination signal is decoded from the low seven bits",
    arguments: [SIGTERM, SIGKILL, SIGINT])
  func signalDecodesFromTheLowBits(signo: Int32) {
    #expect(TerminationStatus(statLoc: signo) == .signalled(signo))
  }

  @Test("The core-dump flag does not change the decoded signal")
  func coreDumpFlagIsMaskedOut() {
    #expect(TerminationStatus(statLoc: SIGSEGV | 0x80 /* WCOREFLAG */) == .signalled(SIGSEGV))
  }

  @Test("A stopped status word decodes as an exit, matching the engine's decode")
  func stoppedStatusDecodesAsAnExit() {
    // The engine's decode has no stopped branch — `wstatus == 0x7f` falls
    // into the exit path and reads the high byte. It can never receive one
    // (it only resolves on termination), but the decode is reproduced
    // bit-for-bit rather than reinterpreted.
    #expect(TerminationStatus(statLoc: (SIGTSTP << 8) | 0x7f) == .exited(SIGTSTP))
  }
}

@Suite
struct CompletedCheckTests {

  private static func completed(_ status: TerminationStatus) -> Subprocess.Completed<Void, Void> {
    Subprocess.Completed(executable: "/usr/bin/tool", processIdentifier: 42, terminationStatus: status, standardOutput: (), standardError: ())
  }

  private struct DomainError: Error, Equatable {
    let code: Int32
  }

  @Test("A clean exit passes the check without invoking the error builder")
  func cleanExitPasses() throws {
    try Self.completed(.exited(0)).checkExitedCleanly { code in
      Issue.record("The error builder ran for a clean exit")
      return DomainError(code: code)
    }
  }

  @Test("A non-zero exit throws the caller's error, carrying the code")
  func nonZeroExitThrowsTheDomainError() {
    #expect(throws: DomainError(code: 149)) {
      try Self.completed(.exited(149)).checkExitedCleanly { DomainError(code: $0) }
    }
  }

  @Test("A signal throws the termination error naming the process, not the caller's error")
  func signalThrowsTheTerminationError() throws {
    do {
      try Self.completed(.signalled(SIGKILL)).checkExitedCleanly { DomainError(code: $0) }
      Issue.record("Expected the check to throw for a signal")
    } catch let error as FBProcessTerminationError {
      #expect(error.localizedDescription == "Process 42 (tool) exited with signal \(SIGKILL)")
    }
  }

  @Test("A clean exit passes the code-less check without constructing the error")
  func cleanExitPassesTheCodelessCheck() throws {
    try Self.completed(.exited(0)).checkExitedCleanly(orThrow: Self.unexpectedError())
  }

  @Test("A non-zero exit throws the caller's error from the code-less check")
  func nonZeroExitThrowsTheCodelessDomainError() {
    #expect(throws: DomainError(code: 0)) {
      try Self.completed(.exited(149)).checkExitedCleanly(orThrow: DomainError(code: 0))
    }
  }

  @Test("A signal throws the caller's error from the code-less check, not the termination error")
  func signalThrowsTheCodelessDomainError() {
    #expect(throws: DomainError(code: 0)) {
      try Self.completed(.signalled(SIGKILL)).checkExitedCleanly(orThrow: DomainError(code: 0))
    }
  }

  private static func unexpectedError() -> DomainError {
    Issue.record("The error was constructed for a clean exit")
    return DomainError(code: 0)
  }
}

@Suite
struct ExitPolicyTests {

  @Test("mustExitZero accepts only a clean exit")
  func mustExitZeroAcceptsOnlyExitZero() {
    #expect(ExitPolicy.mustExitZero.accepts(.exited(0)))
    #expect(!ExitPolicy.mustExitZero.accepts(.exited(1)))
    #expect(!ExitPolicy.mustExitZero.accepts(.signalled(SIGTERM)))
  }

  @Test("mustExit accepts exactly the listed codes")
  func mustExitAcceptsListedCodesOnly() {
    let policy = ExitPolicy.mustExit([0, 1])

    #expect(policy.accepts(.exited(0)))
    #expect(policy.accepts(.exited(1)))
    #expect(!policy.accepts(.exited(2)))
  }

  @Test("mustExit never accepts a signal, even one whose number is a listed code")
  func mustExitRejectsSignalsRegardlessOfNumber() {
    #expect(!ExitPolicy.mustExit([Int32(SIGTERM)]).accepts(.signalled(SIGTERM)))
  }

  @Test("any accepts every termination, signals included")
  func anyAcceptsEverything() {
    #expect(ExitPolicy.any.accepts(.exited(0)))
    #expect(ExitPolicy.any.accepts(.exited(149)))
    #expect(ExitPolicy.any.accepts(.signalled(SIGKILL)))
  }
}
