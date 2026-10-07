/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import Testing

@Suite
struct AsyncFBFutureBridgeTests {

  @Test
  func aSuccessfulFutureBridgesToItsValue() async throws {
    let expected = "hello" as NSString
    let future = FBFuture<NSString>(result: expected)

    #expect(try await bridgeFBFuture(future) == expected)
  }

  @Test
  func aFailedFutureBridgesToItsError() async {
    let future = FBFuture<NSString>(error: NSError(domain: "test", code: 42))

    do {
      _ = try await bridgeFBFuture(future)
      Issue.record("Expected error")
    } catch {
      #expect((error as NSError).domain == "test")
      #expect((error as NSError).code == 42)
    }
  }

  @Test
  func aFutureResolvedLaterBridgesToItsValue() async throws {
    let mutableFuture = FBMutableFuture<NSString>()
    let future = convertFBMutableFuture(mutableFuture)
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
      mutableFuture.resolve(withResult: "delayed" as NSString)
    }

    #expect(try await bridgeFBFuture(future) == "delayed" as NSString)
  }

  @Test
  func aSuccessfulNullFutureBridgesToVoid() async throws {
    try await bridgeFBFutureVoid(FBFuture<NSNull>(result: NSNull()))
  }

  @Test
  func aFailedNullFutureBridgesToItsError() async {
    do {
      try await bridgeFBFutureVoid(FBFuture<NSNull>(error: NSError(domain: "test", code: 1)))
      Issue.record("Expected error")
    } catch {
      #expect((error as NSError).code == 1)
    }
  }

  @Test
  func aConvertedMutableFutureResolvesWithIt() async throws {
    let mutableFuture = FBMutableFuture<NSString>()
    let future = convertFBMutableFuture(mutableFuture)
    mutableFuture.resolve(withResult: "resolved" as NSString)

    #expect(try await bridgeFBFuture(future) == "resolved" as NSString)
  }

  @Test
  func aConvertedMutableFutureFailsWithIt() async {
    let mutableFuture = FBMutableFuture<NSString>()
    let future = convertFBMutableFuture(mutableFuture)
    mutableFuture.resolveWithError(NSError(domain: "test", code: 77))

    do {
      _ = try await bridgeFBFuture(future)
      Issue.record("Expected error")
    } catch {
      #expect((error as NSError).code == 77)
    }
  }
}
