/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// The `dtuhidd` wire models: `Encodable` payloads serialized by `XPCEncoder` into the XPC dictionaries
// `dtuhidd` decodes.

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
 identifying the button and its `state`. All ride as `uint64`.
 */
struct IndigoButtonEvent: Encodable {
  let usagePage: UInt64
  let usageCode: UInt64
  let state: HIDButtonState
}

/**
 The `dtuhidd` `ScrollPoint`: the per-event scroll delta on each axis. The Digital Crown reads `y`;
 `x` and `z` are part of the wire struct and are sent as zero.
 */
struct ScrollPoint: Encodable {
  let x: Double
  let y: Double
  let z: Double

  static func crown(_ delta: Double) -> ScrollPoint {
    ScrollPoint(x: 0, y: delta, z: 0)
  }
}

/**
 The phase of a scroll gesture, as `CoreDevice.ScrollPhase`: an `OptionSet` over `UInt16` on Apple's
 side, of which one member is sent at a time. `mayBegin` is `128`, not the `32` the ordering would
 suggest. Rides as a `uint64`, as the other `dtuhidd` integers do.
 */
enum ScrollPhase: UInt64, Encodable {
  case undefined = 0
  case began = 1
  case changed = 2
  case ended = 4
  case cancelled = 8
  case mayBegin = 128
}

/**
 The inertial phase of a scroll gesture, as `CoreDevice.ScrollMomentum`: an `OptionSet` over
 `UInt8`. Crown samples are not inertial and send `undefined`.
 */
enum ScrollMomentum: UInt64, Encodable {
  case undefined = 0
  case `continue` = 1
  case start = 2
  case end = 4
  case willBegin = 8
  case interrupted = 16
}

/**
 Which rotary control a scroll event drives, as `CoreDevice.ScrollTarget`, whose domain is `0` and
 `1`.
 */
enum ScrollTarget: UInt64, Encodable {
  case digitalCrown = 0
  case dial = 1
}

/**
 The `dtuhidd` `IndigoScrollEvent` payload, sent to the scroll service: a per-event `point` delta,
 the gesture `phase`, its `momentum` and the rotary `target` it drives. The keys are those of
 `CoreDevice.HIDScroll.send(point:phase:momentum:target:)`.
 */
struct IndigoScrollEvent: Encodable {
  let point: ScrollPoint
  let phase: ScrollPhase
  let momentum: ScrollMomentum
  let target: ScrollTarget

  init(point: ScrollPoint, phase: ScrollPhase, momentum: ScrollMomentum = .undefined, target: ScrollTarget) {
    self.point = point
    self.phase = phase
    self.momentum = momentum
    self.target = target
  }
}

/**
 The `dtuhidd` `IndigoVendorDefinedEvent` payload, sent to the vendor-defined service: a HID
 `usagePage` / `usage` pair identifying the control and an opaque `data` report the guest's
 virtual-machine provider decodes (the hinge slider and orientation picker controls).
 */
struct IndigoVendorDefinedEvent: Encodable {
  let usagePage: UInt16
  let usage: UInt16
  let version: UInt32
  let data: Data
}
