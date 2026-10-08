/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import IDBGRPCSwift

enum CrashLogQueryValueTransformer {

  static func predicate(from request: Idb_CrashLogQuery) -> CrashLogPredicate {
    var predicates: [CrashLogPredicate] = []
    if request.since != 0 {
      predicates.append(.newer(than: Date(timeIntervalSince1970: TimeInterval(request.since))))
    }
    if request.before != 0 {
      predicates.append(.older(than: Date(timeIntervalSince1970: TimeInterval(request.before))))
    }
    if !request.bundleID.isEmpty {
      predicates.append(.identifier(request.bundleID))
    }
    if !request.name.isEmpty {
      predicates.append(.name(request.name))
    }
    return .allOf(predicates)
  }
}
