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
  func write(_ string: String)
}

/**
 A Writer Implementation for a File Handle
 */
open class FileHandleWriter : Writer {
  let fileHandle: FileHandle

  init(fileHandle: FileHandle) {
    self.fileHandle = fileHandle
  }

  open func write(_ string: String) {
    var output = string
    if (output.characters.last != "\n") {
      output.append("\n" as Character)
    }
    guard let data = output.data(using: String.Encoding.utf8) else {
      return
    }
    self.fileHandle.write(data)
  }

  open static var stdOutWriter: FileHandleWriter { get {
    return FileHandleWriter(fileHandle: FileHandle.standardOutput)
  }}

  open static var stdErrWriter: FileHandleWriter { get {
    return FileHandleWriter(fileHandle: FileHandle.standardError)
  }}
}
