/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBArtifactStaging
import FBControlCore
import Foundation

/// Why a download failed, in columns that tell a host's trust store apart from the certificate a server
/// presented or the path the request took. Nothing from the URL is recorded, as its query carries signatures.
struct DownloadFailureDetail: Equatable {

  let errorCode: String
  let underlyingError: String?
  let streamErrorCode: Int?
  let report: DownloadReport

  init(underlying: Error, report: DownloadReport) {
    let error = underlying as NSError
    let cause = error.userInfo[NSUnderlyingErrorKey] as? NSError
    errorCode = Self.name(error)
    underlyingError = cause.map(Self.name)
    streamErrorCode = (error.userInfo["_kCFStreamErrorCodeKey"] ?? cause?.userInfo["_kCFStreamErrorCodeKey"]) as? Int
    self.report = report
  }

  func record(into call: CallTelemetry) {
    call.setNormal(errorCode, forKey: "ns_error_code")
    if let underlyingError {
      call.setNormal(underlyingError, forKey: "ns_underlying_error")
    }
    if let streamErrorCode {
      call.setInt(streamErrorCode, forKey: "cf_stream_error_code")
    }
    if let remoteAddress = report.remoteAddress {
      call.setNormal(remoteAddress, forKey: "remote_address")
    }
    if let proxied = report.proxied {
      call.setInt(proxied ? 1 : 0, forKey: "proxy_used")
    }
    guard let trust = report.trust else {
      return
    }
    if let error = trust.error {
      call.setNormal(error, forKey: "tls_trust_error")
    }
    call.setNormal(Self.chainDescription(trust.chain), forKey: "tls_chain")
  }

  private static func name(_ error: NSError) -> String {
    "\(error.domain):\(error.code)"
  }

  /// A JSON array, leaf first, so the chain can be queried without splitting on names that contain separators.
  static func chainDescription(_ chain: [DownloadReport.Certificate]) -> String {
    let formatter = ISO8601DateFormatter()
    let certificates = chain.map { certificate in
      var fields: [String: String] = [:]
      fields["subject"] = certificate.subject
      fields["issuer"] = certificate.issuer
      fields["not_after"] = certificate.notAfter.map(formatter.string(from:))
      return fields
    }
    guard let data = try? JSONSerialization.data(withJSONObject: certificates, options: [.sortedKeys, .withoutEscapingSlashes]) else {
      return "[]"
    }
    return String(decoding: data, as: UTF8.self)
  }
}
