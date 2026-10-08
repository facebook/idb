/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
@testable import FBSimulatorControl
import Foundation
import XCTest

/// The parameters an accessibility request carries on the wire, read back from the arguments a
/// one-shot guest is spawned with.
func decodedBridgeAXArguments(_ request: AXBridgeRequest) throws -> [String: Any] {
  let arguments = try request.arguments
  XCTAssertEqual(arguments.count, 2)
  XCTAssertEqual(arguments.first, "rpc")
  let frame = Data(arguments[1].utf8)
  XCTAssertEqual(try BridgeRequest.decode(frame).command, .accessibility(request))
  return try XCTUnwrap(BridgeRequest.accessibilityParameters(of: frame)).mapValues(\.foundationValue)
}
