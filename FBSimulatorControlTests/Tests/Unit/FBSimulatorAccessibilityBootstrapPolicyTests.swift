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

  @Test
  func testUnparseableRuntimeVersionRequiresBootstrapOnXcode27Host() {
    // Version parsing fails open to 0.0.0; on an Xcode 27+ host this is most
    // likely a cryptex runtime with degraded metadata, so require the bootstrap.
    let unknown = OperatingSystemVersion(majorVersion: 0, minorVersion: 0, patchVersion: 0)
    let host = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)

    #expect(FBSimulatorAccessibilityCommands.requiresAccessibilityBootstrap(for: unknown, hostXcodeVersion: host))
  }

  @Test
  func testUnparseableRuntimeVersionDoesNotRequireBootstrapOnOlderHost() {
    let unknown = OperatingSystemVersion(majorVersion: 0, minorVersion: 0, patchVersion: 0)
    let host = OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 0)

    #expect(!FBSimulatorAccessibilityCommands.requiresAccessibilityBootstrap(for: unknown, hostXcodeVersion: host))
  }
}
