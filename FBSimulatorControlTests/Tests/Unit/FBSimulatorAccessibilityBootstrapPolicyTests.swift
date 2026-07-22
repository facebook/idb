import Foundation
@testable import FBSimulatorControl
import Testing

@Suite
struct FBSimulatorAccessibilityBootstrapPolicyTests {
  @Test
  func testIOS26RuntimeDoesNotRequireBootstrap() {
    let version = OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 0)

    #expect(!FBSimulatorAccessibilityCommands.requiresAccessibilityBootstrap(for: version))
  }

  @Test
  func testIOS27RuntimeRequiresBootstrap() {
    let version = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)

    #expect(FBSimulatorAccessibilityCommands.requiresAccessibilityBootstrap(for: version))
  }

  @Test
  func testFutureRuntimeRequiresBootstrap() {
    let version = OperatingSystemVersion(majorVersion: 28, minorVersion: 0, patchVersion: 0)

    #expect(FBSimulatorAccessibilityCommands.requiresAccessibilityBootstrap(for: version))
  }
}
