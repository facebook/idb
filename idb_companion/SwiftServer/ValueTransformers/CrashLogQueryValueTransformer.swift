/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import IDBGRPCSwift

enum CrashLogQueryValueTransformer {

  static func predicate(from request: Idb_CrashLogQuery) -> NSPredicate {
    var subpredicates: [NSPredicate] = []
    if request.since != 0 {
      subpredicates.append(FBCrashLogInfo.predicateNewerThanDate(Date(timeIntervalSince1970: TimeInterval(request.since))))
    }
    if request.before != 0 {
      subpredicates.append(FBCrashLogInfo.predicateOlderThanDate(Date(timeIntervalSince1970: TimeInterval(request.before))))
    }
    if !request.bundleID.isEmpty {
      subpredicates.append(FBCrashLogInfo.predicate(forIdentifier: request.bundleID))
    }
    if !request.name.isEmpty {
      subpredicates.append(FBCrashLogInfo.predicate(forName: request.name))
    }
    if subpredicates.isEmpty {
      return NSPredicate(value: true)
    }
    return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
  }
}
