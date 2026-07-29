/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

/// The environment key under which the guest `testmanagerd` publishes its remote-automation socket.
let remoteAutomationSockEnvKey = "TESTMANAGERD_REMOTE_AUTOMATION_SIM_SOCK"

/// Drives UI automation over the guest `testmanagerd` remote-automation channel, without an
/// `.xctest` bundle, runner, or build.
///
/// Reached through `FBSimulator.remoteAutomation()`, which memoizes one instance per target. The
/// underlying `FBRemoteAutomationSession` — socket connect, framework preload, handshake — is built
/// and primed once on first use and reused; a failed build clears the memo so a later call retries.
/// An actor so the memoized session is established exactly once under concurrent callers, without a
/// lock across suspension points.
public actor FBSimulatorRemoteAutomation {

  private weak var simulator: FBSimulator?
  private var sessionTask: Task<FBRemoteAutomationSession, Error>?

  init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  public static func commands(with target: FBSimulator) -> FBSimulatorRemoteAutomation {
    FBSimulatorRemoteAutomation(simulator: target)
  }

  /// Submits a synthesized input event (tap, swipe, …) over the remote-automation channel.
  public func sendHIDEvent(_ event: FBSimulatorHIDEvent) async throws {
    let session = try await self.session()
    let record = try Self.eventRecord(for: event)
    try await session.synthesizeEvent(record)
  }

  /// Reads the accessibility element at a screen point (in points) over the remote-automation
  /// channel and serializes it to the accessibility schema as canonical sorted-keys JSON, matching
  /// the legacy `accessibilityDescribe` point output.
  public func describe(atX x: Double, y: Double, keys: Set<FBAXKeys>) async throws -> Data {
    try await ensureAccessibilityEnabled()
    let session = try await self.session()
    let element = try await Self.describeElement(atX: x, y: y, using: session, keys: keys)
    let response = FBAccessibilityElementsResponse(
      elements: element, profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
    )
    return try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
  }

  // MARK: - Read preconditions

  private var accessibilityPreconditionChecked = false

  /// Remote reads need the target app's in-process accessibility server, which the app starts only
  /// when `ApplicationAccessibilityEnabled` (`com.apple.Accessibility`) is set *before* it launches.
  /// The preference cannot take effect for an already-running app, so a read cannot enable it itself;
  /// this instead checks the preference once per session (caching success) and, when unset, throws a
  /// precise, tool-agnostic error naming exactly what to set — rather than silently returning an
  /// empty tree. Any read entry point calls this before touching the accessibility tree.
  func ensureAccessibilityEnabled() async throws {
    if accessibilityPreconditionChecked { return }
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let value = try await simulator.getCurrentPreference("ApplicationAccessibilityEnabled", domain: "com.apple.Accessibility")
    guard ["1", "true", "yes"].contains(value.lowercased()) else {
      throw FBControlCoreError.describe(
        "Remote-automation reads require the accessibility precondition ApplicationAccessibilityEnabled (domain com.apple.Accessibility) to be set before the target app launches; it is currently \(value.isEmpty ? "unset" : "\"\(value)\""). Set it and relaunch the app, e.g. `xcrun simctl spawn <UDID> defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool true`. Without it the app does not start its in-process accessibility server and reads return nothing."
      ).build()
    }
    accessibilityPreconditionChecked = true
  }

  // MARK: - Reads

  /// Reads the element at a point and serializes it to the single-element accessibility schema,
  /// feeding a remote-backed `FBAXPlatformElement` through the same serializer as the legacy path.
  /// The element handle stays a disconnected local (received from the session and used once) so it
  /// never becomes a shareable value that would risk a data race across the session boundary.
  static func describeElement(atX x: Double, y: Double, using session: FBRemoteAutomationSession, keys: Set<FBAXKeys>) async throws -> [String: Any] {
    guard let element = try await session.requestElement(atX: x, y: y) else {
      throw FBControlCoreError.describe("Remote automation found no element at (\(x), \(y))").build()
    }
    let raw = try await session.fetchAttributes(FBRemoteAutomationAXAttribute.fetchList, forElement: element)
    let attributes = (raw as? [String: Any]) ?? [:]
    let platformElement = FBRemoteAutomationPlatformElement(attributes: attributes, children: [], pid: 0)
    return FBSimulatorAccessibilitySerializer.formattedDescription(
      ofElement: platformElement,
      token: "",
      nestedFormat: false,
      keys: keys,
      collector: nil,
      coverageGrid: nil
    )
  }

  // MARK: - Session lifecycle

  private func session() async throws -> FBRemoteAutomationSession {
    if let sessionTask {
      return try await sessionTask.value
    }
    let simulator = self.simulator
    let task = Task { try await Self.makeSession(for: simulator) }
    sessionTask = task
    do {
      return try await task.value
    } catch {
      sessionTask = nil
      throw error
    }
  }

  private static func makeSession(for simulator: FBSimulator?) async throws -> FBRemoteAutomationSession {
    guard let simulator else {
      throw FBWeakTargetError.simulator
    }
    try XCTestBootstrapFrameworkLoader.allDependentFrameworks.loadPrivateFrameworks(simulator.logger)
    let socketPath: String
    do {
      socketPath =
        try await FBSimulatorXCTestCommands
        .commands(with: simulator)
        .testManagerDaemonSocketPath(envKey: remoteAutomationSockEnvKey)
    } catch {
      // testmanagerd only advertises this socket on runtimes that run the remote-automation
      // listener (iOS 27+), so a resolution failure means the backend is unavailable on this
      // simulator rather than a transient miss — surface that instead of the resolver's opaque
      // env-var timeout.
      throw FBControlCoreError.describe(
        "Remote automation is unavailable on this simulator: testmanagerd is not advertising its remote-automation listener (\(remoteAutomationSockEnvKey)). This requires a simulator runtime whose testmanagerd exposes the remote-automation channel (iOS 27+ / Xcode 27)."
      ).caused(by: error as NSError).build()
    }
    let connection = try FBRemoteAutomationConnection(
      socketPath: socketPath,
      queue: simulator.workQueue,
      logger: simulator.logger
    )
    // Let the DTX connection settle after `resume` before the first invocation; sending the
    // handshake immediately races the connection setup and the daemon drops the channel.
    try await Task.sleep(nanoseconds: 300_000_000)
    let session = FBRemoteAutomationSession(invoker: DTXRemoteInvoker(connection: connection), processIdentifier: 0)
    try await session.prime()
    return session
  }

  // MARK: - Event translation

  /// Translates a single-finger `FBSimulatorHIDEvent` (tap or swipe) into an `XCSynthesizedEventRecord`.
  ///
  /// A `.touch(.down)` starts the path (or, once started, moves it); a `.touch(.up)` lifts it; a
  /// `.delay` advances the time offset. A zero-delay tap is given a small nonzero lift offset so the
  /// daemon still registers it as a touch rather than a no-op.
  static func eventRecord(for event: FBSimulatorHIDEvent) throws -> Any {
    let steps = event.subEvents ?? [event]
    var path: FBRemoteAutomationPointerPath?
    var offset: TimeInterval = 0
    var downOffset: TimeInterval = 0
    for step in steps {
      switch step {
      case let .touch(direction, x, y):
        switch direction {
        case .down:
          if let path {
            path.move(toX: x, y: y, atOffset: offset)
          } else {
            let started = try FBRemoteAutomationPointerPath.pathForTouch(atX: x, y: y)
            started.pressDown(atOffset: offset)
            downOffset = offset
            path = started
          }
        case .up:
          path?.liftUp(atOffset: max(offset, downOffset + 0.05))
        @unknown default:
          break
        }
      case let .delay(interval):
        offset += interval
      default:
        break
      }
    }
    guard let path else {
      throw FBControlCoreError.describe("Remote-automation event contained no touch steps").build()
    }
    return try FBRemoteAutomationPayloads.eventRecord(withName: "remote-automation", pointerPaths: [path])
  }
}

public extension FBSimulator {
  /// The remote-automation surface, driving UI automation over the guest `testmanagerd`
  /// remote-automation channel without an `.xctest` bundle, runner, or build. Memoized per target.
  func remoteAutomation() throws -> FBSimulatorRemoteAutomation {
    commandCache.resolve { FBSimulatorRemoteAutomation.commands(with: self) }
  }
}
