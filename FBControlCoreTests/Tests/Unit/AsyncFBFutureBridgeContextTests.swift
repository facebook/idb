/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Records whether the awaiting task has returned, so the test can distinguish "still awaiting
/// teardown" from "returned with teardown in flight".
private actor Completion {
  var isComplete = false
  func complete() {
    isComplete = true
  }
}

@Suite("withFBFutureContext teardown")
struct AsyncFBFutureBridgeContextTests {

  /// A context whose teardown finishes only when the returned future is resolved, so the moment
  /// teardown completes is controlled by the test rather than by timing.
  private func gatedContext(gate: FBMutableFuture<NSNull>) -> FBFutureContext<NSString> {
    let resource: NSString = "resource"
    return FBFuture(result: resource)
      .onQueue(
        DispatchQueue.global(),
        contextualTeardown: { (_: NSString, _: FBFutureState) -> FBFuture<NSNull> in
          convertFBMutableFuture(gate)
        })
  }

  @Test("The resource is delivered to the body and its value returned")
  func deliversTheResource() async throws {
    let gate = FBMutableFuture<NSNull>()
    nonisolated(unsafe) let context = gatedContext(gate: gate)
    let task = Task { try await withFBFutureContext(context) { $0 as String } }
    gate.resolve(withResult: NSNull())
    #expect(try await task.value == "resource")
  }

  @Test("The future from pop: does not resolve before the teardown has completed")
  func popAwaitsTeardown() async throws {
    let gate = FBMutableFuture<NSNull>()
    nonisolated(unsafe) let context = gatedContext(gate: gate)
    let popped = context.onQueue(
      DispatchQueue.global(),
      pop: { (_: NSString) -> FBFuture<AnyObject> in
        FBFuture(result: NSNull())
      })
    let completion = Completion()

    let task = Task {
      _ = try await bridgeFBFuture(popped)
      await completion.complete()
    }

    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(await completion.isComplete == false)

    gate.resolve(withResult: NSNull())
    try await task.value
  }

  @Test("The call does not outlive the context's teardown")
  func awaitsTeardownBeforeReturning() async throws {
    let gate = FBMutableFuture<NSNull>()
    nonisolated(unsafe) let context = gatedContext(gate: gate)
    let completion = Completion()

    let task = Task {
      let value = try await withFBFutureContext(context) { $0 as String }
      await completion.complete()
      return value
    }

    // Long enough for the body to have run and the teardown to have been triggered.
    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(await completion.isComplete == false)

    gate.resolve(withResult: NSNull())
    #expect(try await task.value == "resource")
  }
}
