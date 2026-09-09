/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Foundation
import Testing

/// Whether the manager outlives the caller that owns it, once it has listened for device
/// notifications.
///
/// Registering hands MobileDevice a context pointer to the manager, retained so the C callback has
/// something valid to message. Unregistering has to give that retain back, or the manager is
/// immortal from the first `startListening`.
@Suite
struct AMRestorableDeviceManagerRetentionTests {

  /// `AMDCalls` with just the registration pair stubbed: registering reports a plausible
  /// identifier, unregistering does nothing. No device is involved.
  private func stubbedCalls() -> AMDCalls {
    var calls = CreateZeroedAMDCalls()
    calls.RestorableDeviceRegisterForNotifications = { _, _, _, _ in 1 }
    calls.RestorableDeviceUnregisterForNotifications = { _ in 0 }
    return calls
  }

  private func makeManager() -> AMRestorableDeviceManager {
    AMRestorableDeviceManager(
      calls: stubbedCalls(),
      work: DispatchQueue(label: "com.facebook.fbdevicecontrol.test.work"),
      asyncQueue: DispatchQueue(label: "com.facebook.fbdevicecontrol.test.async"),
      ecidFilter: nil,
      logger: FBControlCoreGlobalConfiguration.defaultLogger)
  }

  @Test
  func unusedManagerIsReleased() {
    weak var weakManager: AMRestorableDeviceManager?
    autoreleasepool {
      let manager = makeManager()
      weakManager = manager
    }
    #expect(weakManager == nil)
  }

  @Test
  func listenedManagerIsReleased() throws {
    weak var weakManager: AMRestorableDeviceManager?
    try autoreleasepool {
      let manager = makeManager()
      weakManager = manager
      try manager.startListening()
      try manager.stopListening()
    }
    #expect(weakManager == nil)
  }
}
