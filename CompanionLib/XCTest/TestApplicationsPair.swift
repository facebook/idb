/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct TestApplicationsPair: CustomStringConvertible {

  public let applicationUnderTest: InstalledApplication?
  public let testHostApp: InstalledApplication?

  public init(applicationUnderTest: InstalledApplication?, testHostApp: InstalledApplication?) {
    self.applicationUnderTest = applicationUnderTest
    self.testHostApp = testHostApp
  }

  public var description: String {
    let autDesc = applicationUnderTest.map { "\($0)" } ?? "(null)"
    let hostDesc = testHostApp.map { "\($0)" } ?? "(null)"
    return "AUT \(autDesc), Test Host \(hostDesc)"
  }
}
