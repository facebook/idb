/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The same command is encoded as a CLI argument or a socket frame.
public enum BridgeCommand: Codable, Equatable, Sendable {
  public enum DNS: Codable, Equatable, Sendable {
    case list
    case set(servers: [String])
    case clear
  }

  public enum DynamicStore: Codable, Equatable, Sendable {
    case snapshot(key: String)
    case restore(key: String, snapshot: Data)
  }

  public enum Proxy: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case http, socks }
    case list
    case set(host: String, port: Int32, kind: Kind)
    case clear
  }

  public enum Notifications: Codable, Equatable, Sendable {
    case list(bundleID: String?)
    case approve(bundleID: String)
    case revoke(bundleID: String)
    case delivered(bundleID: String)
    case clearDelivered(bundleID: String)
  }

  public enum Health: Codable, Equatable, Sendable {
    case list(bundleID: String)
    case clear(bundleID: String)
    case approve(bundleID: String, typeIDs: [String])
    case revoke(bundleID: String, typeIDs: [String])
  }

  case clearContacts
  case clearPhotos
  case dns(DNS)
  case dynamicStore(DynamicStore)
  case proxy(Proxy)
  case notifications(Notifications)
  case health(Health)
  case accessibility([String: BridgeJSONValue])
  case ping
  case shutdown

  /// Only reads can be replayed after a connection failure with an uncertain outcome.
  public var mayRetry: Bool {
    switch self {
    case .clearContacts, .clearPhotos, .shutdown: false
    case let .dns(command):
      switch command {
      case .list: true
      case .set, .clear: false
      }
    case let .dynamicStore(command):
      switch command {
      case .snapshot: true
      case .restore: false
      }
    case let .proxy(command):
      switch command {
      case .list: true
      case .set, .clear: false
      }
    case let .notifications(command):
      switch command {
      case .list, .delivered: true
      case .approve, .revoke, .clearDelivered: false
      }
    case let .health(command):
      switch command {
      case .list: true
      case .clear, .approve, .revoke: false
      }
    case let .accessibility(parameters):
      // Asserting automation mode beside a read is idempotent, so the read stays replayable.
      if case let .string(verb) = parameters[BridgeAXWire.Request.verb.key] {
        [BridgeAXWire.Verb.displays, .describe, .hitTest, .settingsGet].contains { $0.rawValue == verb }
      } else {
        false
      }
    case .ping: true
    }
  }
}
