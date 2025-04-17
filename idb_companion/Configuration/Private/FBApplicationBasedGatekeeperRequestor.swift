// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

struct GatekeeperRequest: Hashable {
  let unixname: String
  let gatekeeperName: String
}

/// Fetches values from `XInternGraphEmployeeGKController.php`
@available(macOSApplicationExtension 10.15, *)
final class FBApplicationBasedGatekeeperRequestor: InternGraphRequestor {

  private let appID: String
  private let token: String
  private let baseURL: String
  private let urlSession: URLSession

  init(appID: String, token: String, baseURL: String, urlSession: URLSession) {
    self.appID = appID
    self.token = token
    self.baseURL = baseURL
    self.urlSession = urlSession
  }

  func read<FetchResult: Decodable>(request: GatekeeperRequest, decoder: JSONDecoder) async throws -> FetchResult {
    let data = try await withCheckedThrowingContinuation { continuation in
      performRequest(request: request) { result in
        continuation.resume(with: result)
      }
    }
    let gkBatch = try decoder.decode([String: FetchResult].self, from: data)
    guard let gkResult = gkBatch[request.gatekeeperName] else {
      throw FBInternGraphInternalError.sitevarNotFoundInResult
    }
    return gkResult
  }

  private func performRequest(request: GatekeeperRequest, handler: @escaping @Sendable (Result<Data, Error>) -> Void) {
    let queryItems = [
      URLQueryItem(name: "app", value: appID),
      URLQueryItem(name: "token", value: token),
      URLQueryItem(name: "unixname", value: request.unixname),
      URLQueryItem(name: "gk[]", value: request.gatekeeperName),
    ]

    guard var urlComps = URLComponents(string: "\(baseURL)/gk/check") else {
      assertionFailure("Incorrect URL components, should never happen")
      handler(.failure(FBInternGraphError.failToFormURLRequest))
      return
    }
    urlComps.queryItems = queryItems
    guard let sitevarURL = urlComps.url else {
      assertionFailure("Fail to formURL, should never happen")
      handler(.failure(FBInternGraphError.failToFormURLRequest))
      return
    }

    URLSession.shared.dataTask(
      with: .init(url: sitevarURL),
      completionHandler: { data, response, error in
        if let error {
          handler(.failure(error))
        } else if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
          let output = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Empty"
          handler(.failure(FBInternGraphInternalError.inacceptableStatusCode(output)))
        } else if let data {
          handler(.success(data))
        } else {
          handler(.failure(FBInternGraphInternalError.notReceiveErrorOrData))
        }
      }
    )
    .resume()
  }
}
