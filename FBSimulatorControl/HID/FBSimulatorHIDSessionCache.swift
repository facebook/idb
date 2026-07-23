/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Synchronization

final class FBSimulatorHIDSessionCache<Session: Sendable>: Sendable {
  private struct State: Sendable {
    var nextGeneration: UInt = 0
    var record: Record?
  }

  private struct Record: Sendable {
    let generation: UInt
    let identity: FBSimulatorHIDBootIdentity
    let session: Session
  }

  private let state = Mutex(State())
  private let disconnect: @Sendable (Session) -> Void

  init(disconnect: @escaping @Sendable (Session) -> Void) {
    self.disconnect = disconnect
  }

  func session(
    for identity: FBSimulatorHIDBootIdentity,
    create: (_ invalidate: @escaping @Sendable () -> Void) throws -> Session,
    currentIdentity: () throws -> FBSimulatorHIDBootIdentity
  ) throws -> Session {
    try state.withLock { state in
      let validatedIdentity = try currentIdentity()
      guard validatedIdentity == identity else {
        if let record = state.record {
          disconnect(record.session)
        }
        state.record = nil
        throw FBSimulatorHIDSessionCacheError.bootChangedDuringConnection
      }
      if let record = state.record, record.identity == identity {
        return record.session
      }
      if let record = state.record {
        disconnect(record.session)
      }
      state.record = nil

      state.nextGeneration &+= 1
      let generation = state.nextGeneration
      let session = try create { [weak self] in
        self?.invalidate(generation: generation)
      }
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
      state.record = Record(generation: generation, identity: identity, session: session)
      return session
    }
  }

  func invalidate() {
    state.withLock { state in
      if let record = state.record {
        disconnect(record.session)
      }
      state.record = nil
    }
  }

  var cachedIdentity: FBSimulatorHIDBootIdentity? {
    state.withLock { $0.record?.identity }
  }

  func invalidate(ifMatching identity: FBSimulatorHIDBootIdentity) {
    state.withLock { state in
      guard state.record?.identity == identity else {
        return
      }
      if let record = state.record {
        disconnect(record.session)
      }
      state.record = nil
    }
  }

  private func invalidate(generation: UInt) {
    state.withLock { state in
      guard state.record?.generation == generation else {
        return
      }
      if let record = state.record {
        disconnect(record.session)
      }
      state.record = nil
    }
  }
}

enum FBSimulatorHIDSessionCacheError: Error, Equatable {
  case bootChangedDuringConnection
}
