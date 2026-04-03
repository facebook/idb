/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public final class FBExceptionInfo: NSObject {

  @objc public let message: String
  @objc public let file: String?
  @objc public let line: UInt

  @objc public init(message: String, file: String?, line: UInt) {
    self.message = message
    self.file = file
    self.line = line
    super.init()
  }

  @objc public convenience init(message: String) {
    self.init(message: message, file: nil, line: 0)
  }

  public override var description: String {
    return "Message \(message) | File \(file ?? "(null)") | Line \(line)"
  }
}
