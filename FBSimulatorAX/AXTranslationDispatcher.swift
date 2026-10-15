/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency internal import AccessibilityPlatformTranslation
import CoreSimulator
import FBControlCore
import FBSimulatorControl
import Foundation

/// One unit of work and its result, carried across the hop onto a dispatch queue and
/// back. SAFETY: the body runs exactly once, on the queue it is dispatched to; the
/// continuation resume that follows it establishes the happens-before for the result
/// read after the await.
// patternlint-disable-next-line unchecked-sendable
private final class AXPSerializedJob<T>: @unchecked Sendable {
  private struct NeverRan: Error {}

  private let body: () throws -> T
  private var result: Result<T, Error> = .failure(NeverRan())

  init(_ body: @escaping () throws -> T) {
    self.body = body
  }

  func run() {
    result = Result(catching: body)
  }

  func takeResult() throws -> T {
    try result.get()
  }
}

/// Answers `AXPTranslator`'s synchronous bridge callbacks. Holds the token→request registry and, per
/// request, performs the translator handshake and hands each translator request to that request's
/// `AXTranslationTransport`.
///
/// An `@objc`/`NSObject` class only because it conforms to the Objective-C
/// `AXPTranslationTokenDelegateHelper` protocol and is installed as
/// `AXPTranslator`'s bridge-token delegate.
// SAFETY: the token registry is only touched under `lock`, `translator` is assigned once in `init`, and every
// translator interaction runs on the one serial work queue below.
// patternlint-disable-next-line unchecked-sendable
final class AXTranslationDispatcher: NSObject, AXPTranslationTokenDelegateHelper, @unchecked Sendable {

  private weak var translator: AXPTranslator?
  private let lock = NSLock()
  private var tokenToRequest: [String: AXTranslationRequest] = [:]

  // AXPTranslator is a process-wide singleton whose internal state (nonatomic
  // properties, shared element caches) is not synchronized, so its API contract is
  // single-threaded. Concurrent translation work over-releases shared
  // bridge-delegate token storage (EXC_BAD_ACCESS in AXTranslationRequest.deinit),
  // so every touch of the translator or its elements funnels through this one serial
  // queue — process-wide, matching the singleton it guards. Running the walks here
  // also keeps their synchronous XPC waits off the cooperative thread pool.
  private static let axpWorkQueue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.accessibility_translator.work")

  init(translator: AXPTranslator) {
    self.translator = translator
    super.init()
  }

  // MARK: - Public

  /// Runs `operation` on the process-wide AXP work queue, awaiting its result. All
  /// translator interaction — the translation handshake, serialization walks,
  /// attribute reads, and actions — must go through here; the queue is what upholds
  /// the translator singleton's single-threaded contract.
  func performSerialized<T>(_ operation: @escaping () throws -> T) async throws -> T {
    try await perform(operation, on: Self.axpWorkQueue, cancellation: nil)
  }

  /// Runs `operation`, which never touches the translator, on a queue it may block — its transport waits
  /// synchronously — off the main actor and the cooperative executor, and not behind translator work.
  func performUnserialized<T>(
    cancelling cancellation: AXReadCancellation? = nil, _ operation: @escaping () throws -> T
  ) async throws -> T {
    try await perform(operation, on: .global(qos: .userInitiated), cancellation: cancellation)
  }

  /// Runs a read of `handle` on the translator's work queue when it goes through the translator, and off it
  /// when it is raw.
  func performRead<T>(
    of handle: AXElementHandle, for request: AXTranslationRequest, reads: AXTranslatorReads,
    _ operation: @escaping () throws -> T
  ) async throws -> T {
    request.readsRaw(handle, reads: reads)
      ? try await performUnserialized(cancelling: request.cancellation, operation) : try await performSerialized(operation)
  }

  /// `cancellation` carries the awaiting task's cancellation into `operation`, which runs where a task cannot
  /// reach it.
  private func perform<T>(
    _ operation: @escaping () throws -> T, on queue: DispatchQueue, cancellation: AXReadCancellation?
  ) async throws -> T {
    let job = AXPSerializedJob(operation)
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        queue.async {
          job.run()
          continuation.resume()
        }
      }
    } onCancel: {
      cancellation?.cancel()
    }
    return try job.takeResult()
  }

  /// Resolves `request`'s root in one request over its transport, without touching the translator.
  func rootHandle(withRequest request: AXTranslationRequest) async throws -> AXElementHandle {
    request.translator = self.translator
    // Registered before resolving: actions on the root and its descendants reach the translator, whose
    // callbacks find the request by its token.
    self.pushRequest(request)
    do {
      return try await performUnserialized(cancelling: request.cancellation) { () throws -> AXElementHandle in
        let translationStart = CFAbsoluteTimeGetCurrent()
        guard let translation = try request.resolveRoot() else {
          throw AccessibilityError.noTranslationObject(request.query)
        }
        request.collector.translationDuration = CFAbsoluteTimeGetCurrent() - translationStart
        translation.bridgeDelegateToken = request.token
        return .translation(translation)
      }
    } catch {
      self.popRequest(request)
      throw error
    }
  }

  // MARK: - Private

  private func pushRequest(_ request: AXTranslationRequest) {
    lock.lock()
    defer { lock.unlock() }
    tokenToRequest[request.token] = request
  }

  /// Idempotent: remediation may already have replaced the request.
  func popRequest(_ request: AXTranslationRequest) {
    lock.lock()
    defer { lock.unlock() }
    tokenToRequest.removeValue(forKey: request.token)
  }

  private func request(forToken token: String) -> AXTranslationRequest? {
    lock.lock()
    defer { lock.unlock() }
    return tokenToRequest[token]
  }

  private static func emptyResponse() -> AXPTranslatorResponse? {
    AXPTranslatorResponse.empty() as? AXPTranslatorResponse
  }

  // MARK: - AXPTranslationTokenDelegateHelper

  // AXPTranslator's delegation is synchronous, so the request's transport waits for each answer. The wait
  // must never run on the main queue.
  func accessibilityTranslationDelegateBridgeCallback(withToken token: String) -> AXPTranslationCallback {
    guard let request = request(forToken: token) else {
      return { _ in Self.emptyResponse() }
    }
    let transport = request.transport
    let collector = request.collector
    let timeoutSeconds = request.requestTimeoutSeconds
    let clientType = request.clientType
    return { axRequest in
      guard let axRequest else {
        return Self.emptyResponse()
      }
      axRequest.clientType = clientType.rawValue
      let xpcStart = CFAbsoluteTimeGetCurrent()
      let response = transport.send(axRequest, timeout: timeoutSeconds)
      collector.recordRequest(type: axRequest.requestType, duration: CFAbsoluteTimeGetCurrent() - xpcStart, answered: response != nil)
      // Unanswered within the timeout: the translator reads the empty response as "no value".
      return response ?? Self.emptyResponse()
    }
  }

  func accessibilityTranslationConvertPlatformFrame(toSystem rect: CGRect, withToken token: String) -> CGRect {
    rect
  }

  func accessibilityTranslationRootParent(withToken token: String) -> Any? {
    nil
  }
}
