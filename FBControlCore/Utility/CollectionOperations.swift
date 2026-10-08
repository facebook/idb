/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum CollectionOperations {

  public static func recursiveFilteredJSONSerializableRepresentation(of input: [String: Any]) -> [String: Any] {
    var output: [String: Any] = [:]
    for (key, value) in input {
      if let resolved = jsonSerializableValueOrNil(value) {
        output[key] = resolved
      }
    }
    return output
  }

  public static func recursiveFilteredJSONSerializableRepresentation(of input: [Any]) -> [Any] {
    var output: [Any] = []
    for value in input {
      if let resolved = jsonSerializableValueOrNil(value) {
        output.append(resolved)
      }
    }
    return output
  }

  private static func jsonSerializableValueOrNil(_ value: Any) -> Any? {
    if value is String || value is NSString {
      return value
    }
    if value is NSNumber {
      return value
    }
    if let dict = value as? [String: Any] {
      return recursiveFilteredJSONSerializableRepresentation(of: dict)
    }
    if let array = value as? [Any] {
      return recursiveFilteredJSONSerializableRepresentation(of: array)
    }
    return nil
  }
}
