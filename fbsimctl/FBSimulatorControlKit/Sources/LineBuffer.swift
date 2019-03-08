/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

class LineBuffer {
  unowned let delegate: LineBufferDelegate

  private var buffer: String = ""

  init(delegate: LineBufferDelegate) {
    self.delegate = delegate
  }

  func appendData(data: NSData) {
    let string = String(data: data, encoding: NSUTF8StringEncoding)!
    buffer.appendContentsOf(string)
    runBuffer()
  }

  private func runBuffer() {
    let buffer = self.buffer
    let lines = buffer
      .componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
      .filter { line in
        line != ""
      }
    if lines.isEmpty {
      return
    }

    self.buffer = ""
    let delegate = self.delegate

    dispatch_async(dispatch_get_main_queue()) {
      for line in lines {
        delegate.buffer(line)
      }
    }
  }
}

protocol LineBufferDelegate: class {
  func buffer(lineAvailable: String)
}
