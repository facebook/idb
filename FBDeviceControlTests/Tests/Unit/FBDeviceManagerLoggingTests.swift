/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import XCTest

/// Records every logged line so log content can be asserted.
private final class RecordingLogger: NSObject, FBControlCoreLogger {
  private(set) var lines: [String] = []
  var name: String? { nil }
  var level: FBControlCoreLogLevel { .multiple }

  func log(_ message: String) -> any FBControlCoreLogger {
    lines.append(message)
    return self
  }

  func info() -> any FBControlCoreLogger { self }
  func debug() -> any FBControlCoreLogger { self }
  func error() -> any FBControlCoreLogger { self }
  func withName(_ name: String) -> any FBControlCoreLogger { self }
  func withDateFormatEnabled(_ enabled: Bool) -> any FBControlCoreLogger { self }
}

final class FBDeviceManagerLoggingTests: XCTestCase {

  /// A stand-in for the CFTypeRef handed to connection callbacks, with a
  /// recognizable description.
  private let privateDevice = "recognizable-private-ref-description" as CFTypeRef

  private func connectDevice(identifier: String) -> RecordingLogger {
    let logger = RecordingLogger()
    let manager = FBDeviceManagerDouble(logger: logger)
    manager.deviceConnected(privateDevice, identifier: identifier, info: [:])
    return logger
  }

  func testConnectionLogsIdentifyTheDeviceWithoutDereferencingTheRef() {
    let logger = connectDevice(identifier: "chip-id-1")
    let allOutput = logger.lines.joined(separator: "\n")
    // BUG: connection logs render the unowned callback ref with %@, which
    // dereferences it for its description; a dead ref crashes the process.
    // Flipped in the following commit to log the identifier instead.
    XCTAssertTrue(allOutput.contains("recognizable-private-ref-description"), "unexpected log output: \(allOutput)")
  }

  func testDisconnectionLogsIdentifyTheDeviceWithoutDereferencingTheRef() {
    let logger = connectDevice(identifier: "chip-id-2")
    let manager = FBDeviceManagerDouble(logger: logger)
    manager.deviceDisconnected(privateDevice, identifier: "chip-id-2")
    let allOutput = logger.lines.joined(separator: "\n")
    // BUG: as above — flipped in the following commit.
    XCTAssertTrue(allOutput.contains("recognizable-private-ref-description"), "unexpected log output: \(allOutput)")
  }
}
