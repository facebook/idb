/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBSimulatorPurpleHIDTests: XCTestCase {

  // MARK: - Helpers

  private func uint32(at offset: Int, in data: Data) -> UInt32 {
    data.withUnsafeBytes { buf -> UInt32 in
      buf.load(fromByteOffset: offset, as: UInt32.self)
    }
  }

  // MARK: - Tests

  func testOrientationEventSize() {
    let purple = FBSimulatorPurpleHID.purple()
    let data = purple.orientationEvent(.portrait)
    XCTAssertEqual(data.count, 112, "Buffer should be 112 bytes (aligned to 8)")
    XCTAssertEqual(uint32(at: 0x04, in: data), 108, "msgh_size should be 108")
  }

  func testOrientationEventMachHeader() {
    let purple = FBSimulatorPurpleHID.purple()
    let data = purple.orientationEvent(.portrait)

    // msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) = 0x13
    XCTAssertEqual(uint32(at: 0x00, in: data), 0x13)
    // msgh_remote_port = 0 (patched later by transport)
    XCTAssertEqual(uint32(at: 0x08, in: data), 0)
    // msgh_local_port = 0
    XCTAssertEqual(uint32(at: 0x0C, in: data), 0)
    // msgh_id = 0x7B (123)
    XCTAssertEqual(uint32(at: 0x14, in: data), 0x7B)
  }

  func testOrientationEventPortrait() {
    let purple = FBSimulatorPurpleHID.purple()
    let data = purple.orientationEvent(.portrait)

    // GSEvent type at offset 0x18 = 50 | 0x20000 = 0x20032
    XCTAssertEqual(uint32(at: 0x18, in: data), 0x20032)
    // record_info_size at offset 0x48 = 4
    XCTAssertEqual(uint32(at: 0x48, in: data), 4)
    // orientation at offset 0x4C = 1 (portrait)
    XCTAssertEqual(uint32(at: 0x4C, in: data), 1)
  }

  func testOrientationEventPortraitUpsideDown() {
    let data = FBSimulatorPurpleHID.purple().orientationEvent(.portraitUpsideDown)
    XCTAssertEqual(uint32(at: 0x4C, in: data), 2)
  }

  func testOrientationEventLandscapeRight() {
    let data = FBSimulatorPurpleHID.purple().orientationEvent(.landscapeRight)
    XCTAssertEqual(uint32(at: 0x4C, in: data), 3)
  }

  func testOrientationEventLandscapeLeft() {
    let data = FBSimulatorPurpleHID.purple().orientationEvent(.landscapeLeft)
    XCTAssertEqual(uint32(at: 0x4C, in: data), 4)
  }

  func testOrientationEventZeroedBody() {
    let data = FBSimulatorPurpleHID.purple().orientationEvent(.portrait)

    // GSEvent body from offset 0x1C to 0x47 (44 bytes) should be zeroed
    data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
      for i in 0x1C..<0x48 {
        let byte = buf.load(fromByteOffset: i, as: UInt8.self)
        XCTAssertEqual(byte, 0, "Byte at offset 0x\(String(i, radix: 16)) should be zero")
      }
    }
  }
}
