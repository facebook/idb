/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// The display a framebuffer captures or a HID operation's touches land on.
public enum DisplaySelection: Hashable, Sendable {
  /// The display with `displayClass` 0: the only display of most devices, and the cover display of an
  /// iPhone Duo. Unlike the others, it does not report display configuration changes.
  case main
  /// The display the simulator's user is looking at. A framebuffer follows it as it changes, and captures the
  /// main display where it cannot be found.
  case active
  /// The display with this CoreDevice UUID.
  case display(uniqueID: String)
  /// The active display of the display configuration with this generation, which must still be current.
  /// Coordinates computed against it then cannot reach a display that has since changed.
  case configuration(generation: UInt64)
}

extension DisplaySelection: CustomStringConvertible {
  public var description: String {
    switch self {
    case .main:
      return "main"
    case .active:
      return "active"
    case let .display(uniqueID):
      return uniqueID
    case let .configuration(generation):
      return "configuration \(generation)"
    }
  }
}
