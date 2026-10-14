/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation
import Testing

@Suite
struct BridgeAXTranslatorAttributeTests {

  @Test
  func theNumberingCoversTheTranslatorsBoundExceptItsTwoUnprefixedNames() {
    // 59 and 62 are `AXPUserTestingMarzipanSmuggledValues` and `AXPImageData`, which the framework names
    // without the `AXPAttribute` prefix.
    #expect(BridgeAXTranslatorAttribute.allCases.map(\.rawValue) == Array(0...129).filter { $0 != 59 && $0 != 62 })
  }

  @Test
  func theAttributesBothReadersFetchKeepTheirNumbers() {
    let numbers: [BridgeAXTranslatorAttribute: Int] = [
      .children: 8, .customActions: 13, .frame: 21, .help: 23, .identifier: 25, .isEnabled: 27,
      .isFocused: 28, .isVisible: 32, .label: 33, .placeholderValue: 42, .role: 45, .roleDescription: 46,
      .subrole: 51, .value: 53, .isRemoteElement: 66, .traits: 77, .visiblePoint: 112, .expanded: 119,
      .memoryAddress: 128,
    ]
    for (attribute, number) in numbers {
      #expect(attribute.rawValue == number, "\(attribute)")
    }
  }

  @Test
  func aMultipleAttributeRequestIsTypeFiveAndCarriesItsListUnderAttributes() {
    #expect(BridgeAXTranslatorRequestType.multipleAttribute.rawValue == 5)
    #expect(BridgeAXTranslatorRequestType.attributesParameterKey == "attributes")
  }

  @Test
  func rolesAndSubrolesAreNamedAsAppKitSpellsThem() {
    #expect(BridgeAXTranslatorRole.allCases.map(\.rawValue) == Array(1...21))
    #expect(BridgeAXTranslatorRole(rawValue: 2)?.name == "Button")
    #expect(BridgeAXTranslatorRole(rawValue: 4)?.name == "GenericElement")
    #expect(BridgeAXTranslatorRole(rawValue: 16)?.name == "WebArea")
    #expect(BridgeAXTranslatorRole(rawValue: 0) == nil)
    #expect(BridgeAXTranslatorSubrole.allCases.map(\.rawValue) == Array(1...6))
    #expect(BridgeAXTranslatorSubrole(rawValue: 3)?.name == "Switch")
    #expect(BridgeAXTranslatorSubrole(rawValue: 7) == nil)
  }
}
