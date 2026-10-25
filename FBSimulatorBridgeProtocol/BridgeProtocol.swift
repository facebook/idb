/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@frozen public enum BridgeProtocolError: Error, Equatable {
  case invalidJSONValue
  case unsupportedVersion(Int)
  case mismatchedResponse
}

public struct BridgeRequest: Codable, Equatable, Sendable {
  public static let currentVersion = 2
  public let version: Int
  public let id: String
  public let command: BridgeCommand

  public init(command: BridgeCommand, id: String = UUID().uuidString) {
    version = Self.currentVersion
    self.id = id
    self.command = command
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(self)
  }

  public var arguments: [String] {
    get throws {
      ["rpc", String(decoding: try encoded(), as: UTF8.self)]
    }
  }

  public static func decode(_ data: Data) throws -> Self {
    // The version is checked before the command so a newer command shape reports the version gap,
    // not a decoding failure.
    let envelope = try JSONDecoder().decode(Envelope.self, from: data)
    guard envelope.version == currentVersion else { throw BridgeProtocolError.unsupportedVersion(envelope.version) }
    return try JSONDecoder().decode(Self.self, from: data)
  }

  /// The identity a request carries even when the rest of it cannot be decoded, so a reply can still name it.
  public static func identity(of data: Data) -> String? {
    (try? JSONDecoder().decode(Identity.self, from: data))?.id
  }

  /// The parameters of an accessibility request as sent, without decoding them into a `BridgeAXRequest`, so the guest
  /// can say what is wrong with a malformed one in an accessibility response rather than failing the frame.
  public static func accessibilityParameters(of data: Data) -> [String: BridgeJSONValue]? {
    (try? JSONDecoder().decode(UndecodedAccessibility.self, from: data))?.command.accessibility._0
  }

  private struct Envelope: Decodable {
    let version: Int
    let id: String
  }

  private struct Identity: Decodable {
    let id: String?
  }

  private struct UndecodedAccessibility: Decodable {
    struct Command: Decodable {
      struct Parameters: Decodable {
        let _0: [String: BridgeJSONValue]
      }
      let accessibility: Parameters
    }
    let command: Command
  }
}

public struct BridgeResult: Codable, Equatable, Sendable {
  @frozen public enum CodingKeys: String, CodingKey {
    case exitCode
    case values
    case error
    case propertyList
  }

  public let exitCode: Int32
  public let values: [BridgeJSONValue]
  public let error: String?
  public let propertyList: Data?

  public init(exitCode: Int32, values: [BridgeJSONValue] = [], error: String? = nil, propertyList: Data? = nil) {
    self.exitCode = exitCode
    self.values = values
    self.error = error
    self.propertyList = propertyList
  }
}

public struct BridgeResponse: Codable, Equatable, Sendable {
  public let version: Int
  public let id: String?
  public let result: BridgeResult

  public init(request: BridgeRequest, result: BridgeResult) {
    self.init(id: request.id, result: result)
  }

  public init(id: String?, result: BridgeResult) {
    self.init(version: BridgeRequest.currentVersion, id: id, result: result)
  }

  private init(version: Int, id: String?, result: BridgeResult) {
    self.version = version
    self.id = id
    self.result = result
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(self)
  }

  public static func decode(_ data: Data, for request: BridgeRequest) throws -> Self {
    let response = try Self(frame: data)
    guard response.version == BridgeRequest.currentVersion else { throw BridgeProtocolError.unsupportedVersion(response.version) }
    guard response.id == request.id else { throw BridgeProtocolError.mismatchedResponse }
    return response
  }

  /// Decodes a frame in one `JSONSerialization` pass instead of through `Codable`. `JSONDecoder` reaches every
  /// node of `result.values` through `BridgeJSONValue.init(from:)`, which tries each case in turn and builds a
  /// `DecodingError` for every miss; on an accessibility tree of a few thousand nodes that dominated the
  /// client's CPU. The result is the same value `Decodable` produced, so `encoded()` round-trips unchanged.
  public init(frame data: Data) throws {
    let object = try Self.object(try JSONSerialization.jsonObject(with: data), "a response frame")
    guard let version = object[CodingKeys.version.stringValue] as? Int else {
      throw Self.corrupted("a response frame carries an integer version")
    }
    let id = object[CodingKeys.id.stringValue] as? String
    let result = try Self.object(object[CodingKeys.result.stringValue], "result")
    guard let exitCode = (result[BridgeResult.CodingKeys.exitCode.stringValue] as? Int).flatMap(Int32.init(exactly:)) else {
      throw Self.corrupted("result.exitCode is a 32-bit integer")
    }
    let values = try (result[BridgeResult.CodingKeys.values.stringValue] as? [Any] ?? []).map(BridgeJSONValue.init(foundationValue:))
    let propertyList: Data?
    switch result[BridgeResult.CodingKeys.propertyList.stringValue] {
    case nil, is NSNull: propertyList = nil
    case let base64 as String:
      guard let bytes = Data(base64Encoded: base64) else { throw Self.corrupted("result.propertyList is base64") }
      propertyList = bytes
    default: throw Self.corrupted("result.propertyList is a base64 string")
    }
    self.init(
      version: version, id: id,
      result: BridgeResult(
        exitCode: exitCode, values: values, error: result[BridgeResult.CodingKeys.error.stringValue] as? String,
        propertyList: propertyList))
  }

  private static func object(_ value: Any?, _ what: String) throws -> [String: Any] {
    guard let object = value as? [String: Any] else { throw corrupted("\(what) is a JSON object") }
    return object
  }

  private static func corrupted(_ expectation: String) -> DecodingError {
    .dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "expected \(expectation)"))
  }
}
