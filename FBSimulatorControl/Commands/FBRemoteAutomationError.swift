/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Failures specific to the `testmanagerd` remote-automation transport — reaching the daemon's
/// channel and putting well-formed work on it. Failures of the *query* (no such element, empty point,
/// timeout, unsupported verb) are backend-neutral and raised as `FBUIAutomationError`, so a caller can
/// handle them without knowing which backend it holds.
public enum FBRemoteAutomationError: LocalizedError, Sendable {
  /// The frontmost application's element tree could not be read at the probe point. Unlike the guest
  /// reader, the `testmanagerd` session gets no tagged outcome to say why — and it requires
  /// `ApplicationAccessibilityEnabled=1` on the target before it launches, so for this backend the flag
  /// is the likeliest cause rather than a guess.
  case treeUnavailable(x: Double, y: Double)
  /// The remote-automation channel is not advertised on this simulator (needs iOS 27+ / Xcode 27).
  case unavailable(underlying: String)
  /// A synthesized input event carried no touch steps.
  case eventMissingTouchSteps

  public var errorDescription: String? {
    switch self {
    case let .treeUnavailable(x, y):
      return "Remote automation could not read the frontmost application tree at (\(x), \(y)). \(FBAccessibilityGuidance.accessibilityServer)"
    case let .unavailable(underlying):
      return "Remote automation is unavailable on this simulator: testmanagerd is not advertising its remote-automation listener (\(remoteAutomationSockEnvKey)). This requires a simulator runtime whose testmanagerd exposes the remote-automation channel (iOS 27+ / Xcode 27). Underlying error: \(underlying)"
    case .eventMissingTouchSteps:
      return "Remote-automation event contained no touch steps"
    }
  }
}

extension FBRemoteAutomationError: CustomStringConvertible {
  public var description: String { errorDescription ?? "FBRemoteAutomationError" }
}
