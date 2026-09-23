/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

enum SimulatorDisplayProtocol {
  /// Older providers omit both activity and stable identity from every display.
  static func captureDisplays(_ reply: xpc_object_t) throws -> [SimulatorDisplay]? {
    let values = try displayValues(reply)
    var hasCaptureFields = false
    for index in 0..<xpc_array_get_count(values) {
      let value = xpc_array_get_value(values, index)
      guard xpc_get_type(value) == XPC_TYPE_DICTIONARY else { throw SimulatorCoreDeviceError.malformed("Invalid display") }
      hasCaptureFields = hasCaptureFields || xpc_dictionary_get_value(value, "active") != nil || xpc_dictionary_get_value(value, "uniqueId") != nil
    }
    if !hasCaptureFields, xpc_array_get_count(values) > 0 {
      for index in 0..<xpc_array_get_count(values) {
        let value = xpc_array_get_value(values, index)
        _ = try string(value, "name")
        _ = try boolean(value, "primary")
        _ = try rectangle(field(value, "bounds", XPC_TYPE_ARRAY))
        let scale = xpc_int64_get_value(try field(value, "pointScale", XPC_TYPE_INT64))
        let type = try field(value, "type", XPC_TYPE_DICTIONARY)
        guard scale > 0, xpc_dictionary_get_count(type) == 1,
          try SimulatorDisplayRotation(rawValue: string(value, "currentOrientation")) != nil
        else { throw SimulatorCoreDeviceError.malformed("Invalid legacy display") }
      }
      return nil
    }
    return try displays(reply)
  }

  private static func displayValues(_ reply: xpc_object_t) throws -> xpc_object_t {
    let output = try CoreDeviceReply.output(of: reply)
    guard try boolean(output, "current") else { throw SimulatorCoreDeviceError.malformed("Report is not current") }
    let values = try field(output, "displays", XPC_TYPE_ARRAY)
    guard xpc_array_get_count(values) <= 32 else { throw SimulatorCoreDeviceError.malformed("Too many displays") }
    return values
  }

  static func displays(_ reply: xpc_object_t) throws -> [SimulatorDisplay] {
    let values = try displayValues(reply)
    var identifiers: Set<String> = []
    var displays: [SimulatorDisplay] = []
    for index in 0..<xpc_array_get_count(values) {
      let value = xpc_array_get_value(values, index)
      let id = try string(value, "uniqueId")
      guard !id.isEmpty, identifiers.insert(id).inserted else { throw SimulatorCoreDeviceError.malformed("Duplicate or empty display identity") }
      let bounds = try rectangle(field(value, "bounds", XPC_TYPE_ARRAY))
      let active = try boolean(value, "active")
      guard !active || !bounds.isEmpty else { throw SimulatorCoreDeviceError.malformed("Active display has empty bounds") }
      let scale = xpc_int64_get_value(try field(value, "pointScale", XPC_TYPE_INT64))
      guard scale > 0 else { throw SimulatorCoreDeviceError.malformed("Invalid display scale") }
      guard let rotation = try SimulatorDisplayRotation(rawValue: string(value, "currentOrientation")) else {
        throw SimulatorCoreDeviceError.malformed("Unknown display rotation")
      }
      let type = try field(value, "type", XPC_TYPE_DICTIONARY)
      guard xpc_dictionary_get_count(type) == 1 else { throw SimulatorCoreDeviceError.malformed("Invalid display type") }
      let integrated = xpc_dictionary_get_value(type, "integrated") != nil
      displays.append(
        SimulatorDisplay(
          uniqueID: id, name: try string(value, "name"), isActive: active,
          isPrimary: try boolean(value, "primary"), isIntegrated: integrated,
          bounds: bounds, scale: Double(scale), rotation: rotation))
    }
    return displays.sorted { $0.uniqueID < $1.uniqueID }
  }

  private static func field(_ object: xpc_object_t, _ key: String, _ type: xpc_type_t) throws -> xpc_object_t {
    guard xpc_get_type(object) == XPC_TYPE_DICTIONARY,
      let value = xpc_dictionary_get_value(object, key), xpc_get_type(value) == type
    else { throw SimulatorCoreDeviceError.malformed(key) }
    return value
  }

  private static func boolean(_ object: xpc_object_t, _ key: String) throws -> Bool {
    xpc_bool_get_value(try field(object, key, XPC_TYPE_BOOL))
  }

  private static func string(_ object: xpc_object_t, _ key: String) throws -> String {
    let value = try field(object, key, XPC_TYPE_STRING)
    guard xpc_string_get_length(value) <= 1024, let bytes = xpc_string_get_string_ptr(value) else {
      throw SimulatorCoreDeviceError.malformed(key)
    }
    return String(cString: bytes)
  }

  private static func pair(_ value: xpc_object_t) throws -> (Double, Double) {
    guard xpc_get_type(value) == XPC_TYPE_ARRAY, xpc_array_get_count(value) == 2 else {
      throw SimulatorCoreDeviceError.malformed("Invalid coordinate pair")
    }
    let first = xpc_array_get_value(value, 0)
    let second = xpc_array_get_value(value, 1)
    guard xpc_get_type(first) == XPC_TYPE_DOUBLE, xpc_get_type(second) == XPC_TYPE_DOUBLE else {
      throw SimulatorCoreDeviceError.malformed("Non-double coordinate")
    }
    let x = xpc_double_get_value(first)
    let y = xpc_double_get_value(second)
    guard x.isFinite, y.isFinite else { throw SimulatorCoreDeviceError.malformed("Non-finite coordinate") }
    return (x, y)
  }

  private static func rectangle(_ value: xpc_object_t) throws -> CGRect {
    guard xpc_array_get_count(value) == 2 else { throw SimulatorCoreDeviceError.malformed("Invalid bounds") }
    let origin = try pair(xpc_array_get_value(value, 0))
    let size = try pair(xpc_array_get_value(value, 1))
    guard size.0 >= 0, size.1 >= 0 else { throw SimulatorCoreDeviceError.malformed("Negative size") }
    return CGRect(x: origin.0, y: origin.1, width: size.0, height: size.1)
  }
}
