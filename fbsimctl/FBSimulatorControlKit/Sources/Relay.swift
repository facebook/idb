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
 A Protocol for defining
 */
protocol Relay {
  func start() throws
  func stop() throws
}

/**
 Wraps an existing Relay, spinning the run loop after the underlying relay has started.
 */
class SynchronousRelay : Relay {
  let relay: Relay
  let reporter: EventReporter

  init(relay: Relay, reporter: EventReporter) {
    self.relay = relay
    self.reporter = reporter
  }

  func start() throws {
    try self.relay.start()
    var signalled = false

    let handler = SignalHandler { info in
      self.reporter.reportSimple(EventName.Signalled, EventType.Discrete, info)
      signalled = true
    }

    handler.register()
    NSRunLoop.currentRunLoop().spinRunLoopWithTimeout(DBL_MAX) { signalled }
    handler.unregister()
  }

  func stop() throws {
    try self.relay.stop()
  }
}

/**
 A Relay that accepts input from stdin, writing it to the Line Buffer.
 */
class FileHandleRelay : Relay {
  let commandBuffer: CommandBuffer
  let input: NSFileHandle

  init(commandBuffer: CommandBuffer, input: NSFileHandle) {
    self.commandBuffer = commandBuffer
    self.input = input
  }

  convenience init(commandBuffer: CommandBuffer) {
    self.init(
      commandBuffer: commandBuffer,
      input: NSFileHandle.fileHandleWithStandardInput()
    )
  }

  func start() throws {
    let commandBuffer = self.commandBuffer
    self.input.readabilityHandler = { handle in
      let data = handle.availableData
      commandBuffer.append(data)
    }
  }

  func stop() {
    self.input.readabilityHandler = nil
  }
}
