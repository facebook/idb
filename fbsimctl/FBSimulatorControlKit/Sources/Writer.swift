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
 A Protocol for writing Strings out.
 */
public protocol Writer {
  func write(string: String)
}

/**
 A Writer Implementation for a File Handle
 */
public class FileHandleWriter : Writer {
  let fileHandle: NSFileHandle

  init(fileHandle: NSFileHandle) {
    self.fileHandle = fileHandle
  }

  public func write(string: String) {
    var output = string
    if (output.characters.last != "\n") {
      output.append("\n" as Character)
    }
    guard let data = output.dataUsingEncoding(NSUTF8StringEncoding) else {
      return
    }
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
