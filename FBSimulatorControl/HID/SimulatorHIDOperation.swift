/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Exclusive use of HID for one complete operation, shared by a simulator's HID instances.
// SAFETY: All mutable state is protected by lock; continuations resume outside it.
final class SimulatorHIDOperationLease: @unchecked Sendable {
  private let lock = NSLock()
  private var inUse = false
  private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []

  func withLease<T>(_ operation: () async throws -> T) async throws -> T {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        park(id, continuation)
      }
    } onCancel: {
      cancel(id)
    }
    defer { release() }
    try Task.checkCancellation()
    return try await operation()
  }

  private func park(_ id: UUID, _ continuation: CheckedContinuation<Void, Error>) {
    lock.lock()
    if Task.isCancelled {
      lock.unlock()
      continuation.resume(throwing: CancellationError())
    } else if inUse {
      waiters.append((id, continuation))
      lock.unlock()
    } else {
      inUse = true
      lock.unlock()
      continuation.resume()
    }
  }

  private func cancel(_ id: UUID) {
    lock.lock()
    guard let index = waiters.firstIndex(where: { $0.0 == id }) else {
      lock.unlock()
      return
    }
    let (_, continuation) = waiters.remove(at: index)
    lock.unlock()
    continuation.resume(throwing: CancellationError())
  }

  private func release() {
    lock.lock()
    if waiters.isEmpty {
      inUse = false
      lock.unlock()
    } else {
      let (_, continuation) = waiters.removeFirst()
      lock.unlock()
      continuation.resume()
    }
  }
}

/// Latches observed changes so a later matching snapshot cannot hide a transition.
// SAFETY: The failure is accessed only while holding lock.
final class SimulatorHIDDisplayObservation: @unchecked Sendable {
  private let lock = NSLock()
  private var failure: Error?

  func record(_ result: Result<SimulatorHIDDisplay?, Error>, matching display: SimulatorHIDDisplay) {
    let error: Error?
    switch result {
    case let .success(current):
      error = current.map { display.hasSameConfiguration(as: $0) } == true ? nil : SimulatorDisplayError.changed
    // Mid-gesture, a transition means the display is changing; the gesture must not wait for it to settle.
    case .failure(SimulatorDisplayError.transitioning): error = SimulatorDisplayError.changed
    case let .failure(cause): error = cause
    }
    lock.lock()
    if failure == nil { failure = error }
    lock.unlock()
  }

  func check() throws {
    lock.lock()
    let error = failure
    lock.unlock()
    if let error { throw error }
  }
}

/// Operation-local state; no caller can send another event through this binding concurrently.
struct SimulatorHIDOperation {
  let displays: (any DisplayCommands)?
  let deliver: @Sendable (SimulatorHIDEvent, SimulatorHIDDisplay?) async throws -> Void
  let flush: @Sendable () async throws -> Void
  let reportCleanupError: @Sendable (Error) -> Void
  let log: @Sendable (String) -> Void

  private let observation: SimulatorHIDDisplayObservation
  private var observationTask: Task<Void, Never>?
  private var resolvedDisplay = false
  private var display: SimulatorHIDDisplay?
  private var singleRelease: SimulatorHIDEvent?
  private var twoFingerRelease: SimulatorHIDEvent?
  private var needsFlush = false

  init(
    displays: (any DisplayCommands)?,
    deliver: @escaping @Sendable (SimulatorHIDEvent, SimulatorHIDDisplay?) async throws -> Void,
    flush: @escaping @Sendable () async throws -> Void,
    reportCleanupError: @escaping @Sendable (Error) -> Void,
    log: @escaping @Sendable (String) -> Void,
    observation: SimulatorHIDDisplayObservation = SimulatorHIDDisplayObservation()
  ) {
    self.observation = observation
    self.displays = displays
    self.deliver = deliver
    self.flush = flush
    self.reportCleanupError = reportCleanupError
    self.log = log
  }

  mutating func send(_ event: SimulatorHIDEvent) async throws {
    try Task.checkCancellation()
    if case let .composite(events) = event {
      for child in events { try await send(child) }
      return
    }
    var event = event
    switch event {
    case let .touch(direction, x, y, edge):
      try await bindOrValidateDisplay()
      let point = try clamp(CGPoint(x: x, y: y))
      event = .touch(direction: direction, x: point.x, y: point.y, edge: edge)
      if direction == .down { singleRelease = .touch(direction: .up, x: point.x, y: point.y, edge: edge) }
    case let .twoFingerTouch(direction, first, second):
      try await bindOrValidateDisplay()
      let first = try clamp(first)
      let second = try clamp(second)
      event = .twoFingerTouch(direction: direction, finger1: first, finger2: second)
      if direction == .down { twoFingerRelease = .twoFingerTouch(direction: .up, finger1: first, finger2: second) }
    case .button, .remoteButton, .keyboard, .trackpad, .delay, .composite:
      break
    }
    try Task.checkCancellation()
    try observation.check()
    try await deliver(event, display)
    needsFlush = true
    switch event {
    case .touch(.up, _, _, _): singleRelease = nil
    case .twoFingerTouch(.up, _, _): twoFingerRelease = nil
    case .touch, .twoFingerTouch, .button, .remoteButton, .keyboard, .trackpad, .delay, .composite:
      break
    }
  }

  mutating func finish(flushing: Bool) async throws {
    try Task.checkCancellation()
    if flushing, needsFlush {
      needsFlush = false
      try await flush()
    }
    try Task.checkCancellation()
    if let display {
      observation.record(.success(try await Self.route(displays)), matching: display)
    }
    await stopObserving()
    try Task.checkCancellation()
    try observation.check()
  }

  private func clamp(_ point: CGPoint) throws -> CGPoint {
    guard point.x.isFinite, point.y.isFinite else { throw SimulatorDisplayInteractionError.nonFinitePoint(point) }
    guard let display else { return point }
    let clamped = display.clampedPoint(point)
    if clamped != point {
      let size = display.geometry.pointSize
      log("Clamped touch point (\(point.x), \(point.y)) to (\(clamped.x), \(clamped.y)) within the display's point bounds (\(size.width) x \(size.height))")
    }
    return clamped
  }

  private mutating func bindOrValidateDisplay() async throws {
    if !resolvedDisplay {
      display = try await Self.route(displays)
      try Task.checkCancellation()
      resolvedDisplay = true
      if let display, let displays {
        let observation = observation
        // Capability round trips must not stretch the gesture's sample intervals. The operation
        // owns this observer and joins it before releasing its lease, including on cancellation.
        observationTask = Task {
          while !Task.isCancelled {
            do {
              let current = try await displays.currentDisplay()
              if Task.isCancelled { return }
              switch current {
              case .transitioning:
                throw SimulatorDisplayError.transitioning
              case .fallback:
                throw SimulatorDisplayError.changed
              case let .target(target):
                guard target.display.hasSameConfiguration(as: display.interactionDisplay) else { throw SimulatorDisplayError.changed }
              }
              try observation.check()
              try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
              if !Task.isCancelled { observation.record(.failure(error), matching: display) }
              return
            }
          }
        }
      }
    }
    try observation.check()
  }

  /// Nil when interactions fall back to the main display, which input reaches without a digitizer target.
  private static func route(_ displays: (any DisplayCommands)?) async throws -> SimulatorHIDDisplay? {
    guard let displays else { return nil }
    switch try await displays.resolveDisplay() {
    case .transitioning: throw SimulatorDisplayError.transitioning
    case .fallback: return nil
    case let .target(.sole(display)): return .sole(display)
    case let .target(.selected(display)): return .selected(display, target: try await displays.digitizerTarget(for: display))
    }
  }

  private func stopObserving() async {
    observationTask?.cancel()
    await observationTask?.value
  }

  /// Cleanup is shielded from cancellation and uses the original target, even if it became inactive.
  func cleanup() async {
    await stopObserving()
    let releases = [singleRelease, twoFingerRelease].compactMap { $0 }
    let display = display
    let deliver = deliver
    let flush = flush
    let report = reportCleanupError
    let shouldFlush = needsFlush || !releases.isEmpty
    let cleanup = Task {
      for event in releases {
        do { try await deliver(event, display) } catch { report(error) }
      }
      if shouldFlush {
        do { try await flush() } catch { report(error) }
      }
    }
    await cleanup.value
  }
}
