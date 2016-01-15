/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

/**
 A Protocol for instances that act as sinks of and sources of lines.
 */
protocol Relay {
  func start()
  func stop()
}

/**
 A Protocol for performing an Action producing an ActionResult.
 */
protocol RelayTransformer {
  func transform(input: String, writer: Writer) -> ActionResult
}

/**
 A Connection of Input-to-Output via a buffer.
 */
class RelayConnection : LineBufferDelegate {
  let transformer: RelayTransformer
  let writer: SuccessFailureWriter
  lazy var lineBuffer: LineBuffer = LineBuffer(delegate: self)

  init (transformer: RelayTransformer, writer: SuccessFailureWriter) {
    self.transformer = transformer
    self.writer = writer
  }

  func buffer(lineAvailable: String) {
    self.writer.writeActionResult(
      self.transformer.transform(lineAvailable, writer: self.writer.success)
    )
  }
}
