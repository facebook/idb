/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import FBSimulatorBridgeProtocol
import Foundation

/// Decodes the answer every axbridge verb sends, a `BridgeAXOutcome`, and preserves the guest's typed failure.
package enum AXBridgeResponse {
  /// The verb's answer, decoded as `Success`; a failure is raised as the error its kind names.
  package static func decode<Success: Codable & Equatable & Sendable>(
    _ data: Data,
    as _: Success.Type,
    context: String,
    pid: pid_t? = nil,
    frontmostMethod: AXBridgeFrontmostMethod? = nil
  ) throws -> Success {
    switch try outcome(data, as: Success.self, context: context) {
    case let .success(success):
      return success
    case let .failure(failure):
      throw self.failure(from: failure, pid: pid, frontmostMethod: frontmostMethod)
    }
  }

  /// The answer as it came, a failure included, for a caller that treats some failures as values.
  package static func outcome<Success: Codable & Equatable & Sendable>(
    _ data: Data, as _: Success.Type, context: String
  ) throws -> BridgeAXOutcome<Success> {
    do {
      return try JSONDecoder().decode(BridgeAXOutcome<Success>.self, from: data)
    } catch {
      throw AXBridgeError.guestFailure("\(context): unparseable guest response (\(error))")
    }
  }

  package static func failure(
    from failure: BridgeAXFailure,
    pid: pid_t?,
    frontmostMethod: AXBridgeFrontmostMethod?
  ) -> AXBridgeError {
    let message = failure.message ?? "the guest reported a failure with no message"
    let reportedPid = failure.pid ?? pid
    switch failure.kind {
    case .applicationUnavailable:
      return .applicationUnavailable(pid: reportedPid)
    case .applicationNotResponding:
      return .applicationNotResponding(pid: reportedPid)
    case .readerUnavailable:
      return .readerUnavailable(message)
    case .frontmostUnresolved:
      guard let frontmostMethod else {
        return .guestFailure(message)
      }
      return .frontmostUnresolved(method: frontmostMethod, reason: message)
    case .assertionFailed:
      return .assertionFailed(message)
    case .badRequest, .runtimeFailed, .capabilityUnavailable, .none:
      guard let pid else {
        return .guestFailure(message)
      }
      return .guestFailure("pid \(pid): \(message)")
    }
  }
}

package struct AXDeviceSettingResponse {
  package let enabled: Bool

  package init(data: Data) throws {
    enabled = try AXBridgeResponse.decode(data, as: BridgeAXSettingResponse.self, context: "device setting").enabled
  }
}
