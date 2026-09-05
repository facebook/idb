/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
@testable import FBSimulatorControl
import XCTest

// MARK: - Test Doubles
//
// The simulator reaches its device by Objective-C message send, having been handed one of these
// in place of a real `SimDevice`, so the doubles are `@objc` `NSObject` subclasses whose
// property names match the selectors the simulator sends.

@objc final class TestSimDeviceType: NSObject {
  @objc var productFamilyID: Int32 = 1
  @objc var mainScreenSize: CGSize = CGSize(width: 750, height: 1334)
  @objc var mainScreenScale: Float = 2.0
  @objc var name: String = "iPhone 14"
}

@objc final class TestSimRuntime: NSObject {
  @objc var root: String = "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot"
  @objc var name: String = "iOS 17.0"
}

@objc final class TestSimDeviceSet: NSObject {
  @objc var setPath: String = ("~/Library/Developer/CoreSimulator/Devices" as NSString).expandingTildeInPath
}

@objc final class TestSimDevice: NSObject {
  @objc var UDID: NSUUID = NSUUID()
  @objc var name: String = "TestSimulator"
  @objc var state: UInt = UInt(FBiOSTargetState.booted.rawValue)
  @objc var dataPath: String = "/tmp/test-sim-data"
  @objc var deviceType = TestSimDeviceType()
  @objc var runtime = TestSimRuntime()
  @objc var deviceSet = TestSimDeviceSet()
  @objc var lookupPort: mach_port_t = mach_port_t(MACH_PORT_NULL)
  @objc var lookupShouldFail = false

  @objc(lookup:error:)
  func lookup(_ name: String, error: NSErrorPointer) -> mach_port_t {
    if lookupShouldFail {
      error?.pointee = NSError(
        domain: "FBSimulatorTestDomain",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Port not found"])
      return mach_port_t(MACH_PORT_NULL)
    }
    return lookupPort
  }
}

// MARK: - Test Class

final class FBSimulatorTests: XCTestCase {

  private var stubDevice: TestSimDevice!
  private var simulator: FBSimulator!

  override func setUpWithError() throws {
    try super.setUpWithError()
    stubDevice = TestSimDevice()
    simulator = Self.createSimulator(with: stubDevice)
  }

  override func tearDownWithError() throws {
    simulator = nil
    stubDevice = nil
    try super.tearDownWithError()
  }

  private static func createSimulator(with device: TestSimDevice) -> FBSimulator {
    FBSimulatorTestSupport.testableSimulator(withDevice: device)
  }

  // MARK: - Product Family

  func testProductFamily_WhenFamilyIDIs1_ReturnsiPhone() {
    stubDevice.deviceType.productFamilyID = 1
    let sim = Self.createSimulator(with: stubDevice)
    XCTAssertEqual(sim.productFamily, .familyiPhone, "productFamilyID 1 should map to iPhone")
  }

  func testProductFamily_WhenFamilyIDIs2_ReturnsiPad() {
    stubDevice.deviceType.productFamilyID = 2
    let sim = Self.createSimulator(with: stubDevice)
    XCTAssertEqual(sim.productFamily, .familyiPad, "productFamilyID 2 should map to iPad")
  }

  func testProductFamily_WhenFamilyIDIs3_ReturnsAppleTV() {
    stubDevice.deviceType.productFamilyID = 3
    let sim = Self.createSimulator(with: stubDevice)
    XCTAssertEqual(sim.productFamily, .familyAppleTV, "productFamilyID 3 should map to AppleTV")
  }

  func testProductFamily_WhenFamilyIDIs4_ReturnsAppleWatch() {
    stubDevice.deviceType.productFamilyID = 4
    let sim = Self.createSimulator(with: stubDevice)
    XCTAssertEqual(sim.productFamily, .familyAppleWatch, "productFamilyID 4 should map to AppleWatch")
  }

  func testProductFamily_WhenFamilyIDIsUnknown_ReturnsUnknown() {
    stubDevice.deviceType.productFamilyID = 99
    let sim = Self.createSimulator(with: stubDevice)
    XCTAssertEqual(sim.productFamily, .familyUnknown, "Unrecognized productFamilyID should map to Unknown")
  }

  // MARK: - Custom Device Set Path

  func testCustomDeviceSetPath_WhenDefaultPath_ReturnsNil() {
    stubDevice.deviceSet.setPath = ("~/Library/Developer/CoreSimulator/Devices" as NSString).expandingTildeInPath
    let sim = Self.createSimulator(with: stubDevice)
    XCTAssertNil(sim.customDeviceSetPath, "customDeviceSetPath should be nil when using the default device set path")
  }

  func testCustomDeviceSetPath_WhenCustomPath_ReturnsPath() {
    let customPath = "/custom/simulator/devices"
    stubDevice.deviceSet.setPath = customPath
    let sim = Self.createSimulator(with: stubDevice)
    XCTAssertEqual(
      sim.customDeviceSetPath, customPath,
      "customDeviceSetPath should return the custom path when not using the default")
  }

  // MARK: - Screen Info

  func testScreenInfo_ReturnsDeviceTypeScreenDimensions() throws {
    stubDevice.deviceType.mainScreenSize = CGSize(width: 1170, height: 2532)
    stubDevice.deviceType.mainScreenScale = 3.0
    let sim = Self.createSimulator(with: stubDevice)

    let screenInfo = try XCTUnwrap(sim.screenInfo, "screenInfo should not be nil")

    XCTAssertEqual(screenInfo.widthPixels, 1170, "widthPixels should match device type mainScreenSize.width")
    XCTAssertEqual(screenInfo.heightPixels, 2532, "heightPixels should match device type mainScreenSize.height")
    XCTAssertEqual(screenInfo.scale, 3.0, accuracy: 0.001, "scale should match device type mainScreenScale")
  }

  // MARK: - Equality and Hashing

  func testIsEqual_WhenSameDevice_ReturnsYES() {
    let sim1 = Self.createSimulator(with: stubDevice)
    let sim2 = Self.createSimulator(with: stubDevice)
    XCTAssertEqual(sim1, sim2, "Two simulators wrapping the same device should be equal")
  }

  func testIsEqual_WhenDifferentDevice_ReturnsNO() {
    let sim2 = Self.createSimulator(with: TestSimDevice())
    XCTAssertNotEqual(simulator, sim2, "Two simulators wrapping different devices should not be equal")
  }

  func testHash_DelegatesToDevice() {
    let sim1 = Self.createSimulator(with: stubDevice)
    let sim2 = Self.createSimulator(with: stubDevice)
    XCTAssertEqual(sim1.hashValue, sim2.hashValue, "Simulators wrapping the same device should hash identically")
    XCTAssertEqual(Set([sim1, sim2]).count, 1, "A set should collapse simulators wrapping the same device")
  }

  // MARK: - Temporary Directory (Lazy Init)

  func testTemporaryDirectory_ReturnsSameInstanceOnSubsequentAccess() {
    let first = simulator.temporaryDirectory
    let second = simulator.temporaryDirectory
    XCTAssertTrue(first === second, "temporaryDirectory should return the same cached instance on subsequent access")
  }

  // MARK: - Healthcheck Helpers

  func testLookupBootstrapPortNamed_WhenPortExists_ReturnsPortNumber() throws {
    stubDevice.lookupPort = 12345
    stubDevice.lookupShouldFail = false
    let sim = Self.createSimulator(with: stubDevice)

    let port = try sim.lookupBootstrapPortNamed("com.apple.testservice")

    XCTAssertEqual(try XCTUnwrap(port).uint32Value, 12345, "Returned port number should match the looked-up port")
  }

  // Both no-port paths throw: the device's own error when it reported one, and a synthesized
  // `FBSimulatorPortLookupError` when it did not. They are told apart by the error's domain.
  func testLookupBootstrapPortNamed_WhenPortIsNull_ProducesNoPort() {
    stubDevice.lookupPort = mach_port_t(MACH_PORT_NULL)
    stubDevice.lookupShouldFail = false
    let sim = Self.createSimulator(with: stubDevice)

    XCTAssertThrowsError(try sim.lookupBootstrapPortNamed("com.apple.nonexistent"), "No port should be produced when MACH_PORT_NULL is returned") { error in
      XCTAssertNotEqual(
        (error as NSError).domain, "FBSimulatorTestDomain",
        "A null port is not a lookup failure - the device reported no error of its own")
    }
  }

  func testLookupBootstrapPortNamed_WhenLookupFails_ReturnsNilWithError() {
    stubDevice.lookupShouldFail = true
    let sim = Self.createSimulator(with: stubDevice)

    XCTAssertThrowsError(try sim.lookupBootstrapPortNamed("com.apple.failing"), "Error should be populated when lookup fails") { error in
      XCTAssertEqual((error as NSError).domain, "FBSimulatorTestDomain", "The device's own lookup error should surface")
    }
  }
}
