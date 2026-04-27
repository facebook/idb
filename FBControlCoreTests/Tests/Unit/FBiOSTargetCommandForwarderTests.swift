/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

private var fooConstructed: UInt = 0
private var foo1Called: UInt = 0
private var foo2Called: UInt = 0
private var barConstructed: UInt = 0
private var bar2Called: UInt = 0

@objc protocol FBiOSTargetCommandForwarder_Proto1: NSObjectProtocol {
  func doFoo()
}

@objc protocol FBiOSTargetCommandForwarder_Proto2: NSObjectProtocol {
  func doBar()
}

class FBiOSTargetCommandForwarder_Impl1: NSObject, FBiOSTargetCommand, FBiOSTargetCommandForwarder_Proto1 {
  required override init() {
    super.init()
  }

  func doFoo() {
    foo1Called += 1
  }

  class func commands(with target: FBiOSTarget) -> Self {
    fooConstructed += 1
    return self.init()
  }
}

class FBiOSTargetCommandForwarder_Impl2: NSObject, FBiOSTargetCommand, FBiOSTargetCommandForwarder_Proto1, FBiOSTargetCommandForwarder_Proto2 {
  required override init() {
    super.init()
  }

  func doFoo() {
    foo2Called += 1
  }

  func doBar() {
    bar2Called += 1
  }

  class func commands(with target: FBiOSTarget) -> Self {
    barConstructed += 1
    return self.init()
  }
}

final class FBiOSTargetCommandForwarderTests: XCTestCase {
  override func setUp() {
    fooConstructed = 0
    foo1Called = 0
    foo2Called = 0
    barConstructed = 0
    bar2Called = 0
  }

  class func commandResponders() -> [AnyClass] {
    return [FBiOSTargetCommandForwarder_Impl1.self, FBiOSTargetCommandForwarder_Impl2.self]
  }

  func testForwardsToFirstInArrayWithNoState() {
    let forwarder =
      FBiOSTargetCommandForwarder(
        target: FBiOSTargetDouble(),
        commandClasses: FBiOSTargetCommandForwarderTests.commandResponders(),
        statefulCommands: Set<AnyHashable>()
      ) as AnyObject

    let doFoo = NSSelectorFromString("doFoo")
    let doBar = NSSelectorFromString("doBar")
    forwarder.perform(doFoo)
    forwarder.perform(doFoo)
    forwarder.perform(doBar)

    XCTAssertEqual(foo1Called, 2)
    XCTAssertEqual(foo2Called, 0)
    XCTAssertEqual(bar2Called, 1)
    XCTAssertEqual(fooConstructed, 2)
    XCTAssertEqual(barConstructed, 1)
  }

  func testForwardsToFirstInArrayWithState() {
    let forwarder =
      FBiOSTargetCommandForwarder(
        target: FBiOSTargetDouble(),
        commandClasses: FBiOSTargetCommandForwarderTests.commandResponders(),
        statefulCommands: NSSet(array: FBiOSTargetCommandForwarderTests.commandResponders()) as! Set<AnyHashable>
      ) as AnyObject

    let doFoo = NSSelectorFromString("doFoo")
    let doBar = NSSelectorFromString("doBar")
    forwarder.perform(doFoo)
    forwarder.perform(doFoo)
    forwarder.perform(doBar)

    XCTAssertEqual(foo1Called, 2)
    XCTAssertEqual(foo2Called, 0)
    XCTAssertEqual(bar2Called, 1)
    XCTAssertEqual(fooConstructed, 1)
    XCTAssertEqual(barConstructed, 1)
  }
}
