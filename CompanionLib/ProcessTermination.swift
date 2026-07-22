/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Awaits termination of the process `pid`, resolving when it exits (or promptly if
/// it is already gone).
public func waitForProcessExit(pid: pid_t) async {
  let watcher = ProcessExitWatcher(pid: pid)
  await withCheckedContinuation { continuation in
    watcher.begin(continuation: continuation)
  }
}

/// Bridges a one-shot `DispatchSource` exit watch to a continuation, resolving
/// exactly once.
///
/// `@unchecked Sendable`: all mutable state is guarded by `lock`. The watcher is
/// deliberately kept alive by its own source and handler closures (a strong cycle)
/// until `resolve()` breaks it, so it outlives the `begin` call it is created in.
private final class ProcessExitWatcher: @unchecked Sendable {

  private let pid: pid_t
  private let queue = DispatchQueue(label: "com.facebook.idb.repl.app-termination")
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var source: (any DispatchSourceProcess)?

  init(pid: pid_t) {
    self.pid = pid
  }

  func begin(continuation: CheckedContinuation<Void, Never>) {
    lock.lock()
    self.continuation = continuation
    let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
    self.source = source
    lock.unlock()

    // Strong `self` in the handlers intentionally keeps the watcher (and its source)
    // alive until `resolve()` clears them -- i.e. until the process exits.
    source.setEventHandler { self.resolve() }
    source.resume()

    // The process may have exited between resolving its pid and arming the watch, in
    // which case `.exit` is never delivered; probe liveness and resolve if it is
    // already gone.
    queue.async { self.resolveIfProcessGone() }
  }

  private func resolveIfProcessGone() {
    if Darwin.kill(pid, 0) != 0 && errno == ESRCH {
      resolve()
    }
  }

  private func resolve() {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    let source = self.source
    self.source = nil
    lock.unlock()

    guard let continuation else {
      return // already resolved
    }
    source?.cancel()
    continuation.resume()
  }
}
