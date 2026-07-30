/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SwiftConcurrencyUtils

/// Errors surfaced by the remote-automation session and its invoker.
public enum FBRemoteAutomationError: Error, CustomStringConvertible {
  /// A remote invocation did not complete within its deadline.
  case invocationTimedOut(operation: String, deadline: TimeInterval)
  /// A runtime-loaded payload class or receipt was unavailable (framework not loaded).
  case payloadUnavailable(String)

  public var description: String {
    switch self {
    case let .invocationTimedOut(operation, deadline):
      return "Remote invocation \(operation) timed out after \(deadline)s"
    case let .payloadUnavailable(name):
      return "Remote-automation payload \(name) is unavailable; is XCTest.framework loaded?"
    }
  }
}

/// The async boundary the session depends on: the typed remote-automation operations, each
/// bounded by a deadline.
///
/// Injecting this keeps handshake ordering, capability parsing, and payload decoding
/// unit-testable with a fake, without a live DTX connection. The real implementation
/// (`DTXRemoteInvoker`) messages the typed proxy directly; a fake returns canned values.
public protocol RemoteInvoking: Sendable {
  func beginSession(clientProtocolVersion: Int, deadline: TimeInterval) async throws
  func exchangeCapabilities(deadline: TimeInterval) async throws -> sending Any?
  func loadAccessibility(timeout: TimeInterval, deadline: TimeInterval) async throws
  func synthesizeEvent(_ record: sending Any, implicitConfirmationInterval: TimeInterval, deadline: TimeInterval) async throws
  func requestElement(atPoint point: sending Any, deadline: TimeInterval) async throws -> sending Any?
  func fetchAttributes(_ attributes: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws -> sending Any?
  func setAttribute(_ attribute: sending Any, value: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws
  func performDeviceEvent(_ event: sending Any, deadline: TimeInterval) async throws
}

public extension RemoteInvoking {
  /// Default: this invoker does not implement the device-event selector (e.g. a test fake). The real
  /// `DTXRemoteInvoker` overrides this to message the guest daemon.
  func performDeviceEvent(_ event: sending Any, deadline: TimeInterval) async throws {
    throw FBRemoteAutomationError.payloadUnavailable("performDeviceEvent")
  }
}

/// Serializes the one-shot completion of a single remote invocation to exactly one
/// continuation resume, resolving the race between the DTX receipt, the deadline timer,
/// and task cancellation.
///
// SAFETY: every read/write of the continuation and flags is serialized by `lock`, and the
// continuation is resumed only after the lock is released, so no external code runs under
// the lock. `AssertingSafeContinuation` additionally tolerates redundant resumes.
// patternlint-disable-next-line unchecked-sendable
private final class InvocationBridge: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: AssertingSafeContinuation<Any?, Error>?
  private var finished = false
  private var pendingCancellation = false

  func store(_ continuation: AssertingSafeContinuation<Any?, Error>) {
    lock.lock()
    if pendingCancellation {
      lock.unlock()
      continuation.resume(throwing: CancellationError())
      return
    }
    self.continuation = continuation
    lock.unlock()
  }

  func resolve(_ result: Result<Any?, Error>) {
    lock.lock()
    if finished {
      lock.unlock()
      return
    }
    finished = true
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(with: result)
  }

  func cancel() {
    lock.lock()
    if finished {
      lock.unlock()
      return
    }
    finished = true
    let continuation = self.continuation
    self.continuation = nil
    if continuation == nil {
      // Cancellation raced ahead of the continuation being stored; defer to `store`.
      pendingCancellation = true
    }
    lock.unlock()
    continuation?.resume(throwing: CancellationError())
  }
}

/// The real `RemoteInvoking`, driving a resumed DTX connection.
///
/// Messages the typed `FBRemoteAutomationServer` proxy directly and bridges each returned
/// `FBRemoteAutomationReceipt` to a continuation, bounding it with a per-call deadline (a
/// cold `loadAccessibility` can hang) and honouring task cancellation by throwing
/// `CancellationError` — without tearing the shared connection, since a hard per-call abort
/// would abort other in-flight commands on the one channel.
public final class DTXRemoteInvoker: RemoteInvoking {

  // SAFETY: FBRemoteAutomationConnection serializes its DTX sends internally and exposes only
  // atomic state and the thread-safe proxy, so messaging it from any thread/task is safe.
  // patternlint-disable-next-line swift-nonisolated-unsafe
  nonisolated(unsafe) private let connection: FBRemoteAutomationConnection
  private let queue: DispatchQueue

  public init(connection: FBRemoteAutomationConnection) {
    self.connection = connection
    self.queue = DispatchQueue(label: "com.facebook.FBRemoteAutomation.invoker")
  }

  public func beginSession(clientProtocolVersion: Int, deadline: TimeInterval) async throws {
    let receipt = connection.remoteProxy.beginSession(clientProtocolVersion: NSNumber(value: clientProtocolVersion))
    _ = try await awaitReceipt(receipt, operation: "beginSession", deadline: deadline)
  }

  public func exchangeCapabilities(deadline: TimeInterval) async throws -> sending Any? {
    let receipt = connection.remoteProxy.exchangeCapabilities(NSDictionary())
    return try await awaitReceipt(receipt, operation: "exchangeCapabilities", deadline: deadline)
  }

  public func loadAccessibility(timeout: TimeInterval, deadline: TimeInterval) async throws {
    let receipt = connection.remoteProxy.loadAccessibility(timeout: NSNumber(value: timeout))
    _ = try await awaitReceipt(receipt, operation: "loadAccessibility", deadline: deadline)
  }

  public func synthesizeEvent(_ record: sending Any, implicitConfirmationInterval: TimeInterval, deadline: TimeInterval) async throws {
    let receipt = connection.remoteProxy.synthesizeEvent(record, implicitConfirmationInterval: NSNumber(value: implicitConfirmationInterval))
    _ = try await awaitReceipt(receipt, operation: "synthesizeEvent", deadline: deadline)
  }

  public func requestElement(atPoint point: sending Any, deadline: TimeInterval) async throws -> sending Any? {
    let receipt = connection.remoteProxy.requestElement(atPoint: point)
    return try await awaitReceipt(receipt, operation: "requestElementAtPoint", deadline: deadline)
  }

  public func fetchAttributes(_ attributes: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws -> sending Any? {
    let receipt = connection.remoteProxy.fetchAttributes(attributes, forElement: element)
    return try await awaitReceipt(receipt, operation: "fetchAttributes", deadline: deadline)
  }

  public func setAttribute(_ attribute: sending Any, value: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws {
    let receipt = connection.remoteProxy.setAttribute(attribute, value: value, element: element)
    _ = try await awaitReceipt(receipt, operation: "setAttribute", deadline: deadline)
  }

  public func performDeviceEvent(_ event: sending Any, deadline: TimeInterval) async throws {
    let receipt = connection.remoteProxy.performDeviceEvent(event)
    _ = try await awaitReceipt(receipt, operation: "performDeviceEvent", deadline: deadline)
  }

  private func awaitReceipt(_ receipt: sending (any FBRemoteAutomationReceipt)?, operation: String, deadline: TimeInterval) async throws -> sending Any? {
    try await awaitRemoteReceipt(receipt, operation: operation, deadline: deadline, queue: queue)
  }
}

/// Awaits a single remote-automation receipt, resolving the race between the receipt's
/// completion, a per-call deadline, and task cancellation down to exactly one continuation
/// resume.
///
/// Split out from `DTXRemoteInvoker` so this deadline/cancel/single-resume behaviour — the
/// hot-spot — is unit-testable against a fake `FBRemoteAutomationReceipt`, with no live
/// connection.
func awaitRemoteReceipt(
  _ receipt: sending (any FBRemoteAutomationReceipt)?,
  operation: String,
  deadline: TimeInterval,
  queue: DispatchQueue
) async throws -> sending Any? {
  try Task.checkCancellation()
  guard let receipt else {
    throw FBRemoteAutomationError.payloadUnavailable("receipt for \(operation)")
  }
  let bridge = InvocationBridge()
  return try await withTaskCancellationHandler {
    try await withAssertingSafeThrowingContinuation { (continuation: AssertingSafeContinuation<Any?, Error>) in
      bridge.store(continuation)
      let timeout = DispatchWorkItem {
        bridge.resolve(.failure(FBRemoteAutomationError.invocationTimedOut(operation: operation, deadline: deadline)))
      }
      queue.asyncAfter(deadline: .now() + deadline, execute: timeout)
      receipt.handleCompletion { value, error in
        timeout.cancel()
        if let error {
          bridge.resolve(.failure(error))
        } else {
          bridge.resolve(.success(value))
        }
      }
    }
  } onCancel: {
    bridge.cancel()
  }
}
