/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// How the client handed over what it wants installed.
enum InstallPayloadKind: String {
  /// Bytes streamed over the RPC.
  case data
  /// A URL for the companion to fetch.
  case url
  /// A path already on the companion's host.
  case filePath = "file_path"
}

/// The format of an app streamed over the RPC, which the client picks from what the companion advertises.
enum InstallStreamFormat: String {
  case zip
  case zstdZip = "zip_zstd"
  case gzipTar = "tar_gzip"
  case zstdTar = "tar_zstd"

  init(tarCompression: FBCompressionFormat) {
    switch tarCompression {
    case .GZIP:
      self = .gzipTar
    case .ZSTD:
      self = .zstdTar
    }
  }
}

/// Where an install was when it failed: in one of its stages, or receiving a streamed payload before
/// any stage began.
enum InstallFailureStage: Equatable {
  case stage(InstallStage)
  case receive

  var name: String {
    switch self {
    case .stage(let stage):
      stage.rawValue
    case .receive:
      "receive"
    }
  }
}

/// Accumulates what one install did into the columns its event reports.
///
/// `receive_ms` and `size` describe getting the payload onto the companion's host: streamed over the
/// RPC for `data`, downloaded for `url`. Stage durations come from each stage's completion, so a stage
/// that never finished has none.
// SAFETY: every stored property is only read or written inside `lock`.
// patternlint-disable-next-line unchecked-sendable
final class InstallTelemetry: @unchecked Sendable {

  private let lock = NSLock()
  private let payloadKind: InstallPayloadKind
  private var streamFormat: InstallStreamFormat?
  private var receivedBytes: Int64?
  private var receiveMs: Int64?
  private var receiving = false
  private var stagesInFlight: Set<InstallStage> = []
  private var stageMs: [InstallStage: Int64] = [:]
  private var failure: (stage: InstallFailureStage?, kind: String, cancelled: Bool)?

  init(payloadKind: InstallPayloadKind) {
    self.payloadKind = payloadKind
  }

  func streamed(_ format: InstallStreamFormat) {
    lock.withLock { streamFormat = format }
  }

  /// Measures `body` receiving the streamed payload, reporting what it received whether or not it
  /// completes. A receive that throws is left in progress, so the failure is attributed to it.
  func receive<T>(_ body: (inout InstallReceive) async throws -> T) async rethrows -> T {
    lock.withLock { receiving = true }
    var receive = InstallReceive(telemetry: self)
    do {
      let result = try await body(&receive)
      receive.finish(completed: true)
      return result
    } catch {
      receive.finish(completed: false)
      throw error
    }
  }

  fileprivate func received(bytes: Int64, elapsedMs: Int64, completed: Bool) {
    lock.withLock {
      receiving = !completed
      receivedBytes = bytes
      receiveMs = elapsedMs
    }
  }

  func observe(_ event: InstallProgressEvent) {
    lock.withLock {
      switch event {
      case .downloadStarted, .extractStarted, .installStarted:
        stagesInFlight.insert(event.stage)
      case .downloadProgress:
        break
      case .downloadCompleted(let timing, let totalBytes):
        stagesInFlight.remove(.download)
        receivedBytes = totalBytes
        receiveMs = timing.elapsedMs
      case .extractCompleted, .installCompleted:
        stagesInFlight.remove(event.stage)
        stageMs[event.stage] = event.elapsedMs
      }
    }
  }

  /// Download and extraction overlap, and a failed download also fails the extraction reading it, so
  /// the failure belongs to the earliest stage still running. A streamed payload that fails before any
  /// stage starts failed while being received.
  ///
  /// A failure once the RPC or the call's task is cancelled was brought on by the client going away,
  /// whatever error it surfaced as. gRPC marks the RPC cancelled without cancelling the task, so
  /// callers pass what the RPC's cancellation handle says.
  func failed(_ error: Error, rpcCancelled: Bool = false) {
    let cancelled = rpcCancelled || Task.isCancelled
    lock.withLock {
      let stage =
        [InstallStage.download, .extract, .install].first(where: stagesInFlight.contains).map(InstallFailureStage.stage)
        ?? (receiving ? .receive : nil)
      failure = (stage, Self.kind(of: error), cancelled)
    }
  }

  func record(into call: CallTelemetry) {
    lock.withLock {
      call.setNormal(payloadKind.rawValue, forKey: "payload_kind")
      if let streamFormat {
        call.setNormal(streamFormat.rawValue, forKey: "stream_format")
      }
      if let receivedBytes {
        call.setSize(receivedBytes)
      }
      if let receiveMs {
        call.setInt(Int(receiveMs), forKey: "receive_ms")
      }
      if let extractMs = stageMs[.extract] {
        call.setInt(Int(extractMs), forKey: "extract_ms")
      }
      if let installMs = stageMs[.install] {
        call.setInt(Int(installMs), forKey: "install_ms")
      }
      if let failure {
        if let stage = failure.stage {
          call.setNormal(stage.name, forKey: "failure_stage")
        }
        call.setNormal(failure.kind, forKey: "failure_kind")
        if failure.cancelled {
          call.setNormal("client", forKey: "cancel_source")
        }
      }
    }
  }

  /// An `InstallError` is named by its case, so failures group by cause. Anything else is named by its
  /// type, which at least separates a target refusing the install from a transport failure.
  static func kind(of error: Error) -> String {
    guard let error = error as? InstallError else {
      return String(describing: type(of: error))
    }
    switch error {
    case .httpStatus:
      return "http_status"
    case .transferFailed:
      return "transfer_failed"
    case .notAnHTTPResponse:
      return "not_an_http_response"
    case .extractionFailed:
      return "extraction_failed"
    case .noInstallableBundle:
      return "no_installable_bundle"
    }
  }
}

/// Counts a streamed payload's bytes and time for `InstallTelemetry.receive`.
struct InstallReceive {
  private let telemetry: InstallTelemetry
  private let start = Date()
  private var bytes: Int64 = 0

  fileprivate init(telemetry: InstallTelemetry) {
    self.telemetry = telemetry
  }

  mutating func count(_ data: Data) {
    bytes += Int64(data.count)
  }

  fileprivate func finish(completed: Bool) {
    telemetry.received(bytes: bytes, elapsedMs: Int64(Date().timeIntervalSince(start) * 1000), completed: completed)
  }
}
