/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

enum IDBFeature {
  case grpcEndpoint
}

protocol IDBKillswitch {
  func disabled(_ killswitch: IDBFeature) async -> Bool
}

extension IDBKillswitch {
  var objcBridged: IDBKillswitchBridge {
    .init(idbKillswitch: self)
  }
}

final class EmptyIDBKillswitch: IDBKillswitch {
  func disabled(_ killswitch: IDBFeature) async -> Bool { true }
}
