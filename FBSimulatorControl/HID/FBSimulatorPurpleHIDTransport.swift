/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Darwin
@preconcurrency import FBControlCore
import Foundation

/**
 The transport for GSEvents — device orientation and lock — delivered as raw mach messages to
 SpringBoard's PurpleWorkspacePort. Guest-side: `GraphicsServices._PurpleEventCallback` → backboardd.

 Not transport-switchable: unlike the Indigo-family primitives there is no alternative path, so this is
 a concrete transport rather than one case of a choice. It completes the split Indigo already had, where
 `FBSimulatorIndigoHID` builds the payload and `FBSimulatorIndigoHIDTransport` sends it —
 `FBSimulatorPurpleHID` was the codec half with no transport, so the send lived inline on the composite.

 Connectionless: the port is looked up per send, so there is nothing to hold open, drain or tear down.

 SAFETY: holds only an immutable weak reference to the target; the mach send owns no shared state.
 */
// patternlint-disable-next-line unchecked-sendable
final class FBSimulatorPurpleHIDTransport: @unchecked Sendable {

  /// Default Mach send timeout (in milliseconds). Healthy round-trips return in low single-digit
  /// milliseconds; 2000ms absorbs scheduler jitter while bounding the wedge condition where
  /// SpringBoard's PurpleWorkspacePort receive queue fills.
  private static let defaultSendTimeoutMs: mach_msg_timeout_t = 2000

  /// The GSEvent payload builder.
  private let purple: FBSimulatorPurpleHID
  private weak var simulator: FBSimulator?

  init(purple: FBSimulatorPurpleHID = FBSimulatorPurpleHID(), simulator: FBSimulator?) {
    self.purple = purple
    self.simulator = simulator
  }

  // MARK: Sends

  /// Rotates the device.
  func sendOrientation(_ orientation: FBSimulatorHIDDeviceOrientation) throws {
    try send(purple.orientationEvent(orientation))
  }

  /// Locks the device.
  func sendLockDevice() throws {
    try send(purple.lockDeviceEvent())
  }

  // MARK: Mach transit

  /**
   Sends a raw mach message to the simulator's PurpleWorkspacePort, bounded by a send-side timeout.
   The `msgh_remote_port` field is patched with the PurpleWorkspacePort looked up from the simulator's
   bootstrap namespace. The send always uses `mach_msg(MACH_SEND_TIMEOUT)`; on `MACH_SEND_TIMED_OUT` the
   kernel guarantees the message is not enqueued.
   */
  private func send(_ data: Data, timeoutMs: mach_msg_timeout_t = defaultSendTimeoutMs) throws {
    guard let simulator else {
      throw FBWeakTargetError.simulator
    }

    var lookupError: NSError?
    let purplePort = simulator.device.lookup("PurpleWorkspacePort", error: &lookupError)
    if purplePort == 0 {
      throw FBSimulatorHIDError.purpleWorkspacePortUnavailable(underlying: lookupError)
    }

    // Copy the payload and patch msgh_remote_port with the looked-up port.
    var mutableData = data
    let kr: kern_return_t = mutableData.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> kern_return_t in
      guard let base = buffer.baseAddress else { return KERN_FAILURE }
      let header = base.assumingMemoryBound(to: mach_msg_header_t.self)
      header.pointee.msgh_remote_port = purplePort
      return mach_msg(
        header,
        MACH_SEND_MSG | MACH_SEND_TIMEOUT,
        header.pointee.msgh_size,
        0,
        mach_port_t(MACH_PORT_NULL),
        timeoutMs,
        mach_port_t(MACH_PORT_NULL))
    }

    if kr == KERN_SUCCESS {
      return
    }
    if kr == MACH_SEND_TIMED_OUT {
      throw FBSimulatorHIDError.machSendTimedOut(
        port: purplePort, timeoutMs: timeoutMs, detail: String(cString: mach_error_string(kr)))
    }
    throw FBSimulatorHIDError.machSendFailed(
      port: purplePort, detail: String(cString: mach_error_string(kr)), code: kr)
  }
}
