/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// Parses the response envelope shared by every axbridge verb and preserves the guest's typed failure.
enum AXBridgeResponse {
  static func validated(
    _ data: Data,
    context: String,
    pid: pid_t? = nil,
    frontmostMethod: FBAXBridgeFrontmostMethod? = nil
  ) throws -> [String: Any] {
    guard let object = try? JSONSerialization.jsonObject(with: data), let response = object as? [String: Any] else {
      throw AXBridgeError.guestFailure("\(context): unparseable guest response")
    }
    guard (response[AXWire.Envelope.ok.rawValue] as? Bool) == true else {
      throw failure(from: response, pid: pid, frontmostMethod: frontmostMethod)
    }
    return response
  }

  private static func failure(
    from response: [String: Any],
    pid: pid_t?,
    frontmostMethod: FBAXBridgeFrontmostMethod?
  ) -> AXBridgeError {
    let message = (response[AXWire.Envelope.error.rawValue] as? String) ?? "the guest reported a failure with no message"
    let reportedPid = (response[AXWire.Envelope.pid.rawValue] as? Int).flatMap(pid_t.init(exactly:)) ?? pid
    let rawKind = response[AXWire.Envelope.errorKind.rawValue] as? String
    switch rawKind.flatMap(AXWire.ErrorKind.init(rawValue:)) {
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
    case .badRequest, .none:
      guard let pid else {
        return .guestFailure(message)
      }
      return .guestFailure("pid \(pid): \(message)")
    }
  }
}

struct AXDeviceSettingResponse {
  let enabled: Bool

  init(data: Data) throws {
    let response = try AXBridgeResponse.validated(data, context: "device setting")
    guard let enabled = response[AXWire.Envelope.enabled.rawValue] as? Bool else {
      throw AXBridgeError.guestFailure("device setting response without an enabled value")
    }
    self.enabled = enabled
  }
}
