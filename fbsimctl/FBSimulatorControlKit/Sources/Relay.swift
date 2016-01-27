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
  func transform(input: String, reporter: EventReporter) -> ActionResult
}

/**
 A Connection of Reporter-to-Transformer, linebuffering an input
 */
class RelayConnection : LineBufferDelegate {
  let transformer: RelayTransformer
  let reporter: EventReporter
  lazy var lineBuffer: LineBuffer = LineBuffer(delegate: self)

  init (transformer: RelayTransformer, reporter: EventReporter) {
    self.transformer = transformer
    self.reporter = reporter
  }

  func buffer(lineAvailable: String) {
    let result = self.transformer.transform(lineAvailable, reporter: self.reporter)
    switch result {
    case .Failure(let error):
      self.reporter.reportSimple(EventName.Failure, EventType.Discrete, error)
    default:
      break
    }
  }
}
