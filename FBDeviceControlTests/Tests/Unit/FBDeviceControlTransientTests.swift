/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import XCTest

final class FBDeviceControlTransientTests: XCTestCase {

  // MARK: - FBDeviceStorage Tests

  func testAttachAndLookupDevice() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("device1" as NSString, forKey: "key1")

    let retrieved = storage.device(forKey: "key1") as? NSString
    XCTAssertEqual(retrieved, "device1")
  }

  func testAttachedPropertyReflectsAttachedDevices() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("device1" as NSString, forKey: "key1")
    storage.deviceAttached("device2" as NSString, forKey: "key2")

    let attached = storage.attached as? [String: NSString]
    XCTAssertEqual(attached?.count, 2)
    XCTAssertEqual(attached?["key1"], "device1")
    XCTAssertEqual(attached?["key2"], "device2")
  }

  func testDetachRemovesFromAttached() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("device1" as NSString, forKey: "key1")
    storage.deviceDetached(forKey: "key1")

    let attached = storage.attached as? [String: NSString]
    XCTAssertEqual(attached?.count, 0)
  }

  func testLookupReturnsNilForUnknownKey() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    let result = storage.device(forKey: "nonexistent")
    XCTAssertNil(result)
  }

  func testReattachUpdatesDevice() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("old" as NSString, forKey: "key1")
    storage.deviceAttached("new" as NSString, forKey: "key1")

    let retrieved = storage.device(forKey: "key1") as? NSString
    XCTAssertEqual(retrieved, "new")
  }

  func testDetachedDeviceNotInAttachedButStillLookupable() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("device1" as NSString, forKey: "key1")
    storage.deviceDetached(forKey: "key1")

    // After detach, device is removed from the attached dictionary
    let attached = storage.attached as? [String: NSString]
    XCTAssertNil(attached?["key1"])

    // But it can still be found via lookup (weak reference from NSString literal persists)
    let retrieved = storage.device(forKey: "key1")
    XCTAssertNotNil(retrieved)
  }

  func testMultipleDevicesAttachAndDetach() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("d1" as NSString, forKey: "k1")
    storage.deviceAttached("d2" as NSString, forKey: "k2")
    storage.deviceAttached("d3" as NSString, forKey: "k3")

    storage.deviceDetached(forKey: "k2")

    XCTAssertNotNil(storage.device(forKey: "k1"))
    XCTAssertNotNil(storage.device(forKey: "k3"))

    let attached = storage.attached as? [String: NSString]
    XCTAssertEqual(attached?.count, 2)
    XCTAssertNil(attached?["k2"])
  }

  func testReferencedPropertyTracksAllKnownDevices() {
    let storage = FBDeviceStorage<NSString>(logger: FBControlCoreGlobalConfiguration.defaultLogger)
    storage.deviceAttached("d1" as NSString, forKey: "k1")
    storage.deviceAttached("d2" as NSString, forKey: "k2")

    // Both attached and referenced should have 2 entries
    let referenced = storage.referenced as? [String: NSString]
    XCTAssertEqual(referenced?.count, 2)

    // Detach one - attached drops to 1, referenced still has 2 (string literals are immortal)
    storage.deviceDetached(forKey: "k1")
    let attached = storage.attached as? [String: NSString]
    XCTAssertEqual(attached?.count, 1)

    let referencedAfter = storage.referenced as? [String: NSString]
    XCTAssertEqual(referencedAfter?.count, 2)
  }

  // MARK: - FBDeviceControlError Tests

  func testErrorDomain() {
    XCTAssertEqual(FBDeviceControlErrorDomain, "com.facebook.FBDeviceControl")
  }

  func testErrorBuilderCreatesErrorInCorrectDomain() {
    let nsError = FBDeviceControlError.describe("test error").build() as NSError
    XCTAssertEqual(nsError.domain, "com.facebook.FBDeviceControl")
  }

  func testErrorBuilderWithDescription() {
    let nsError = FBDeviceControlError.describe("error foo 42").build() as NSError
    XCTAssertTrue(nsError.localizedDescription.contains("foo"))
    XCTAssertTrue(nsError.localizedDescription.contains("42"))
  }

  func testErrorFailFuture() {
    let future: FBFuture<AnyObject> = FBDeviceControlError.describe("future error").failFuture()
    do {
      _ = try future.await()
      XCTFail("Expected future to throw")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, "com.facebook.FBDeviceControl")
    }
  }

  // MARK: - FileManager+TemporaryFile Tests

  func testTemporaryFileCreation() throws {
    let url = try FileManager.default.temporaryFile(extension: "txt")
    XCTAssertTrue(
      url.lastPathComponent.hasSuffix(".txt") || url.lastPathComponent.contains("."),
      "Temporary file should have a file extension component")
    // The parent directory should exist (it was created by the method)
    let parentDir: String
    if #available(macOS 13.0, *) {
      parentDir = url.deletingLastPathComponent().path()
    } else {
      parentDir = url.deletingLastPathComponent().path
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: parentDir))
  }

  func testTemporaryFileUniqueness() throws {
    let url1 = try FileManager.default.temporaryFile(extension: "json")
    let url2 = try FileManager.default.temporaryFile(extension: "json")
    XCTAssertNotEqual(url1, url2, "Each call should produce a unique path")
  }

  func testTemporaryFileDifferentExtensions() throws {
    let txtURL = try FileManager.default.temporaryFile(extension: "txt")
    let jsonURL = try FileManager.default.temporaryFile(extension: "json")
    if #available(macOS 13.0, *) {
      XCTAssertTrue(txtURL.lastPathComponent.hasSuffix(".txt"))
      XCTAssertTrue(jsonURL.lastPathComponent.hasSuffix(".json"))
    }
  }

  // MARK: - Wallpaper Name Constants Tests

  func testWallpaperNameConstants() {
    XCTAssertEqual(FBWallpaperName.homescreen.rawValue, "homescreen")
    XCTAssertEqual(FBWallpaperName.lockscreen.rawValue, "lockscreen")
  }

  // MARK: - Springboard Service Name Constants

  func testSpringboardServiceName() {
    XCTAssertEqual(FBSpringboardServiceName, "com.apple.springboardservices")
  }

  func testManagedConfigServiceName() {
    XCTAssertEqual(FBManagedConfigService, "com.apple.mobile.MCInstall")
  }
}
