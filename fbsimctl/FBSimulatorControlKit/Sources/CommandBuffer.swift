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
 A Sink of raw data, which will result in command/s occuring when a full command is encountered.
 */
class CommandBuffer {
  internal let performer: ActionPerformer
  internal let reporter: EventReporter
  fileprivate let buffer: FBLineBuffer

  init (performer: ActionPerformer, reporter: EventReporter) {
    self.performer = performer
    self.reporter = reporter
    self.buffer = FBLineBuffer()
  }

  func append(_ data: Data) -> [CommandResult] {
    self.buffer.append(data)
    return self.runBuffer()
  }

  fileprivate func runBuffer() -> [CommandResult] {
    let lines = Array(IteratorSequence(self.buffer.stringIterator()))
    if lines.isEmpty {
      return []
    }

    var results: [CommandResult] = []
    DispatchQueue.main.sync {
      for line in lines {
        results.append(self.lineAvailable(line))
      }
    }
    return results
  }

  fileprivate func lineAvailable(_ line: String) -> CommandResult {
    return self.performer.perform(line, reporter: self.reporter)
  }
}
