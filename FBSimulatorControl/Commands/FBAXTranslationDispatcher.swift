/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency @_implementationOnly import AccessibilityPlatformTranslation
import CoreSimulator
import FBControlCore
import Foundation

/// Mutable holder so the synchronous bridge can capture the response out of the
/// `@Sendable` CoreSimulator completion handler. The `DispatchGroup` wait below
/// establishes the happens-before needed before the value is read, so unchecked
/// Sendable is safe here.
private final class AXPResponseBox: @unchecked Sendable {
  var response: AXPTranslatorResponse?
}

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

/// Bridges the asynchronous CoreSimulator accessibility API to the synchronous
/// callback model `AXPTranslator` expects. Holds the token→request registry and,
/// per request, performs the translator handshake and converts the lazy AXP
/// attribute callbacks into synchronous CoreSimulator XPC round-trips.
///
/// Created and driven entirely from Swift in this module (see
/// `FBSimulatorAccessibilityCommands`). It remains an `@objc`/`NSObject` class
/// only because it conforms to the Objective-C `AXPTranslationTokenDelegateHelper`
/// protocol and is installed as `AXPTranslator`'s bridge-token delegate.
@objc(FBAXTranslationDispatcher)
final class FBAXTranslationDispatcher: NSObject, AXPTranslationTokenDelegateHelper {

  private weak var translator: AXPTranslator?
  private let logger: FBControlCoreLogger?
  private let callbackQueue: DispatchQueue
  private let lock = NSLock()
  private var tokenToRequest: [String: FBAXTranslationRequest] = [:]

  // AXPTranslator is a process-wide singleton whose internal state (nonatomic
  // properties, shared element caches) is not synchronized, so its API contract is
  // single-threaded. Concurrent translation work over-releases shared
  // bridge-delegate token storage (EXC_BAD_ACCESS in FBAXTranslationRequest.deinit),
  // so every touch of the translator or its elements funnels through this one serial
  // queue — process-wide, matching the singleton it guards. Running the walks here
  // also keeps their synchronous XPC waits off the cooperative thread pool.
  private static let axpWorkQueue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.accessibility_translator.work")

  init(translator: AXPTranslator, logger: FBControlCoreLogger?) {
    self.translator = translator
    self.logger = logger
    self.callbackQueue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.accessibility_translator.callback")
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

  func platformElement(withRequest request: FBAXTranslationRequest, simulator: FBSimulator) async throws -> FBAXWritableElement {
    // The synchronous XPC round-trips driven by the delegate callback must never
    // run on the main queue; the serialized hop below moves them to the AXP work
    // queue, off the main actor and off the cooperative executor.
    request.device = simulator.device
    request.translator = self.translator
    self.pushRequest(request)
    let translator = self.translator

    do {
      return try await performSerialized { () throws -> FBAXWritableElement in
        let collector = request.collector
        let translationStart = CFAbsoluteTimeGetCurrent()
        guard let translator, let translation = request.perform(withTranslator: translator) else {
          throw FBAccessibilityError.noTranslationObject
        }
        collector?.translationDuration = CFAbsoluteTimeGetCurrent() - translationStart
        translation.bridgeDelegateToken = request.token

        let conversionStart = CFAbsoluteTimeGetCurrent()
        let rawElement = translator.macPlatformElement(fromTranslation: translation)
        collector?.elementConversionDuration = CFAbsoluteTimeGetCurrent() - conversionStart

        guard let element = rawElement as? FBAXWritableElement else {
          throw FBAccessibilityError.noTranslationObject
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

  private func pushRequest(_ request: FBAXTranslationRequest) {
    lock.lock()
    defer { lock.unlock() }
    tokenToRequest[request.token] = request
    logger?.log("Registered request with token \(request.token)")
  }

  func popRequest(_ request: FBAXTranslationRequest) {
    lock.lock()
    let present = tokenToRequest[request.token] != nil
    if present {
      tokenToRequest.removeValue(forKey: request.token)
    }
    lock.unlock()
    if present {
      logger?.log("Removed request with token \(request.token)")
    } else {
      logger?.log("popRequest: token \(request.token) not found (already popped or replaced by remediation), ignoring")
    }
  }

  private func request(forToken token: String) -> FBAXTranslationRequest? {
    lock.lock()
    defer { lock.unlock() }
    return tokenToRequest[token]
  }

  private static func emptyResponse() -> AXPTranslatorResponse? {
    AXPTranslatorResponse.empty() as? AXPTranslatorResponse
  }

  // MARK: - AXPTranslationTokenDelegateHelper

  // Since the CoreSimulator accessibility API is asynchronous but AXPTranslator's
  // delegation is synchronous, a DispatchGroup acts as a mutex to wait on the
  // result. The wait must never run on the main queue.
  func accessibilityTranslationDelegateBridgeCallback(withToken token: String) -> AXPTranslationCallback {
    guard let request = request(forToken: token) else {
      return { [weak self] _ in
        self?.logger?.log("Request with token \(token) is gone. Returning empty response")
        return Self.emptyResponse()
      }
    }
    let device = request.device
    let collector = request.collector
    let logger = request.logger
    let timeoutSeconds = request.requestTimeoutSeconds
    let callbackQueue = self.callbackQueue
    return { axRequest in
      logger?.log("Sending Accessibility Request \(String(describing: axRequest))")
      let group = DispatchGroup()
      group.enter()
      let box = AXPResponseBox()

      let xpcStart = CFAbsoluteTimeGetCurrent()
      device?.sendAccessibilityRequestAsync(axRequest, completionQueue: callbackQueue) { innerResponse in
        box.response = innerResponse
        group.leave()
      }
      let waitResult = group.wait(timeout: .now() + timeoutSeconds)
      collector?.addXPCCallDuration(CFAbsoluteTimeGetCurrent() - xpcStart)

      if waitResult == .timedOut {
        logger?.log("Accessibility request \(String(describing: axRequest)) timed out after \(timeoutSeconds)s — returning empty response")
        return Self.emptyResponse()
      }
      logger?.log("Got Accessibility Response \(String(describing: box.response))")
      return box.response
    }
  }

  func accessibilityTranslationConvertPlatformFrame(toSystem rect: CGRect, withToken token: String) -> CGRect {
    rect
  }

  func accessibilityTranslationRootParent(withToken token: String) -> Any? {
    logger?.log("Delegate method 'accessibilityTranslationRootParentWithToken:', with unknown implementation called with token \(token). Returning nil.")
    return nil
  }
}
