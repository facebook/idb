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

  public static var stdOutWriter: FileHandleWriter {
    get {
      return FileHandleWriter(fileHandle: NSFileHandle.fileHandleWithStandardOutput())
    }
  }

  public static var stdErrWriter: FileHandleWriter {
    get {
      return FileHandleWriter(fileHandle: NSFileHandle.fileHandleWithStandardError())
    }
  }
}


class StdIORelay : Relay {
  let relayConnection: RelayConnection
  let stdIn: NSFileHandle
  let reporter: RelayReporter

  init(configuration: Configuration, performer: ActionPerformer, reporter: RelayReporter) {
    self.relayConnection = RelayConnection(performer: performer, reporter: configuration.output.createReporter(FileHandleWriter.stdOutWriter))
    self.stdIn = NSFileHandle.fileHandleWithStandardInput()
    self.reporter = reporter
  }

  func start() {
    let lineBuffer = self.relayConnection.lineBuffer
    self.stdIn.readabilityHandler = { handle in
      let data = handle.availableData
      lineBuffer.appendData(data)
    }
    self.reporter.started()
    SignalHandler.runUntilSignalled(self.reporter.reporter)
    self.reporter.ended(nil)
  }

  func stop() {
    self.stdIn.readabilityHandler = nil
  }
}
