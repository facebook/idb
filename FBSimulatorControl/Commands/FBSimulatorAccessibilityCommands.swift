/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import AccessibilityPlatformTranslation
import AppKit
import CoreSimulator
import FBControlCore
import Foundation

// MARK: - FBSimulator (translation dispatcher construction)

extension FBSimulator {

  /// Builds a dispatcher for the given translator and wires it up as the
  /// translator's token delegate. `translator` is typed `Any` to accept the test
  /// fixture's mock `AXPTranslator` (mirrors the original `id` parameter). Swift-only
  /// (not `@objc`): an `@objc` `Any` parameter double-visions as `Any`/`Any!` and
  /// makes the call ambiguous; nothing in Objective-C calls this anymore.
  public static func createAccessibilityTranslationDispatcher(withTranslator translator: Any) -> FBAXTranslationDispatcher {
    let axTranslator = unsafeBitCast(translator as AnyObject, to: AXPTranslator.self)
    let dispatcher = FBAXTranslationDispatcher(translator: axTranslator, logger: nil)
    axTranslator.bridgeTokenDelegate = dispatcher
    return dispatcher
  }

  // Process-wide singleton: AXPTranslator is itself a singleton with a single
  // bridgeTokenDelegate slot, so exactly one dispatcher backs every simulator (it
  // disambiguates concurrent requests by token, guarded internally by a lock).
  // The lazy `static let` initialiser is thread-safe; `nonisolated(unsafe)` opts
  // this shared instance out of Swift 6 Sendable checking accordingly.
  private nonisolated(unsafe) static let sharedAccessibilityTranslationDispatcher: FBAXTranslationDispatcher = {
    let translator = unsafeBitCast(AXPTranslator.sharedInstance() as AnyObject, to: AXPTranslator.self)
    return FBSimulator.createAccessibilityTranslationDispatcher(withTranslator: translator)
  }()

  @objc public var accessibilityTranslationDispatcher: FBAXTranslationDispatcher {
    FBSimulator.sharedAccessibilityTranslationDispatcher
  }
}

// MARK: - FBSimulatorAccessibilityCommands

/// Simulator implementation of the accessibility command surface. Resolves the
/// frontmost / at-point / matching accessibility element via the translation
/// dispatcher, applying SpringBoard-crash remediation for frontmost lookups.
///
/// Not `final` and `translationDispatcher()` is overridable so unit tests can
/// inject a mock dispatcher (via `@testable`).
public class FBSimulatorAccessibilityCommands: NSObject, AsyncAccessibilityOperations {

  private static let coreSimulatorBridgeServiceName = "com.apple.CoreSimulator.bridge"

  private weak var simulator: FBSimulator?

  @objc(initWithSimulator:)
  public required init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  @objc(commandsWithTarget:)
  public class func commands(with target: FBSimulator) -> Self {
    self.init(simulator: target)
  }

  // MARK: Translation Dispatcher Hook

  /// The translation dispatcher used for accessibility requests. Defaults to
  /// `simulator.accessibilityTranslationDispatcher`; tests override this to
  /// inject a mock. Returns `Any` to mirror the original `- (id)` seam.
  @objc public func translationDispatcher() -> Any {
    guard let simulator else {
      fatalError("FBSimulatorAccessibilityCommands.translationDispatcher accessed after the simulator was deallocated")
    }
    return simulator.accessibilityTranslationDispatcher
  }

  // MARK: AsyncAccessibilityOperations

  public func accessibilityElement(at point: CGPoint) async throws -> FBAccessibilityElement {
    try validateAccessibility()
    let request = FBAXTranslationRequest(kind: .point(point))
    return try await accessibilityElement(request: request, remediationPermitted: false)
  }

  public func accessibilityElementForFrontmostApplication() async throws -> FBAccessibilityElement {
    try validateAccessibility()
    let request = FBAXTranslationRequest(kind: .frontmostApplication)
    return try await accessibilityElement(request: request, remediationPermitted: true)
  }

  public func accessibilityElementMatching(value: String, forKey key: FBAXSearchableKey, depth: UInt) async throws -> FBAccessibilityElement {
    try validateAccessibility()
    let request = FBAXTranslationRequest(kind: .frontmostApplication)
    let root = try await accessibilityElement(request: request, remediationPermitted: true)
    return try root.findElement(withValue: value, forKey: key, depth: depth)
  }

  // MARK: Private

  // Uses the CoreSimulator accessibility API via
  // -[SimDevice sendAccessibilityRequestAsync:completionQueue:completionHandler:].
  // This API requires Xcode 12+ to have been installed on the host at some point.
  private func validateAccessibility() throws {
    guard let simulator else {
      throw FBAccessibilityError.simulatorDeallocated
    }
    guard simulator.state == .booted else {
      throw FBAccessibilityError.simulatorNotBooted(description: "\(simulator)")
    }
    let selector = NSSelectorFromString("sendAccessibilityRequestAsync:completionQueue:completionHandler:")
    guard simulator.device.responds(to: selector) else {
      throw FBAccessibilityError.accessibilityUnavailable
    }
    try FBSimulatorControlFrameworkLoader.accessibilityFrameworks.loadPrivateFrameworks(simulator.logger)
  }

  // Returns an FBAccessibilityElement wrapping the platform element for the given request.
  // The handle owns the request's token and pops it on close.
  //
  // When remediationPermitted and a stale SpringBoard is detected (zero accessibility frame +
  // dead pid), the original request's token is popped manually (it is not wrapped in a handle
  // yet at that point), CoreSimulatorBridge is restarted, and the lookup retries with a fresh
  // request. The retry passes remediationPermitted=false, bounding it to a single attempt.
  private func accessibilityElement(request: FBAXTranslationRequest, remediationPermitted: Bool) async throws -> FBAccessibilityElement {
    guard let simulator else {
      throw FBAccessibilityError.simulatorDeallocated
    }
    guard let dispatcher = translationDispatcher() as? FBAXTranslationDispatcher else {
      throw FBAccessibilityError.dispatcherUnavailable
    }
    let element = try await dispatcher.platformElement(withRequest: request, simulator: simulator)
    if !remediationPermitted {
      return FBAccessibilityElement(element: element, request: request, dispatcher: dispatcher, simulator: simulator)
    }
    if try await !Self.remediationRequired(forSimulator: simulator, element: element) {
      return FBAccessibilityElement(element: element, request: request, dispatcher: dispatcher, simulator: simulator)
    }
    // The request's token was pushed by the dispatcher but is not yet wrapped in an
    // FBAccessibilityElement, so pop it manually before discarding the request.
    dispatcher.popRequest(request)
    let nextRequest = request.cloneWithNewToken()
    try await Self.remediateSpringBoard(forSimulator: simulator)
    return try await accessibilityElement(request: nextRequest, remediationPermitted: false)
  }

  private static func remediationRequired(forSimulator simulator: FBSimulator, element: AXPMacPlatformElement) async throws -> Bool {
    // A quick check: a non-zero accessibility frame indicates a healthy element.
    if !element.accessibilityFrame().equalTo(.zero) {
      return false
    }
    // Otherwise confirm whether the translation object's pid represents a real process.
    // If it does not, we likely got the pid of a crashed SpringBoard; restarting
    // CoreSimulatorBridge lets launchd bring a fresh SpringBoard (and bridge) back up.
    let pid = element.translation?.pid ?? 0
    do {
      _ = try await bridgeFBFuture(simulator.serviceName(forProcessIdentifier: pid))
      return false
    } catch {
      simulator.logger?.log("pid \(pid) does not exist, this likely means that SpringBoard has restarted, \(coreSimulatorBridgeServiceName) should be restarted")
      return true
    }
  }

  private static func remediateSpringBoard(forSimulator simulator: FBSimulator) async throws {
    do {
      _ = try await bridgeFBFuture(simulator.stopService(withName: coreSimulatorBridgeServiceName))
    } catch {
      throw FBAccessibilityError.springBoardRemediationFailed(serviceName: coreSimulatorBridgeServiceName)
    }
  }
}

// MARK: - FBSimulator+AsyncAccessibilityCommands

extension FBSimulator: AsyncAccessibilityCommands {

  public func accessibilityElement(at point: CGPoint) async throws -> FBAccessibilityElement {
    try await accessibilityCommands().accessibilityElement(at: point)
  }

  public func accessibilityElementForFrontmostApplication() async throws -> FBAccessibilityElement {
    try await accessibilityCommands().accessibilityElementForFrontmostApplication()
  }

  public func accessibilityElementMatching(
    value: String,
    forKey key: FBAXSearchableKey,
    depth: UInt
  ) async throws -> FBAccessibilityElement {
    try await accessibilityCommands().accessibilityElementMatching(value: value, forKey: key, depth: depth)
  }
}
