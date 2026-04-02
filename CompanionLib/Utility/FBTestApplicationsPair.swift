/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc public final class FBTestApplicationsPair: NSObject {

  @objc public let applicationUnderTest: FBInstalledApplication?
  @objc public let testHostApp: FBInstalledApplication?

  @objc public init(applicationUnderTest: FBInstalledApplication?, testHostApp: FBInstalledApplication?) {
    self.applicationUnderTest = applicationUnderTest
    self.testHostApp = testHostApp
    super.init()
  }

  public override var description: String {
    let autDesc = applicationUnderTest.map { "\($0)" } ?? "(null)"
    let hostDesc = testHostApp.map { "\($0)" } ?? "(null)"
    return "AUT \(autDesc), Test Host \(hostDesc)"
  }
}
