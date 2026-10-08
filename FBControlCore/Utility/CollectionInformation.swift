/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc
public final class CollectionInformation: NSObject {

  @objc(oneLineDescriptionFromArray:)
  public class func oneLineDescription(from array: [Any]) -> String {
    joined(array)
  }

  private static func joined(_ elements: [Any]) -> String {
    "[\(elements.map { String(describing: $0) }.joined(separator: ", "))]"
  }

  @objc(oneLineDescriptionFromDictionary:)
  public class func oneLineDescription(from dictionary: [String: Any]) -> String {
    let pieces = dictionary.map { "\($0.key) => \($0.value)" }
    return "{\(pieces.joined(separator: ", "))}"
  }
}
