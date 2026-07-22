import AppKit
@testable import FBSimulatorControl
import Foundation
import Testing

@Suite
struct FBSimulatorAccessibilitySerializerCompatibilityTests {
  @Test
  func xcode27PreservesTraitsKeyWithoutReadingUnsupportedAttribute() {
    let element = makeElement()
    element.stubTraits = ["Button"]

    let value = FBSimulatorAccessibilitySerializer.serializedTraits(
      for: element,
      xcodeVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
    )

    #expect(value is NSNull)
    #expect(!element.accessedProperties.contains("accessibilityTraits"))
  }

  @Test
  func xcode26ReadsAndReturnsTraits() {
    let element = makeElement()
    element.stubTraits = ["Button", "Selected"]

    let value = FBSimulatorAccessibilitySerializer.serializedTraits(
      for: element,
      xcodeVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0)
    )

    #expect(value as? [String] == ["Button", "Selected"])
    #expect(element.accessedProperties.contains("accessibilityTraits"))
  }

  private func makeElement() -> FBSimulatorControlTests_AXPMacPlatformElement_Double {
    FBAccessibilityTestElementBuilder.button(
      withLabel: "Continue",
      identifier: "continue",
      frame: NSRect(x: 20, y: 20, width: 100, height: 44)
    )
  }
}
