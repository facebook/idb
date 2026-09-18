/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc
public final class FBAXBridgeWire: NSObject {
  @objc(requestFromData:) public static func request(from data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  /// Replaces non-finite numbers with JSON null, preserving other values for the guarded encoder.
  @objc public static func sanitized(_ value: Any) -> Any {
    if let number = value as? NSNumber {
      return CFNumberIsFloatType(number) && !number.doubleValue.isFinite ? NSNull() : number
    }
    if let dictionary = value as? [AnyHashable: Any] {
      return dictionary.mapValues { sanitized($0) }
    }
    if let array = value as? [Any] {
      return array.map { sanitized($0) }
    }
    return value
  }
}
