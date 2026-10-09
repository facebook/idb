/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public final class TestExceptionInfo: NSObject {

  public let message: String
  public let file: String?
  public let line: UInt

  @objc public init(message: String, file: String?, line: UInt) {
    self.message = message
    self.file = file
    self.line = line
    super.init()
  }

  public convenience init(message: String) {
    self.init(message: message, file: nil, line: 0)
  }

  public override var description: String {
    "Message \(message) | File \(file ?? "(null)") | Line \(line)"
  }
}
