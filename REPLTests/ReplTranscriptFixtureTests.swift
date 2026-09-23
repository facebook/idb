/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import IDBGRPCSwift
import SwiftProtobuf
import Testing

private final class ReplTranscriptFixtureBundleToken {}

@Suite
struct ReplTranscriptFixtureTests {
  private struct Transcript: Decodable {
    let version: Int
    let scope: String
    let steps: [Step]
  }

  private struct Step: Decodable {
    enum Kind: String, Decodable {
      case start = "Start"
      case ready = "Ready"
      case execute = "Execute"
      case result = "Result"
      case clientHalfClose = "client_half_close"
      case stopped = "Stopped"
    }

    let kind: Kind
    let protobufBase64: String?

    enum CodingKeys: String, CodingKey {
      case kind
      case protobufBase64 = "protobuf_base64"
    }
  }

  @Test
  func languageNeutralTranscript() throws {
    let url = try #require(
      Bundle(for: ReplTranscriptFixtureBundleToken.self)
        .url(forResource: "repl_transcript.v1", withExtension: "json")
    )
    let data = try Data(contentsOf: url)
    let rawTranscript = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(Set(rawTranscript.keys) == ["scope", "steps", "version"])
    let rawSteps = try #require(rawTranscript["steps"] as? [[String: Any]])
    for rawStep in rawSteps {
      let kind = try #require(rawStep["kind"] as? String)
      let expectedKeys =
        kind == "client_half_close"
        ? Set(["kind"])
        : Set(["kind", "protobuf_base64"])
      #expect(Set(rawStep.keys) == expectedKeys)
    }

    let transcript = try JSONDecoder().decode(Transcript.self, from: data)

    #expect(transcript.version == 1)
    #expect(transcript.scope == "swift-protobuf-wire-contract")
    #expect(
      transcript.steps.map(\.kind)
        == [.start, .ready, .execute, .result, .clientHalfClose, .stopped]
    )

    let startBytes = try protobufBytes(transcript.steps[0])
    let startRequest = try Idb_ReplRequest(serializedBytes: startBytes)
    #expect(try startRequest.serializedData() == startBytes)
    guard case let .start(start) = startRequest.control else {
      Issue.record("Expected Start")
      return
    }
    #expect(start.testBundlePath == "FixtureTests.xctest")
    #expect(start.context == .test)
    #expect(start.probeFilePath == "/tmp/idb-repl-fixture-probe")

    let readyBytes = try protobufBytes(transcript.steps[1])
    let readyResponse = try Idb_ReplResponse(serializedBytes: readyBytes)
    #expect(try readyResponse.serializedData() == readyBytes)
    guard case let .ready(ready) = readyResponse.event else {
      Issue.record("Expected Ready")
      return
    }
    #expect(ready.deviceType == "iphone")
    #expect(ready.generatedInterfaces.count == 1)
    #expect(ready.generatedInterfaces[0].moduleName == "IDB")
    #expect(ready.generatedInterfaces[0].contents == "public struct Fixture {}")
    #expect(ready.osVersion == "26.0")
    #expect(ready.nextRunIndex == 0)
    #expect(ready.sharedFilesystem)
    #expect(ready.sessionID == "fixture-session")

    let executeBytes = try protobufBytes(transcript.steps[2])
    let executeRequest = try Idb_ReplRequest(serializedBytes: executeBytes)
    #expect(try executeRequest.serializedData() == executeBytes)
    guard case let .execute(execute) = executeRequest.control else {
      Issue.record("Expected Execute")
      return
    }
    #expect(execute.dylib == Data([0xca, 0xfe]))
    #expect(execute.symbol == "idb_repl_0")

    let resultBytes = try protobufBytes(transcript.steps[3])
    let resultResponse = try Idb_ReplResponse(serializedBytes: resultBytes)
    #expect(try resultResponse.serializedData() == resultBytes)
    guard case let .result(result) = resultResponse.event else {
      Issue.record("Expected Result")
      return
    }
    #expect(result.success)
    #expect(result.output == "ok")
    #expect(result.nextRunIndex == 1)
    #expect(result.artifacts.count == 1)
    #expect(
      result.artifacts[0].hostPath
        == "/tmp/idb-repl-artifacts/fixture-session/capture.png"
    )
    #expect(
      result.artifacts[0].containerPath
        == "idb-repl-artifacts/fixture-session/capture.png"
    )

    #expect(transcript.steps[4].protobufBase64 == nil)

    let stoppedBytes = try protobufBytes(transcript.steps[5])
    let stoppedResponse = try Idb_ReplResponse(serializedBytes: stoppedBytes)
    #expect(try stoppedResponse.serializedData() == stoppedBytes)
    guard case let .stopped(stopped) = stoppedResponse.event else {
      Issue.record("Expected Stopped")
      return
    }
    #expect(stopped.desc == "REPL session ended")
  }

  private func protobufBytes(_ step: Step) throws -> Data {
    let encoded = try #require(step.protobufBase64)
    return try #require(Data(base64Encoded: encoded))
  }
}
