/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import Testing

/// The double is not a `SimRuntime` — it merely responds to the selectors the resolver sends —
/// so any checked conversion traps; round-tripping through the opaque pointer performs no check.
private func asSimRuntime(_ object: AnyObject) -> SimRuntime {
  Unmanaged<SimRuntime>.fromOpaque(Unmanaged.passUnretained(object).toOpaque()).takeUnretainedValue()
}

@Suite("FBSimulatorConfiguration runtime resolution")
struct FBSimulatorRuntimeResolutionTests {

  private static let device = FBiOSTargetConfiguration.nameToDevice[FBDeviceModel(rawValue: "iPhone 16")]!

  private static var configuration: FBSimulatorConfiguration {
    FBSimulatorConfiguration(device: device, os: FBOSVersion.generic(withName: "iOS 27.0"))
  }

  private static func makeRuntime(name: String, build: String, available: Bool = true) -> SimRuntime {
    let runtime = FBSimulatorControlTests_SimDeviceRuntime_Double()
    runtime.name = name
    runtime.versionString = String(name.split(separator: " ").last ?? "")
    runtime.buildVersionString = build
    runtime.available = available
    runtime.supportedProductFamilyIDs = [NSNumber(value: device.family.rawValue)]
    return asSimRuntime(runtime)
  }

  @Test func singleMatchingRuntimeResolves() throws {
    let match = Self.makeRuntime(name: "iOS 27.0", build: "24A5423a")
    let resolved = try FBSimulatorConfiguration.resolveRuntime(
      for: Self.configuration,
      from: [Self.makeRuntime(name: "iOS 26.5", build: "23F77"), match])
    #expect(resolved.buildVersionString == "24A5423a")
  }

  @Test func noMatchingRuntimeThrows() {
    #expect(throws: FBSimulatorConfigurationError.self) {
      try FBSimulatorConfiguration.resolveRuntime(
        for: Self.configuration,
        from: [Self.makeRuntime(name: "iOS 26.5", build: "23F77")])
    }
  }

  @Test func unavailableRuntimeDoesNotMatch() {
    #expect(throws: FBSimulatorConfigurationError.self) {
      try FBSimulatorConfiguration.resolveRuntime(
        for: Self.configuration,
        from: [Self.makeRuntime(name: "iOS 27.0", build: "24A5423a", available: false)])
    }
  }

  @Test func multipleBuildsOfTheSameVersionAreAmbiguous() throws {
    // BUG: multiple installed builds of one runtime version (a normal beta-cycle state) should
    // resolve to the newest build; instead resolution fails as ambiguous, making the version
    // unusable. Flipped in the following commit.
    do {
      _ = try FBSimulatorConfiguration.resolveRuntime(
        for: Self.configuration,
        from: [
          Self.makeRuntime(name: "iOS 27.0", build: "24A5370g"),
          Self.makeRuntime(name: "iOS 27.0", build: "24A5423a"),
          Self.makeRuntime(name: "iOS 27.0", build: "24A5390f"),
        ])
      Issue.record("Expected ambiguous resolution to throw")
    } catch let error as FBSimulatorConfigurationError {
      guard case .ambiguousRuntime = error else {
        Issue.record("Expected ambiguousRuntime, got \(error)")
        return
      }
    }
  }
}
