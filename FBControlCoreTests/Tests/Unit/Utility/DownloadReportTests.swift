/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Security
import XCTest

/// A leaf for `idb.test` that expired at the start of 2020, issued by a root no host trusts.
private let leaf = "MIIBmDCCAT+gAwIBAgIUf5MbB8df1yjj/mm6ZNs5iKDsIMgwCgYIKoZIzj0EAwIwGDEWMBQGA1UEAwwNaWRiIHRlc3Qgcm9vdDAeFw0xOTAxMDEwMDAwMDBaFw0yMDAxMDEwMDAwMDBaMBMxETAPBgNVBAMMCGlkYi50ZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEWOW1JDIKhQka0u/3iYf+1mOZ6MO60VS8sR6Je1s8AFIqwZVT1dJBHJZi6ZMQSeiufAsAObYYw2HFKewEt1IEMqNsMGowEwYDVR0RBAwwCoIIaWRiLnRlc3QwEwYDVR0lBAwwCgYIKwYBBQUHAwEwHQYDVR0OBBYEFMYdOyTr0V1tBu36jKtYrruKZ64CMB8GA1UdIwQYMBaAFLGAadq3gOc3GhKvIIULnioUDJ0LMAoGCCqGSM49BAMCA0cAMEQCIBsgyBvPSTEHieCkDaT6HDWWgoFihT+y7RZxTR0Z+1eiAiBCsPECzKRgxPHtwPh1LDOdyUT4dPZ0hx0iPdR1UTrYiA=="
private let root = "MIIBhDCCASugAwIBAgIUeUl6bSZSDGhznsk6ZHIGIyGn7rkwCgYIKoZIzj0EAwIwGDEWMBQGA1UEAwwNaWRiIHRlc3Qgcm9vdDAeFw0xOTAxMDEwMDAwMDBaFw00MDAxMDEwMDAwMDBaMBgxFjAUBgNVBAMMDWlkYiB0ZXN0IHJvb3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASzOioj5VFzqQZ924JDcID2ZS9KEyg7qW+BoPvaNAPlKRd+3m0xWQ7Zwju7nsFWrWFG7fEUa0ju3kiBMZnRJXXxo1MwUTAdBgNVHQ4EFgQUsYBp2reA5zcaEq8ghQueKhQMnQswHwYDVR0jBBgwFoAUsYBp2reA5zcaEq8ghQueKhQMnQswDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNHADBEAiACwSE54/tGEudDuolSRb+RswW2qu0gf/dZGZUY+51oGwIgEj5+/Gqdf10XMJyOzQkxG5lCHr5MOqQsuiIUiR0U2Zs="

private func untrustedTrust() throws -> SecTrust {
  let certificates = try [leaf, root].map { encoded in
    try XCTUnwrap(Data(base64Encoded: encoded).flatMap { SecCertificateCreateWithData(nil, $0 as CFData) })
  }
  var trust: SecTrust?
  XCTAssertEqual(SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateSSL(true, "idb.test" as CFString), &trust), errSecSuccess)
  return try XCTUnwrap(trust)
}

final class DownloadReportTests: XCTestCase {

  func testAnUntrustedChainReportsWhyAndEachCertificateItPresented() throws {
    let trust = DownloadReport.Trust(evaluating: try untrustedTrust())

    XCTAssertNotNil(trust.error)
    XCTAssertEqual(
      trust.chain,
      [
        DownloadReport.Certificate(subject: "idb.test", issuer: "idb test root", notAfter: Date(timeIntervalSince1970: 1_577_836_800)),
        DownloadReport.Certificate(subject: "idb test root", issuer: "idb test root", notAfter: Date(timeIntervalSince1970: 2_208_988_800)),
      ])
  }

  func testATLSFailureIsEvaluatedFromThePeerTrustItCarries() throws {
    let failure = NSError(
      domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed,
      userInfo: [NSURLErrorFailingURLPeerTrustErrorKey: try untrustedTrust()])

    XCTAssertEqual(DownloadReport.Trust.evaluating(failure: failure)?.chain.map(\.subject), ["idb.test", "idb test root"])
  }

  func testAFailureWithoutAPeerTrustHasNoTrust() {
    XCTAssertNil(DownloadReport.Trust.evaluating(failure: URLError(.networkConnectionLost)))
  }
}
