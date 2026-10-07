/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBControlCore
import FBSimulatorControl
import GRPCCore
import XCTest

final class InstallMethodHandlerTests: XCTestCase {

  func testSuspendedApplicationMapsToFailedPrecondition() async {
    do {
      let _: Void = try await InstallMethodHandler.mapSimulatorInstallErrors {
        throw SimulatorApplicationInstallError.processSuspended(
          bundleID: "com.example.app",
          processIdentifier: 42,
          debuggerAttached: true)
      }
      XCTFail("Expected a failed-precondition status")
    } catch let status as RPCError {
      XCTAssertEqual(status.code, .failedPrecondition)
      XCTAssertTrue(status.message.contains("com.example.app"))
      XCTAssertTrue(status.message.contains("PID 42"))
      XCTAssertTrue(status.message.contains("debugger"))
    } catch {
      XCTFail("Expected a RPCError, got \(error)")
    }
  }

  func testDebuggerAttachedApplicationMapsToFailedPrecondition() async {
    do {
      let _: Void = try await InstallMethodHandler.mapSimulatorInstallErrors {
        throw SimulatorApplicationInstallError.processDebuggerAttached(
          bundleID: "com.example.app",
          processIdentifier: 42)
      }
      XCTFail("Expected a failed-precondition status")
    } catch let status as RPCError {
      XCTAssertEqual(status.code, .failedPrecondition)
      XCTAssertTrue(status.message.contains("com.example.app"))
      XCTAssertTrue(status.message.contains("PID 42"))
      XCTAssertTrue(status.message.contains("debugger"))
    } catch {
      XCTFail("Expected a RPCError, got \(error)")
    }
  }

  func testUnmappedUninstallErrorPassesThroughUnchanged() async {
    let underlying = NSError(
      domain: "com.example.install",
      code: 42,
      userInfo: [NSLocalizedDescriptionKey: "sentinel failure"])

    do {
      let _: Void = try await InstallMethodHandler.mapSimulatorInstallErrors {
        throw SimulatorApplicationUninstallError.uninstallFailed(
          bundleID: "com.example.app",
          underlying: underlying)
      }
      XCTFail("Expected the original simulator application error")
    } catch let error as SimulatorApplicationUninstallError {
      guard case let .uninstallFailed(bundleID, actualUnderlying) = error else {
        return XCTFail("Expected uninstallFailed, got \(error)")
      }
      XCTAssertEqual(bundleID, "com.example.app")
      XCTAssertTrue((actualUnderlying as NSError) === underlying)
    } catch {
      XCTFail("Expected SimulatorApplicationUninstallError, got \(error)")
    }
  }

  func testTargetReadinessErrorsMapToFailedPrecondition() async {
    let errors: [SimulatorApplicationInstallError] = [
      .targetNotBooted(state: "Shutdown"),
      .targetUnavailable(reason: "runtime unavailable"),
    ]

    for error in errors {
      do {
        let _: Void = try await InstallMethodHandler.mapSimulatorInstallErrors {
          throw error
        }
        XCTFail("Expected a failed-precondition status")
      } catch let status as RPCError {
        XCTAssertEqual(status.code, .failedPrecondition)
        XCTAssertFalse(status.message.isEmpty)
      } catch {
        XCTFail("Expected a RPCError, got \(error)")
      }
    }
  }

  func testEveryKindButADylibIsStagedFromItsURL() {
    let staged: [InstallDestination] = [.application(makeDebuggable: false), .xctest(skipSigningBundles: false), .dsym(linkTo: nil), .framework]
    for destination in staged {
      XCTAssertEqual(InstallMethodHandler.urlRoute(for: destination), .staged, "\(destination)")
    }
    XCTAssertEqual(InstallMethodHandler.urlRoute(for: .dylib), .gzippedFile)
  }

  func testADylibDownloadThatFails() async throws {
    let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    let download = DataDownloadInput.dataDownload(withURL: missing, logger: FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false))
    let staged = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    do {
      _ = try await InstallMethodHandler.installDownload(download) { _ in
        InstalledArtifact(name: "A.dSYM", uuid: nil, path: staged)
      }
      XCTFail("Expected the failed download to fail the install")
    } catch let error as InstallError {
      guard case .transferFailed = error else {
        return XCTFail("Expected transferFailed, got \(error)")
      }
    }
  }
}
