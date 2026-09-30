/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
@preconcurrency import FBControlCore
import Foundation
import Testing

private let url = URL(string: "http://127.0.0.1/app.ipa")!
private let start = Date(timeIntervalSince1970: 0)

/// Whole seconds, so the milliseconds come out exact.
private func timing(seconds: Int) -> InstallProgressTiming {
  .measure(stageStart: start, totalStart: start, now: start.addingTimeInterval(TimeInterval(seconds)))
}

private func columns(of telemetry: InstallTelemetry) -> [String] {
  let call = CallTelemetry()
  telemetry.record(into: call)
  return call.columnDescriptions
}

private struct Refused: Error {}

@Suite struct InstallTelemetryTests {

  @Test func aDownloadedInstallReportsBytesAndStageTimings() {
    let telemetry = InstallTelemetry(payloadKind: .url)
    telemetry.observe(.downloadStarted(timing: timing(seconds: 0), url: url))
    telemetry.observe(.extractStarted(timing: timing(seconds: 0), destinationPath: "/tmp/x"))
    telemetry.observe(.downloadProgress(timing: timing(seconds: 10), bytesDownloaded: 100, totalBytes: 4096))
    telemetry.observe(.downloadCompleted(timing: timing(seconds: 20), totalBytes: 4096))
    telemetry.observe(.extractCompleted(timing: timing(seconds: 30), destinationPath: "/tmp/x"))
    telemetry.observe(.installStarted(timing: timing(seconds: 0), appPath: "/tmp/x/A.app"))
    telemetry.observe(.installCompleted(timing: timing(seconds: 40), appPath: "/tmp/x/A.app", bundleId: "com.a"))

    #expect(columns(of: telemetry) == ["size=4096", "extract_ms=30000", "install_ms=40000", "payload_kind=url", "receive_ms=20000"])
  }

  @Test func aStreamedPayloadReportsWhatWasReceived() {
    let telemetry = InstallTelemetry(payloadKind: .data)
    var receive = telemetry.startReceiving()
    receive.count(Data(count: 10))
    receive.count(Data(count: 22))
    receive.finish()

    let call = CallTelemetry()
    telemetry.record(into: call)
    #expect(call.size == 32)
    #expect(call.ints["receive_ms"] != nil)
    #expect(call.normals == ["payload_kind": "data"])
  }

  @Test func aLocalPathReportsOnlyItsKindAndStages() {
    let telemetry = InstallTelemetry(payloadKind: .filePath)
    telemetry.observe(.installStarted(timing: timing(seconds: 0), appPath: "/a/A.app"))
    telemetry.observe(.installCompleted(timing: timing(seconds: 7), appPath: "/a/A.app", bundleId: "com.a"))

    #expect(columns(of: telemetry) == ["install_ms=7000", "payload_kind=file_path"])
  }

  @Test func aFailedDownloadIsAttributedToTheDownloadNotTheExtractionReadingIt() {
    let telemetry = InstallTelemetry(payloadKind: .url)
    telemetry.observe(.downloadStarted(timing: timing(seconds: 0), url: url))
    telemetry.observe(.extractStarted(timing: timing(seconds: 0), destinationPath: "/tmp/x"))
    telemetry.failed(InstallError.httpStatus(url: url, statusCode: 404))

    #expect(columns(of: telemetry) == ["failure_kind=http_status", "failure_stage=download", "payload_kind=url"])
  }

  @Test func aFailedExtractionIsAttributedToTheExtraction() {
    let telemetry = InstallTelemetry(payloadKind: .url)
    telemetry.observe(.downloadStarted(timing: timing(seconds: 0), url: url))
    telemetry.observe(.extractStarted(timing: timing(seconds: 0), destinationPath: "/tmp/x"))
    telemetry.observe(.downloadCompleted(timing: timing(seconds: 5), totalBytes: 9))
    telemetry.failed(InstallError.extractionFailed(underlying: Refused()))

    let call = CallTelemetry()
    telemetry.record(into: call)
    #expect(call.normals["failure_stage"] == "extract")
    #expect(call.normals["failure_kind"] == "extraction_failed")
    #expect(call.size == 9)
  }

  @Test func aRefusedInstallIsAttributedToTheInstallAndNamedByType() {
    let telemetry = InstallTelemetry(payloadKind: .filePath)
    telemetry.observe(.installStarted(timing: timing(seconds: 0), appPath: "/a/A.app"))
    telemetry.failed(Refused())

    #expect(columns(of: telemetry) == ["failure_kind=Refused", "failure_stage=install", "payload_kind=file_path"])
  }

  @Test func aStreamThatFailsBeforeAnyStageFailedWhileReceiving() {
    let telemetry = InstallTelemetry(payloadKind: .data)
    _ = telemetry.startReceiving()
    telemetry.failed(Refused())

    #expect(columns(of: telemetry) == ["failure_kind=Refused", "failure_stage=receive", "payload_kind=data"])
  }

  @Test func aFailureOutsideAnyStageHasNoStage() {
    let telemetry = InstallTelemetry(payloadKind: .filePath)
    telemetry.failed(Refused())

    #expect(columns(of: telemetry) == ["failure_kind=Refused", "payload_kind=file_path"])
  }

  @Test(arguments: [
    (InstallError.httpStatus(url: url, statusCode: 500), "http_status"),
    (InstallError.transferFailed(url: url, underlying: Refused()), "transfer_failed"),
    (InstallError.notAnHTTPResponse(url: url), "not_an_http_response"),
    (InstallError.extractionFailed(underlying: Refused()), "extraction_failed"),
    (InstallError.noInstallableBundle(inDirectory: "/tmp/x", underlying: Refused()), "no_installable_bundle"),
  ])
  func installErrorsAreNamedByCase(error: InstallError, kind: String) {
    #expect(InstallTelemetry.kind(of: error) == kind)
  }
}
