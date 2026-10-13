/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBArtifactStaging
import FBControlCore
import FBSimulatorControl
import Foundation
import GRPCCore
import Testing

@Suite
struct InstallMethodHandlerTests {

  @Test
  func suspendedApplicationMapsToFailedPrecondition() async {
    do {
      let _: Void = try await InstallMethodHandler.mapSimulatorInstallErrors {
        throw SimulatorApplicationInstallError.processSuspended(
          bundleID: "com.example.app",
          processIdentifier: 42,
          debuggerAttached: true)
      }
      Issue.record("Expected a failed-precondition status")
    } catch let status as RPCError {
      #expect(status.code == .failedPrecondition)
      #expect(status.message.contains("com.example.app"))
      #expect(status.message.contains("PID 42"))
      #expect(status.message.contains("debugger"))
    } catch {
      Issue.record("Expected a RPCError, got \(error)")
    }
  }

  @Test
  func debuggerAttachedApplicationMapsToFailedPrecondition() async {
    do {
      let _: Void = try await InstallMethodHandler.mapSimulatorInstallErrors {
        throw SimulatorApplicationInstallError.processDebuggerAttached(
          bundleID: "com.example.app",
          processIdentifier: 42)
      }
      Issue.record("Expected a failed-precondition status")
    } catch let status as RPCError {
      #expect(status.code == .failedPrecondition)
      #expect(status.message.contains("com.example.app"))
      #expect(status.message.contains("PID 42"))
      #expect(status.message.contains("debugger"))
    } catch {
      Issue.record("Expected a RPCError, got \(error)")
    }
  }

  @Test
  func unmappedUninstallErrorPassesThroughUnchanged() async {
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
      Issue.record("Expected the original simulator application error")
    } catch let error as SimulatorApplicationUninstallError {
      guard case let .uninstallFailed(bundleID, actualUnderlying) = error else {
        Issue.record("Expected uninstallFailed, got \(error)")
        return
      }
      #expect(bundleID == "com.example.app")
      #expect((actualUnderlying as NSError) === underlying)
    } catch {
      Issue.record("Expected SimulatorApplicationUninstallError, got \(error)")
    }
  }

  @Test
  func targetReadinessErrorsMapToFailedPrecondition() async {
    let errors: [SimulatorApplicationInstallError] = [
      .targetNotBooted(state: "Shutdown"),
      .targetUnavailable(reason: "runtime unavailable"),
    ]

    for error in errors {
      do {
        let _: Void = try await InstallMethodHandler.mapSimulatorInstallErrors {
          throw error
        }
        Issue.record("Expected a failed-precondition status")
      } catch let status as RPCError {
        #expect(status.code == .failedPrecondition)
        #expect(!status.message.isEmpty)
      } catch {
        Issue.record("Expected a RPCError, got \(error)")
      }
    }
  }
}
