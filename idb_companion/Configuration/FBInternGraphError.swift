// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

/// Possible errors of incorrect library implementation or usage. This should be explicitly handled by client and fixed.
public enum FBInternGraphError: Error, LocalizedError {
  case failToFormURLRequest
  case inconsistentSitevarTypes

  public var errorDescription: String? {
    switch self {
    case .failToFormURLRequest:
      return "\(FBInternGraphError.self): failed to form URL request. Most likely you provide incorrect baseURL"
    case .inconsistentSitevarTypes:
      return "\(FBInternGraphError.self): received request, found cached response, but types mismatched. Usage of different types for same entity name is not supported"
    }
  }
}

/// Internal library error that should not be propagated to user directly.
/// The cause is unobvious so we will just user `defaultValue` of request. Most likely some configuration or netwokring problems
enum FBInternGraphInternalError: Error, CustomStringConvertible {
  case sitevarNotFoundInResult
  case notReceiveErrorOrData
  case inacceptableStatusCode(String)

  var description: String {
    switch self {
    case .notReceiveErrorOrData:
      return "\(FBInternGraphInternalError.self): not received error or data from request. This is internal library error that should never happen"
    case .sitevarNotFoundInResult:
      return "\(FBInternGraphInternalError.self): sitevar not found in result. Most likely you provide incorrect input parameters"
    case .inacceptableStatusCode(let output):
      return "\(FBInternGraphInternalError.self): received inacceptable status code from server. Most likely appID or token is incorrect. Output: \(output)"
    }
  }
}
