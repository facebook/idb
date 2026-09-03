/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency @_implementationOnly import AccessibilityPlatformTranslation
import AppKit
import CoreSimulator
import FBControlCore
import Foundation

// MARK: - FBSimulator (translation dispatcher construction)

extension FBSimulator {

  /// Builds a dispatcher for the given translator and wires it up as the
  /// translator's token delegate. `translator` is typed `Any` so tests can pass
  /// a mock `AXPTranslator`.
  static func createAccessibilityTranslationDispatcher(withTranslator translator: Any) -> FBAXTranslationDispatcher {
    let axTranslator = unsafeBitCast(translator as AnyObject, to: AXPTranslator.self)
    let dispatcher = FBAXTranslationDispatcher(translator: axTranslator, logger: nil)
    axTranslator.bridgeTokenDelegate = dispatcher
    return dispatcher
  }

  // Process-wide singleton: AXPTranslator is itself a singleton with a single
  // bridgeTokenDelegate slot, so exactly one dispatcher backs every simulator (it
  // disambiguates concurrent requests by token, guarded internally by a lock).
  private nonisolated(unsafe) static let sharedAccessibilityTranslationDispatcher: FBAXTranslationDispatcher = {
    let translator = unsafeBitCast(AXPTranslator.sharedInstance() as AnyObject, to: AXPTranslator.self)
    return FBSimulator.createAccessibilityTranslationDispatcher(withTranslator: translator)
  }()

  var accessibilityTranslationDispatcher: FBAXTranslationDispatcher {
    FBSimulator.sharedAccessibilityTranslationDispatcher
  }
}

// MARK: - FBSimulatorAccessibilityCommands

/// Simulator implementation of the accessibility command surface. Resolves the
/// frontmost / at-point / matching accessibility element via the translation
/// dispatcher, applying SpringBoard-crash remediation for frontmost lookups.
final class FBSimulatorAccessibilityCommands: AccessibilityOperations {

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

  class func commands(with target: FBSimulator) -> Self {
    self.init(simulator: target)
  }

  // MARK: Translation Dispatcher

  private var resolvedDispatcher: FBAXTranslationDispatcher? {
    translationDispatcher ?? simulator?.accessibilityTranslationDispatcher
  }

  private func resolvedLaunchCtl(_ simulator: FBSimulator) -> any LaunchCtlCommands {
    launchCtl ?? simulator
  }

  // MARK: AccessibilityOperations

  func resolveElement(for query: FBAccessibilityElementQuery) async throws -> FBAccessibilityElement {
    try validateAccessibility()
    switch query {
    case let .point(point):
      let request = FBAXTranslationRequest(kind: .point(point))
      return try await accessibilityElement(request: request, remediationPermitted: false)
    case .frontmost:
      let request = FBAXTranslationRequest(kind: .frontmostApplication)
      return try await accessibilityElement(request: request, remediationPermitted: true)
    case let .marker(value, key, depth, ignoresCase):
      let request = FBAXTranslationRequest(kind: .frontmostApplication)
      let root = try await accessibilityElement(request: request, remediationPermitted: true)
      return try await root.findElement(withValue: value, forKey: key, depth: depth, ignoresCase: ignoresCase)
    case let .application(pid):
      // An explicit pid target: read that application directly, no SpringBoard stale-hierarchy
      // remediation (that is only meaningful for the frontmost read).
      let request = FBAXTranslationRequest(kind: .applicationForPid(pid))
      return try await accessibilityElement(request: request, remediationPermitted: false)
    }
  }

  // MARK: Private

  // Uses the CoreSimulator accessibility API via
  // -[SimDevice sendAccessibilityRequestAsync:completionQueue:completionHandler:].
  // This API requires Xcode 12+ to have been installed on the host at some point.
  private func validateAccessibility() throws {
    guard let simulator else {
      throw FBWeakTargetError.simulator
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

  // Returns an FBAccessibilityElement wrapping the platform element for the given request;
  // the handle owns the request's token and pops it on close. Stale-SpringBoard remediation
  // retries with remediationPermitted=false, bounding it to a single attempt.
  private func accessibilityElement(request: FBAXTranslationRequest, remediationPermitted: Bool) async throws -> FBAccessibilityElement {
    guard let simulator else {
      throw FBWeakTargetError.simulator
    }
    guard let dispatcher = resolvedDispatcher else {
      throw FBAccessibilityError.dispatcherUnavailable
    }
    let element: FBAXWritableElement
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
    let requiresRemediation = try await remediationRequired(forSimulator: simulator, element: element, dispatcher: dispatcher)
    if !requiresRemediation {
      return FBAccessibilityElement(element: element, request: request, dispatcher: dispatcher, simulator: simulator)
    }
    // The request's token was pushed by the dispatcher but is not yet wrapped in an
    // FBAccessibilityElement, so pop it manually before discarding the request.
    dispatcher.popRequest(request)
    let nextRequest = request.cloneWithNewToken()
    try await remediateSpringBoard(forSimulator: simulator)
    return try await accessibilityElement(request: nextRequest, remediationPermitted: false)
  }

  private func remediationRequired(forSimulator simulator: FBSimulator, element: FBAXPlatformElement, dispatcher: FBAXTranslationDispatcher) async throws -> Bool {
    // A quick check: a non-zero accessibility frame indicates a healthy element.
    // An attribute read, so it takes the serialized hop like every other translator touch.
    let frame = try await dispatcher.performSerialized { element.axFrame() }
    if !frame.equalTo(.zero) {
      return false
    }
    // A zero-framed root is stale unless its owning pid is still a live launchd service.
    // A launchctl failure is treated as "not live" so recovery is still attempted.
    let pid = element.axTranslationPid
    let pidIsLive = (try? await resolvedLaunchCtl(simulator).processIsRunning(withProcessIdentifier: pid)) ?? false
    if pidIsLive {
      return false
    }
    simulator.logger.log("Frontmost accessibility hierarchy is stale: the root element has a zero frame and its owning pid \(pid) is no longer a registered launchd service. SpringBoard has crashed and CoreSimulator's \(Self.coreSimulatorBridgeServiceName) is still bound to the dead pid; restarting \(Self.coreSimulatorBridgeServiceName) to recover.")
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

// MARK: - FBSimulator+AccessibilityOperations

extension FBSimulator: AccessibilityOperations {

  func resolveElement(for query: FBAccessibilityElementQuery) async throws -> FBAccessibilityElement {
    try await accessibility.resolveElement(for: query)
  }
}
