/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// The display a framebuffer captures.
public enum FramebufferDisplay: Hashable, Sendable {
  /// The display with `displayClass` 0: the only display of most devices, and the cover display of an
  /// iPhone Duo.
  case main
  /// The display the simulator's user is looking at, followed as it changes. Where it cannot be
  /// found, the main display.
  case active
  /// The display with this CoreDevice UUID.
  case display(uniqueID: String)
}

extension FramebufferDisplay: CustomStringConvertible {
  public var description: String {
    switch self {
    case .main:
      return "main"
    case .active:
      return "active"
    case let .display(uniqueID):
      return uniqueID
    }
  }
}
