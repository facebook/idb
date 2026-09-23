/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XPC

/// Builders for the replies and events the tests hand to the protocol parsers. Production code
/// encodes with `XPCEncoder`; these exist so a test can shape a reply the provider would never send.
extension SimulatorCoreDevice {
  static func dictionary(_ values: [String: xpc_object_t]) -> xpc_object_t {
    let result = xpc_dictionary_create(nil, nil, 0)
    for (key, value) in values { xpc_dictionary_set_value(result, key, value) }
    return result
  }

  static func array(_ values: [xpc_object_t]) -> xpc_object_t {
    let result = xpc_array_create(nil, 0)
    for value in values { xpc_array_append_value(result, value) }
    return result
  }
}
