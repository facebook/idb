/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

struct Arguments {
  static func fromString(_ string: String) -> [String] {
    let characterSet = NSMutableCharacterSet()
    characterSet.formUnion(with: CharacterSet.alphanumerics)
    characterSet.formUnion(with: CharacterSet.symbols)
    characterSet.formUnion(with: CharacterSet.punctuationCharacters)
    characterSet.invert()

    return string
      .trimmingCharacters(in: characterSet as CharacterSet)
      .components(separatedBy: CharacterSet.whitespaces)
  }
}
