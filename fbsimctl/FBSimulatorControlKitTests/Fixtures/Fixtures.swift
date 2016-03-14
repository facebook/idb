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
  static var application: FBSimulatorApplication { get {
    return FBSimulatorApplication.xcodeSimulator()
  }}

  static var binary: FBSimulatorBinary { get {
    let basePath: NSString = FBControlCoreGlobalConfiguration.developerDirectory()
    return try! FBSimulatorBinary(
      path: basePath.stringByAppendingPathComponent("Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/sbin/launchd_sim")
    )
  }}

  static var photoPath: String { get {
    return NSBundle(forClass: FBSimulatorControlKitTestsNSObject.self).pathForResource("photo0", ofType: "png")!
  }}

  static var photoDiagnostic: FBDiagnostic { get {
    return FBDiagnosticBuilder().updatePath(self.photoPath).build()
  }}

  static var videoPath: String { get {
    return NSBundle(forClass: FBSimulatorControlKitTestsNSObject.self).pathForResource("video0", ofType: "mp4")!
  }}

  static var videoDiagnostic: FBDiagnostic { get {
    return FBDiagnosticBuilder().updatePath(self.videoPath).build()
  }}
}
