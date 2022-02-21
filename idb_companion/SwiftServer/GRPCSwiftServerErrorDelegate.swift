/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPC
import NIOHPACK

final class GRPCSwiftServerErrorDelegate: ServerErrorDelegate {

  func transformRequestHandlerError(_ error: Error, headers: HPACKHeaders) -> GRPCStatusAndTrailers? {
    if error is GRPCStatus || error is GRPCStatusTransformable {
      // Use default error propagation transformation
      return nil
    }
    return GRPCStatusAndTrailers(status: GRPCStatus(code: .internalError, message: error.localizedDescription))
  }

}
