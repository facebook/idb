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
  let started: (Void) -> Void

  init(relay: Relay, reporter: EventReporter, started: @escaping (Void) -> Void) {
    self.relay = relay
    self.reporter = reporter
    self.started = started
  }

  func start() throws {
    // Setup the Signal Handling first, so sending a Signal cannot race with starting the relay.
    var signalled = false
    let handler = SignalHandler { info in
      self.reporter.reportSimple(EventName.Signalled, EventType.Discrete, info)
      signalled = true
    }
    handler.register()

    // Start the Relay and notify consumers.
    try self.relay.start()
    self.started()

    // Start the event loop.
    RunLoop.current.spinRunLoop(withTimeout: DBL_MAX) { signalled }
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
  let input: FileHandle

  init(commandBuffer: CommandBuffer, input: FileHandle) {
    self.commandBuffer = commandBuffer
    self.input = input
  }

  convenience init(commandBuffer: CommandBuffer) {
    self.init(
      commandBuffer: commandBuffer,
      input: FileHandle.standardInput
    )
  }

  func start() throws {
    let commandBuffer = self.commandBuffer
    self.input.readabilityHandler = { handle in
      let data = handle.availableData
      let _ = commandBuffer.append(data)
    }
  }

  func stop() {
    self.input.readabilityHandler = nil
  }
}
