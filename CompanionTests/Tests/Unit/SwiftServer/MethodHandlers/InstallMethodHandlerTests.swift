/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
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

  func testZstdZipStreamIsRecognisedByItsSkippableFrame() {
    let marked = Data([0x5E, 0x2A, 0x4D, 0x18, 0x08, 0x00, 0x00, 0x00]) + Data("idb-zip\0".utf8) + Data([0x28, 0xB5, 0x2F, 0xFD])
    XCTAssertTrue(InstallMethodHandler.isZstdZipStream(marked))
  }

  func testOtherStreamsAreNotZstdZipStreams() {
    let streams: [Data] = [
      Data([0x50, 0x4B, 0x03, 0x04]),
      Data([0x28, 0xB5, 0x2F, 0xFD]),
      Data([0x50, 0x2A, 0x4D, 0x18, 0x04, 0x00, 0x00, 0x00]),
      Data([0x5E, 0x2A, 0x4D, 0x18, 0x08, 0x00, 0x00, 0x00]) + Data("idb-tar\0".utf8),
      Data([0x5E, 0x2A, 0x4D, 0x18]),
    ]
    for stream in streams {
      XCTAssertFalse(InstallMethodHandler.isZstdZipStream(stream), "\(stream as NSData)")
    }
  }

  func testTarDeclaredZstdThatStartsWithAZstdFrameIsExtractedAsZstd() {
    let streams: [Data] = [
      Data([0x28, 0xB5, 0x2F, 0xFD, 0x04, 0x00]),
      Data([0x50, 0x2A, 0x4D, 0x18, 0x04, 0x00, 0x00, 0x00]),
      Data([0x5F, 0x2A, 0x4D, 0x18, 0x04, 0x00, 0x00, 0x00]),
    ]
    for stream in streams {
      XCTAssertEqual(InstallMethodHandler.tarCompression(declared: .ZSTD, initial: stream), .ZSTD, "\(stream as NSData)")
    }
  }

  func testTarDeclaredZstdThatDoesNotStartWithAZstdFrame() {
    let tarHeader = Data("A.app/".utf8) + Data(count: 251) + Data("ustar\0".utf8)
    let streams: [Data] = [
      Data([0x1F, 0x8B, 0x08, 0x00]),
      tarHeader,
    ]
    for stream in streams {
      // BUG: a stream declared zstd that is gzip or a plain tar is extracted with the zstd decompressor, which rejects it — flipped in the following commit.
      XCTAssertEqual(InstallMethodHandler.tarCompression(declared: .ZSTD, initial: stream), .ZSTD, "\(stream as NSData)")
    }
  }

  func testTarDeclaredZstdTooShortToTellKeepsItsDeclaration() {
    XCTAssertEqual(InstallMethodHandler.tarCompression(declared: .ZSTD, initial: Data([0x1F, 0x8B])), .ZSTD)
  }

  func testTarDeclaredGzipIsExtractedAsDeclared() {
    for stream in [Data([0x1F, 0x8B, 0x08, 0x00]), Data([0x28, 0xB5, 0x2F, 0xFD])] {
      XCTAssertEqual(InstallMethodHandler.tarCompression(declared: .GZIP, initial: stream), .GZIP, "\(stream as NSData)")
    }
  }
}
