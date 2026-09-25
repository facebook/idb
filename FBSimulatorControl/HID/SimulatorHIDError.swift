/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@preconcurrency import FBControlCore
import Foundation

/// The failure cases of the HID layer. They are surfaced only as messages — no consumer inspects
/// domain or code.
public enum SimulatorHIDError: Error, LocalizedError {
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
  /// The `dtuhidd` digitizer service could not be looked up in the simulator's bootstrap namespace.
  case dtuhidDigitizerServiceUnavailable(underlying: Error?)
  case dtuhidServiceUnavailable(name: String, underlying: Error?)
  /// The simulator's runtime does not vend the named `dtuhidd` service at all.
  case dtuhidServiceNotVended(name: String)
  /// The simulator is not booted, so it vends no `dtuhidd` service.
  case dtuhidSimulatorNotBooted(name: String, state: TargetState)
  /// The private `_4sim` XPC endpoint symbols could not be resolved (older toolchain).
  case dtuhidXPCSymbolsUnavailable
  /// The `dtuhidd` host XPC connection could not be created.
  case dtuhidConnectionFailed
  /// The connection was built, but no live `dtuhidd` answered behind it.
  case dtuhidUnresponsive(attempts: Int, underlying: Error?)
  /// An established connection to the named service has been invalidated, so nothing sent on it
  /// can arrive.
  case dtuhidConnectionInvalidated(name: String)
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
    case let .dtuhidServiceUnavailable(name, _):
      return "Could not look up the dtuhidd service (\(name))"
    case let .dtuhidServiceNotVended(name):
      return "The simulator's runtime does not vend the dtuhidd service (\(name))"
    case let .dtuhidSimulatorNotBooted(name, state):
      return "The simulator is \(state.stateString.rawValue), not booted, so the dtuhidd service (\(name)) cannot be looked up"
    case .dtuhidDigitizerServiceUnavailable:
      return "Could not look up the dtuhidd digitizer service (com.apple.coredevice.feature.remote.hid.digitizer)"
    case .dtuhidXPCSymbolsUnavailable:
      return "Could not resolve the private _4sim XPC endpoint symbols required for the DTUHID transport"
    case .dtuhidConnectionFailed:
      return "Could not create the dtuhidd host XPC connection"
    case let .dtuhidUnresponsive(attempts, underlying):
      let detail = underlying.map { " (\($0))" } ?? ""
      return
        "dtuhidd did not answer a liveness probe in \(attempts) attempts\(detail) — the daemon is not running and launchd is not keeping it up, so every HID event sent to it would be discarded without error"
    case let .dtuhidConnectionInvalidated(name):
      return "The dtuhidd connection (\(name)) has been invalidated; events sent on it would be discarded"
    case .touchUnsupportedOnAppleTV:
      return "Touch input is not supported on tvOS targets (no touchscreen)"
    }
  }

  /// How a failure to build the host XPC connection reads for the DTUHID transport.
  init(dtuhidConnection error: SimulatorXPCConnectionError) {
    switch error {
    case .symbolsUnavailable:
      self = .dtuhidXPCSymbolsUnavailable
    case let .notBooted(service, state):
      self = .dtuhidSimulatorNotBooted(name: service, state: state)
    case let .lookupFailed(service, _) where error.isServiceUnsupported:
      self = .dtuhidServiceNotVended(name: service)
    case let .lookupFailed(service, underlying):
      self = .dtuhidServiceUnavailable(name: service, underlying: underlying)
    case .connectionFailed:
      self = .dtuhidConnectionFailed
    }
  }

  /// Whether this failure could clear on its own, so connecting is worth another attempt.
  ///
  /// The service lookup fails while the job is being torn down and respawned, which is the state a
  /// retry exists to ride out. Absent `_4sim` symbols, or a runtime that does not vend the service,
  /// are the opposite: properties of the toolchain or runtime that no amount of waiting changes.
  var isTransientDTUHIDFailure: Bool {
    switch self {
    case .dtuhidServiceUnavailable, .dtuhidDigitizerServiceUnavailable, .dtuhidConnectionFailed, .dtuhidUnresponsive:
      return true
    default:
      return false
    }
  }

  /// Whether this failure means `dtuhidd` could not be reached on this host at all, as opposed to a
  /// fault in a transport that was successfully established. Only these are worth negotiating
  /// around by falling back to the legacy Indigo transport; anything else is a real error that has
  /// to surface to the caller.
  var isDTUHIDUnreachable: Bool {
    switch self {
    case .dtuhidXPCSymbolsUnavailable, .dtuhidServiceUnavailable, .dtuhidServiceNotVended, .dtuhidDigitizerServiceUnavailable,
      .dtuhidConnectionFailed, .dtuhidUnresponsive:
      return true
    default:
      return false
    }
  }
}
