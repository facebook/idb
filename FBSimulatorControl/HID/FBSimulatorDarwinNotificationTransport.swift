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

 Connectionless: each post goes straight to the device, so there is nothing to hold open, drain or tear
 down. The post is a synchronous hop into CoreSimulator, so it runs on a private serial queue and the
 caller awaits it, for the same reason the Purple transport does — a cooperative thread should not be
 held by a blocking call.

 SAFETY: holds only an immutable weak reference to the target and posts through it.
 */
// patternlint-disable-next-line unchecked-sendable
final class FBSimulatorDarwinNotificationTransport: @unchecked Sendable {

  private static let shake = "com.apple.UIKit.SimulatorShake"
  private static let inCallStatusBar = "com.apple.iphonesimulator.toggleincallstatusbar"

  /// Serial, so the blocking post never runs on a cooperative thread.
  private let postQueue = DispatchQueue(label: "com.facebook.FBSimulatorControl.darwin-notification")
  private weak var simulator: FBSimulator?

  init(simulator: FBSimulator?) {
    self.simulator = simulator
  }

  // MARK: Sends

  /// Shakes the device.
  func sendShake() async throws {
    try await post(Self.shake)
  }

  /// Toggles the in-call status bar.
  func sendToggleInCallStatusBar() async throws {
    try await post(Self.inCallStatusBar)
  }

  // MARK: Transit

  private func post(_ notificationName: String) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      postQueue.async {
        do {
          try self.postBlocking(notificationName)
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func postBlocking(_ notificationName: String) throws {
    guard let simulator else {
      throw FBWeakTargetError.simulator
    }
    try simulator.device.postDarwinNotification(notificationName)
  }
}
