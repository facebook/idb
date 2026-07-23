@testable import FBSimulatorControl
import Foundation
import Testing

@objcMembers
private final class AccessibilityRequestClientTypeDouble: NSObject {
  var clientType: Int = 0
}

@Suite
struct FBAXRuntimeBridgeClientTypeTests {
  @Test
  func setsXCTestClientTypeThroughRuntimeBoundary() {
    let request = AccessibilityRequestClientTypeDouble()

    let supported = FBAXRuntimeBridge.setClientType(2, onRequest: request)

    #expect(supported)
    #expect(request.clientType == 2)
  }

  @Test
  func unsupportedRequestRemainsSafe() {
    let request = NSObject()

    let supported = FBAXRuntimeBridge.setClientType(2, onRequest: request)

    #expect(!supported)
  }
}
