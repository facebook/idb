/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A TLS identity: a PEM holding the certificate chain and a PEM holding the
/// private key. These are usually the same combined PEM file, but may be two
/// separate files (e.g. when sourced from distinct environment-variable paths).
public struct CompanionTLSIdentity: Sendable, Equatable {
  public let certificateChainPath: String
  public let privateKeyPath: String

  public init(certificateChainPath: String, privateKeyPath: String) {
    self.certificateChainPath = certificateChainPath
    self.privateKeyPath = privateKeyPath
  }

  /// Convenience for the common case where one PEM holds both the chain and key.
  public init(combinedPEMPath path: String) {
    self.init(certificateChainPath: path, privateKeyPath: path)
  }
}

/// Supplies the local TLS identities used for companion TCP connections.
///
/// A provider may be registered via `CompanionTLS.provider` at startup. When none
/// is registered, companion TCP connections fall back to plaintext.
public protocol CompanionTLSProvider: Sendable {
  /// The identity the client presents when connecting to a companion, or nil.
  func clientIdentity() -> CompanionTLSIdentity?
  /// The identity the server presents to connecting clients, or nil.
  func serverIdentity() -> CompanionTLSIdentity?
}

/// The process-wide TLS identity provider.
///
/// Set once at startup, before any connection is made or accepted, if a provider is
/// available; left nil otherwise, in which case companion TCP falls back to
/// plaintext.
public enum CompanionTLS {
  /// Lock-guarded box for the provider. A `static let` of an `@unchecked Sendable`
  /// type keeps this global concurrency-safe without an unsafe opt-out attribute.
  private final class Storage: @unchecked Sendable {
    let lock = NSLock()
    var provider: (any CompanionTLSProvider)?
  }
  private static let storage = Storage()

  public static var provider: (any CompanionTLSProvider)? {
    get {
      storage.lock.lock()
      defer { storage.lock.unlock() }
      return storage.provider
    }
    set {
      storage.lock.lock()
      defer { storage.lock.unlock() }
      storage.provider = newValue
    }
  }
}

/// How a companion server sources its TLS identity for a TCP listen.
public enum CompanionServerTLS: Sendable, Equatable {
  /// Plaintext — no TLS.
  case disabled
  /// TLS using the certificate+key PEM at this path.
  case certificate(path: String)
  /// TLS using the server identity from the registered `CompanionTLS.provider`;
  /// plaintext when no provider is registered.
  case metaIdentity
}

/// How a companion client sources its TLS identity for a TCP connection.
public enum CompanionClientTLS: Sendable, Equatable {
  /// Plaintext — no TLS.
  case disabled
  /// TLS presenting the client identity from the registered `CompanionTLS.provider`;
  /// plaintext when no provider is registered.
  case metaIdentity
}
