/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

enum SimulatorHingeProtocol {
  static let service = "com.apple.coredevice.feature.monitormotion"

  /// A CoreDevice duration: signed high bits and unsigned low bits, in attoseconds.
  struct Duration: Encodable {
    let attoseconds: UInt64

    static let hundredMilliseconds = Duration(attoseconds: 100_000_000_000_000_000)

    func encode(to encoder: Encoder) throws {
      var container = encoder.unkeyedContainer()
      try container.encode(Int64(0))
      try container.encode(attoseconds)
    }
  }

  /// A CoreDevice measurement unit; the hinge angle is requested in plain degrees.
  struct Unit: Encodable {
    struct Converter: Encodable {
      let coefficient: Double
      let constant: Double
    }
    let symbol: String
    let converter: Converter

    static let degrees = Unit(symbol: "°", converter: Converter(coefficient: 1, constant: 0))
  }

  struct Measurement: Encodable {
    let value: Double
    let unit: Unit
  }

  /// The input of `streamhingeangle`: how often and on what change to push samples, and the side
  /// channel they are pushed on.
  struct StreamInput: Encodable {
    struct ActualInput: Encodable {
      let changeThreshold: Measurement
      let updateInterval: Duration
    }
    struct StreamProxy: Encodable {
      let sideChannel: UUID
    }
    let actualInput: ActualInput
    let streamProxy: StreamProxy

    init(channel: UUID) {
      actualInput = ActualInput(changeThreshold: Measurement(value: 0.1, unit: .degrees), updateInterval: .hundredMilliseconds)
      streamProxy = StreamProxy(sideChannel: channel)
    }
  }

  static func request(deviceID: String, version: CoreDeviceVersion, channel: UUID) throws -> xpc_object_t {
    try CoreDeviceRequest(
      action: "com.apple.coredevice.action.streamhingeangle", deviceID: deviceID, version: version,
      input: StreamInput(channel: channel)
    ).encoded()
  }

  static func sample(
    _ event: xpc_object_t, channel: UUID, notBefore: TimeInterval, now: TimeInterval
  ) throws -> SimulatorHingeAngle? {
    try requireDictionary(event)
    guard try string(event, "XPCSideChannel.uniqueIdentifier") == channel.uuidString else {
      throw SimulatorCoreDeviceError.malformed("Unexpected side channel")
    }
    let status = try field(event, "CoreDevice.XPCMessageKey.sideChannelStatus", XPC_TYPE_DICTIONARY)
    let pushing = try field(status, "pushing", XPC_TYPE_DICTIONARY)
    let elements = try field(pushing, "elements", XPC_TYPE_ARRAY)
    guard xpc_array_get_count(elements) <= 64 else { throw SimulatorCoreDeviceError.malformed("Oversized sample batch") }
    var latest: (timestamp: Double, angle: SimulatorHingeAngle)?
    for index in 0..<xpc_array_get_count(elements) {
      let sample = xpc_array_get_value(elements, index)
      try requireDictionary(sample)
      guard xpc_bool_get_value(try field(sample, "isAngleValid", XPC_TYPE_BOOL)) else { continue }
      let timestamp = try number(sample, "timestamp")
      guard timestamp <= now else { throw SimulatorCoreDeviceError.malformed("Sample timestamp is in the future") }
      guard timestamp >= notBefore else { continue }
      let measurement = try field(sample, "angle", XPC_TYPE_DICTIONARY)
      let unit = try field(measurement, "unit", XPC_TYPE_DICTIONARY)
      let converter = try field(unit, "converter", XPC_TYPE_DICTIONARY)
      guard try string(unit, "symbol") == "°", try number(converter, "coefficient") == 1, try number(converter, "constant") == 0 else {
        throw SimulatorCoreDeviceError.malformed("Angle is not in degrees")
      }
      let angle = try SimulatorHingeAngle(degrees: number(measurement, "value"))
      if let latest, timestamp < latest.timestamp { continue }
      latest = (timestamp, angle)
    }
    return latest?.angle
  }

  static func checkReply(_ reply: xpc_object_t) throws {
    _ = try CoreDeviceReply.output(of: reply)
  }

  private static func requireDictionary(_ value: xpc_object_t) throws {
    guard xpc_get_type(value) == XPC_TYPE_DICTIONARY else {
      throw SimulatorCoreDeviceError.unavailable("Motion connection closed or returned a non-dictionary value")
    }
  }

  private static func field(_ object: xpc_object_t, _ key: String, _ type: xpc_type_t) throws -> xpc_object_t {
    guard let value = xpc_dictionary_get_value(object, key), xpc_get_type(value) == type else {
      throw SimulatorCoreDeviceError.malformed(key)
    }
    return value
  }

  private static func number(_ object: xpc_object_t, _ key: String) throws -> Double {
    let value = xpc_double_get_value(try field(object, key, XPC_TYPE_DOUBLE))
    guard value.isFinite else { throw SimulatorCoreDeviceError.malformed(key) }
    return value
  }

  private static func string(_ object: xpc_object_t, _ key: String) throws -> String {
    let value = try field(object, key, XPC_TYPE_STRING)
    guard xpc_string_get_length(value) <= 256, let bytes = xpc_string_get_string_ptr(value) else {
      throw SimulatorCoreDeviceError.malformed(key)
    }
    return String(cString: bytes)
  }
}
