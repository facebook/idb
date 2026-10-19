/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension CodingUserInfoKey {
  /// The kind of answer a decoder is reading, which the request it answers decides.
  // A constant key: `init(rawValue:)` fails for no string.
  // swiftlint:disable:next force_unwrapping
  public static let bridgeAXAnswerKind = CodingUserInfoKey(rawValue: "BridgeAXAnswer.Kind")!
}

/// The guest's answer to an accessibility request: what the request's verb answers with, or why it could not.
///
/// It encodes as its outcome alone, `ok` beside the answer's own fields, with nothing naming the verb: the request
/// already does. So it decodes only where the request is known, through `BridgeResponse.decode(_:for:)` or
/// `decode(_:as:)`.
@frozen public enum BridgeAXAnswer: Codable, Equatable, Sendable {
  case tree(BridgeAXTreeResponse)
  case hitTest(BridgeAXHitTestResponse)
  case write(BridgeAXWriteResponse)
  case setting(BridgeAXSettingResponse)
  case displays(BridgeAXDisplayInventory)
  case settingSnapshot(BridgeAXSettingSnapshot)
  case quiescence(BridgeAXQuiescenceEvent)
  /// Why the request could not be answered, which reads the same whatever it asked.
  case failure(BridgeAXFailure)

  /// Which answer a request gets when it succeeds.
  @frozen public enum Kind: String, Sendable, CaseIterable {
    case tree
    case hitTest
    case write
    case setting
    case displays
    case settingSnapshot
    case quiescence
  }

  public var succeeded: Bool {
    guard case .failure = self else { return true }
    return false
  }

  /// An answer as a guest wrote it on its own, for a request answered with `kind`.
  public static func decode(_ data: Data, as kind: Kind) throws -> BridgeAXAnswer {
    let decoder = JSONDecoder()
    decoder.userInfo[.bridgeAXAnswerKind] = kind
    return try decoder.decode(Self.self, from: data)
  }

  public init(from decoder: Decoder) throws {
    let envelope = try decoder.container(keyedBy: BridgeAXWire.Envelope.self)
    guard try envelope.decode(Bool.self, forKey: .ok) else {
      self = .failure(try BridgeAXFailure(from: decoder))
      return
    }
    guard let kind = decoder.userInfo[.bridgeAXAnswerKind] as? Kind else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "an accessibility answer decodes only against the request it answers"))
    }
    switch kind {
    case .tree: self = .tree(try BridgeAXTreeResponse(from: decoder))
    case .hitTest: self = .hitTest(try BridgeAXHitTestResponse(from: decoder))
    case .write: self = .write(try BridgeAXWriteResponse(from: decoder))
    case .setting: self = .setting(try BridgeAXSettingResponse(from: decoder))
    case .displays: self = .displays(try BridgeAXDisplayInventory(from: decoder))
    case .settingSnapshot: self = .settingSnapshot(try BridgeAXSettingSnapshot(from: decoder))
    case .quiescence: self = .quiescence(try BridgeAXQuiescenceEvent(from: decoder))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var envelope = encoder.container(keyedBy: BridgeAXWire.Envelope.self)
    try envelope.encode(succeeded, forKey: .ok)
    switch self {
    case let .tree(answer): try answer.encode(to: encoder)
    case let .hitTest(answer): try answer.encode(to: encoder)
    case let .write(answer): try answer.encode(to: encoder)
    case let .setting(answer): try answer.encode(to: encoder)
    case let .displays(answer): try answer.encode(to: encoder)
    case let .settingSnapshot(answer): try answer.encode(to: encoder)
    case let .quiescence(answer): try answer.encode(to: encoder)
    case let .failure(failure): try failure.encode(to: encoder)
    }
  }
}

extension BridgeAXRequest {
  /// The answer this request gets when it succeeds.
  public var answerKind: BridgeAXAnswer.Kind {
    switch self {
    case .read, .readFrontmost: .tree
    case .hitTest: .hitTest
    case .write: .write
    case .deviceSettingRead, .deviceSettingWrite: .setting
    case .deviceSettingChanges: .settingSnapshot
    case .quiescence: .quiescence
    case .displays: .displays
    }
  }
}
