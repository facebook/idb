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
 A Class that acts as a sink and source of lines, transforming input to output via InputOutputRelayDataSource
 */
protocol Relay {
  func start()
  func stop()
}

/**
 DataSource for transforming Input to Output
 */
protocol RelayTransformer {
  func transform(input: String) -> Output
}

/**
  Enum for defining the result of a translation
 */
public enum Output {
  case Success(String)
  case Failure(String)
}

/**
 A sink of Strings
 */
protocol OutputWriter {
  func writeOut(string: String)
  func writeErr(string: String)
}

/**
  A Connection of input to output via a buffer
 */
class RelayConnection : LineBufferDelegate {
  let transformer: RelayTransformer
  let outputWriter: OutputWriter
  lazy var lineBuffer: LineBuffer = LineBuffer(delegate: self)

  init (transformer: RelayTransformer, outputWriter: OutputWriter) {
    self.transformer = transformer
    self.outputWriter = outputWriter
  }

  func buffer(lineAvailable: String) {
    let result = self.transformer.transform(lineAvailable)
    switch (result) {
    case .Success(let string):
      self.outputWriter.writeOut(string)
    case .Failure(let string):
      self.outputWriter.writeErr(string)
    }
  }
}
