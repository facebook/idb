/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// One answer from a service other than accessibility. A command can answer with several, such as one per section
/// or per delivered notification, and the host reports each as a line of JSON.
@frozen public enum BridgeServiceAnswer: Codable, Equatable, Sendable {
  case notificationSettings(BridgeNotificationSettings)
  case deliveredNotification(BridgeDeliveredNotification)
  case health(BridgeHealthAnswer)
  case networkConfiguration(BridgeNetworkConfiguration)

  /// The answer as the host reports it: one line of JSON, its keys sorted.
  public func jsonLine() throws -> String {
    switch self {
    case let .notificationSettings(settings): try Self.line(settings)
    case let .deliveredNotification(notification): try Self.line(notification)
    case let .health(answer): try Self.line(answer)
    case let .networkConfiguration(configuration): try configuration.jsonLine()
    }
  }

  private static func line(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}

/// An application's notification settings, or that it has none.
public struct BridgeNotificationSettings: Codable, Equatable, Sendable {
  public struct Settings: Equatable, Sendable {
    public let allowsNotifications: Bool
    public let authorizationStatus: UInt
    /// Nil on a runtime whose sections carry no such setting.
    public let showsInNotificationCenter: Bool?
    public let showsInLockScreen: Bool?

    public init(allowsNotifications: Bool, authorizationStatus: UInt, showsInNotificationCenter: Bool?, showsInLockScreen: Bool?) {
      self.allowsNotifications = allowsNotifications
      self.authorizationStatus = authorizationStatus
      self.showsInNotificationCenter = showsInNotificationCenter
      self.showsInLockScreen = showsInLockScreen
    }
  }

  public let bundleID: String
  /// Nil when the application has no notification section.
  public let settings: Settings?

  public init(bundleID: String, settings: Settings?) {
    self.bundleID = bundleID
    self.settings = settings
  }

  private enum CodingKeys: String, CodingKey {
    case bundleID, found, allowsNotifications, authorizationStatus, showsInNotificationCenter, showsInLockScreen
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    bundleID = try container.decode(String.self, forKey: .bundleID)
    guard try container.decode(Bool.self, forKey: .found) else {
      settings = nil
      return
    }
    settings = Settings(
      allowsNotifications: try container.decode(Bool.self, forKey: .allowsNotifications),
      authorizationStatus: try container.decode(UInt.self, forKey: .authorizationStatus),
      showsInNotificationCenter: try container.decodeIfPresent(Bool.self, forKey: .showsInNotificationCenter),
      showsInLockScreen: try container.decodeIfPresent(Bool.self, forKey: .showsInLockScreen))
  }

  /// A found section names every setting, null where the runtime has none.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(bundleID, forKey: .bundleID)
    try container.encode(settings != nil, forKey: .found)
    guard let settings else { return }
    try container.encode(settings.allowsNotifications, forKey: .allowsNotifications)
    try container.encode(settings.authorizationStatus, forKey: .authorizationStatus)
    try container.encode(settings.showsInNotificationCenter, forKey: .showsInNotificationCenter)
    try container.encode(settings.showsInLockScreen, forKey: .showsInLockScreen)
  }
}

/// A notification an application has delivered. Absent text is empty.
public struct BridgeDeliveredNotification: Codable, Equatable, Sendable {
  public let bundleID: String
  public let identifier: String
  public let title: String
  public let subtitle: String
  public let body: String
  public let threadIdentifier: String
  /// Seconds since 1970, when the notification has a date.
  public let date: Double?

  public init(bundleID: String, identifier: String, title: String, subtitle: String, body: String, threadIdentifier: String, date: Double?) {
    self.bundleID = bundleID
    self.identifier = identifier
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.threadIdentifier = threadIdentifier
    self.date = date
  }
}

/// A sample type's authorization for an application.
public struct BridgeHealthRecord: Codable, Equatable, Sendable {
  public let identifier: String?
  public let sharingAuthorizationAllowed: Bool?
  public let readingAuthorizationAllowed: Bool?

  public init(identifier: String?, sharingAuthorizationAllowed: Bool?, readingAuthorizationAllowed: Bool?) {
    self.identifier = identifier
    self.sharingAuthorizationAllowed = sharingAuthorizationAllowed
    self.readingAuthorizationAllowed = readingAuthorizationAllowed
  }
}

/// What a health action did. Each case is reported with the fields it has always had.
@frozen public enum BridgeHealthAnswer: Codable, Equatable, Sendable {
  @frozen public enum WriteAction: String, Codable, Sendable {
    case approve
    case revoke
  }

  @frozen public enum Action: String, Codable, Sendable {
    case approve
    case revoke
    case clear
    case list
  }

  /// An authorization write that ran: `ok` when both the seed and the write succeeded, with each stage's error.
  case write(action: WriteAction, bundleID: String, ok: Bool, resolvedTypes: [String], unresolvedTypes: [String], seedError: String?, setError: String?)
  /// An authorization write that named no type the runtime knows, so nothing was written.
  case nothingResolved(action: WriteAction, bundleID: String, unresolvedTypes: [String])
  /// An authorization write on a runtime whose authorization store has no setter this guest knows.
  case noAuthorizationSpelling(action: WriteAction, bundleID: String, resolvedTypes: [String], unresolvedTypes: [String])
  case clear(bundleID: String, ok: Bool, error: String?)
  /// The records are reported even when the fetch also reported an error.
  case list(bundleID: String, ok: Bool, error: String?, records: [BridgeHealthRecord])
  /// A stage the daemon did not complete in time; `error` names the stage.
  case timedOut(action: Action, bundleID: String, error: String)

  public static let nothingResolvedError = "no resolvable HK types in request"
  public static let noAuthorizationSpellingError = "HKAuthorizationStore declares no known setAuthorizationStatuses: spelling"

  private enum CodingKeys: String, CodingKey {
    case action, bundleID, ok, error, completionStatus, resolvedTypes, unresolvedTypes, seedError, setError, records
  }

  private static let timedOutStatus = "timedOut"

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let action = try container.decode(Action.self, forKey: .action)
    let bundleID = try container.decode(String.self, forKey: .bundleID)
    if container.contains(.completionStatus) {
      self = .timedOut(action: action, bundleID: bundleID, error: try container.decode(String.self, forKey: .error))
      return
    }
    switch action {
    case .clear:
      self = .clear(bundleID: bundleID, ok: try container.decode(Bool.self, forKey: .ok), error: try container.decodeIfPresent(String.self, forKey: .error))
    case .list:
      self = .list(
        bundleID: bundleID, ok: try container.decode(Bool.self, forKey: .ok), error: try container.decodeIfPresent(String.self, forKey: .error),
        records: try container.decode([BridgeHealthRecord].self, forKey: .records))
    case .approve, .revoke:
      let write: WriteAction = action == .approve ? .approve : .revoke
      let unresolved = try container.decode([String].self, forKey: .unresolvedTypes)
      if container.contains(.seedError) {
        self = .write(
          action: write, bundleID: bundleID, ok: try container.decode(Bool.self, forKey: .ok),
          resolvedTypes: try container.decode([String].self, forKey: .resolvedTypes), unresolvedTypes: unresolved,
          seedError: try container.decodeIfPresent(String.self, forKey: .seedError), setError: try container.decodeIfPresent(String.self, forKey: .setError))
      } else if container.contains(.resolvedTypes) {
        self = .noAuthorizationSpelling(
          action: write, bundleID: bundleID, resolvedTypes: try container.decode([String].self, forKey: .resolvedTypes), unresolvedTypes: unresolved)
      } else {
        self = .nothingResolved(action: write, bundleID: bundleID, unresolvedTypes: unresolved)
      }
    }
  }

  /// An error the action could have but did not is reported as null.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .write(action, bundleID, ok, resolvedTypes, unresolvedTypes, seedError, setError):
      try container.encode(action.rawValue, forKey: .action)
      try container.encode(bundleID, forKey: .bundleID)
      try container.encode(ok, forKey: .ok)
      try container.encode(resolvedTypes, forKey: .resolvedTypes)
      try container.encode(unresolvedTypes, forKey: .unresolvedTypes)
      try container.encode(seedError, forKey: .seedError)
      try container.encode(setError, forKey: .setError)
    case let .nothingResolved(action, bundleID, unresolvedTypes):
      try container.encode(action.rawValue, forKey: .action)
      try container.encode(bundleID, forKey: .bundleID)
      try container.encode(false, forKey: .ok)
      try container.encode(Self.nothingResolvedError, forKey: .error)
      try container.encode(unresolvedTypes, forKey: .unresolvedTypes)
    case let .noAuthorizationSpelling(action, bundleID, resolvedTypes, unresolvedTypes):
      try container.encode(action.rawValue, forKey: .action)
      try container.encode(bundleID, forKey: .bundleID)
      try container.encode(false, forKey: .ok)
      try container.encode(Self.noAuthorizationSpellingError, forKey: .error)
      try container.encode(resolvedTypes, forKey: .resolvedTypes)
      try container.encode(unresolvedTypes, forKey: .unresolvedTypes)
    case let .clear(bundleID, ok, error):
      try container.encode(Action.clear.rawValue, forKey: .action)
      try container.encode(bundleID, forKey: .bundleID)
      try container.encode(ok, forKey: .ok)
      try container.encode(error, forKey: .error)
    case let .list(bundleID, ok, error, records):
      try container.encode(Action.list.rawValue, forKey: .action)
      try container.encode(bundleID, forKey: .bundleID)
      try container.encode(ok, forKey: .ok)
      try container.encode(error, forKey: .error)
      try container.encode(records, forKey: .records)
    case let .timedOut(action, bundleID, error):
      try container.encode(action.rawValue, forKey: .action)
      try container.encode(bundleID, forKey: .bundleID)
      try container.encode(false, forKey: .ok)
      try container.encode(error, forKey: .error)
      try container.encode(Self.timedOutStatus, forKey: .completionStatus)
    }
  }
}

/// What a network configuration store holds. The store keeps whatever was written to it, so its contents travel as
/// the property list they are, restricted to what JSON can report.
public struct BridgeNetworkConfiguration: Codable, Equatable, Sendable {
  /// The contents as a binary property list.
  public let propertyList: Data

  /// Refuses contents JSON cannot hold, such as a date or data, since the host reports them as JSON.
  public init(_ contents: Any) throws {
    guard JSONSerialization.isValidJSONObject([contents]) else { throw BridgeProtocolError.invalidJSONValue }
    propertyList = try PropertyListSerialization.data(fromPropertyList: contents, format: .binary, options: 0)
  }

  public init(from decoder: Decoder) throws {
    propertyList = try decoder.singleValueContainer().decode(Data.self)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(propertyList)
  }

  /// The contents as one line of JSON, its keys sorted.
  func jsonLine() throws -> String {
    let contents = try PropertyListSerialization.propertyList(from: propertyList, format: nil)
    return String(decoding: try JSONSerialization.data(withJSONObject: contents, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
  }
}
