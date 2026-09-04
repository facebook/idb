/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import SimulatorApp

/// The wire identities a hardware button has. Both transports read this, so the two vocabularies live
/// together and cannot drift: a button is described once, and each transport takes the part it can
/// carry.
///
/// A sum type rather than two independent optionals because "neither" is not a real state — every
/// button reaches the guest somehow — and a pair of optionals would leave the transports handling a
/// case that cannot occur. Apple Pay has only a legacy source (it is a double side-button press, not a
/// single HID usage); the Consumer-page buttons the legacy builder has no dedicated source for have
/// only a usage; the rest have both.
enum FBSimulatorHIDButtonIdentity {

  /// Only a legacy Indigo `ButtonEventSource`.
  case indigoSource(Int32)
  /// Only a HID Consumer-page usage.
  case consumerUsage(page: UInt16, code: UInt16)
  /// Both a legacy source and a Consumer-page usage.
  case indigoSourceAndConsumerUsage(source: Int32, page: UInt16, code: UInt16)

  /// The legacy Indigo `ButtonEventSource`, where this button has one.
  var indigoSourceValue: Int32? {
    switch self {
    case let .indigoSource(source), let .indigoSourceAndConsumerUsage(source, _, _):
      return source
    case .consumerUsage:
      return nil
    }
  }

  /// The HID Consumer-page usage, where this button has one.
  var consumerUsage: (page: UInt16, code: UInt16)? {
    switch self {
    case let .consumerUsage(page, code), let .indigoSourceAndConsumerUsage(_, page, code):
      return (page, code)
    case .indigoSource:
      return nil
    }
  }
}

extension FBSimulatorHIDButton {

  /// How this button is identified on the wire. Consumer-page usages are from the HID Usage Tables
  /// (page 0x0C); the legacy sources are the `ButtonEventSource` values in `Indigo.h`.
  var identity: FBSimulatorHIDButtonIdentity {
    switch self {
    case .applePay:
      // A double press of the side button, so there is no single HID usage for it.
      return .indigoSource(Int32(ButtonEventSourceApplePay))
    case .homeButton:
      return .indigoSourceAndConsumerUsage(source: Int32(ButtonEventSourceHomeButton), page: 0x0C, code: 0x40) // Menu
    case .lock:
      return .indigoSourceAndConsumerUsage(source: Int32(ButtonEventSourceLock), page: 0x0C, code: 0x30) // Power
    case .sideButton:
      // The side button is the power/lock button, so it shares the Power usage.
      return .indigoSourceAndConsumerUsage(source: Int32(ButtonEventSourceSideButton), page: 0x0C, code: 0x30)
    case .siri:
      return .indigoSourceAndConsumerUsage(source: Int32(ButtonEventSourceSiri), page: 0x0C, code: 0xCF) // Voice Command
    case .playPause:
      return .consumerUsage(page: 0x0C, code: 0xCD) // Play/Pause
    }
  }
}
