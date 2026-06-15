/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// The core, transport-agnostic HID value types. Every transport (Indigo, DTUHID) and the
/// `FBSimulatorHIDEvent` dispatch share these; they are intentionally independent of any one
/// transport's wire format.

/// The direction of a HID event.
public enum FBSimulatorHIDDirection: Int32, Sendable {
  case down = 1
  case up = 2
}

/// A hardware button press.
public enum FBSimulatorHIDButton: Int32, Sendable {
  case applePay = 1
  case homeButton = 2
  case lock = 3
  case sideButton = 4
  case siri = 5
}

/// Device orientation. Values match UIDeviceOrientation (1-4, excluding faceUp/faceDown).
public enum FBSimulatorHIDDeviceOrientation: Int32, Sendable {
  case portrait = 1
  case portraitUpsideDown = 2
  case landscapeRight = 3
  case landscapeLeft = 4
}
