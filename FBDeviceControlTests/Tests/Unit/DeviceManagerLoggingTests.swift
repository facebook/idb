/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Testing

/// Records every logged line so log content can be asserted.
private final class RecordingLogger: NSObject, ControlCoreLogger {
  private(set) var lines: [String] = []
  var name: String? { nil }
  var level: FBControlCoreLogLevel { .multiple }

  func log(_ message: String) -> any ControlCoreLogger {
    lines.append(message)
    return self
  }

  func info() -> any ControlCoreLogger { self }
  func debug() -> any ControlCoreLogger { self }
  func error() -> any ControlCoreLogger { self }
  func withName(_ name: String) -> any ControlCoreLogger { self }
  func withDateFormatEnabled(_ enabled: Bool) -> any ControlCoreLogger { self }
}

@Suite
struct DeviceManagerLoggingTests {

  /// A stand-in for the CFTypeRef handed to connection callbacks, with a
  /// recognizable description.
  private let privateDevice = "recognizable-private-ref-description" as CFTypeRef

  private func connectDevice(identifier: String) -> RecordingLogger {
    let logger = RecordingLogger()
    let manager = DeviceManagerDouble(logger: logger)
    manager.deviceConnected(privateDevice, identifier: identifier, info: [:])
    return logger
  }

  @Test
  func connectionLogsIdentifyTheDeviceWithoutDereferencingTheRef() {
    let logger = connectDevice(identifier: "chip-id-1")
    let allOutput = logger.lines.joined(separator: "\n")
    #expect(!(allOutput.contains("recognizable-private-ref-description")), "unexpected log output: \(allOutput)")
    #expect((allOutput.contains("chip-id-1")), "unexpected log output: \(allOutput)")
  }

  @Test
  func disconnectionLogsIdentifyTheDeviceWithoutDereferencingTheRef() {
    let logger = connectDevice(identifier: "chip-id-2")
    let manager = DeviceManagerDouble(logger: logger)
    manager.deviceDisconnected(privateDevice, identifier: "chip-id-2")
    let allOutput = logger.lines.joined(separator: "\n")
    #expect(!(allOutput.contains("recognizable-private-ref-description")), "unexpected log output: \(allOutput)")
    #expect((allOutput.contains("chip-id-2")), "unexpected log output: \(allOutput)")
  }
}
