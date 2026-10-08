/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A hardware/device action, named once for everyone who can perform it.
///
/// The human reaches these through the toolbar and the Device menu; the agent reaches them through
/// the control channel's `button` method. Sharing the list is what makes the two parties' entries in
/// the action log indistinguishable except for who did it.
struct DeviceAction {
  /// The name understood by `SimBackend.perform(deviceAction:)`, and by the channel's `button` method.
  let name: String
  let label: String
  /// SF Symbol for the toolbar item.
  let symbol: String
  /// The action-log narration.
  let prose: String

  static let all: [DeviceAction] = [
    DeviceAction(name: "home", label: "Home", symbol: "house.fill", prose: "Pressed the Home button."),
    DeviceAction(name: "side", label: "Side", symbol: "power", prose: "Pressed the Side (power) button."),
    DeviceAction(name: "lock", label: "Lock", symbol: "lock.fill", prose: "Locked the device."),
    DeviceAction(name: "siri", label: "Siri", symbol: "waveform", prose: "Activated Siri."),
    DeviceAction(name: "applePay", label: "Apple Pay", symbol: "creditcard.fill", prose: "Triggered the Apple Pay shortcut."),
    DeviceAction(name: "playPause", label: "Play/Pause", symbol: "playpause.fill", prose: "Pressed Play/Pause."),
    DeviceAction(name: "shake", label: "Shake", symbol: "iphone.radiowaves.left.and.right", prose: "Shook the device."),
  ]

  /// Case-insensitive lookup, so an agent writing `"Home"` or `"applepay"` is understood.
  static func named(_ name: String) -> DeviceAction? {
    all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
  }

  static var names: String {
    all.map(\.name).joined(separator: ", ")
  }
}
