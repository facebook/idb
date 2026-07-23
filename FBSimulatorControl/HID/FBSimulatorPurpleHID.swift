/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/**
 Constructs GSEvent payloads for PurpleWorkspacePort.
 Mirrors `FBSimulatorIndigoHID` (which constructs Indigo payloads for IndigoHIDRegistrationPort).

 The returned `Data` contains a complete mach message (including `mach_msg_header_t`)
 ready to be sent via `mach_msg_send`. The `msgh_remote_port` field is left as 0
 and must be patched by the transport (`FBSimulatorHID.sendPurpleEvent:`) before sending.

 See `SimulatorApp/GSEvent.h` for the wire format documentation.

 Unlike `FBSimulatorIndigoHID`, this class has no dlsym dependencies — payloads are
 constructed from documented constants.
 */
public final class FBSimulatorPurpleHID {

  // GSEvent constants. Values mirror SimulatorApp/GSEvent.h.
  private static let gsEventTypeDeviceOrientationChanged: UInt32 = 50
  private static let gsEventTypeLockDevice: UInt32 = 1014
  private static let gsEventHostFlag: UInt32 = 0x2_0000
  private static let gsEventMachMessageID: UInt32 = 0x7B

  /**
   Constructs a GSEvent orientation change mach message.
   The message uses GSEvent type 50 (kGSEventDeviceOrientationChanged) with the host flag.

   - Parameter orientation: the desired device orientation.
   - Returns: a `Data` containing the complete mach message (112 bytes, msgh_size=108).
   */
  public func orientationEvent(_ orientation: FBSimulatorHIDDeviceOrientation) -> Data {
    // Construct a 112-byte buffer (aligned to 8 bytes, >= 108 = 0x6C mach message size).
    // See GSEvent.h for the complete wire format documentation.
    var buf = [UInt8](repeating: 0, count: 112)
    FBSimulatorPurpleHID.writeMachHeader(into: &buf)

    // GSEvent type at offset 0x18.
    FBSimulatorPurpleHID.writeUInt32(
      FBSimulatorPurpleHID.gsEventTypeDeviceOrientationChanged | FBSimulatorPurpleHID.gsEventHostFlag,
      into: &buf,
      at: 0x18)
    // record_info_size at offset 0x48.
    FBSimulatorPurpleHID.writeUInt32(4, into: &buf, at: 0x48)
    // orientation value at offset 0x4C.
    FBSimulatorPurpleHID.writeUInt32(UInt32(orientation.rawValue), into: &buf, at: 0x4C)

    return Data(buf)
  }

  /**
   Constructs a GSEvent lock device mach message.
   The message uses GSEvent type 1014 (kGSEventLockDevice) with the host flag.
   No payload is needed (record_info_size = 0).

   - Returns: a `Data` containing the complete mach message (112 bytes).
   */
  public func lockDeviceEvent() -> Data {
    // Same 112-byte buffer as orientation, but with GSEventTypeLockDevice and no payload.
    var buf = [UInt8](repeating: 0, count: 112)
    FBSimulatorPurpleHID.writeMachHeader(into: &buf)

    FBSimulatorPurpleHID.writeUInt32(
      FBSimulatorPurpleHID.gsEventTypeLockDevice | FBSimulatorPurpleHID.gsEventHostFlag,
      into: &buf,
      at: 0x18)

    // record_info_size = 0, no payload.
    return Data(buf)
  }

  // MARK: - Wire format helpers

  /// Writes the common `mach_msg_header_t` fields. `msgh_remote_port` is left as
  /// MACH_PORT_NULL and patched by `FBSimulatorHID.sendPurpleEvent:` before sending.
  private static func writeMachHeader(into buf: inout [UInt8]) {
    // msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) = 0x13.
    writeUInt32(0x13, into: &buf, at: 0x00)
    // msgh_size = 108 — align4(4 + 0x6B), matches Simulator.app's sendPurpleEvent:.
    writeUInt32(108, into: &buf, at: 0x04)
    // msgh_remote_port = MACH_PORT_NULL (patched by the transport).
    writeUInt32(0, into: &buf, at: 0x08)
    // msgh_local_port = MACH_PORT_NULL.
    writeUInt32(0, into: &buf, at: 0x0C)
    // msgh_id.
    writeUInt32(gsEventMachMessageID, into: &buf, at: 0x14)
  }

  /// Writes a little-endian `UInt32` at the given byte offset (host byte order on the
  /// x86_64 / arm64 macOS hosts that idb runs on).
  private static func writeUInt32(_ value: UInt32, into buf: inout [UInt8], at offset: Int) {
    buf[offset] = UInt8(value & 0xFF)
    buf[offset + 1] = UInt8((value >> 8) & 0xFF)
    buf[offset + 2] = UInt8((value >> 16) & 0xFF)
    buf[offset + 3] = UInt8((value >> 24) & 0xFF)
  }
}
