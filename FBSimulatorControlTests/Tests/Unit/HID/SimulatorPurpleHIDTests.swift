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
struct SimulatorPurpleHIDTests {

  private func uint32(at offset: Int, in data: Data) -> UInt32 {
    data.withUnsafeBytes { buf -> UInt32 in
      buf.load(fromByteOffset: offset, as: UInt32.self)
    }
  }

  // MARK: - Tests

  @Test
  func orientationEventSize() {
    let purple = SimulatorPurpleHID()
    let data = purple.orientationEvent(.portrait)
    #expect(data.count == 112, "Buffer should be 112 bytes (aligned to 8)")
    #expect(uint32(at: 0x04, in: data) == 108, "msgh_size should be 108")
  }

  @Test
  func orientationEventMachHeader() {
    let purple = SimulatorPurpleHID()
    let data = purple.orientationEvent(.portrait)

    // msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) = 0x13
    #expect(uint32(at: 0x00, in: data) == 0x13)
    // msgh_remote_port = 0 (patched later by transport)
    #expect(uint32(at: 0x08, in: data) == 0)
    // msgh_local_port = 0
    #expect(uint32(at: 0x0C, in: data) == 0)
    // msgh_id = 0x7B (123)
    #expect(uint32(at: 0x14, in: data) == 0x7B)
  }

  @Test
  func orientationEventPortrait() {
    let purple = SimulatorPurpleHID()
    let data = purple.orientationEvent(.portrait)

    // GSEvent type at offset 0x18 = 50 | 0x20000 = 0x20032
    #expect(uint32(at: 0x18, in: data) == 0x20032)
    // record_info_size at offset 0x48 = 4
    #expect(uint32(at: 0x48, in: data) == 4)
    // orientation at offset 0x4C = 1 (portrait)
    #expect(uint32(at: 0x4C, in: data) == 1)
  }

  @Test
  func orientationEventPortraitUpsideDown() {
    let data = SimulatorPurpleHID().orientationEvent(.portraitUpsideDown)
    #expect(uint32(at: 0x4C, in: data) == 2)
  }

  @Test
  func orientationEventLandscapeRight() {
    let data = SimulatorPurpleHID().orientationEvent(.landscapeRight)
    #expect(uint32(at: 0x4C, in: data) == 3)
  }

  @Test
  func orientationEventLandscapeLeft() {
    let data = SimulatorPurpleHID().orientationEvent(.landscapeLeft)
    #expect(uint32(at: 0x4C, in: data) == 4)
  }

  @Test
  func orientationEventZeroedBody() {
    let data = SimulatorPurpleHID().orientationEvent(.portrait)

    // GSEvent body from offset 0x1C to 0x47 (44 bytes) should be zeroed
    data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
      for i in 0x1C..<0x48 {
        let byte = buf.load(fromByteOffset: i, as: UInt8.self)
        #expect(byte == 0, "Byte at offset 0x\(String(i, radix: 16)) should be zero")
      }
    }
  }

  // MARK: - Lock Device

  @Test
  func lockDeviceEventSize() {
    let data = SimulatorPurpleHID().lockDeviceEvent()
    #expect(data.count == 112, "Buffer should be 112 bytes (aligned to 8)")
    #expect(uint32(at: 0x04, in: data) == 108, "msgh_size should be 108")
  }

  @Test
  func lockDeviceEventMachHeader() {
    let data = SimulatorPurpleHID().lockDeviceEvent()

    // msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) = 0x13
    #expect(uint32(at: 0x00, in: data) == 0x13)
    // msgh_remote_port = 0 (patched later by transport)
    #expect(uint32(at: 0x08, in: data) == 0)
    // msgh_local_port = 0
    #expect(uint32(at: 0x0C, in: data) == 0)
    // msgh_id = 0x7B (123)
    #expect(uint32(at: 0x14, in: data) == 0x7B)
  }

  @Test
  func lockDeviceEventType() {
    let data = SimulatorPurpleHID().lockDeviceEvent()

    // GSEvent type at offset 0x18 = 1014 | 0x20000 = 0x203F6
    #expect(uint32(at: 0x18, in: data) == 0x203F6)
    // record_info_size at offset 0x48 = 0 (no payload for lock)
    #expect(uint32(at: 0x48, in: data) == 0)
  }

  @Test
  func lockDeviceEventZeroedBody() {
    let data = SimulatorPurpleHID().lockDeviceEvent()

    // Everything after the GSEvent type word (0x1C..end) carries no payload and should be zeroed.
    data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
      for i in 0x1C..<112 {
        let byte = buf.load(fromByteOffset: i, as: UInt8.self)
        #expect(byte == 0, "Byte at offset 0x\(String(i, radix: 16)) should be zero")
      }
    }
  }
}
