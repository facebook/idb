/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBCollectionInformation)
public final class FBCollectionInformation: NSObject {

  @objc(oneLineDescriptionFromArray:)
  public class func oneLineDescription(from array: [Any]) -> String {
    joined(array)
  }

  @objc(oneLineDescriptionFromArray:atKeyPath:)
  public class func oneLineDescription(from array: [Any], atKeyPath keyPath: String) -> String {
    // A keyPath that isn't a per-element property (an aggregate operator, say) resolves to a scalar;
    // describe the elements themselves rather than dropping them from the description entirely.
    joined((array as NSArray).value(forKeyPath: keyPath) as? [Any] ?? array)
  }

  private static func joined(_ elements: [Any]) -> String {
    "[\(elements.map { String(describing: $0) }.joined(separator: ", "))]"
  }

  @objc(oneLineDescriptionFromDictionary:)
  public class func oneLineDescription(from dictionary: [String: Any]) -> String {
    let pieces = dictionary.map { "\($0.key) => \($0.value)" }
    return "{\(pieces.joined(separator: ", "))}"
  }

  @objc(isArrayHeterogeneous:withClass:)
  public class func isArrayHeterogeneous(_ array: [Any], with cls: AnyClass) -> Bool {
    for object in array {
      if !(object as AnyObject).isKind(of: cls) {
        return false
      }
    }
    return true
  }

  @objc(isDictionaryHeterogeneous:keyClass:valueClass:)
  public class func isDictionaryHeterogeneous(_ dictionary: [AnyHashable: Any], keyClass keyCls: AnyClass, valueClass valueCls: AnyClass) -> Bool {
    for key in dictionary.keys {
      if !(key as AnyObject).isKind(of: keyCls) {
        return false
      }
    }
    for value in dictionary.values {
      if !(value as AnyObject).isKind(of: valueCls) {
        return false
      }
    }
    return true
  }
}
