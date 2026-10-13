/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation
import XCTest

final class BridgeAXTranslatorAttributeTests: XCTestCase {
  func testTheNumberingCoversTheTranslatorsBoundExceptItsTwoUnprefixedNames() {
    // 59 and 62 are `AXPUserTestingMarzipanSmuggledValues` and `AXPImageData`, which the framework names
    // without the `AXPAttribute` prefix.
    XCTAssertEqual(
      BridgeAXTranslatorAttribute.allCases.map(\.rawValue), Array(0...129).filter { $0 != 59 && $0 != 62 })
  }

  func testTheAttributesBothReadersFetchKeepTheirNumbers() {
    let numbers: [BridgeAXTranslatorAttribute: Int] = [
      .children: 8, .customActions: 13, .frame: 21, .help: 23, .identifier: 25, .isEnabled: 27,
      .isFocused: 28, .isVisible: 32, .label: 33, .placeholderValue: 42, .role: 45, .roleDescription: 46,
      .subrole: 51, .value: 53, .isRemoteElement: 66, .traits: 77, .visiblePoint: 112, .expanded: 119,
      .memoryAddress: 128,
    ]
    for (attribute, number) in numbers {
      XCTAssertEqual(attribute.rawValue, number, "\(attribute)")
    }
  }

  func testAMultipleAttributeRequestIsTypeFiveAndCarriesItsListUnderAttributes() {
    XCTAssertEqual(BridgeAXTranslatorRequestType.multipleAttribute.rawValue, 5)
    XCTAssertEqual(BridgeAXTranslatorRequestType.attributesParameterKey, "attributes")
  }

  func testRolesAndSubrolesAreNamedAsAppKitSpellsThem() {
    XCTAssertEqual(BridgeAXTranslatorRole.allCases.map(\.rawValue), Array(1...21))
    XCTAssertEqual(BridgeAXTranslatorRole(rawValue: 2)?.name, "Button")
    XCTAssertEqual(BridgeAXTranslatorRole(rawValue: 4)?.name, "GenericElement")
    XCTAssertEqual(BridgeAXTranslatorRole(rawValue: 16)?.name, "WebArea")
    XCTAssertNil(BridgeAXTranslatorRole(rawValue: 0))
    XCTAssertEqual(BridgeAXTranslatorSubrole.allCases.map(\.rawValue), Array(1...6))
    XCTAssertEqual(BridgeAXTranslatorSubrole(rawValue: 3)?.name, "Switch")
    XCTAssertNil(BridgeAXTranslatorSubrole(rawValue: 7))
  }
}
