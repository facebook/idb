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
    telemetry.observe(.installStarted(timing: timing(seconds: 0), artifactPath: "/tmp/x/A.app"))
    telemetry.observe(.installCompleted(timing: timing(seconds: 40), artifactPath: "/tmp/x/A.app", name: "com.a"))

    #expect(columns(of: telemetry) == ["size=4096", "extract_ms=30000", "install_ms=40000", "payload_kind=url", "receive_ms=20000"])
  }

  @Test func aStreamedPayloadReportsWhatWasReceived() async {
    let telemetry = InstallTelemetry(payloadKind: .data)
    await telemetry.receive { receive in
      receive.count(Data(count: 10))
      receive.count(Data(count: 22))
    }

    let call = CallTelemetry()
    telemetry.record(into: call)
    #expect(call.size == 32)
    #expect(call.ints["receive_ms"] != nil)
    #expect(call.normals == ["payload_kind": "data"])
  }

  @Test(arguments: [
    (InstallStreamFormat.zip, "zip"),
    (.zstdZip, "zip_zstd"),
    (InstallStreamFormat(tarCompression: .GZIP), "tar_gzip"),
    (InstallStreamFormat(tarCompression: .ZSTD), "tar_zstd"),
  ])
  func aStreamedAppReportsItsFormat(format: InstallStreamFormat, column: String) {
    let telemetry = InstallTelemetry(payloadKind: .data)
    telemetry.streamed(format)

    #expect(columns(of: telemetry) == ["payload_kind=data", "stream_format=\(column)"])
  }

  @Test(arguments: [
    (ExtractionRoute(format: .gzip, extractor: .inProcessTar), ["extractor=tar_inprocess", "stream_format=tar_gzip"]),
    (ExtractionRoute(format: .other, extractor: .inProcessTar), ["extractor=tar_inprocess", "stream_format=tar"]),
    (ExtractionRoute(format: .zip, extractor: .zipStream), ["extractor=zip_stream", "stream_format=zip", "zip_spool_fallback=0"]),
    (ExtractionRoute(format: .zstdZip, extractor: .zipSpool), ["extractor=zip_spool", "stream_format=zip_zstd", "zip_spool_fallback=1"]),
  ])
  func aDownloadedAppReportsTheFormatItsFirstBytesNamedAndItsExtractor(route: ExtractionRoute, routeColumns: [String]) {
    let telemetry = InstallTelemetry(payloadKind: .url)
    telemetry.staged(.route(route))

    #expect(columns(of: telemetry) == (routeColumns + ["payload_kind=url"]).sorted())
  }

  @Test func aStreamedAppKeepsTheFormatItsClientDeclared() {
    let telemetry = InstallTelemetry(payloadKind: .data)
    telemetry.streamed(InstallStreamFormat(tarCompression: .ZSTD))
    telemetry.staged(.route(ExtractionRoute(format: .undetermined, extractor: .inProcessTar)))

    #expect(columns(of: telemetry) == ["extractor=tar_inprocess", "payload_kind=data", "stream_format=tar_zstd"])
  }

  @Test func aLocalPathReportsOnlyItsKindAndStages() {
    let telemetry = InstallTelemetry(payloadKind: .filePath)
    telemetry.observe(.installStarted(timing: timing(seconds: 0), artifactPath: "/a/A.app"))
    telemetry.observe(.installCompleted(timing: timing(seconds: 7), artifactPath: "/a/A.app", name: "com.a"))

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
    telemetry.observe(.installStarted(timing: timing(seconds: 0), artifactPath: "/a/A.app"))
    telemetry.failed(Refused())

    #expect(columns(of: telemetry) == ["failure_kind=Refused", "failure_stage=install", "payload_kind=file_path"])
  }

  @Test func aStreamThatFailsBeforeAnyStageFailedWhileReceiving() async {
    let telemetry = InstallTelemetry(payloadKind: .data)
    await #expect(throws: Refused.self) {
      try await telemetry.receive { _ in throw Refused() }
    }
    telemetry.failed(Refused())

    let call = CallTelemetry()
    telemetry.record(into: call)
    #expect(call.size == 0)
    #expect(call.normals == ["failure_kind": "Refused", "failure_stage": "receive", "payload_kind": "data"])
  }

  @Test func aStreamThatFailsPartwayReportsWhatItReceivedAndFailedWhileReceiving() async {
    let telemetry = InstallTelemetry(payloadKind: .data)
    await #expect(throws: Refused.self) {
      try await telemetry.receive { receive in
        receive.count(Data(count: 10))
        throw Refused()
      }
    }
    telemetry.failed(Refused())

    let call = CallTelemetry()
    telemetry.record(into: call)
    #expect(call.size == 10)
    #expect(call.ints["receive_ms"] != nil)
    #expect(call.normals == ["failure_kind": "Refused", "failure_stage": "receive", "payload_kind": "data"])
  }

  @Test func aFailureOutsideAnyStageHasNoStage() {
    let telemetry = InstallTelemetry(payloadKind: .filePath)
    telemetry.failed(Refused())

    #expect(columns(of: telemetry) == ["failure_kind=Refused", "payload_kind=file_path"])
  }

  @Test func aFailureOnceTheCallIsCancelledReportsTheClientAsItsCancelSource() async {
    let telemetry = InstallTelemetry(payloadKind: .url)
    telemetry.observe(.downloadStarted(timing: timing(seconds: 0), url: url))
    await Task {
      withUnsafeCurrentTask { $0?.cancel() }
      telemetry.failed(InstallError.transferFailed(url: url, underlying: URLError(.networkConnectionLost)))
    }.value

    #expect(
      columns(of: telemetry) == [
        "size=0", "cancel_source=client", "failure_kind=transfer_failed", "failure_stage=download", "ns_error_code=NSURLErrorDomain:-1005",
        "payload_kind=url",
      ])
  }

  @Test func aFailureOnceTheRPCIsCancelledReportsTheClientAsItsCancelSource() {
    let telemetry = InstallTelemetry(payloadKind: .url)
    telemetry.observe(.downloadStarted(timing: timing(seconds: 0), url: url))
    telemetry.failed(InstallError.transferFailed(url: url, underlying: URLError(.networkConnectionLost)), rpcCancelled: true)

    let call = CallTelemetry()
    telemetry.record(into: call)
    #expect(call.normals["cancel_source"] == "client")
  }

  @Test func aTLSFailureReportsItsErrorsTrustAndChainButNothingOfTheURL() {
    let cause = NSError(domain: kCFErrorDomainCFNetwork as String, code: -1200, userInfo: ["_kCFStreamErrorCodeKey": -9807])
    let failure = NSError(
      domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed,
      userInfo: [NSUnderlyingErrorKey: cause, "_kCFStreamErrorCodeKey": -9807, NSURLErrorFailingURLErrorKey: url])
    let report = DownloadReport(
      receivedBytes: 0, remoteAddress: "192.0.2.1:443", proxied: false,
      trust: DownloadReport.Trust(
        error: "“idb.test” certificate is not trusted",
        chain: [
          DownloadReport.Certificate(subject: "idb.test", issuer: "idb test root", notAfter: Date(timeIntervalSince1970: 1_577_836_800)),
          DownloadReport.Certificate(subject: "idb test root", issuer: nil, notAfter: nil),
        ]))
    let telemetry = InstallTelemetry(payloadKind: .url)
    telemetry.observe(.downloadStarted(timing: timing(seconds: 0), url: url))
    telemetry.failed(InstallError.transferFailed(url: url, underlying: failure, report: report))

    #expect(
      columns(of: telemetry) == [
        "size=0",
        "cf_stream_error_code=-9807",
        "failure_kind=transfer_failed",
        "failure_stage=download",
        "ns_error_code=NSURLErrorDomain:-1200",
        "ns_underlying_error=kCFErrorDomainCFNetwork:-1200",
        "payload_kind=url",
        "proxy_used=0",
        "remote_address=192.0.2.1:443",
        #"tls_chain=[{"issuer":"idb test root","not_after":"2020-01-01T00:00:00Z","subject":"idb.test"},{"subject":"idb test root"}]"#,
        "tls_trust_error=“idb.test” certificate is not trusted",
      ])
  }

  @Test func aDownloadThatFailsPartWayReportsWhatItReceived() {
    let telemetry = InstallTelemetry(payloadKind: .url)
    telemetry.observe(.downloadStarted(timing: timing(seconds: 0), url: url))
    telemetry.failed(
      InstallError.transferFailed(url: url, underlying: URLError(.networkConnectionLost), report: DownloadReport(receivedBytes: 4096, proxied: true)))

    let call = CallTelemetry()
    telemetry.record(into: call)
    #expect(call.size == 4096)
    #expect(call.ints["proxy_used"] == 1)
    #expect(call.normals["tls_chain"] == nil)
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
