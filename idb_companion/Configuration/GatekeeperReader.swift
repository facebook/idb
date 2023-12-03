// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

/// Reads gatekeeper value from interngraph via http request.
/// Batch gatekeeper request is not implemented.
/// To use that reader you should create and FB application using https://www.internalfb.com/intern/wiki/XcontrollerGuide/XInternGraphController/#creating-an-app-id-and-t
@available(macOSApplicationExtension 10.15, *)
public final class GatekeeperReader {

  private let reader: InternGraphCachableReader<FBApplicationBasedGatekeeperRequestor>
  private let decoder: JSONDecoder

  /// Provide appID and token from FB application. To obtain follow [this insctructions](https://www.internalfb.com/intern/wiki/XcontrollerGuide/XInternGraphController/#creating-an-app-id-and-t)
  /// - Parameters:
  ///   - appID: FB application identifier
  ///   - token: Generated token
  ///   - cacheInvalidationInterval: Sets cache lifetime
  ///   - sessionConfiguration: Controls setup for network calls. Default one sets request timeout to 15 seconds
  public init(appID: String, token: String,
              baseURL: String = DefaultConfiguration.baseURL,
              cacheInvalidationInterval: TimeInterval = DefaultConfiguration.cacheInvalidationInterval,
              sessionConfiguration: URLSessionConfiguration = DefaultConfiguration.urlSessionConfiguration) {

    let session = URLSession(configuration: sessionConfiguration)
    self.reader = .init(cacheInvalidationInterval: cacheInvalidationInterval,
                        internGraphRequestor: FBApplicationBasedGatekeeperRequestor(appID: appID, token: token, baseURL: baseURL, urlSession: session))
    self.decoder = JSONDecoder()
  }

  /// Reads and caches gatekeeper value.
  ///
  /// - Parameters:
  ///   - sitevarName: Your fancy name of the gatekeeper
  ///   - default: value to use on network error
  /// - Returns: Sitevar value
  /// - Throws: FBInternGraphError on incorrect library usage or implementation. Network/server errors do *not* throw an error but uses `defaultValue`
  public func read(name: String, unixname: String, `default` defaultValue: Bool) async throws -> Bool {
    do {
      let request = GatekeeperRequest(unixname: unixname, gatekeeperName: name)
      return try await reader.readWithCache(request: request, decoder: decoder, defaultValue: defaultValue)
    } catch is DecodingError {
      assertionFailure("We should not receive DecodingError in that reader, because it is library-internal and not configured by user. Check server implemenation. Most likely simething changed")
      return defaultValue
    } catch {
      throw error
    }
  }
}
