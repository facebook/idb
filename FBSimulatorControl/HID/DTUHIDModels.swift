/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// The `dtuhidd` wire models: the `Encodable` payloads serialized by `XPCEncoder` into the plain-XPC
// dictionaries `dtuhidd` decodes. Each HID capability adds its payload type to this file.

/**
 The plain-XPC envelope every `dtuhidd` message shares: a `messageType` discriminator, the
 `isBarrier` flag, the originating `featureIdentifier` (the looked-up service name), and a typed
 `payload`. Encoded to an `xpc_object_t` with `XPCEncoder`; the keys match `dtuhidd`'s `Codable`
 decode (`messageType` / `isBarrier` / `featureIdentifier` / `payload`).
 */
struct DTUHIDMessage<Payload: Encodable>: Encodable {
  let messageType: String
  let isBarrier: Bool
  let featureIdentifier: String
  let payload: Payload

  init(messageType: String, featureIdentifier: String, isBarrier: Bool = false, payload: Payload) {
    self.messageType = messageType
    self.isBarrier = isBarrier
    self.featureIdentifier = featureIdentifier
    self.payload = payload
  }
}

/// A single digitizer contact, as normalized top-left coordinates in `0...1`.
struct DigitizerPoint: Encodable {
  let x: Double
  let y: Double
}

/// The `IndigoDigitizerEvent` per-contact phase. Encoded as a `uint64` (its type drives the wire
/// type via `XPCEncoder`) — `dtuhidd`'s `Codable` decode rejects these as strings.
enum DigitizerEventType: UInt64, Encodable {
  case start = 0
  case position = 1
  case end = 2
}

/**
 The `dtuhidd` `IndigoDigitizerEvent` payload: one contact (`pointOne`) for single-finger touch, or
 two (`pointOne` + `pointTwo`) for pinch/two-finger gestures, plus the per-contact `eventType`.

 `pointTwo` is `nil` for single-finger touch — `XPCEncoder` omits the key entirely, matching the
 single-contact wire shape. `eventType` / `edge` / `target` ride as `uint64`.
 */
struct IndigoDigitizerEvent: Encodable {
  let pointOne: DigitizerPoint
  let pointTwo: DigitizerPoint?
  let eventType: DigitizerEventType
  let edge: UInt64
  let target: UInt64

  init(
    pointOne: DigitizerPoint,
    pointTwo: DigitizerPoint? = nil,
    eventType: DigitizerEventType,
    edge: UInt64 = 0,
    target: UInt64 = 0
  ) {
    self.pointOne = pointOne
    self.pointTwo = pointTwo
    self.eventType = eventType
    self.edge = edge
    self.target = target
  }
}

/// The `dtuhidd` `HIDButtonState`, shared by keyboard and hardware-button events. It is 1-based:
/// value `0` is rejected at decode (confirmed live — "Cannot initialize HIDButtonState from invalid
/// UInt8 value 0"), so these are `down = 1`, `up = 2`. Encodes as a `uint64`.
enum HIDButtonState: UInt64, Encodable {
  case down = 1
  case up = 2
}

/**
 The `dtuhidd` `IndigoKeyboardButtonEvent` payload: a USB HID keyboard `usageCode` (the same value
 the legacy path forwards) and its `state`. Both ride as `uint64`.
 */
struct IndigoKeyboardButtonEvent: Encodable {
  let usageCode: UInt64
  let state: HIDButtonState
}

/**
 The `dtuhidd` `IndigoButtonEvent` payload for a hardware button: the HID `usagePage` / `usageCode`
 identifying the button (see `FBSimulatorDTUHIDTransport.buttonUsage(for:)`) and its `state`. All
 ride as `uint64`.
 */
struct IndigoButtonEvent: Encodable {
  let usagePage: UInt64
  let usageCode: UInt64
  let state: HIDButtonState
}
