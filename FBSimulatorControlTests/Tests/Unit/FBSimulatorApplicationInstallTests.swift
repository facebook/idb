/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest

final class FBSimulatorApplicationInstallTests: XCTestCase {

  private enum TestError: Error {
    case conditionNotMet
  }

  private func infoPlistError() -> NSError {
    NSError(
      domain: "com.example.install",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Failed to load Info.plist from bundle at path /tmp/App.app"])
  }

  private func installFailure() -> FBSimulatorApplicationError {
    .installFailed(bundleDescription: "an app", options: "no options")
  }

  func testCleanInstallSucceedsWithoutRetry() async throws {
    var attempts: [FBSimulatorApplicationInstallAttempt] = []
    var resolveCalls = 0

    let application = try await FBSimulatorApplicationCommands.installAndResolveApplication(
      install: { attempts.append($0) },
      resolveInstalledApplication: {
        resolveCalls += 1
        return "installed"
      },
      installFailure: installFailure)

    XCTAssertEqual(application, "installed")
    XCTAssertEqual(attempts, [.initial])
    XCTAssertEqual(resolveCalls, 1)
  }

  func testInfoPlistInstallFailureRetriesSuccessfully() async throws {
    var attempts: [FBSimulatorApplicationInstallAttempt] = []

    let application = try await FBSimulatorApplicationCommands.installAndResolveApplication(
      install: { attempt in
        attempts.append(attempt)
        if attempt == .initial {
          throw self.infoPlistError()
        }
      },
      resolveInstalledApplication: { "installed" },
      installFailure: installFailure)

    XCTAssertEqual(application, "installed")
    XCTAssertEqual(attempts, [.initial, .retry])
  }

  func testInfoPlistLookupFailureRetriesSuccessfully() async throws {
    var attempts: [FBSimulatorApplicationInstallAttempt] = []
    var resolveCalls = 0

    let application = try await FBSimulatorApplicationCommands.installAndResolveApplication(
      install: { attempts.append($0) },
      resolveInstalledApplication: {
        resolveCalls += 1
        if resolveCalls == 1 {
          throw self.infoPlistError()
        }
        return "installed"
      },
      installFailure: installFailure)

    XCTAssertEqual(application, "installed")
    XCTAssertEqual(attempts, [.initial, .retry])
    XCTAssertEqual(resolveCalls, 2)
  }

  func testNonRetryableInitialFailureBecomesInstallFailure() async {
    do {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { _ in throw TestError.conditionNotMet },
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

  func testNonRetryableInitialLookupFailureBecomesInstallFailure() async {
    do {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { _ in },
        resolveInstalledApplication: { throw TestError.conditionNotMet },
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

  func testRetryInstallFailureBecomesInstallFailure() async {
    var attempts: [FBSimulatorApplicationInstallAttempt] = []

    do {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { attempt in
          attempts.append(attempt)
          if attempt == .initial {
            throw self.infoPlistError()
          }
          throw TestError.conditionNotMet
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
    XCTAssertEqual(attempts, [.initial, .retry])
  }

  func testLookupFailureAfterSuccessfulRetryKeepsOriginalError() async {
    do {
      let _: String = try await FBSimulatorApplicationCommands.installAndResolveApplication(
        install: { attempt in
          if attempt == .initial {
            throw self.infoPlistError()
          }
        },
        resolveInstalledApplication: { throw TestError.conditionNotMet },
        installFailure: installFailure)
      XCTFail("Expected lookup error")
    } catch TestError.conditionNotMet {
    } catch {
      XCTFail("Expected original lookup error, got \(error)")
    }
  }
}
