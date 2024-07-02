/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

struct CodeLocation: CustomStringConvertible {
  let function: String?
  let file: String
  let line: Int
  let column: Int

  var description: String {
    "Located at file: \(file), line: \(line), column: \(column)" + (function.map { ", function: " + $0 } ?? "")
  }
}
