/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

public class FileHandleWriter : Writer {
  let fileHandle: NSFileHandle

  init(fileHandle: NSFileHandle) {
    self.fileHandle = fileHandle
  }

  public func write(var string: String) {
    if (string.characters.last != "\n") {
      string.append("\n" as Character)
    }
    let data = string.dataUsingEncoding(NSUTF8StringEncoding)!
    self.fileHandle.writeData(data)
  }

  public static var stdIOWriter: SuccessFailureWriter {
    get {
      return SuccessFailureWriter(
        success: FileHandleWriter(fileHandle: NSFileHandle.fileHandleWithStandardOutput()),
        failure: FileHandleWriter(fileHandle: NSFileHandle.fileHandleWithStandardError())
      )
    }
  }
}


class StdIORelay : Relay {
  let relayConnection: RelayConnection

  private let stdIn: NSFileHandle

  init(transformer: RelayTransformer) {
    self.relayConnection = RelayConnection(transformer: transformer, writer: FileHandleWriter.stdIOWriter)
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
}
