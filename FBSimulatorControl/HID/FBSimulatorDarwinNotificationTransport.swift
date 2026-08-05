/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

/**
 The transport for the two inputs the simulator takes as Darwin notifications rather than as synthesized
 input: shake, and toggling the in-call status bar.

 Not transport-switchable, and the only one of the four with no codec — the payload is a notification
 name, so there is nothing to build. Naming the two here rather than at the dispatch site keeps the
 strings with the thing that posts them.

 Connectionless: each post goes straight to the device, so there is nothing to hold open, drain or tear
 down.

 SAFETY: holds only an immutable weak reference to the target and posts through it.
 */
// patternlint-disable-next-line unchecked-sendable
final class FBSimulatorDarwinNotificationTransport: @unchecked Sendable {

  private static let shake = "com.apple.UIKit.SimulatorShake"
  private static let inCallStatusBar = "com.apple.iphonesimulator.toggleincallstatusbar"

  private weak var simulator: FBSimulator?

  init(simulator: FBSimulator?) {
    self.simulator = simulator
  }

  // MARK: Sends

  /// Shakes the device.
  func sendShake() throws {
    try post(Self.shake)
  }

  /// Toggles the in-call status bar.
  func sendToggleInCallStatusBar() throws {
    try post(Self.inCallStatusBar)
  }

  // MARK: Transit

  private func post(_ notificationName: String) throws {
    guard let simulator else {
      throw FBWeakTargetError.simulator
    }
    try simulator.device.postDarwinNotification(notificationName)
  }
}
