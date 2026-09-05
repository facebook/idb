/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public final class FBDataDownloadInput: NSObject, @unchecked Sendable {

  public let input: FBProcessInput<AnyObject>

  /// Waits for the transfer to finish, throwing if the server rejected the request or the connection
  /// dropped. `input` alone cannot distinguish a failed download from a short one.
  public func completed() async throws {
    _ = try await bridgeFBFuture(completedFuture)
  }

  private let completedFuture: FBMutableFuture<NSNull>
  private let logger: FBControlCoreLogger

  public static func dataDownload(withURL url: URL, logger: FBControlCoreLogger) -> FBDataDownloadInput {
    return dataDownload(withURL: url, configuration: .default, logger: logger)
  }

  /// Downloads over a caller-supplied session configuration, so that timeouts,
  /// caching policy and protocol handling are the caller's to decide.
  public static func dataDownload(withURL url: URL, configuration: URLSessionConfiguration, logger: FBControlCoreLogger) -> FBDataDownloadInput {
    let download = FBDataDownloadInput(logger: logger)
    download.startDownload(from: url, configuration: configuration)
    return download
  }

  private init(logger: FBControlCoreLogger) {
    self.logger = logger
    self.completedFuture = FBMutableFuture<NSNull>()
    let rawInput = FBProcessInput<NSObject>.fromConsumer()
    self.input = unsafeBitCast(rawInput, to: FBProcessInput<AnyObject>.self)
    super.init()
  }

  // The session holds both the delegate and the resumed task for the lifetime of the download, so neither needs storing here.
  private func startDownload(from url: URL, configuration: URLSessionConfiguration) {
    let delegateQueue = OperationQueue()
    delegateQueue.name = "CompanionLib.FBDataDownloadInput.urlSessionDelegate"
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    session.dataTask(with: url).resume()
  }
}

// MARK: - URLSessionDataDelegate

extension FBDataDownloadInput: URLSessionDataDelegate {

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard let httpResponse = response as? HTTPURLResponse else {
      completionHandler(.allow)
      return
    }
    guard httpResponse.statusCode == 200 else {
      // Without this the body of an error page is piped onward as though it were
      // the payload, and the caller is told it has a malformed archive.
      let error = FBInstallError.httpStatus(
        url: dataTask.originalRequest?.url ?? httpResponse.url,
        statusCode: httpResponse.statusCode)
      logger.error().log(error.description)
      completedFuture.resolveWithError(error)
      completionHandler(.cancel)
      return
    }
    completionHandler(.allow)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    (input.contents as? FBDataConsumer)?.consumeData(data)
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error {
      logger.error().log("Download task \(task) failed with error \(error)")
      // First resolution wins, so a cancellation triggered by a rejected response
      // does not displace the HTTP status that caused it.
      completedFuture.resolveWithError(
        FBInstallError.transferFailed(url: task.originalRequest?.url, underlying: error))
    } else {
      _ = completedFuture.resolve(withResult: NSNull())
    }
    (input.contents as? FBDataConsumer)?.consumeEndOfFile()
  }
}
