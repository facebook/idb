/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

struct Arguments {
  static func fromString(string: String) -> [String] {
    let characterSet = NSMutableCharacterSet()
    characterSet.formUnionWithCharacterSet(NSCharacterSet.alphanumericCharacterSet())
    characterSet.formUnionWithCharacterSet(NSCharacterSet.symbolCharacterSet())
    characterSet.formUnionWithCharacterSet(NSCharacterSet.punctuationCharacterSet())
    characterSet.invert()

    return string
      .stringByTrimmingCharactersInSet(characterSet)
      .componentsSeparatedByCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
  }
}
