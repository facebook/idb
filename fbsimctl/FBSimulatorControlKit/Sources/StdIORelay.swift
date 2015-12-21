/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

class StdIORelay : Relay {
  let relayConnection: RelayConnection

  private let stdIn: NSFileHandle

  init(transformer: RelayTransformer) {
    self.relayConnection = RelayConnection(transformer: transformer, outputWriter: StdIOWriter())
    self.stdIn = NSFileHandle.fileHandleWithStandardInput()
  }

  func start() {
    let lineBuffer = self.relayConnection.lineBuffer

    self.stdIn.readabilityHandler = { handle in
      let data = handle.availableData
      lineBuffer.appendData(data)
    }
    SignalHandler.runUntilSignalled()
  }

  func stop() {
    self.stdIn.readabilityHandler = nil
  }

  class StdIOWriter : OutputWriter {
    private let stdOut: NSFileHandle
    private let stdErr: NSFileHandle

    init() {
      self.stdOut = NSFileHandle.fileHandleWithStandardOutput()
      self.stdErr = NSFileHandle.fileHandleWithStandardError()
    }

    func writeOut(string: String) {
      self.write(string, handle: self.stdOut)
    }

    func writeErr(string: String) {
      self.write(string, handle: self.stdErr)
    }

    private func write(var string: String, handle: NSFileHandle) {
      if (string.characters.last != "\n") {
        string.append("\n" as Character)
      }
      let data = string.dataUsingEncoding(NSUTF8StringEncoding)!
      handle.writeData(data)
    }
  }
}
