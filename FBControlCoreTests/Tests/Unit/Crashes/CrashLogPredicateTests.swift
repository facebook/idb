/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct CrashLogPredicateTests {

  private let crashLog: CrashLogInfo
  private let crashDate: Date

  init() throws {
    crashLog = try CrashLogInfo.fromCrashLog(atPath: TestFixtures.assetsdCrashPathWithCustomDeviceSet)
    crashDate = crashLog.date
  }

  @Test
  func fieldPredicatesMatchOnlyTheirValue() {
    #expect(CrashLogPredicate.processIdentifier(39942).matches(crashLog))
    #expect(!CrashLogPredicate.processIdentifier(1).matches(crashLog))
    #expect(CrashLogPredicate.identifier("assetsd").matches(crashLog))
    #expect(!CrashLogPredicate.identifier("other").matches(crashLog))
    #expect(CrashLogPredicate.executablePathContains("AssetsLibrary.framework").matches(crashLog))
    #expect(!CrashLogPredicate.executablePathContains("Nope.framework").matches(crashLog))
  }

  @Test
  func newerAndOlderSplitAroundTheCrashDate() {
    let before = crashDate.addingTimeInterval(-60)
    let after = crashDate.addingTimeInterval(60)
    #expect(CrashLogPredicate.newer(than: before).matches(crashLog))
    #expect(!CrashLogPredicate.newer(than: after).matches(crashLog))
    #expect(CrashLogPredicate.older(than: after).matches(crashLog))
    #expect(!CrashLogPredicate.older(than: before).matches(crashLog))
  }

  @Test
  func compositionRequiresEveryPredicate() {
    let identifier = CrashLogPredicate.identifier("assetsd")
    #expect((identifier && .processIdentifier(39942)).matches(crashLog))
    #expect(!(identifier && .processIdentifier(1)).matches(crashLog))
    #expect(!(!identifier).matches(crashLog))
    #expect(CrashLogPredicate.allOf([]).matches(crashLog))
    #expect(!CrashLogPredicate.none.matches(crashLog))
    #expect((identifier && .processIdentifier(1)).description == "(identifier == assetsd && processIdentifier == 1)")
  }
}
