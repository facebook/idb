/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public final class TestExceptionInfo: CustomStringConvertible {

  public let message: String
  public let file: String?
  public let line: UInt

  public init(message: String, file: String?, line: UInt) {
    self.message = message
    self.file = file
    self.line = line
  }

  public convenience init(message: String) {
    self.init(message: message, file: nil, line: 0)
  }

  public var description: String {
    "Message \(message) | File \(file ?? "(null)") | Line \(line)"
  }
}
