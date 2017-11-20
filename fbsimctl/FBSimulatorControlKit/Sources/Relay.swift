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
  let continuation: FBiOSTargetContinuation?
  let started: () -> Void

  init(relay: Relay, reporter: EventReporter, continuation: FBiOSTargetContinuation?, started: @escaping () -> Void) {
    self.relay = relay
    self.reporter = reporter
    self.continuation = continuation
    self.started = started
  }

  func start() throws {
    // Start the Relay and notify consumers.
    try self.relay.start()
    self.started()

    var futures: [FBFuture<NSNull>] = []
    if let completedFuture = self.continuation?.completed {
      futures.append(completedFuture)
    }
    let signalFuture = SignalHandler.future.onQueue(DispatchQueue.main, map: { info in
      self.reporter.reportSimple(.signalled, .discrete, info)
      return NSNull()
    }) as! FBFuture<NSNull>
    futures.append(signalFuture)
    let _ = try FBFuture(race: futures).await()
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
