/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// The failure cases of the HID layer. They are surfaced only as messages — no consumer inspects
/// domain or code.
public enum FBSimulatorHIDError: Error, LocalizedError {
  /// The runtime-only `SimDeviceLegacyHIDClient` class could not be looked up by name.
  case clientClassUnavailable(className: String)
  /// The HID client class was found but `initWithDevice:error:` returned nil.
  case clientCreationFailed(clientClass: String, underlying: Error?)
  /// A HID operation was attempted after the client had been disposed of.
  case clientDisposed
  /// The `PurpleWorkspacePort` could not be found in the simulator's bootstrap namespace.
  case purpleWorkspacePortUnavailable(underlying: Error?)
  /// The `mach_msg` to `PurpleWorkspacePort` timed out (receive queue full).
  case machSendTimedOut(port: mach_port_t, timeoutMs: mach_msg_timeout_t, detail: String)
  /// The `mach_msg` to `PurpleWorkspacePort` failed for a reason other than timeout.
  case machSendFailed(port: mach_port_t, detail: String, code: kern_return_t)
  /// The SimulatorKit framework executable could not be opened.
  case simulatorKitUnavailable
  /// The legacy keyboard HID service has been handed over to `dtuhidd` (Xcode 27+).
  case keyboardSuppressedByDTUHIDD
  /// A primitive is not (yet) implemented on the DTUHID transport.
  case notImplementedOnDTUHIDTransport(operation: String)
  /// A primitive has no legacy Indigo representation (e.g. a Consumer-page button); use DTUHID.
  case notImplementedOnIndigoTransport(operation: String)
  /// The `dtuhidd` digitizer service could not be looked up in the simulator's bootstrap namespace.
  case dtuhidDigitizerServiceUnavailable(underlying: Error?)
  /// The private `_4sim` XPC endpoint symbols could not be resolved (older toolchain).
  case dtuhidXPCSymbolsUnavailable
  /// The `dtuhidd` host XPC connection could not be created.
  case dtuhidConnectionFailed
  /// A touchscreen touch was attempted on a tvOS target, which has no touchscreen.
  case touchUnsupportedOnAppleTV

  public var errorDescription: String? {
    switch self {
    case let .clientClassUnavailable(className):
      return "Could not look up class \(className)"
    case let .clientCreationFailed(clientClass, underlying):
      guard let underlying else {
        return "Could not create instance of \(clientClass)"
      }
      return "Could not create instance of \(clientClass): \(underlying.localizedDescription)"
    case .clientDisposed:
      return "Cannot Connect, HID client has already been disposed of"
    case .purpleWorkspacePortUnavailable:
      return "Could not find PurpleWorkspacePort in simulator bootstrap namespace"
    case let .machSendTimedOut(port, timeoutMs, detail):
      return
        "mach_msg to PurpleWorkspacePort \(port) timed out after \(timeoutMs) ms — receive queue full, SpringBoard is likely not draining HID events: \(detail)"
    case let .machSendFailed(port, detail, code):
      return "mach_msg to PurpleWorkspacePort \(port) failed: \(detail) (kr=0x\(String(code, radix: 16)))"
    case .simulatorKitUnavailable:
      return "Could not open the SimulatorKit framework executable"
    case .keyboardSuppressedByDTUHIDD:
      return
        "Keyboard HID is suppressed: CoreSimulator-1155.4 (Xcode 27) and later hand the legacy keyboard service over to dtuhidd for the lifetime of the boot. Use the DTUHID transport, which is the default on this CoreSimulator."
    case let .notImplementedOnDTUHIDTransport(operation):
      return "\(operation) is not implemented on the DTUHID transport"
    case let .notImplementedOnIndigoTransport(operation):
      return "\(operation) is not implemented on the legacy Indigo transport"
    case .dtuhidDigitizerServiceUnavailable:
      return "Could not look up the dtuhidd digitizer service (com.apple.coredevice.feature.remote.hid.digitizer)"
    case .dtuhidXPCSymbolsUnavailable:
      return "Could not resolve the private _4sim XPC endpoint symbols required for the DTUHID transport"
    case .dtuhidConnectionFailed:
      return "Could not create the dtuhidd host XPC connection"
    case .touchUnsupportedOnAppleTV:
      return "Touch input is not supported on tvOS targets (no touchscreen)"
    }
  }

  /// Whether this failure means `dtuhidd` could not be reached on this host at all, as opposed to a
  /// fault in a transport that was successfully established. Only these are worth negotiating
  /// around by falling back to the legacy Indigo transport; anything else is a real error that has
  /// to surface to the caller.
  var isDTUHIDUnreachable: Bool {
    switch self {
    case .dtuhidXPCSymbolsUnavailable, .dtuhidDigitizerServiceUnavailable, .dtuhidConnectionFailed:
      return true
    default:
      return false
    }
  }
}
