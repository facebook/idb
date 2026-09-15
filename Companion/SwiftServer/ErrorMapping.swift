/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPCCore

/// Turns errors a handler throws into the status the client sees.
///
/// gRPC Swift 2 maps every thrown error that is not an `RPCError` to a bare `unknown` status
/// with no message, which would discard the `NSError` descriptions the Objective-C frameworks
/// produce. This keeps `RPCError`s as thrown and gives everything else an `internalError`
/// carrying the error's description, unwrapping legacy `NSError` `userInfo` for detail.
enum ErrorMapping {

  static func rpcError(from error: any Error) -> RPCError {
    if let rpcError = error as? RPCError {
      return rpcError
    }

    var message = error.localizedDescription
    if type(of: error) == NSError.self {
      // Legacy NSError from objc, we should unwrap it for more expressive error handling.
      // Don't use `is NSError` check because all swift errors bridges to NSError successfully and this check passed
      message = extractMessage(fromLegacyNSError: error as NSError)
    }
    return RPCError(code: .internalError, message: message)
  }

  private static func extractMessage(fromLegacyNSError error: NSError) -> String {
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
