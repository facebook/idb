/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// What a HID operation's touches must land on. Every binding is checked at the first touch, and the operation
/// fails if the display configuration changes before it finishes.
public enum SimulatorHIDDisplayBinding: Equatable, Sendable {
  /// Whichever display is active at the first touch.
  case active
  /// The display with this unique ID, which must be active at the first touch.
  case display(uniqueID: String)
  /// This configuration, which must still be current at the first touch. Coordinates computed against it then
  /// cannot reach a display that has since changed.
  case configuration(SimulatorDisplayConfiguration)
}
