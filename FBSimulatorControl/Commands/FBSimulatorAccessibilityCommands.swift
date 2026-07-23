/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly @preconcurrency import AccessibilityPlatformTranslation
import AppKit
@_implementationOnly import CoreSimulator
import FBControlCore
import Foundation

// MARK: - FBSimulator (translation dispatcher construction)

extension FBSimulator {

  /// Builds a dispatcher for the given translator and wires it up as the
  /// translator's token delegate. `translator` is typed `Any` to accept the test
  /// fixture's mock `AXPTranslator` (mirrors the original `id` parameter). Swift-only
  /// (not `@objc`): an `@objc` `Any` parameter double-visions as `Any`/`Any!` and
  /// makes the call ambiguous; nothing in Objective-C calls this anymore.
  static func createAccessibilityTranslationDispatcher(withTranslator translator: Any) -> FBAXTranslationDispatcher {
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

  @objc var accessibilityTranslationDispatcher: FBAXTranslationDispatcher {
    FBSimulator.sharedAccessibilityTranslationDispatcher
  }
}

// MARK: - FBSimulatorAccessibilityCommands

/// Simulator implementation of the accessibility command surface. Resolves the
/// frontmost / at-point / matching accessibility element via the translation
/// dispatcher, applying SpringBoard-crash remediation for frontmost lookups.
///
/// Plain Swift, no `NSObject`/`@objc`: nothing in Objective-C references this class, and the
/// command cache (`FBTargetCommandCache`) stores values as `Any`, so it imposes no such requirement.
public final class FBSimulatorAccessibilityCommands: AccessibilityOperations {

  private static let coreSimulatorBridgeServiceName = "com.apple.CoreSimulator.bridge"
  private static let springBoardServiceName = "com.apple.SpringBoard"

  private weak var simulator: FBSimulator?

  private let translationDispatcher: FBAXTranslationDispatcher?
  private let launchCtl: (any LaunchCtlCommands)?

  init(
    simulator: FBSimulator,
    translationDispatcher: FBAXTranslationDispatcher? = nil,
    launchCtl: (any LaunchCtlCommands)? = nil
  ) {
    self.simulator = simulator
    self.translationDispatcher = translationDispatcher
    self.launchCtl = launchCtl
  }

  public class func commands(with target: FBSimulator) -> Self {
    self.init(simulator: target)
  }

  // MARK: Translation Dispatcher

  /// The translation dispatcher for accessibility requests: the supplied one when
  /// present, otherwise the simulator's process-wide shared dispatcher.
  private var resolvedDispatcher: FBAXTranslationDispatcher? {
    translationDispatcher ?? simulator?.accessibilityTranslationDispatcher
  }

  /// The launchctl command surface for service-liveness checks: the supplied one when
  /// present, otherwise the simulator itself.
  private func resolvedLaunchCtl(_ simulator: FBSimulator) -> any LaunchCtlCommands {
    launchCtl ?? simulator
  }

  // MARK: AccessibilityOperations

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
    guard let dispatcher = resolvedDispatcher else {
      throw FBAccessibilityError.dispatcherUnavailable
    }
    let element: FBAXPlatformElement
    do {
      element = try await dispatcher.platformElement(withRequest: request, simulator: simulator)
    } catch FBAccessibilityError.noTranslationObject where remediationPermitted {
      // On the frontmost path a nil translation usually means SpringBoard (the provider of the
      // frontmost application) is down. Re-label the error when we can confirm that; a probe
      // failure or a live reading keeps the original .noTranslationObject (e.g. a genuine
      // invalid point or a transient mid-respawn).
      let springBoardRunning = (try? await resolvedLaunchCtl(simulator).serviceIsRunning(named: Self.springBoardServiceName)) ?? true
      if !springBoardRunning {
        throw FBAccessibilityError.springBoardNotRunning
      }
      throw FBAccessibilityError.noTranslationObject
    }
    if !remediationPermitted {
      return FBAccessibilityElement(element: element, request: request, dispatcher: dispatcher, simulator: simulator)
    }
    if await !remediationRequired(forSimulator: simulator, element: element) {
      return FBAccessibilityElement(element: element, request: request, dispatcher: dispatcher, simulator: simulator)
    }
    // The request's token was pushed by the dispatcher but is not yet wrapped in an
    // FBAccessibilityElement, so pop it manually before discarding the request.
    dispatcher.popRequest(request)
    let nextRequest = request.cloneWithNewToken()
    try await remediateSpringBoard(forSimulator: simulator)
    return try await accessibilityElement(request: nextRequest, remediationPermitted: false)
  }

  private func remediationRequired(forSimulator simulator: FBSimulator, element: FBAXPlatformElement) async -> Bool {
    // A quick check: a non-zero accessibility frame indicates a healthy element.
    if !element.axFrame().equalTo(.zero) {
      return false
    }
    // Otherwise the zero-framed root is stale unless its owning pid is still a live launchd
    // service. A dead pid means SpringBoard crashed; restarting CoreSimulatorBridge lets
    // launchd bring a fresh SpringBoard (and bridge) back up. A launchctl failure is treated
    // as "not live" so recovery is still attempted.
    let pid = element.axTranslationPid
    let pidIsLive = (try? await resolvedLaunchCtl(simulator).processIsRunning(withProcessIdentifier: pid)) ?? false
    if pidIsLive {
      return false
    }
    simulator.logger?.log("Frontmost accessibility hierarchy is stale: the root element has a zero frame and its owning pid \(pid) is no longer a registered launchd service. SpringBoard has crashed and CoreSimulator's \(Self.coreSimulatorBridgeServiceName) is still bound to the dead pid; restarting \(Self.coreSimulatorBridgeServiceName) to recover.")
    return true
  }

  private func remediateSpringBoard(forSimulator simulator: FBSimulator) async throws {
    do {
      _ = try await resolvedLaunchCtl(simulator).stopService(withName: Self.coreSimulatorBridgeServiceName)
    } catch {
      throw FBAccessibilityError.springBoardRemediationFailed(serviceName: Self.coreSimulatorBridgeServiceName)
    }
  }
}

// MARK: - FBSimulator+AccessibilityCommands

extension FBSimulator: AccessibilityCommands {

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
