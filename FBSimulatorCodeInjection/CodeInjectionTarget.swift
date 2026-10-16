/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The process on a Simulator that code is injected into, and so what a session's lifetime is.
public enum CodeInjectionTarget: Sendable, Equatable {
  /// An installed app, launched with the shim injected, or relaunched if it is running without it.
  /// With `reattach`, an app still serving a session from earlier is joined instead of relaunched,
  /// keeping its state. The app outlives the session.
  case application(bundleID: String, reattach: Bool = false)
  /// The Simulator's guest bridge, which runs with the Simulator's own privileges and exits when the
  /// session ends.
  case simulator
  /// A logic-test bundle, run under the logic-test runner until the session ends, so injected code
  /// reaches the bundle's own types.
  case logicTestBundle(path: String)
}

/// Which copy of the shim to inject. The shim binds the control socket inside the host and runs the
/// code a session executes.
public enum CodeInjectionShim: Sendable, Equatable {
  /// The shim bundled with this library: in the bundle that links it, or in the `Resources/`
  /// directory beside a standalone binary.
  case bundled
  /// A shim at this path, for a host that lays out its resources differently.
  case path(String)

  func resolvedPath() throws -> String {
    switch self {
    case .bundled:
      guard let path = BundledResources.path(forItem: SimulatorAudioInjectionCommands.injectionShimName) else {
        throw CodeInjectionError.resourceMissing(name: SimulatorAudioInjectionCommands.injectionShimName)
      }
      return path
    case let .path(path):
      return path
    }
  }
}
