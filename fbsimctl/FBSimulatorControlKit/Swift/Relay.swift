/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

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
class CompositeRelay: Relay {
  let relays: [Relay]

  init(relays: [Relay]) {
    self.relays = relays
  }

  func start() throws {
    for relay in relays {
      try relay.start()
    }
  }

  func stop() throws {
    for relay in relays {
      // We want to stop all relays, so ignoring error propogation will ensure we clean up all of them.
      try? relay.stop()
    }
  }
}

/**
 Wraps an existing Relay, spinning the run loop after the underlying relay has started.
 */
class SynchronousRelay: Relay {
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
    try relay.start()
    started()

    // Construct the futures, whichever completes first will cause the await to break.
    var futures: [FBFuture<NSNull>] = []
    if let completedFuture = self.continuation?.completed {
      futures.append(completedFuture)
    }
    let signalFuture = SignalHandler.future.onQueue(DispatchQueue.main, map: { info in
      self.reporter.reportSimple(.signalled, .discrete, info)
      return NSNull()
    }) as! FBFuture<NSNull>
    futures.append(signalFuture)
    _ = try FBFuture(race: futures).await()

    // If there's an async cancellation, we can ensure that we wait for it to finish.
    if let completedFuture = self.continuation?.completed, completedFuture.state == .cancelled {
      _ = try completedFuture.cancel().await()
    }
  }

  func stop() throws {
    try relay.stop()
  }
}

/**
 Bridges an Action Reader to a Relay
 */
extension FBiOSActionReader: Relay {
  func start() throws {
    try startListening().await()
  }

  func stop() throws {
    try stopListening().await()
  }
}
