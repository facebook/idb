/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Everything that can go wrong fetching and unpacking an application.
///
/// A caller deciding what to do about a failure -- retry the fetch, report a bad
/// URL, tell the user their archive is empty -- matches on a case rather than on
/// the text of a message.
public enum FBInstallError: Error, CustomStringConvertible {

  /// The server answered, and refused.
  case httpStatus(url: URL?, statusCode: Int)

  /// The transfer did not finish.
  case transferFailed(url: URL?, underlying: Error)

  /// The response was not HTTP at all, so there is no status to report.
  case notAnHTTPResponse(url: URL)

  public var description: String {
    switch self {
    case .httpStatus(let url, let statusCode):
      let target = url.map { " of \($0.absoluteString)" } ?? ""
      return "Download\(target) failed with HTTP status \(statusCode)"
    case .transferFailed(let url, let underlying):
      let target = url.map { " of \($0.absoluteString)" } ?? ""
      return "Download\(target) did not complete: \(underlying)"
    case .notAnHTTPResponse(let url):
      return "Download of \(url.absoluteString) got a non-HTTP response"
    }
  }
}

// MARK: - Bridging

extension FBInstallError: CustomNSError {

  public static var errorDomain: String { "com.facebook.FBControlCore.install" }

  /// Carries the description across the Objective-C and gRPC boundaries, both of
  /// which report `localizedDescription` rather than the Swift error.
  public var errorUserInfo: [String: Any] {
    [NSLocalizedDescriptionKey: description]
  }
}
