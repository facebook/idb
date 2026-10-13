/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

@Suite
struct SimulatorApplicationInstallTests {

  private enum TestError: Error {
    case conditionNotMet
  }

  private func infoPlistError() -> NSError {
    NSError(
      domain: "com.example.install",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Failed to load Info.plist from bundle at path /tmp/App.app"])
  }

  private func installFailure() -> SimulatorApplicationInstallError {
    .installFailed(bundleDescription: "an app", options: "no options")
  }

  @Test
  func cleanInstallSucceedsWithoutRetry() async throws {
    var attempts: [SimulatorApplicationInstallAttempt] = []
    var resolveCalls = 0

    let application = try await SimulatorApplicationCommands.installAndResolveApplication(
      install: { attempts.append($0) },
      resolveInstalledApplication: {
        resolveCalls += 1
        return "installed"
      },
      installFailure: installFailure)

    #expect(application == "installed")
    #expect(attempts == [.initial])
    #expect(resolveCalls == 1)
  }

  @Test
  func infoPlistInstallFailureRetriesSuccessfully() async throws {
    var attempts: [SimulatorApplicationInstallAttempt] = []

    let application = try await SimulatorApplicationCommands.installAndResolveApplication(
      install: { attempt in
        attempts.append(attempt)
        if attempt == .initial {
          throw self.infoPlistError()
        }
      },
      resolveInstalledApplication: { "installed" },
      installFailure: installFailure)

    #expect(application == "installed")
    #expect(attempts == [.initial, .retry])
  }

  @Test
  func infoPlistLookupFailureRetriesSuccessfully() async throws {
    var attempts: [SimulatorApplicationInstallAttempt] = []
    var resolveCalls = 0

    let application = try await SimulatorApplicationCommands.installAndResolveApplication(
      install: { attempts.append($0) },
      resolveInstalledApplication: {
        resolveCalls += 1
        if resolveCalls == 1 {
          throw self.infoPlistError()
        }
        return "installed"
      },
      installFailure: installFailure)

    #expect(application == "installed")
    #expect(attempts == [.initial, .retry])
    #expect(resolveCalls == 2)
  }

  @Test
  func nonRetryableInitialFailureBecomesInstallFailure() async {
    do {
      let _: String = try await SimulatorApplicationCommands.installAndResolveApplication(
        install: { _ in throw TestError.conditionNotMet },
        resolveInstalledApplication: { "installed" },
        installFailure: installFailure)
      Issue.record("Expected install failure")
    } catch let error as SimulatorApplicationInstallError {
      guard case .installFailed = error else {
        Issue.record("Expected installFailed, got \(error)")
        return
      }
    } catch {
      Issue.record("Expected installFailed, got \(error)")
    }
  }

  @Test
  func nonRetryableInitialLookupFailureBecomesInstallFailure() async {
    do {
      let _: String = try await SimulatorApplicationCommands.installAndResolveApplication(
        install: { _ in },
        resolveInstalledApplication: { throw TestError.conditionNotMet },
        installFailure: installFailure)
      Issue.record("Expected install failure")
    } catch let error as SimulatorApplicationInstallError {
      guard case .installFailed = error else {
        Issue.record("Expected installFailed, got \(error)")
        return
      }
    } catch {
      Issue.record("Expected installFailed, got \(error)")
    }
  }

  @Test
  func retryInstallFailureBecomesInstallFailure() async {
    var attempts: [SimulatorApplicationInstallAttempt] = []

    do {
      let _: String = try await SimulatorApplicationCommands.installAndResolveApplication(
        install: { attempt in
          attempts.append(attempt)
          if attempt == .initial {
            throw self.infoPlistError()
          }
          throw TestError.conditionNotMet
        },
        resolveInstalledApplication: { "installed" },
        installFailure: installFailure)
      Issue.record("Expected install failure")
    } catch let error as SimulatorApplicationInstallError {
      guard case .installFailed = error else {
        Issue.record("Expected installFailed, got \(error)")
        return
      }
    } catch {
      Issue.record("Expected installFailed, got \(error)")
    }
    #expect(attempts == [.initial, .retry])
  }

  @Test
  func lookupFailureAfterSuccessfulRetryKeepsOriginalError() async {
    do {
      let _: String = try await SimulatorApplicationCommands.installAndResolveApplication(
        install: { attempt in
          if attempt == .initial {
            throw self.infoPlistError()
          }
        },
        resolveInstalledApplication: { throw TestError.conditionNotMet },
        installFailure: installFailure)
      Issue.record("Expected lookup error")
    } catch TestError.conditionNotMet {
    } catch {
      Issue.record("Expected original lookup error, got \(error)")
    }
  }
}
