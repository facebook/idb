/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest

private actor AsyncGate {
  private var continuations: [CheckedContinuation<Void, Never>] = []
  private var isOpen = false

  func wait() async {
    if isOpen {
      return
    }
    await withCheckedContinuation { continuations.append($0) }
  }

  func open() {
    isOpen = true
    let waiting = continuations
    continuations.removeAll()
    for continuation in waiting {
      continuation.resume()
    }
  }
}

final class FBSimulatorApplicationInstallPreflightTests: XCTestCase {

  private enum TestError: Error {
    case conditionNotMet
  }

  private func installFailure() -> FBSimulatorApplicationError {
    .installFailed(bundleDescription: "an app", options: "no options")
  }

  func testRunningProcessWithoutDebuggerDoesNotBlockInstall() async throws {
    try await FBSimulatorApplicationCommands.confirmApplicationProcessIsInstallable(
      bundleID: "com.example.app",
      resolveProcessIdentifier: { 42 },
      processIsSuspended: { _ in false },
      debuggerIsAttached: { _ in false })
  }

  func testRunningDebuggedProcessBlocksInstall() async {
    do {
      try await FBSimulatorApplicationCommands.confirmApplicationProcessIsInstallable(
        bundleID: "com.example.app",
        resolveProcessIdentifier: { 42 },
        processIsSuspended: { _ in false },
        debuggerIsAttached: { _ in true })
      XCTFail("Expected debugger-attached process error")
    } catch let error as FBSimulatorApplicationError {
      guard case let .applicationProcessDebuggerAttached(bundleID, processIdentifier) = error else {
        return XCTFail("Expected a debugger-attached process error, got \(error)")
      }
      XCTAssertEqual(bundleID, "com.example.app")
      XCTAssertEqual(processIdentifier, 42)
      XCTAssertEqual(
        error.localizedDescription,
        "Cannot install 'com.example.app' because a debugger is attached to its existing process (PID 42). Detach the debugger or terminate the app, then retry.")
    } catch {
      XCTFail("Expected a debugger-attached process error, got \(error)")
    }
  }

  func testSuspendedProcessBlocksInstall() async {
    do {
      try await FBSimulatorApplicationCommands.confirmApplicationProcessIsInstallable(
        bundleID: "com.example.app",
        resolveProcessIdentifier: { 42 },
        processIsSuspended: { _ in true },
        debuggerIsAttached: { _ in false })
      XCTFail("Expected suspended process error")
    } catch let error as FBSimulatorApplicationError {
      guard case let .applicationProcessSuspended(bundleID, processIdentifier, debuggerAttached) = error else {
        return XCTFail("Expected a suspended-process install error, got \(error)")
      }
      XCTAssertEqual(bundleID, "com.example.app")
      XCTAssertEqual(processIdentifier, 42)
      XCTAssertFalse(debuggerAttached)
      XCTAssertEqual(
        error.localizedDescription,
        "Cannot install 'com.example.app' because its existing process (PID 42) is suspended. Resume or terminate the app, then retry.")
    } catch {
      XCTFail("Expected a suspended-process install error, got \(error)")
    }
  }

  func testSuspendedDebuggedProcessAddsDebuggerRemediation() async {
    do {
      try await FBSimulatorApplicationCommands.confirmApplicationProcessIsInstallable(
        bundleID: "com.example.app",
        resolveProcessIdentifier: { 42 },
        processIsSuspended: { _ in true },
        debuggerIsAttached: { _ in true })
      XCTFail("Expected suspended process error")
    } catch let error as FBSimulatorApplicationError {
      guard case let .applicationProcessSuspended(_, _, debuggerAttached) = error else {
        return XCTFail("Expected a suspended-process install error, got \(error)")
      }
      XCTAssertTrue(debuggerAttached)
      XCTAssertEqual(
        error.localizedDescription,
        "Cannot install 'com.example.app' because its existing process (PID 42) is suspended. A debugger is attached; detach the debugger or terminate the app, then retry.")
    } catch {
      XCTFail("Expected a suspended-process install error, got \(error)")
    }
  }

  func testSuspendedProcessPreventsInitialCoreSimulatorInstall() async {
    do {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { _ in
          throw FBSimulatorApplicationError.applicationProcessSuspended(
            bundleID: "com.example.app", processIdentifier: 42, debuggerAttached: false)
        },
        resolveInstalledApplication: { "installed" },
        installFailure: installFailure)
      XCTFail("Expected suspended process error")
    } catch let error as FBSimulatorApplicationError {
      guard case .applicationProcessSuspended = error else {
        return XCTFail("Expected a suspended-process install error, got \(error)")
      }
    } catch {
      XCTFail("Expected a suspended-process install error, got \(error)")
    }
  }

  func testDebuggerAttachedProcessPreventsInitialCoreSimulatorInstall() async {
    do {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { _ in
          throw FBSimulatorApplicationError.applicationProcessDebuggerAttached(
            bundleID: "com.example.app", processIdentifier: 42)
        },
        resolveInstalledApplication: { "installed" },
        installFailure: installFailure)
      XCTFail("Expected debugger-attached process error")
    } catch let error as FBSimulatorApplicationError {
      guard case .applicationProcessDebuggerAttached = error else {
        return XCTFail("Expected a debugger-attached process error, got \(error)")
      }
    } catch {
      XCTFail("Expected a debugger-attached process error, got \(error)")
    }
  }

  func testProcessBecomingSuspendedAfterInfoPlistFailurePreventsRetry() async {
    var installCalls = 0

    do {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { attempt in
          if attempt == .retry {
            throw FBSimulatorApplicationError.applicationProcessSuspended(
              bundleID: "com.example.app", processIdentifier: 42, debuggerAttached: true)
          }
          installCalls += 1
          throw NSError(
            domain: "com.example.install",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to load Info.plist from bundle at path /tmp/App.app"])
        },
        resolveInstalledApplication: { "installed" },
        installFailure: installFailure)
      XCTFail("Expected suspended process error")
    } catch let error as FBSimulatorApplicationError {
      guard case .applicationProcessSuspended = error else {
        return XCTFail("Expected a suspended-process install error, got \(error)")
      }
    } catch {
      XCTFail("Expected a suspended-process install error, got \(error)")
    }

    XCTAssertEqual(installCalls, 1)
  }

  func testDebuggerAttachedProcessAfterInfoPlistFailurePreventsRetry() async {
    var installCalls = 0

    do {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { attempt in
          if attempt == .retry {
            throw FBSimulatorApplicationError.applicationProcessDebuggerAttached(
              bundleID: "com.example.app", processIdentifier: 42)
          }
          installCalls += 1
          throw NSError(
            domain: "com.example.install",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to load Info.plist from bundle at path /tmp/App.app"])
        },
        resolveInstalledApplication: { "installed" },
        installFailure: installFailure)
      XCTFail("Expected debugger-attached process error")
    } catch let error as FBSimulatorApplicationError {
      guard case .applicationProcessDebuggerAttached = error else {
        return XCTFail("Expected a debugger-attached process error, got \(error)")
      }
    } catch {
      XCTFail("Expected a debugger-attached process error, got \(error)")
    }

    XCTAssertEqual(installCalls, 1)
  }

  func testNonWhitelistedApplicationErrorOnInitialAttemptBecomesInstallFailure() async {
    do {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { _ in
          throw FBSimulatorApplicationError.applicationInfoUnavailable(path: "/tmp/App.app")
        },
        resolveInstalledApplication: { "installed" },
        installFailure: installFailure)
      XCTFail("Expected install failure")
    } catch let error as FBSimulatorApplicationError {
      guard case .installFailed = error else {
        return XCTFail("Expected installFailed, got \(error)")
      }
    } catch {
      XCTFail("Expected installFailed, got \(error)")
    }
  }

  func testNonWhitelistedApplicationErrorOnRetryBecomesInstallFailure() async {
    do {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { attempt in
          if attempt == .initial {
            throw NSError(
              domain: "com.example.install",
              code: 1,
              userInfo: [NSLocalizedDescriptionKey: "Failed to load Info.plist from bundle at path /tmp/App.app"])
          }
          throw FBSimulatorApplicationError.applicationInfoUnavailable(path: "/tmp/App.app")
        },
        resolveInstalledApplication: { "installed" },
        installFailure: installFailure)
      XCTFail("Expected install failure")
    } catch let error as FBSimulatorApplicationError {
      guard case .installFailed = error else {
        return XCTFail("Expected installFailed, got \(error)")
      }
    } catch {
      XCTFail("Expected installFailed, got \(error)")
    }
  }

  func testCancellationFromInstallAttemptIsPreserved() async {
    let started = expectation(description: "preflight started")
    let gate = AsyncGate()
    var installCalls = 0

    let task = Task {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { _ in
          started.fulfill()
          await gate.wait()
          try Task.checkCancellation()
          installCalls += 1
        },
        resolveInstalledApplication: { "installed" },
        installFailure: installFailure)
    }
    await fulfillment(of: [started], timeout: 1)
    task.cancel()
    await gate.open()

    switch await task.result {
    case .failure(let error):
      XCTAssertTrue(error is CancellationError)
    case .success:
      XCTFail("Expected cancellation")
    }
    XCTAssertEqual(installCalls, 0)
  }

  func testCancellationAfterInstallAttemptReturnsIsPreserved() async {
    let started = expectation(description: "install attempt started")
    let gate = AsyncGate()
    var resolveCalls = 0

    let task = Task {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { _ in
          started.fulfill()
          await gate.wait()
        },
        resolveInstalledApplication: {
          resolveCalls += 1
          return "installed"
        },
        installFailure: installFailure)
    }
    await fulfillment(of: [started], timeout: 1)
    task.cancel()
    await gate.open()

    switch await task.result {
    case .failure(let error):
      XCTAssertTrue(error is CancellationError)
    case .success:
      XCTFail("Expected cancellation")
    }
    XCTAssertEqual(resolveCalls, 0)
  }

  func testCancellationAfterInstallAttemptThrowsIsPreserved() async {
    let started = expectation(description: "install attempt started")
    let gate = AsyncGate()

    let task = Task {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { _ in
          started.fulfill()
          await gate.wait()
          throw TestError.conditionNotMet
        },
        resolveInstalledApplication: { "installed" },
        installFailure: installFailure)
    }
    await fulfillment(of: [started], timeout: 1)
    task.cancel()
    await gate.open()

    switch await task.result {
    case .failure(let error):
      XCTAssertTrue(error is CancellationError)
    case .success:
      XCTFail("Expected cancellation")
    }
  }

  func testProcessLookupPreservesCancellation() async {
    do {
      try await FBSimulatorApplicationCommands.confirmApplicationProcessIsInstallable(
        bundleID: "com.example.app",
        resolveProcessIdentifier: { throw CancellationError() },
        processIsSuspended: { _ in true },
        debuggerIsAttached: { _ in true })
      XCTFail("Expected cancellation")
    } catch is CancellationError {
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  func testInstallWrapperPreservesCancellation() async {
    do {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { _ in throw CancellationError() },
        resolveInstalledApplication: { "installed" },
        installFailure: installFailure)
      XCTFail("Expected cancellation")
    } catch is CancellationError {
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }
  }

  func testUnbootedTargetFailsReadinessWithoutAvailabilityProbe() {
    var checkedAvailability = false

    XCTAssertThrowsError(
      try FBSimulatorApplicationCommands.confirmApplicationInstallTargetIsReady(
        state: .shutdown,
        stateDescription: "Shutdown",
        checkAvailability: { checkedAvailability = true })
    ) { error in
      guard case let .applicationInstallTargetNotBooted(state) = error as? FBSimulatorApplicationError else {
        return XCTFail("Expected an unbooted-target error, got \(error)")
      }
      XCTAssertEqual(state, "Shutdown")
    }
    XCTAssertFalse(checkedAvailability)
  }

  func testBootedAvailableTargetPassesReadiness() {
    XCTAssertNoThrow(
      try FBSimulatorApplicationCommands.confirmApplicationInstallTargetIsReady(
        state: .booted,
        stateDescription: "Booted",
        checkAvailability: {}))
  }

  func testAvailabilityQueryFailureIsPreservedInReadinessError() {
    let expectedReason = "simulator availability probe failed"

    XCTAssertThrowsError(
      try FBSimulatorApplicationCommands.confirmApplicationInstallTargetIsReady(
        state: .booted,
        stateDescription: "Booted",
        checkAvailability: {
          throw NSError(
            domain: "com.example.simulator",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: expectedReason])
        })
    ) { error in
      guard case let .applicationInstallTargetUnavailable(reason) = error as? FBSimulatorApplicationError else {
        return XCTFail("Expected an unavailable-target error, got \(error)")
      }
      XCTAssertEqual(reason, expectedReason)
    }
  }

  func testInstallWrapperPreservesReadinessErrors() async {
    let errors: [FBSimulatorApplicationError] = [
      .applicationInstallTargetNotBooted(state: "Shutdown"),
      .applicationInstallTargetUnavailable(reason: "runtime unavailable"),
    ]

    for expected in errors {
      do {
        let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
          install: { _ in throw expected },
          resolveInstalledApplication: { "installed" },
          installFailure: installFailure)
        XCTFail("Expected readiness error")
      } catch let actual as FBSimulatorApplicationError {
        XCTAssertEqual(actual.localizedDescription, expected.localizedDescription)
      } catch {
        XCTFail("Expected readiness error, got \(error)")
      }
    }
  }

  func testInstallWrapperPreservesReadinessErrorsOnRetry() async {
    let errors: [FBSimulatorApplicationError] = [
      .applicationInstallTargetNotBooted(state: "Shutdown"),
      .applicationInstallTargetUnavailable(reason: "runtime unavailable"),
    ]

    for expected in errors {
      do {
        let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
          install: { attempt in
            if attempt == .initial {
              throw NSError(
                domain: "com.example.install",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load Info.plist from bundle at path /tmp/App.app"])
            }
            throw expected
          },
          resolveInstalledApplication: { "installed" },
          installFailure: installFailure)
        XCTFail("Expected readiness error")
      } catch let actual as FBSimulatorApplicationError {
        XCTAssertEqual(actual.localizedDescription, expected.localizedDescription)
      } catch {
        XCTFail("Expected readiness error, got \(error)")
      }
    }
  }
}
