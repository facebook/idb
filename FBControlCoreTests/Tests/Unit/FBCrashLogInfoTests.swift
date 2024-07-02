/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore

import XCTest

final class FBCrashLogInfoTests: XCTestCase {

  func testAssetsdCustomSet() throws {
    let info = try FBCrashLogInfo.fromCrashLog(atPath: TestFixtures.assetsdCrashPathWithCustomDeviceSet)

    XCTAssertEqual(info.processIdentifier, 39942)
    XCTAssertEqual(info.parentProcessIdentifier, 39927)
    XCTAssertEqual(info.identifier, "assetsd")
    XCTAssertEqual(info.processName, "assetsd")
    XCTAssertEqual(info.parentProcessName, "launchd_sim")
    XCTAssertEqual(info.executablePath, "/Applications/xcode_7.2.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/System/Library/Frameworks/AssetsLibrary.framework/Support/assetsd")
    XCTAssertEqual(info.date.timeIntervalSinceReferenceDate, 479723902, accuracy: 1)
    XCTAssertEqual(info.processType, .system)
  }

  func testAgentCustomSet() throws {
    let info = try FBCrashLogInfo.fromCrashLog(atPath: TestFixtures.agentCrashPathWithCustomDeviceSet)

    XCTAssertEqual(info.processIdentifier, 39655)
    XCTAssertEqual(info.parentProcessIdentifier, 39576)
    XCTAssertEqual(info.identifier, "WebDriverAgent")
    XCTAssertEqual(info.processName, "WebDriverAgent")
    XCTAssertEqual(info.parentProcessName, "launchd_sim")
    XCTAssertEqual(info.executablePath, "/Users/USER/*/WebDriverAgent")
    XCTAssertEqual(info.date.timeIntervalSinceReferenceDate, 479723798, accuracy: 1)
    XCTAssertEqual(info.processType, .custom)
  }

  func testAppDefaultSet() throws {
    let info = try FBCrashLogInfo.fromCrashLog(atPath: TestFixtures.appCrashPathWithDefaultDeviceSet)

    XCTAssertEqual(info.processIdentifier, 37083)
    XCTAssertEqual(info.parentProcessIdentifier, 37007)
    XCTAssertEqual(info.identifier, "TableSearch")
    XCTAssertEqual(info.processName, "TableSearch")
    XCTAssertEqual(info.parentProcessName, "launchd_sim")
    XCTAssertEqual(info.executablePath, "/Users/USER/Library/Developer/CoreSimulator/Devices/2FF8DD07-20B7-4D04-97F0-092DF61CD3C3/data/Containers/Bundle/Application/2BF2C731-1965-497D-B3E2-E347BD7BF464/TableSearch.app/TableSearch")
    XCTAssertEqual(info.date.timeIntervalSinceReferenceDate, 479723201, accuracy: 1)
    XCTAssertEqual(info.processType, .application)
  }

  func testAppCustomSet() throws {
    let info = try FBCrashLogInfo.fromCrashLog(atPath: TestFixtures.appCrashPathWithCustomDeviceSet)

    XCTAssertEqual(info.processIdentifier, 40119)
    XCTAssertEqual(info.parentProcessIdentifier, 39927)
    XCTAssertEqual(info.identifier, "TableSearch")
    XCTAssertEqual(info.processName, "TableSearch")
    XCTAssertEqual(info.parentProcessName, "launchd_sim")
    XCTAssertEqual(info.executablePath, "/private/var/folders/*/TableSearch.app/TableSearch")
    XCTAssertEqual(info.date.timeIntervalSinceReferenceDate, 479723902, accuracy: 1)
    XCTAssertEqual(info.processType, .application)
  }

  func testIdentifierPredicate() throws {
    try XCTAssertEqual(allCrashLogs.filtered(using: FBCrashLogInfo.predicate(forIdentifier: "assetsd")).count, 1)
  }

  func testNamePredicate() throws {
    try XCTAssertEqual(allCrashLogs.filtered(using: FBCrashLogInfo.predicate(forName: "assetsd_custom_set.crash")).count, 1)
  }

  func testJSONCrashLogFormat() throws {
    let info = try FBCrashLogInfo.fromCrashLog(atPath: TestFixtures.appCrashWithJSONFormat)

    XCTAssertEqual(info.processIdentifier, 82406)
    XCTAssertEqual(info.parentProcessIdentifier, 81861)
    XCTAssertEqual(info.identifier, "xctest3")
    XCTAssertEqual(info.processName, "xctest3")
    XCTAssertEqual(info.parentProcessName, "idb")
    XCTAssertEqual(info.executablePath, "/Applications/Xcode_13.3.0_fb.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest")
    XCTAssertEqual(info.date.timeIntervalSinceReferenceDate, 672154593, accuracy: 1)
    XCTAssertEqual(info.processType, .system)
  }

  private var allCrashLogs: NSArray {
    get throws {
      return try [
        FBCrashLogInfo.fromCrashLog(atPath: TestFixtures.assetsdCrashPathWithCustomDeviceSet),
        FBCrashLogInfo.fromCrashLog(atPath: TestFixtures.agentCrashPathWithCustomDeviceSet),
        FBCrashLogInfo.fromCrashLog(atPath: TestFixtures.appCrashPathWithDefaultDeviceSet),
        FBCrashLogInfo.fromCrashLog(atPath: TestFixtures.appCrashPathWithCustomDeviceSet),
      ]
    }
  }
}
