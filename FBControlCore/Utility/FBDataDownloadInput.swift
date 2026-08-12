/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public final class FBDataDownloadInput: NSObject, @unchecked Sendable {

  public let input: FBProcessInput<AnyObject>

  /// Waits for the transfer to finish, throwing if the server rejected the
  /// request or the connection dropped.
  ///
  /// A data consumer carries only bytes and an end of file, so a failed download
  /// is indistinguishable from a short one on `input` alone -- a caller that
  /// needs to tell them apart awaits this. It is deliberately not `@objc`: the
  /// future underneath is an implementation detail, and every caller is Swift.
  public func completed() async throws {
    _ = try await bridgeFBFuture(completedFuture)
  }

  private let completedFuture: FBMutableFuture<NSNull>
  private var urlSessionTask: URLSessionTask!
  private let logger: FBControlCoreLogger

  public static func dataDownload(withURL url: URL, logger: FBControlCoreLogger) -> FBDataDownloadInput {
    return dataDownload(withURL: url, configuration: .default, logger: logger)
  }

  /// Downloads over a caller-supplied session configuration, so that timeouts,
  /// caching policy and protocol handling are the caller's to decide.
  public static func dataDownload(withURL url: URL, configuration: URLSessionConfiguration, logger: FBControlCoreLogger) -> FBDataDownloadInput {
    let download = FBDataDownloadInput(url: url, configuration: configuration, logger: logger)
    download.urlSessionTask.resume()
    return download
  }

  private init(url: URL, configuration: URLSessionConfiguration, logger: FBControlCoreLogger) {
    self.logger = logger
    self.completedFuture = FBMutableFuture<NSNull>()
    let rawInput = FBProcessInput<NSObject>.fromConsumer()
    self.input = unsafeBitCast(rawInput, to: FBProcessInput<AnyObject>.self)
    super.init()
    let delegateQueue = OperationQueue()
    delegateQueue.name = "CompanionLib.FBDataDownloadInput.urlSessionDelegate"
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    self.urlSessionTask = session.dataTask(with: url)
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
