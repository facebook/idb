/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Synchronization

final class FBSimulatorHIDSessionCache<Session: Sendable>: Sendable {
  private struct Record: Sendable {
    let identity: FBSimulatorHIDBootIdentity
    let session: Session
  }

  private let record = Mutex<Record?>(nil)
  private let disconnect: @Sendable (Session) -> Void

  init(disconnect: @escaping @Sendable (Session) -> Void) {
    self.disconnect = disconnect
  }

  func session(
    for identity: FBSimulatorHIDBootIdentity,
    create: () throws -> Session,
    currentIdentity: () throws -> FBSimulatorHIDBootIdentity
  ) throws -> Session {
    try record.withLock { record in
      let validatedIdentity = try currentIdentity()
      guard validatedIdentity == identity else {
        if let record {
          disconnect(record.session)
        }
        record = nil
        throw FBSimulatorHIDSessionCacheError.bootChangedDuringConnection
      }
      if let record, record.identity == identity {
        return record.session
      }
      if let record {
        disconnect(record.session)
      }
      record = nil

      let session = try create()
      let resolvedIdentity: FBSimulatorHIDBootIdentity
      do {
        resolvedIdentity = try currentIdentity()
      } catch {
        disconnect(session)
        throw error
      }
      guard resolvedIdentity == identity else {
        disconnect(session)
        throw FBSimulatorHIDSessionCacheError.bootChangedDuringConnection
      }
      record = Record(identity: identity, session: session)
      return session
    }
  }

  func invalidate() {
    record.withLock { record in
      if let record {
        disconnect(record.session)
      }
      record = nil
    }
  }

  var cachedIdentity: FBSimulatorHIDBootIdentity? {
    record.withLock { $0?.identity }
  }

  func invalidate(ifMatching identity: FBSimulatorHIDBootIdentity) {
    record.withLock { record in
      guard record?.identity == identity else {
        return
      }
      if let record {
        disconnect(record.session)
      }
      record = nil
    }
  }
}

enum FBSimulatorHIDSessionCacheError: Error, Equatable {
  case bootChangedDuringConnection
}
