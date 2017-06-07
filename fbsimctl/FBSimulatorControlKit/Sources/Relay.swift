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

/**
 A Protocol for defining
 */
protocol Relay {
  func start() throws
  func stop() throws
}

/**
 A Relay that composes multiple relays.
 */
class CompositeRelay : Relay {
  let relays: [Relay]

  init(relays: [Relay]) {
    self.relays = relays
  }

  func start() throws {
    for relay in self.relays {
      try relay.start()
    }
  }

  func stop() throws {
    for relay in self.relays {
      // We want to stop all relays, so ignoring error propogation will ensure we clean up all of them.
      try? relay.stop()
    }
  }
}

/**
 Wraps an existing Relay, spinning the run loop after the underlying relay has started.
 */
class SynchronousRelay : Relay {
  let relay: Relay
  let reporter: EventReporter
  let awaitable: FBTerminationAwaitable?
  let started: () -> Void

  init(relay: Relay, reporter: EventReporter, awaitable: FBTerminationAwaitable?, started: @escaping () -> Void) {
    self.relay = relay
    self.reporter = reporter
    self.awaitable = awaitable
    self.started = started
  }

  func start() throws {
    // Setup the Signal Handling first, so sending a Signal cannot race with starting the relay.
    var signalled = false
    let handler = SignalHandler { info in
      self.reporter.reportSimple(.signalled, .discrete, info)
      signalled = true
    }
    handler.register()

    // Start the Relay and notify consumers.
    try self.relay.start()
    self.started()

    // Start the event loop.
    let awaitable = self.awaitable
    RunLoop.current.spinRunLoop(withTimeout: Double.greatestFiniteMagnitude, untilTrue: {
      // Check the awaitable (if present)
      if awaitable?.hasTerminated == true {
        return true
      }
      // Or return the current signal status.
      return signalled
    })
    handler.unregister()
  }

  func stop() throws {
    try self.relay.stop()
  }
}

/**
 Bridges an Action Reader to a Relay
 */
extension FBiOSActionReader : Relay {
  func start() throws {
    try self.startListening()
  }

  func stop() throws {
    try self.stopListening()
  }
}
