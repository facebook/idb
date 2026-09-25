/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum FBAXBridgeWire {
  /// Replaces non-finite numbers with JSON null, preserving other values for the guarded encoder.
  public static func sanitized(_ value: Any) -> Any {
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
