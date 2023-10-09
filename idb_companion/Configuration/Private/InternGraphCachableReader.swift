// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

@available(macOSApplicationExtension 10.15, *)
actor InternGraphCachableReader<Requestor: InternGraphRequestor> {

  private let internGraphRequestor: Requestor

  private var ongoingTasks: [Requestor.Request: Task<any Sendable, Error>] = [:]
  private var cachedValues: [Requestor.Request: (lastSyncDate: Date, value: any Sendable)] = [:]

  private let cacheInvalidationInterval: TimeInterval

  init(cacheInvalidationInterval: TimeInterval, internGraphRequestor: Requestor) {
    self.cacheInvalidationInterval = cacheInvalidationInterval
    self.internGraphRequestor = internGraphRequestor
  }

  func readWithCache<FetchResult: Decodable & Sendable>(request: Requestor.Request, decoder: JSONDecoder, defaultValue: FetchResult) async throws -> FetchResult {
    if let ongoingFetchTask = ongoingTasks[request] {
      let taskResult = try await ongoingFetchTask.value
      guard let typedResult = taskResult as? FetchResult else {
        throw FBInternGraphError.inconsistentSitevarTypes
      }
      return typedResult
    }
    if let cachedResult = cachedValues[request], Date().timeIntervalSince(cachedResult.lastSyncDate) < cacheInvalidationInterval {
      guard let typedResult = cachedResult.value as? FetchResult else {
        throw FBInternGraphError.inconsistentSitevarTypes
      }
      return typedResult
    }
    return try await fetchConfig(request: request, decoder: decoder, defaultValue: defaultValue)
  }

  // swiftlint:disable force_cast
  private func fetchConfig<FetchResult: Decodable & Sendable>(request: Requestor.Request, decoder: JSONDecoder, defaultValue: FetchResult) async throws -> FetchResult {
    let getInterngraphValueTask = Task<any Sendable, Error> {
      defer { ongoingTasks.removeValue(forKey: request) }

      do {
        let fetchResult: FetchResult = try await internGraphRequestor.read(request: request, decoder: decoder)
        cachedValues[request] = (lastSyncDate: Date(), value: fetchResult)

        return fetchResult
      } catch let error as FBInternGraphError {
        throw error
      } catch {
        return defaultValue
      }
    }
    ongoingTasks[request] = getInterngraphValueTask

    return try await getInterngraphValueTask.value as! FetchResult
  }
}
