/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Testing

@Suite
struct FBDeviceControlTransientTests {

  // MARK: - FBDeviceStorage Tests

  @Test
  func attachAndLookupDevice() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("device1" as NSString, forKey: "key1")

    let retrieved = storage.device(forKey: "key1") as? NSString
    #expect((retrieved) == ("device1"))
  }

  @Test
  func attachedPropertyReflectsAttachedDevices() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("device1" as NSString, forKey: "key1")
    storage.deviceAttached("device2" as NSString, forKey: "key2")

    let attached = storage.attached as? [String: NSString]
    #expect((attached?.count) == (2))
    #expect((attached?["key1"]) == ("device1"))
    #expect((attached?["key2"]) == ("device2"))
  }

  @Test
  func detachRemovesFromAttached() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("device1" as NSString, forKey: "key1")
    storage.deviceDetached(forKey: "key1")

    let attached = storage.attached as? [String: NSString]
    #expect((attached?.count) == (0))
  }

  @Test
  func lookupReturnsNilForUnknownKey() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    let result = storage.device(forKey: "nonexistent")
    #expect((result) == nil)
  }

  @Test
  func reattachUpdatesDevice() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("old" as NSString, forKey: "key1")
    storage.deviceAttached("new" as NSString, forKey: "key1")

    let retrieved = storage.device(forKey: "key1") as? NSString
    #expect((retrieved) == ("new"))
  }

  @Test
  func detachedDeviceNotInAttachedButStillLookupable() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("device1" as NSString, forKey: "key1")
    storage.deviceDetached(forKey: "key1")

    // After detach, device is removed from the attached dictionary
    let attached = storage.attached as? [String: NSString]
    #expect((attached?["key1"]) == nil)

    // But it can still be found via lookup (weak reference from NSString literal persists)
    let retrieved = storage.device(forKey: "key1")
    #expect((retrieved) != nil)
  }

  @Test
  func multipleDevicesAttachAndDetach() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("d1" as NSString, forKey: "k1")
    storage.deviceAttached("d2" as NSString, forKey: "k2")
    storage.deviceAttached("d3" as NSString, forKey: "k3")

    storage.deviceDetached(forKey: "k2")

    #expect((storage.device(forKey: "k1")) != nil)
    #expect((storage.device(forKey: "k3")) != nil)

    let attached = storage.attached as? [String: NSString]
    #expect((attached?.count) == (2))
    #expect((attached?["k2"]) == nil)
  }

  @Test
  func referencedPropertyTracksAllKnownDevices() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("d1" as NSString, forKey: "k1")
    storage.deviceAttached("d2" as NSString, forKey: "k2")

    // Both attached and referenced should have 2 entries
    let referenced = storage.referenced as? [String: NSString]
    #expect((referenced?.count) == (2))

    // Detach one - attached drops to 1, referenced still has 2 (string literals are immortal)
    storage.deviceDetached(forKey: "k1")
    let attached = storage.attached as? [String: NSString]
    #expect((attached?.count) == (1))

    let referencedAfter = storage.referenced as? [String: NSString]
    #expect((referencedAfter?.count) == (2))
  }

  /// A device type that is not rooted in `NSObject`, which the weakly-referencing map has to hold
  /// just as well as an Objective-C one.
  private final class NativeDevice {}

  @Test
  func attachAndLookupNativeSwiftDevice() {
    let storage = FBDeviceStorage<NativeDevice>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    let device = NativeDevice()
    storage.deviceAttached(device, forKey: "key1")

    #expect(storage.device(forKey: "key1") === device)
    #expect(storage.attached["key1"] === device)
    #expect(storage.referenced["key1"] === device)
  }

  @Test
  func detachedNativeSwiftDeviceIsStillLookupableWhileHeld() {
    let storage = FBDeviceStorage<NativeDevice>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    let device = NativeDevice()
    storage.deviceAttached(device, forKey: "key1")
    storage.deviceDetached(forKey: "key1")

    #expect(storage.attached["key1"] == nil)
    #expect(storage.device(forKey: "key1") === device)
    #expect(storage.referenced["key1"] === device)
  }

  @Test
  func detachedNativeSwiftDeviceLeavesTheReferenceMapOnceReleased() {
    let storage = FBDeviceStorage<NativeDevice>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    // The device goes into the reference map through an Objective-C accessor, which can leave an
    // autoreleased reference behind, so it is released inside a pool of its own rather than
    // relying on the scope end alone to be the point of deallocation.
    autoreleasepool {
      let device = NativeDevice()
      storage.deviceAttached(device, forKey: "key1")
      storage.deviceDetached(forKey: "key1")
    }

    #expect(storage.device(forKey: "key1") == nil)
    #expect(storage.referenced.isEmpty)
  }

  // MARK: - FBDeviceControlError Tests

  @Test
  func errorDomain() {
    #expect((FBDeviceControlErrorDomain) == ("com.facebook.FBDeviceControl"))
  }

  @Test
  func errorBuilderCreatesErrorInCorrectDomain() {
    let nsError = FBDeviceControlError.describe("test error").build() as NSError
    #expect((nsError.domain) == ("com.facebook.FBDeviceControl"))
  }

  @Test
  func errorBuilderWithDescription() {
    let nsError = FBDeviceControlError.describe("error foo 42").build() as NSError
    #expect((nsError.localizedDescription.contains("foo")))
    #expect((nsError.localizedDescription.contains("42")))
  }

  @Test
  func errorFailFuture() async {
    let future: FBFuture<AnyObject> = FBDeviceControlError.describe("future error").failFuture()
    do {
      _ = try await bridgeFBFuture(future)
      Issue.record("Expected future to throw")
    } catch {
      let nsError = error as NSError
      #expect((nsError.domain) == ("com.facebook.FBDeviceControl"))
    }
  }

  // MARK: - FileManager+TemporaryFile Tests

  @Test
  func temporaryFileCreation() throws {
    let url = try FileManager.default.temporaryFile(extension: "txt")
    #expect((url.lastPathComponent.hasSuffix(".txt") || url.lastPathComponent.contains(".")), "Temporary file should have a file extension component")
    // The parent directory should exist (it was created by the method)
    let parentDir: String
    if #available(macOS 13.0, *) {
      parentDir = url.deletingLastPathComponent().path()
    } else {
      parentDir = url.deletingLastPathComponent().path
    }
    #expect((FileManager.default.fileExists(atPath: parentDir)))
  }

  @Test
  func temporaryFileUniqueness() throws {
    let url1 = try FileManager.default.temporaryFile(extension: "json")
    let url2 = try FileManager.default.temporaryFile(extension: "json")
    #expect((url1) != (url2), "Each call should produce a unique path")
  }

  @Test
  func temporaryFileDifferentExtensions() throws {
    let txtURL = try FileManager.default.temporaryFile(extension: "txt")
    let jsonURL = try FileManager.default.temporaryFile(extension: "json")
    if #available(macOS 13.0, *) {
      #expect((txtURL.lastPathComponent.hasSuffix(".txt")))
      #expect((jsonURL.lastPathComponent.hasSuffix(".json")))
    }
  }

  // MARK: - Wallpaper Name Constants Tests

  @Test
  func wallpaperNameConstants() {
    #expect((FBWallpaperName.homescreen.rawValue) == ("homescreen"))
    #expect((FBWallpaperName.lockscreen.rawValue) == ("lockscreen"))
  }

  // MARK: - Springboard Service Name Constants

  @Test
  func springboardServiceName() {
    #expect((FBSpringboardServiceName) == ("com.apple.springboardservices"))
  }

  @Test
  func managedConfigServiceName() {
    #expect((FBManagedConfigService) == ("com.apple.mobile.MCInstall"))
  }
}
