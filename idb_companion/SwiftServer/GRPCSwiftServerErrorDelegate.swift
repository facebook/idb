/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import Foundation
import GRPC
import NIOHPACK

final class GRPCSwiftServerErrorDelegate: ServerErrorDelegate {

  func transformRequestHandlerError(_ error: Error, headers: HPACKHeaders) -> GRPCStatusAndTrailers? {
    if error is GRPCStatus || error is GRPCStatusTransformable {
      // Use default error propagation transformation
      return nil
    }

    var message = error.localizedDescription
    if type(of: error) == NSError.self {
      // Legacy NSError from objc, we should unwrap it for more expressive error handling.
      // Don't use `is NSError` check because all swift errors bridges to NSError successfully and this check passed

      message = extractMessage(fromLegacyNSError: error as NSError)
    }
    return GRPCStatusAndTrailers(status: GRPCStatus(code: .internalError, message: message))
  }

  private func extractMessage(fromLegacyNSError error: NSError) -> String {
    var userInfo = error.userInfo

    var message: String
    if let localizedDescription = userInfo.removeValue(forKey: NSLocalizedDescriptionKey) as? String {
      message = localizedDescription
    } else {
      message = error.description
    }
    if !userInfo.isEmpty {
      message += "\nInfo: \(userInfo)"
    }
    return message
  }
}
