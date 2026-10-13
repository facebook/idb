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

/// One unit of translator work and its result, carried across the hop onto the AXP
/// work queue and back. SAFETY: the body runs exactly once, on the serial AXP work
/// queue; the continuation resume that follows it establishes the happens-before for
/// the result read after the await. The queue is the synchronization.
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
  /// The request resolving its root on the work queue, which a callback without a token belongs to: the
  /// translator sends some root lookups (an application by pid) with no translation, and so no token, and
  /// only one request is ever inside the translator at a time.
  private var resolvingRequest: AXTranslationRequest?

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
    let job = AXPSerializedJob(operation)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      Self.axpWorkQueue.async {
        job.run()
        continuation.resume()
      }
    }
    return try job.takeResult()
  }

  /// Resolves `request`'s root element, through the transport the request already carries.
  func platformElement(withRequest request: AXTranslationRequest) async throws -> AXWritableElement {
    // The synchronous XPC round-trips driven by the delegate callback must never
    // run on the main queue; the serialized hop below moves them to the AXP work
    // queue, off the main actor and off the cooperative executor.
    request.translator = self.translator
    self.pushRequest(request)
    let translator = self.translator

    do {
      return try await performSerialized { () throws -> AXWritableElement in
        let collector = request.collector
        let translationStart = CFAbsoluteTimeGetCurrent()
        guard let translator, let translation = try self.resolving(request, { try request.perform(withTranslator: translator) })
        else {
          throw AccessibilityError.noTranslationObject
        }
        collector.translationDuration = CFAbsoluteTimeGetCurrent() - translationStart
        translation.bridgeDelegateToken = request.token

        let conversionStart = CFAbsoluteTimeGetCurrent()
        let rawElement = translator.macPlatformElement(fromTranslation: translation)
        collector.elementConversionDuration = CFAbsoluteTimeGetCurrent() - conversionStart

        guard let element = rawElement as? AXWritableElement else {
          throw AccessibilityError.noTranslationObject
        }
        element.axSetBridgeDelegateToken(request.token)
        return element
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

  private func resolving<T>(_ request: AXTranslationRequest, _ body: () throws -> T) rethrows -> T {
    lock.withLock { resolvingRequest = request }
    defer { lock.withLock { resolvingRequest = nil } }
    return try body()
  }

  /// The request a callback belongs to: by its token, or the resolving request when it carries none.
  private func request(forToken token: String) -> AXTranslationRequest? {
    lock.lock()
    defer { lock.unlock() }
    guard !token.isEmpty else {
      return resolvingRequest
    }
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
      guard let axRequest, let transport else {
        return Self.emptyResponse()
      }
      axRequest.clientType = clientType.rawValue
      let xpcStart = CFAbsoluteTimeGetCurrent()
      let response = transport.send(axRequest, timeout: timeoutSeconds)
      collector.addXPCCallDuration(CFAbsoluteTimeGetCurrent() - xpcStart)
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
