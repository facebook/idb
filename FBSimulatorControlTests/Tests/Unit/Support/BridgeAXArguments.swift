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

/// The accessibility action a request is sent as, as JSON text with sorted keys, read back from the arguments a
/// one-shot guest is spawned with.
func wireAction(_ request: AXBridgeRequest) throws -> String {
  let arguments = try request.arguments
  XCTAssertEqual(arguments.count, 2)
  XCTAssertEqual(arguments.first, "rpc")
  let frame = Data(arguments[1].utf8)
  XCTAssertEqual(try BridgeRequest.decode(frame).command, .accessibility(request))
  let object = try XCTUnwrap(JSONSerialization.jsonObject(with: frame) as? [String: Any])
  let command = try XCTUnwrap(object["command"] as? [String: Any])
  let accessibility = try XCTUnwrap(command["accessibility"] as? [String: Any])
  let action = try XCTUnwrap(accessibility["action"])
  return String(decoding: try JSONSerialization.data(withJSONObject: action, options: .sortedKeys), as: UTF8.self)
}
