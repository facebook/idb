/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import IOKit
import Testing
import XPC

@Suite
struct SimulatorVendorOrientationTests {
  @Test
  func orientationReportPreservesNamedDirections() throws {
    let cases: [(SimulatorHIDDeviceOrientation, String)] = [
      (.portrait, "portrait"), (.portraitUpsideDown, "pud"),
      (.landscapeLeft, "landscape-left"), (.landscapeRight, "landscape-right"),
    ]
    for (orientation, expected) in cases {
      let event = try orientation.vendorEvent()
      #expect(event.usagePage == 0xff61)
      #expect(event.usage == 0x5b)
      #expect(event.version == 0)
      let decoded = try event.data.withUnsafeBytes { bytes in
        try #require(
          IOCFUnserializeWithSize(
            bytes.baseAddress!.assumingMemoryBound(to: CChar.self), bytes.count, nil, 0, nil) as? [String: String])
      }
      #expect(
        decoded == [
          "provider": "com.apple.Virtualization.VirtualMachines",
          "source": "orientation-picker-control", "type": "enum", "value": expected,
        ])
    }
  }

  @Test
  func motionCapabilityIsIndependentOfHinge() throws {
    for hinge in [false, true] {
      for motion in [false, true] {
        let reply = SimulatorCoreDevice.dictionary([
          "CoreDevice.output": SimulatorCoreDevice.dictionary([
            "hingeAngle": xpc_bool_create(hinge), "deviceMotionState": xpc_bool_create(motion),
          ])
        ])
        if motion {
          try SimulatorMotionCapability.deviceMotionState.requireSupported(in: reply)
        } else {
          let error = #expect(throws: (any Error).self) { try SimulatorMotionCapability.deviceMotionState.requireSupported(in: reply) }
          guard let error else { continue }
          guard case SimulatorCoreDeviceError.unsupported = error else {
            Issue.record("Expected unsupported, got \(error)")
            continue
          }
        }
      }
    }
  }

  @Test
  func unadvertisedMotionCapabilitySelectsLegacyTransport() throws {
    let reply = SimulatorCoreDevice.dictionary([
      "CoreDevice.output": SimulatorCoreDevice.dictionary(["hingeAngle": xpc_bool_create(false)])
    ])
    let error = try #require(#expect(throws: (any Error).self) { try SimulatorMotionCapability.deviceMotionState.requireSupported(in: reply) })
    guard case SimulatorCoreDeviceError.unsupported = error else {
      Issue.record("Expected unsupported, got \(error)")
      return
    }
  }

  @Test
  func malformedMotionCapabilityDoesNotSelectLegacyTransport() throws {
    for value in [xpc_int64_create(1), xpc_string_create("true"), xpc_null_create()] {
      let output = SimulatorCoreDevice.dictionary(["hingeAngle": xpc_bool_create(true)])
      xpc_dictionary_set_value(output, "deviceMotionState", value)
      let reply = SimulatorCoreDevice.dictionary(["CoreDevice.output": output])
      let error = #expect(throws: (any Error).self) { try SimulatorMotionCapability.deviceMotionState.requireSupported(in: reply) }
      guard let error else { continue }
      guard case SimulatorCoreDeviceError.malformed = error else {
        Issue.record("Expected invalid reply, got \(error)")
        continue
      }
    }
  }
}
