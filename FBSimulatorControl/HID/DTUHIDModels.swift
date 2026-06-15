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
