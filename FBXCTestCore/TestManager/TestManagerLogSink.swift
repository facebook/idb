/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The logging surface the Objective-C DTX layer sees, so `ControlCoreLogger` need not be `@objc`.
@objc public protocol TestManagerLogSink: NSObjectProtocol {
  func log(_ message: String)
}

final class ControlCoreLoggerSink: NSObject, TestManagerLogSink {
  private let logger: ControlCoreLogger

  init(_ logger: ControlCoreLogger) {
    self.logger = logger
  }

  func log(_ message: String) {
    logger.log(message)
  }
}
