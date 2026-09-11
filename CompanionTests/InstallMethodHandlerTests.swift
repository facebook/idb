/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import GRPC
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
    } catch let status as GRPCStatus {
      XCTAssertEqual(status.code, .failedPrecondition)
      XCTAssertTrue(status.message?.contains("com.example.app") ?? false)
      XCTAssertTrue(status.message?.contains("PID 42") ?? false)
      XCTAssertTrue(status.message?.contains("debugger") ?? false)
    } catch {
      XCTFail("Expected a GRPCStatus, got \(error)")
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
    } catch let status as GRPCStatus {
      XCTAssertEqual(status.code, .failedPrecondition)
      XCTAssertTrue(status.message?.contains("com.example.app") ?? false)
      XCTAssertTrue(status.message?.contains("PID 42") ?? false)
      XCTAssertTrue(status.message?.contains("debugger") ?? false)
    } catch {
      XCTFail("Expected a GRPCStatus, got \(error)")
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
      } catch let status as GRPCStatus {
        XCTAssertEqual(status.code, .failedPrecondition)
        XCTAssertFalse(status.message?.isEmpty ?? true)
      } catch {
        XCTFail("Expected a GRPCStatus, got \(error)")
      }
    }
  }
}
