// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

/// Reads sitevar value from interngraph via http request.
/// Batch sitevar request is not implemented.
/// To use that reader you should create and FB application using https://www.internalfb.com/intern/wiki/XcontrollerGuide/XInternGraphController/#creating-an-app-id-and-t
@available(macOSApplicationExtension 10.15, *)
public final class SitevarReader {

  private let reader: InternGraphCachableReader<FBApplicationBasedSitevarRequestor>

  /// Provide appID and token from FB application. To obtain follow [this insctructions](https://www.internalfb.com/intern/wiki/XcontrollerGuide/XInternGraphController/#creating-an-app-id-and-t)
  /// - Parameters:
  ///   - appID: FB application identifier
  ///   - token: Generated token
  ///   - cacheInvalidationInterval: Sets cache lifetime
  ///   - sessionConfiguration: Controls setup for network calls. Default one sets request timeout to 15 seconds
  public init(
    appID: String, token: String,
    baseURL: String = DefaultConfiguration.baseURL,
    cacheInvalidationInterval: TimeInterval = DefaultConfiguration.cacheInvalidationInterval,
    sessionConfiguration: URLSessionConfiguration = DefaultConfiguration.urlSessionConfiguration
  ) {

    let session = URLSession(configuration: sessionConfiguration)
    self.reader = .init(
      cacheInvalidationInterval: cacheInvalidationInterval,
      internGraphRequestor: FBApplicationBasedSitevarRequestor(appID: appID, token: token, baseURL: baseURL, urlSession: session))
  }

  /// Reads and caches sitevar value.
  ///
  /// - Parameters:
  ///   - sitevarName: Your fancy name of the sitevar
  ///   - decoder: Decoder to use to unmap server response
  ///   - default: value to use on network error
  /// - Returns: Sitevar value
  /// - Throws: FBInternGraphError on incorrect library usage or implementation or DecodingError. Network/server errors do *not* throw an error but uses `defaultValue`
  public func read<Sitevar: Decodable & Sendable>(name sitevarName: String, decoder: JSONDecoder, `default` defaultValue: Sitevar) async throws -> Sitevar {
    try await reader.readWithCache(request: sitevarName, decoder: decoder, defaultValue: defaultValue)
  }
}
