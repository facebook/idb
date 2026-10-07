/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol

// The requests are defined in FBSimulatorBridgeProtocol, which the guest decodes them with; the host
// keeps its own names for them, the way `AXWire` names `BridgeAXWire`.
public typealias AXBridgeFrontmostMethod = BridgeAXFrontmostMethod
package typealias AXBridgeWriteAssertion = BridgeAXWriteAssertion
package typealias AXBridgeWriteRequest = BridgeAXWriteRequest
package typealias AXBridgeReadRequest = BridgeAXReadOptions
package typealias AXBridgeRequest = BridgeAXRequest
