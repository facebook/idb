/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

enum SimulatorHingeReadError: Error, LocalizedError {
  case unavailable(String)
  case malformed(String)
  case timedOut
  case endedWithoutSample

  var errorDescription: String? {
    switch self {
    case let .unavailable(detail): "Simulator hinge read unavailable: \(detail)"
    case let .malformed(detail): "Invalid simulator hinge response: \(detail)"
    case .timedOut: "Timed out reading a fresh simulator hinge angle"
    case .endedWithoutSample: "Simulator hinge stream ended without a fresh valid sample"
    }
  }
}

enum SimulatorHingeProtocol {
  static let service = "com.apple.coredevice.feature.monitormotion"

  static func request(deviceID: String, version: String, channel: UUID) throws -> xpc_object_t {
    let dictionary = SimulatorCoreDevice.dictionary
    var uuid = channel.uuid
    let identifier = withUnsafePointer(to: &uuid) {
      $0.withMemoryRebound(to: UInt8.self, capacity: 16) { xpc_uuid_create($0) }
    }
    let unit = dictionary([
      "symbol": xpc_string_create("°"),
      "converter": dictionary(["coefficient": xpc_double_create(1), "constant": xpc_double_create(0)]),
    ])
    return try SimulatorCoreDevice.request(
      action: "com.apple.coredevice.action.streamhingeangle", deviceID: deviceID, version: version,
      input: dictionary([
        "actualInput": dictionary([
          "changeThreshold": dictionary(["value": xpc_double_create(0.1), "unit": unit]),
          // Duration encodes signed high bits and unsigned low bits, in attoseconds (100ms).
          "updateInterval": SimulatorCoreDevice.array([xpc_int64_create(0), xpc_uint64_create(100_000_000_000_000_000)]),
        ]),
        "streamProxy": dictionary(["sideChannel": identifier]),
      ]))
  }

  static func sample(
    _ event: xpc_object_t, channel: UUID, notBefore: TimeInterval, now: TimeInterval
  ) throws -> SimulatorHingeAngle? {
    try requireDictionary(event)
    guard try string(event, "XPCSideChannel.uniqueIdentifier") == channel.uuidString else {
      throw SimulatorHingeReadError.malformed("Unexpected side channel")
    }
    let status = try field(event, "CoreDevice.XPCMessageKey.sideChannelStatus", XPC_TYPE_DICTIONARY)
    let pushing = try field(status, "pushing", XPC_TYPE_DICTIONARY)
    let elements = try field(pushing, "elements", XPC_TYPE_ARRAY)
    guard xpc_array_get_count(elements) <= 64 else { throw SimulatorHingeReadError.malformed("Oversized sample batch") }
    var latest: (timestamp: Double, angle: SimulatorHingeAngle)?
    for index in 0..<xpc_array_get_count(elements) {
      let sample = xpc_array_get_value(elements, index)
      try requireDictionary(sample)
      guard xpc_bool_get_value(try field(sample, "isAngleValid", XPC_TYPE_BOOL)) else { continue }
      let timestamp = try number(sample, "timestamp")
      guard timestamp <= now else { throw SimulatorHingeReadError.malformed("Sample timestamp is in the future") }
      guard timestamp >= notBefore else { continue }
      let measurement = try field(sample, "angle", XPC_TYPE_DICTIONARY)
      let unit = try field(measurement, "unit", XPC_TYPE_DICTIONARY)
      let converter = try field(unit, "converter", XPC_TYPE_DICTIONARY)
      guard try string(unit, "symbol") == "°", try number(converter, "coefficient") == 1, try number(converter, "constant") == 0 else {
        throw SimulatorHingeReadError.malformed("Angle is not in degrees")
      }
      let angle = try SimulatorHingeAngle(degrees: number(measurement, "value"))
      if let latest, timestamp < latest.timestamp { continue }
      latest = (timestamp, angle)
    }
    return latest?.angle
  }

  static func checkReply(_ reply: xpc_object_t) throws {
    try requireDictionary(reply)
    if let error = xpc_dictionary_get_value(reply, "CoreDevice.error") {
      try requireDictionary(error)
      let domain = try string(error, "domain")
      let code = xpc_int64_get_value(try field(error, "code", XPC_TYPE_INT64))
      throw SimulatorHingeReadError.unavailable("\(domain) (\(code))")
    }
    _ = try field(reply, "CoreDevice.output", XPC_TYPE_DICTIONARY)
  }

  private static func requireDictionary(_ value: xpc_object_t) throws {
    guard xpc_get_type(value) == XPC_TYPE_DICTIONARY else {
      throw SimulatorHingeReadError.unavailable("Motion connection closed or returned a non-dictionary value")
    }
  }

  private static func field(_ object: xpc_object_t, _ key: String, _ type: xpc_type_t) throws -> xpc_object_t {
    guard let value = xpc_dictionary_get_value(object, key), xpc_get_type(value) == type else {
      throw SimulatorHingeReadError.malformed(key)
    }
    return value
  }

  private static func number(_ object: xpc_object_t, _ key: String) throws -> Double {
    let value = xpc_double_get_value(try field(object, key, XPC_TYPE_DOUBLE))
    guard value.isFinite else { throw SimulatorHingeReadError.malformed(key) }
    return value
  }

  private static func string(_ object: xpc_object_t, _ key: String) throws -> String {
    let value = try field(object, key, XPC_TYPE_STRING)
    guard xpc_string_get_length(value) <= 256, let bytes = xpc_string_get_string_ptr(value) else {
      throw SimulatorHingeReadError.malformed(key)
    }
    return String(cString: bytes)
  }
}
