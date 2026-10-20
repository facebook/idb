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
  public static let currentVersion = 4
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

  private struct Envelope: Decodable {
    let version: Int
    let id: String
  }

  private struct Identity: Decodable {
    let id: String?
  }
}

public struct BridgeResult: Codable, Equatable, Sendable {
  public let exitCode: Int32
  public let values: [BridgeJSONValue]
  public let error: String?
  public let propertyList: Data?
  /// An accessibility command's answer, carried in the frame in its own shape.
  public let accessibility: BridgeAXAnswer?

  public init(
    exitCode: Int32, values: [BridgeJSONValue] = [], error: String? = nil, propertyList: Data? = nil, accessibility: BridgeAXAnswer? = nil
  ) {
    self.exitCode = exitCode
    self.values = values
    self.error = error
    self.propertyList = propertyList
    self.accessibility = accessibility
  }
}

extension BridgeResult {
  /// The command's output as the host reports it: each value a line of JSON, its keys sorted.
  public var jsonLines: String {
    get throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      return try values.map { String(decoding: try encoder.encode($0), as: UTF8.self) + "\n" }.joined()
    }
  }

  /// What the host reports for the command, whether it succeeded or failed: its error, then its output.
  public var reportedOutput: String {
    get throws {
      try [error, jsonLines].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
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
    version = BridgeRequest.currentVersion
    self.id = id
    self.result = result
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(self)
  }

  /// Decodes the response to `request`; an accessibility answer decodes as the kind the request's verb answers with.
  public static func decode(_ data: Data, for request: BridgeRequest) throws -> Self {
    let decoder = JSONDecoder()
    if case let .accessibility(accessibility) = request.command {
      decoder.userInfo[.bridgeAXAnswerKind] = accessibility.answerKind
    }
    let response = try decoder.decode(Self.self, from: data)
    try check(version: response.version, id: response.id, for: request)
    return response
  }

  /// Checks `data` is the response to `request`, at this version, without decoding its result.
  public static func validate(_ data: Data, for request: BridgeRequest) throws {
    let identity = try JSONDecoder().decode(Identity.self, from: data)
    try check(version: identity.version, id: identity.id, for: request)
  }

  private static func check(version: Int, id: String?, for request: BridgeRequest) throws {
    guard version == BridgeRequest.currentVersion else { throw BridgeProtocolError.unsupportedVersion(version) }
    guard id == request.id else { throw BridgeProtocolError.mismatchedResponse }
  }

  private struct Identity: Decodable {
    let version: Int
    let id: String?
  }
}
