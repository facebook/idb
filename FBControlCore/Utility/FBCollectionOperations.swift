/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBCollectionOperations)
public final class FBCollectionOperations: NSObject {

  @objc(arrayFromIndices:)
  public class func array(from indices: IndexSet) -> [NSNumber] {
    var array: [NSNumber] = []
    for index in indices {
      array.append(NSNumber(value: index))
    }
    return array
  }

  @objc(recursiveFilteredJSONSerializableRepresentationOfDictionary:)
  public class func recursiveFilteredJSONSerializableRepresentation(of input: [String: Any]) -> [String: Any] {
    var output: [String: Any] = [:]
    for (key, value) in input {
      if let resolved = jsonSerializableValueOrNil(value) {
        output[key] = resolved
      }
    }
    return output
  }

  @objc(recursiveFilteredJSONSerializableRepresentationOfArray:)
  public class func recursiveFilteredJSONSerializableRepresentation(of input: [Any]) -> [Any] {
    var output: [Any] = []
    for value in input {
      if let resolved = jsonSerializableValueOrNil(value) {
        output.append(resolved)
      }
    }
    return output
  }

  @objc(indicesFromArray:)
  public class func indices(from array: [NSNumber]) -> IndexSet {
    var indexSet = IndexSet()
    for number in array {
      indexSet.insert(number.intValue)
    }
    return indexSet
  }

  @objc(nullableValueForDictionary:key:)
  public class func nullableValue(for dictionary: [AnyHashable: Any], key: NSCopying) -> Any? {
    let value = (dictionary as NSDictionary).object(forKey: key)
    if value is NSNull {
      return nil
    }
    return value
  }

  @objc(arrayWithObject:count:)
  public class func array(with object: Any, count: UInt) -> [Any] {
    return Array(repeating: object, count: Int(count))
  }

  // MARK: Private

  private class func jsonSerializableValueOrNil(_ value: Any) -> Any? {
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
