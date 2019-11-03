/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
@testable import FBSimulatorControlKit
import XCTest

/**
 * FakeDesc
 *
 * Fake, probe-able ParserDescription
 */
struct FakeDesc: ParserDescription {
  public let summary: String
  public let isDelimited: Bool
  public let children: [ParserDescription]
  public let isNormalised: Bool

  init(summary: String,
       isDelimited: Bool,
       children: [ParserDescription],
       isNormalised: Bool) {
    self.summary = summary
    self.isDelimited = isDelimited
    self.children = children
    self.isNormalised = isNormalised
  }

  init(_ n: Int, WithChildren children: [ParserDescription]) {
    self.init(summary: "fake-desc-" + String(n),
              isDelimited: false,
              children: children,
              isNormalised: false)
  }

  init(_ n: Int) {
    self.init(n, WithChildren: [])
  }

  public var normalised: ParserDescription {
    return FakeDesc(summary: summary,
                    isDelimited: isDelimited,
                    children: children.map { $0.normalised },
                    isNormalised: true)
  }
}

/**
 * AssertCast<U, T>(_ obj: U, _ tests: (T) -> Void)
 *
 * Check whether `obj : U` can be dynamically cast to a value of type `T`, and
 * if it can, pass it on to a continuation for potential further testing.
 */
func AssertCast<U, T>(_ obj: U, _ tests: (T) -> Void) {
  switch obj {
  case let casted as T:
    tests(casted)
  default:
    XCTFail("AssertCast: Could not dynamically cast value")
  }
}

/**
 * AssertEqualDesc(_ lhs: ParserDescription, _ rhs: ParserDescription)
 *
 * Check whether the descriptions `lhs` and `rhs` are observationally
 * equivalent.
 */
func AssertEqualDesc(_ lhs: ParserDescription, _ rhs: ParserDescription) {
  XCTAssertEqual(lhs.summary, rhs.summary)
  XCTAssertEqual(lhs.delimitedSummary, rhs.delimitedSummary)
  XCTAssertEqual(lhs.isDelimited, rhs.isDelimited)
  XCTAssertEqual(lhs.description, rhs.description)

  let lcs = lhs.children
  let rcs = rhs.children

  XCTAssertEqual(lcs.count, rcs.count)
  for (l, r) in zip(lcs, rcs) {
    AssertEqualDesc(l, r)
  }
}

class NormalisationTests: XCTestCase {
  func testPrimitive() {
    let prim = PrimitiveDesc(name: "name", desc: "desc")
    AssertEqualDesc(prim, prim.normalised)
  }

  func testFlag() {
    let flag = FlagDesc(name: "name", desc: "desc")
    AssertEqualDesc(flag, flag.normalised)
  }

  func testCmd() {
    let cmd = CmdDesc(cmd: "cmd")
    AssertEqualDesc(cmd, cmd.normalised)
  }

  func testSection() {
    let sect = SectionDesc(tag: "tag", name: "name", desc: "desc",
                           child: FakeDesc(1))
    let norm = sect.normalised
    AssertEqualDesc(sect, norm)
    AssertCast(norm) { (norm: SectionDesc) in
      AssertCast(norm.child) { (child: FakeDesc) in
        XCTAssertTrue(child.isNormalised)
      }
    }
  }

  func testAtleast() {
    let atleast = AtleastDesc(lowerBound: 1,
                              child: FakeDesc(1))
    let norm = atleast.normalised
    AssertEqualDesc(atleast, norm)
    AssertCast(norm) { (norm: AtleastDesc) in
      AssertCast(norm.child) { (child: FakeDesc) in
        XCTAssertTrue(child.isNormalised)
      }
    }
  }

  func testOptional() {
    let opt = OptionalDesc(child: FakeDesc(1))
    AssertEqualDesc(opt, opt.normalised)
  }

  func testOptionalNonEmptyFlattening() {
    let nonEmpty = AtleastDesc(lowerBound: 1,
                               child: FakeDesc(1),
                               sep: FakeDesc(2))
    let opt = OptionalDesc(child: nonEmpty)

    let expected = AtleastDesc(lowerBound: 0,
                               child: nonEmpty.child,
                               sep: nonEmpty.sep)

    AssertEqualDesc(opt.normalised, expected)
  }

  func testOptionalAtleastPreserve() {
    let atleast = AtleastDesc(lowerBound: 2,
                              child: FakeDesc(1),
                              sep: FakeDesc(2))
    let opt = OptionalDesc(child: atleast)

    AssertEqualDesc(opt, opt.normalised)
  }

  func testSequenceDiscarding() {
    let fake = FakeDesc(1)
    let seq = SequenceDesc(children: [fake])
    let norm = seq.normalised

    AssertEqualDesc(fake, norm)
    AssertCast(norm) { (actual: FakeDesc) in
      XCTAssertTrue(actual.isNormalised)
    }
  }

  func testSequenceFlattening() {
    let seq = SequenceDesc(children: [
      FakeDesc(1),
      FakeDesc(2),
      SequenceDesc(children: [
        FakeDesc(3),
        SequenceDesc(children: [
          FakeDesc(4),
        ]),
      ]),
      FakeDesc(5, WithChildren: [
        SequenceDesc(children: [
          FakeDesc(6),
        ]),
        FakeDesc(7),
      ]),
    ])

    let expected = SequenceDesc(children: [
      FakeDesc(1),
      FakeDesc(2),
      FakeDesc(3),
      FakeDesc(4),
      FakeDesc(5, WithChildren: [
        FakeDesc(6),
        FakeDesc(7),
      ]),
    ])

    AssertEqualDesc(expected, seq.normalised)
  }

  func testSequenceEmpty() {
    let seq = SequenceDesc(children: [])
    AssertEqualDesc(seq, seq.normalised)
  }

  func testChoiceDiscarding() {
    let fake = FakeDesc(1)
    let choices = ChoiceDesc(children: [fake])
    let norm = choices.normalised

    AssertEqualDesc(fake, norm)
    AssertCast(norm) { (actual: FakeDesc) in
      XCTAssertTrue(actual.isNormalised)
    }
  }

  func testChoiceFlattening() {
    let choices = ChoiceDesc(children: [
      FakeDesc(1),
      FakeDesc(2),
      ChoiceDesc(children: [
        FakeDesc(3),
        ChoiceDesc(children: [
          FakeDesc(4),
        ]),
      ]),
      FakeDesc(5, WithChildren: [
        ChoiceDesc(children: [
          FakeDesc(6),
        ]),
        FakeDesc(7),
      ]),
    ])

    let expected = ChoiceDesc(children: [
      FakeDesc(1),
      FakeDesc(2),
      FakeDesc(3),
      FakeDesc(4),
      FakeDesc(5, WithChildren: [
        FakeDesc(6),
        FakeDesc(7),
      ]),
    ])

    AssertEqualDesc(expected, choices.normalised)
  }

  func testChoiceEmpty() {
    let choice = ChoiceDesc(children: [])
    AssertEqualDesc(choice, choice.normalised)
  }

  func testPreservesExpandednessOfChoice() {
    let choice = ChoiceDesc(children: [FakeDesc(1), FakeDesc(2)]).expanded
    AssertEqualDesc(choice, choice.normalised)
  }
}

class DelimitedSummaryTest: XCTestCase {
  func testNotDelimited() {
    let fake = FakeDesc(summary: "summary",
                        isDelimited: false,
                        children: [],
                        isNormalised: false)

    XCTAssertEqual("{{ summary }}", fake.delimitedSummary)
  }

  func testDelimited() {
    let fake = FakeDesc(summary: "summary",
                        isDelimited: true,
                        children: [],
                        isNormalised: false)
    XCTAssertEqual("summary", fake.delimitedSummary)
  }
}

class FindAllTests: XCTestCase {
  func testSingleton() {
    let fake = FakeDesc(1)
    var fakes = [FakeDesc]()
    fake.findAll(&fakes)

    XCTAssertEqual(0, fakes.count)
  }

  func testNested() {
    let fake4 = FakeDesc(4)
    let fake3 = FakeDesc(3, WithChildren: [fake4])
    let fake2 = FakeDesc(2)
    let fake1 = FakeDesc(1, WithChildren: [fake2, fake3])

    let expectedFakes = [fake2, fake3, fake4]
    var actualFakes = [FakeDesc]()
    fake1.findAll(&actualFakes)

    XCTAssertEqual(expectedFakes.count, actualFakes.count)
    for fake in expectedFakes {
      XCTAssert(actualFakes.contains { $0.summary == fake.summary })
    }
  }

  func testHiddenBySect() {
    let fake2 = FakeDesc(2)
    let fake1 = FakeDesc(1, WithChildren: [
      fake2,
      SectionDesc(tag: "tag", name: "name", desc: "desc", child: FakeDesc(3)),
    ])

    var actualFakes = [FakeDesc]()
    fake1.findAll(&actualFakes)
    XCTAssertEqual(1, actualFakes.count)
    AssertEqualDesc(fake2, actualFakes.first!)
  }
}
