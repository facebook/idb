/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly @preconcurrency import AccessibilityPlatformTranslation
@_implementationOnly import CoreSimulator
import FBControlCore
import Foundation

/// Mutable holder so the synchronous bridge can capture the response out of the
/// `@Sendable` CoreSimulator completion handler. The `DispatchGroup` wait below
/// establishes the happens-before needed before the value is read, so unchecked
/// Sendable is safe here.
private final class AXPResponseBox: @unchecked Sendable {
  var response: AXPTranslatorResponse?
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

  init(translator: AXPTranslator, logger: FBControlCoreLogger?) {
    self.translator = translator
    self.logger = logger
    self.callbackQueue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.accessibility_translator.callback")
    super.init()
  }

  // MARK: - Public

  func platformElement(withRequest request: FBAXTranslationRequest, simulator: FBSimulator) async throws -> FBAXPlatformElement {
    // The synchronous XPC round-trips driven below (via the delegate callback)
    // must never run on the main queue. This `nonisolated` async method runs on
    // the cooperative executor, off the main actor.
    request.device = simulator.device
    request.translator = self.translator
    self.pushRequest(request)
    let collector = request.collector

    let translationStart = CFAbsoluteTimeGetCurrent()
    guard let translator = self.translator, let translation = request.perform(withTranslator: translator) else {
      self.popRequest(request)
      throw FBAccessibilityError.noTranslationObject
    }
    collector?.translationDuration = CFAbsoluteTimeGetCurrent() - translationStart
    translation.bridgeDelegateToken = request.token

    let conversionStart = CFAbsoluteTimeGetCurrent()
    let rawElement = translator.macPlatformElement(fromTranslation: translation)
    collector?.elementConversionDuration = CFAbsoluteTimeGetCurrent() - conversionStart

    guard let element = rawElement as? FBAXPlatformElement else {
      throw FBAccessibilityError.noTranslationObject
    }
    element.axSetBridgeDelegateToken(request.token)
    return element
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
