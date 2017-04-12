/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBControlCore
import FBSimulatorControl

class HIDSocketConsumer : NSObject, FBSocketConsumer {
  let hid: FBSimulatorHID
  let buffer: FBLineBuffer

  init(hid: FBSimulatorHID) {
    self.hid = hid
    self.buffer = FBLineBuffer()
    super.init()
  }

  func consumeData(_ data: Data, writeBack: FBFileConsumer) {
    self.buffer.append(data)
    guard let response = self.perform() else {
      return
    }
    guard let data = response.data(using: String.Encoding.utf8) else {
      return
    }
    writeBack.consumeData(data)
  }

  private func perform() -> String? {
    var response = ""
    for lineData in IteratorSequence(self.buffer.dataIterator()) {
      response += self.runLine(input: lineData)
      response += "\n"
    }
    return response
  }

  private func runLine(input: Data) -> String {
    do {
      let json = try JSON.fromData(input)
      let event = try FBSimulatorHIDEvent.inflate(fromJSON: json.decode())
      try event.perform(on: self.hid)
      let response = JSON.dictionary([
        ResponseKeys.Status.rawValue : JSON.string(ResponseKeys.Success.rawValue),
        ResponseKeys.Events.rawValue: json,
      ])
      return try! response.serializeToString(false)
    } catch let error as CustomStringConvertible {
      return HIDSocketConsumer.describeError(error: error)
    } catch {
      return HIDSocketConsumer.describeError(error: nil)
    }
  }

  private static func describeError(error: CustomStringConvertible?) -> String {
    var contents = [
      ResponseKeys.Status.rawValue : JSON.string(ResponseKeys.Failure.rawValue),
    ]
    if let string = error?.description {
      contents[ResponseKeys.Message.rawValue] = JSON.string(string)
    }
    return try! JSON.dictionary(contents).serializeToString(false)
  }
}

class HIDSocketReaderDelegate : NSObject, FBSocketReaderDelegate {
  let hid: FBSimulatorHID

  init(hid: FBSimulatorHID) {
    self.hid = hid
    super.init()
  }

  func consumer(withClientAddress clientAddress: in6_addr) -> FBSocketConsumer {
    return HIDSocketConsumer(hid: self.hid)
  }
}

class HIDSocketRelay : Relay {
  let reader: FBSocketReader
  let delegate: HIDSocketReaderDelegate

  init(portNumber: in_port_t, hid: FBSimulatorHID) {
    self.delegate = HIDSocketReaderDelegate(hid: hid)
    self.reader = FBSocketReader(onPort: portNumber, delegate: self.delegate)
  }

  func start() throws {
    try self.reader.startListening()
  }

  func stop() throws {
    try self.reader.stopListening()
  }
}
