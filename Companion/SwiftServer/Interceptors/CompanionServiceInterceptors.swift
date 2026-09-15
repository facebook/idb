/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPCCore

/// The interceptors applied to every companion RPC, outermost first.
enum CompanionServiceInterceptors {
  static func make(logger: IDBLogger) -> [any ServerInterceptor] {
    [
      LoggingInterceptor(logger: logger)
    ]
  }
}
