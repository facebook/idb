/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation

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
      return Int32(ContactsService.handleContactsAction(action: "clear", output: output))
      #endif
    case .clearPhotos:
      return Int32(PhotoLibraryService.handlePhotoLibraryAction(action: "clear", output: output))
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
      return Int32(DnsService.handleDnsAction(action: action, arguments: arguments, output: output))
    case let .dynamicStore(command):
      switch command {
      case let .snapshot(key):
        return Int32(DynamicStoreService.handleDynamicStoreAction(action: "snapshot", arguments: [key], input: { Data() }, output: output))
      case let .restore(key, snapshot):
        return Int32(DynamicStoreService.handleDynamicStoreAction(action: "restore", arguments: [key], input: { snapshot }, output: output))
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
      return Int32(ProxyService.handleProxyAction(action: action, arguments: arguments, output: output))
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
        return DeliveredNotificationsService.handleAction("delivered", bundleID: identifier, directory: nil, timeout: 0, output: output)
        #endif
      case let .clearDelivered(identifier):
        #if os(tvOS)
        return unavailable("The notifications clear-delivered action", output: output)
        #else
        return DeliveredNotificationsService.handleAction("clear-delivered", bundleID: identifier, directory: nil, timeout: 0, output: output)
        #endif
      }
      return Int32(NotificationSettingsService.handleNotificationSettingsAction(action: action, bundleID: bundleID, output: output))
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
      return Int32(HealthSettingsService.handleHealthSettingsAction(action: action, bundleID: bundleID, typeIdentifiers: types, output: output))
      #endif
    case let .accessibility(request):
      return accessibility(AccessibilityService.handleRequest(request), output: output)
    }
  }

  /// The answer to an accessibility frame whose parameters are not a request, in the response a malformed request has
  /// always had.
  public static func undecodedAccessibility(_ parameters: [String: BridgeJSONValue]) -> BridgeResult {
    accessibilityResult(AccessibilityService.handleRequest(parameters: parameters))
  }

  /// Commands that answer with a stream of results rather than one; nil for every other command.
  public static func stream(_ command: BridgeCommand) -> BridgeStreamStart? {
    guard case let .accessibility(request) = command, let start = AccessibilityService.stream(request) else { return nil }
    switch start {
    case let .stream(events):
      return .stream(AccessibilityResultStream(events: events))
    case let .failure(response):
      return .result(accessibilityResult(response))
    }
  }

  /// The answer goes on the wire as the bytes `serializeResponse` wrote, so nothing parses it before the host does.
  private static func accessibility(_ response: [String: Any], output: BridgeOutput) -> Int32 {
    output.write(accessibility: AccessibilityService.serializeResponse(response))
    return (response[BridgeAXWire.Envelope.ok.rawValue] as? NSNumber)?.boolValue == true ? 0 : 1
  }

  fileprivate static func accessibilityResult(_ response: [String: Any]) -> BridgeResult {
    let output = BridgeOutput()
    return output.finish(status: accessibility(response, output: output))
  }

  /// A streamed frame arrives already serialized; only its `ok` is read back, to set the exit status.
  fileprivate static func accessibilityResult(_ data: Data) -> BridgeResult {
    let output = BridgeOutput()
    output.write(accessibility: data)
    let ok = (try? JSONDecoder().decode(StreamedFrameStatus.self, from: data))?.ok == true
    return output.finish(status: ok ? 0 : 1)
  }

  private struct StreamedFrameStatus: Decodable {
    let ok: Bool
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
