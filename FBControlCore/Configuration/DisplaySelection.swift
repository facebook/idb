/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// The display an operation reaches: what a framebuffer or screenshot captures, and where HID input and
/// accessibility reads and actions land. `.active` is resolved when the operation runs. Every other selection
/// is a requirement: an operation that cannot reach the selected display fails rather than reaching another.
public enum DisplaySelection: Hashable, Sendable {
  /// The display with `displayClass` 0: the only display of most devices, and the cover display of an
  /// iPhone Duo. Unlike the others, it does not report display configuration changes. Framebuffers and
  /// screenshots only.
  case main
  /// The display the simulator's user is looking at. A framebuffer follows it as it changes. Framebuffers and
  /// screenshots capture the main display where it cannot be found; HID input and accessibility fail.
  case active
  /// The display with this CoreDevice UUID. A framebuffer captures it whether or not it is active; HID input,
  /// accessibility and screenshots require it to be the active display.
  case display(uniqueID: String)
  /// The active display of the display configuration with this generation, which must still be current.
  /// Coordinates computed against it then cannot reach a display that has since changed. A framebuffer bound
  /// to it ends once the configuration is replaced.
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
