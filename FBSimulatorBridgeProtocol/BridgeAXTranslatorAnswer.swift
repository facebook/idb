/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// One element's answer to a multiple-attribute translator request: the response's `resultData`, keyed by
/// the attributes it was asked for. The host reads it over CoreSimulatorBridge and the guest in-process; both
/// read values out of it by `BridgeAXTranslatorAttribute` rather than by number.
///
/// Values are the translator's own objects, so only a reader that knows how to convert them should look
/// inside: the guest coerces them to JSON under its exception guard, the host converts them as AppKit would.
public struct BridgeAXTranslatorAnswer {
  private let values: [Int: Any]

  /// Nil unless `resultData` is a dictionary, which is how the translator reports that it could not read
  /// the element at all rather than that the element has no values.
  public init?(resultData: Any?) {
    guard let dictionary = resultData as? NSDictionary else {
      return nil
    }
    var values: [Int: Any] = [:]
    for case let (key as NSNumber, value) in dictionary {
      values[key.intValue] = value
    }
    self.values = values
  }

  public subscript(attribute: BridgeAXTranslatorAttribute) -> Any? {
    values[attribute.rawValue]
  }
}
