/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import XCTest
import FBSimulatorControl
@testable import FBSimulatorControlKit

@objc class FBSimulatorControlKitTestsNSObject : NSObject {

}

struct Fixtures {
  static var application: FBApplicationDescriptor { get {
    return FBApplicationDescriptor.xcodeSimulator()
  }}

  static var binary: FBBinaryDescriptor { get {
    let basePath: NSString = FBControlCoreGlobalConfiguration.developerDirectory() as NSString
    return try! FBBinaryDescriptor.binary(
      withPath: basePath.appendingPathComponent("Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/sbin/launchd_sim")
    )
  }}

  static var photoPath: String { get {
    return Bundle(for: FBSimulatorControlKitTestsNSObject.self).path(forResource: "photo0", ofType: "png")!
  }}

  static var photoDiagnostic: FBDiagnostic { get {
    return FBDiagnosticBuilder().updatePath(self.photoPath).build()
  }}

  static var videoPath: String { get {
    return Bundle(for: FBSimulatorControlKitTestsNSObject.self).path(forResource: "video0", ofType: "mp4")!
  }}

  static var videoDiagnostic: FBDiagnostic { get {
    return FBDiagnosticBuilder().updatePath(self.videoPath).build()
  }}

  static var testBundlePath: String { get {
    return Bundle.main.bundlePath
  }}
}

extension CreationSpecification {
  static var empty: CreationSpecification { get {
    return CreationSpecification.individual(
      IndividualCreationConfiguration(osVersion: nil, deviceType: nil, auxDirectory: nil)
    )
  }}

  static var iOS9CreationSpecification: CreationSpecification { get {
    return CreationSpecification.individual(
      IndividualCreationConfiguration(osVersion: FBControlCoreConfiguration_iOS_9_0(), deviceType: nil, auxDirectory: nil)
    )
  }}

  static var iPhone6Configuration: CreationSpecification { get {
    return CreationSpecification.individual(
      IndividualCreationConfiguration(osVersion: nil, deviceType: FBControlCoreConfiguration_Device_iPhone6(), auxDirectory: nil)
    )
  }}

  static var auxDirectoryConfiguration: CreationSpecification { get {
    return CreationSpecification.individual(
      IndividualCreationConfiguration(osVersion: nil, deviceType: nil, auxDirectory: "/usr/bin")
    )
  }}

  static var compoundConfiguration0: CreationSpecification { get {
    return CreationSpecification.individual(
      IndividualCreationConfiguration(osVersion: FBControlCoreConfiguration_iOS_9_3(), deviceType: FBControlCoreConfiguration_Device_iPhone6S(), auxDirectory: nil)
    )
  }}

  static var compoundConfiguration1: CreationSpecification { get {
    return CreationSpecification.individual(
      IndividualCreationConfiguration(osVersion: FBControlCoreConfiguration_iOS_10_0(), deviceType: FBControlCoreConfiguration_Device_iPadAir2(), auxDirectory: nil)
    )
  }}
}
