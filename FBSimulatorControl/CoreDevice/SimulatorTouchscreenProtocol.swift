/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

/// An available touchscreen, joined to display snapshots by stable identity.
public struct SimulatorTouchscreen: Equatable, Sendable {
  public let displayUniqueID: String
  /// The explicit target accepted by the Indigo digitizer service.
  public let digitizerTarget: UInt32
}

enum SimulatorTouchscreenProtocol {
  static let service = "com.apple.coredevice.feature.remote.universalhidservice"

  private struct Request: Encodable {
    struct Payload: Encodable {
      struct ConnectedServices: Encodable {}
      let connectedServices = ConnectedServices()
    }
    let isBarrier = false
    let payload = Payload()
  }

  static func request() throws -> xpc_object_t {
    try XPCEncoder().encode(Request())
  }

  static func touchscreens(_ reply: xpc_object_t) throws -> [SimulatorTouchscreen] {
    let services = try field(reply, "connectedServices", XPC_TYPE_ARRAY)
    guard xpc_array_get_count(services) <= 256 else {
      throw SimulatorDisplayError.invalidResponse("Too many HID services")
    }
    var identities: Set<String> = []
    var targets: Set<UInt32> = []
    var touchscreens: [SimulatorTouchscreen] = []
    var missingIdentity = false
    for index in 0..<xpc_array_get_count(services) {
      let service = xpc_array_get_value(services, index)
      guard xpc_get_type(service) == XPC_TYPE_DICTIONARY else {
        throw SimulatorDisplayError.invalidResponse("Invalid HID service")
      }
      guard let page = xpc_dictionary_get_value(service, "PrimaryUsagePage"), xpc_get_type(page) == XPC_TYPE_UINT64,
        let usage = xpc_dictionary_get_value(service, "PrimaryUsage"), xpc_get_type(usage) == XPC_TYPE_UINT64,
        xpc_uint64_get_value(page) == 0x0D, xpc_uint64_get_value(usage) == 0x04
      else { continue }
      let serviceID = xpc_uint64_get_value(try field(service, "_ServiceID", XPC_TYPE_UINT64))
      // HIDServiceID.touchscreenDisplayID accepts the 0x100 namespace. Indigo target zero is a main-screen alias.
      guard serviceID & ~0xFF == 0x100, serviceID & 0xFF != 0 else {
        throw SimulatorDisplayError.invalidResponse("HID service has no explicit touchscreen target")
      }
      let target = UInt32(serviceID & 0xFF)
      guard let identity = xpc_dictionary_get_value(service, "displayUUID") else {
        missingIdentity = true
        continue
      }
      guard xpc_get_type(identity) == XPC_TYPE_STRING,
        xpc_string_get_length(identity) > 0, xpc_string_get_length(identity) <= 1024,
        let bytes = xpc_string_get_string_ptr(identity)
      else { throw SimulatorDisplayError.invalidResponse("Invalid touchscreen display identity") }
      let data = Data(bytes: bytes, count: xpc_string_get_length(identity))
      guard !data.contains(0), let uniqueID = String(data: data, encoding: .utf8) else {
        throw SimulatorDisplayError.invalidResponse("Invalid touchscreen display identity")
      }
      guard targets.insert(target).inserted else {
        throw SimulatorDisplayError.invalidResponse("Ambiguous touchscreen target")
      }
      guard identities.insert(uniqueID).inserted else {
        throw SimulatorDisplayError.invalidResponse("Ambiguous touchscreen display identity")
      }
      touchscreens.append(SimulatorTouchscreen(displayUniqueID: uniqueID, digitizerTarget: target))
    }
    if missingIdentity {
      guard touchscreens.isEmpty else { throw SimulatorDisplayError.invalidResponse("Partial touchscreen display identities") }
      throw SimulatorCoreDeviceError.unsupported("Touchscreen display identities")
    }
    return touchscreens.sorted { $0.displayUniqueID < $1.displayUniqueID }
  }

  private static func field(_ object: xpc_object_t, _ key: String, _ type: xpc_type_t) throws -> xpc_object_t {
    guard xpc_get_type(object) == XPC_TYPE_DICTIONARY,
      let value = xpc_dictionary_get_value(object, key), xpc_get_type(value) == type
    else { throw SimulatorDisplayError.invalidResponse("Invalid HID field: \(key)") }
    return value
  }
}
