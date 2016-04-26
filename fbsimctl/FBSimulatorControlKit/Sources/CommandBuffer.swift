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
protocol CommandBuffer {
  var performer: CommandPerformer { get }
  var reporter: EventReporter { get }
  func append(data: NSData) -> [CommandResult]
}

/**
 A CommandBuffer that will dispatch a command when a newline is encountered.
 */
class LineBuffer : CommandBuffer {
  internal let performer: CommandPerformer
  internal let reporter: EventReporter
  private var buffer: String = ""

  init (performer: CommandPerformer, reporter: EventReporter) {
    self.performer = performer
    self.reporter = reporter
  }

  func append(data: NSData) -> [CommandResult] {
    let string = String(data: data, encoding: NSUTF8StringEncoding)!
    self.buffer.appendContentsOf(string)
    return self.runBuffer()
  }

  private func runBuffer() -> [CommandResult] {
    let buffer = self.buffer
    let lines = buffer
      .componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
      .filter { line in
        line != ""
    }
    if (lines.isEmpty) {
      return []
    }

    self.buffer = ""
    var results: [CommandResult] = []
    dispatch_sync(dispatch_get_main_queue()) {
      for line in lines {
        results.append(self.lineAvailable(line))
      }
    }
    return results
  }

  private func lineAvailable(line: String) -> CommandResult {
    return self.performer.perform(line, reporter: self.reporter)
  }
}
