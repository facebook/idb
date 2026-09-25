/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import SimulatorFrameworkBridgeProtocol

public enum BridgeServices {
  public static func execute(_ command: BridgeCommand) -> BridgeResult {
    let output = BridgeOutput()
    return output.finish(status: run(command, output: output))
  }

  private static func run(_ command: BridgeCommand, output: BridgeOutput) -> Int32 {
    switch command {
    case .ping, .shutdown:
      return 0
    case .clearContacts:
      #if os(tvOS)
      return unavailable("The contacts service", output: output)
      #else
      return Int32(FBContactsService.handleContactsAction(action: "clear", output: output))
      #endif
    case .clearPhotos:
      return Int32(FBPhotoLibraryService.handlePhotoLibraryAction(action: "clear", output: output))
    case let .dns(command):
      let action: String
      let arguments: [String]
      switch command {
      case .list:
        action = "list"
        arguments = []
      case .clear:
        action = "clear"
        arguments = []
      case let .set(servers):
        action = "set"
        arguments = servers
      }
      return Int32(FBDnsService.handleDnsAction(action: action, arguments: arguments, output: output))
    case let .dynamicStore(command):
      switch command {
      case let .snapshot(key):
        return Int32(FBDynamicStoreService.handleDynamicStoreAction(action: "snapshot", arguments: [key], input: { Data() }, output: output))
      case let .restore(key, snapshot):
        return Int32(FBDynamicStoreService.handleDynamicStoreAction(action: "restore", arguments: [key], input: { snapshot }, output: output))
      }
    case let .proxy(command):
      let action: String
      let arguments: [String]
      switch command {
      case .list:
        action = "list"
        arguments = []
      case .clear:
        action = "clear"
        arguments = []
      case let .set(host, port, kind):
        action = "set"
        arguments = [host, String(port), kind.rawValue]
      }
      return Int32(FBProxyService.handleProxyAction(action: action, arguments: arguments, output: output))
    case let .notifications(command):
      let action: String
      let bundleID: String?
      switch command {
      case let .list(identifier):
        action = "list"
        bundleID = identifier
      case let .approve(identifier):
        action = "approve"
        bundleID = identifier
      case let .revoke(identifier):
        action = "revoke"
        bundleID = identifier
      case let .delivered(identifier):
        #if os(tvOS)
        return unavailable("The notifications delivered action", output: output)
        #else
        return FBDeliveredNotificationsService.handleAction("delivered", bundleID: identifier, directory: nil, timeout: 0, output: output)
        #endif
      case let .clearDelivered(identifier):
        #if os(tvOS)
        return unavailable("The notifications clear-delivered action", output: output)
        #else
        return FBDeliveredNotificationsService.handleAction("clear-delivered", bundleID: identifier, directory: nil, timeout: 0, output: output)
        #endif
      }
      return Int32(FBNotificationSettingsService.handleNotificationSettingsAction(action: action, bundleID: bundleID, output: output))
    case let .health(command):
      #if os(tvOS)
      return unavailable("The health service", output: output)
      #else
      let action: String
      let bundleID: String
      let types: [String]
      switch command {
      case let .list(identifier):
        action = "list"
        bundleID = identifier
        types = []
      case let .clear(identifier):
        action = "clear"
        bundleID = identifier
        types = []
      case let .approve(identifier, identifiers):
        action = "approve"
        bundleID = identifier
        types = identifiers
      case let .revoke(identifier, identifiers):
        action = "revoke"
        bundleID = identifier
        types = identifiers
      }
      return Int32(FBHealthSettingsService.handleHealthSettingsAction(action: action, bundleID: bundleID, typeIdentifiers: types, output: output))
      #endif
    case let .accessibility(parameters):
      let response = FBAccessibilityService.handleRequest(parameters.mapValues(\.foundationValue))
      return accessibility(FBAccessibilityService.serializeResponse(response), output: output)
    }
  }

  /// Commands that answer with a stream of results rather than one; nil for every other command.
  public static func stream(_ command: BridgeCommand) -> BridgeStreamStart? {
    guard case let .accessibility(parameters) = command, let start = FBAccessibilityService.quiescence(parameters.mapValues(\.foundationValue)) else { return nil }
    switch start {
    case let .stream(events):
      return .stream(AccessibilityResultStream(events: events))
    case let .failure(response):
      return .result(accessibilityResult(FBAccessibilityService.serializeResponse(response)))
    }
  }

  private static func accessibility(_ data: Data, output: BridgeOutput) -> Int32 {
    guard let value = output.write(json: data) else { return 1 }
    if case let .object(fields) = value, fields[BridgeAXWire.Envelope.ok.rawValue] == .bool(true) { return 0 }
    return 1
  }

  fileprivate static func accessibilityResult(_ data: Data) -> BridgeResult {
    let output = BridgeOutput()
    return output.finish(status: accessibility(data, output: output))
  }

  private static func unavailable(_ subject: String, output: BridgeOutput) -> Int32 {
    Int32(output.failure("\(subject) is not available in a tvOS guest"))
  }
}

private final class AccessibilityResultStream: BridgeResultStream {
  private let events: BridgeResponseStream

  init(events: BridgeResponseStream) {
    self.events = events
  }

  func run(emit: @escaping (BridgeResult) -> Bool) {
    events.run { emit(BridgeServices.accessibilityResult($0)) }
  }

  func cancel() {
    events.cancel()
  }
}
