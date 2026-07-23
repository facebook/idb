@testable import FBSimulatorControl
import Foundation
import Synchronization
import Testing

private enum HIDBootIdentityTestError: Error {
  case processInspectionDenied
}

private enum HIDClientTestError: Error, Equatable {
  case sendFailed
}

/// A device double that, like `SimDevice`, exposes an Objective-C visible `lastBootedAt` getter.
private final class HIDBootMetadataDeviceDouble: NSObject {
  @objc let lastBootedAt: Date

  init(lastBootedAt: Date) {
    self.lastBootedAt = lastBootedAt
  }
}

private final class HIDSessionDouble: @unchecked Sendable {
  let id: Int
  let invalidate: @Sendable () -> Void

  init(id: Int, invalidate: @escaping @Sendable () -> Void = {}) {
    self.id = id
    self.invalidate = invalidate
  }
}

private final class HIDSessionTestRecorder: Sendable {
  private let creationCount = Mutex(0)
  private let disconnectedIDs = Mutex<[Int]>([])

  func recordCreation() -> Int {
    creationCount.withLock { count in
      count += 1
      return count
    }
  }

  func recordDisconnection(_ session: HIDSessionDouble) {
    disconnectedIDs.withLock { $0.append(session.id) }
  }

  var creations: Int {
    creationCount.withLock { $0 }
  }

  var disconnections: [Int] {
    disconnectedIDs.withLock { $0 }
  }
}

private final class HIDClientTestRecorder: Sendable {
  private let invalidationCount = Mutex(0)
  private let disposalCount = Mutex(0)
  private let sendCount = Mutex(0)

  func recordInvalidation() {
    invalidationCount.withLock { $0 += 1 }
  }

  func recordSend() {
    sendCount.withLock { $0 += 1 }
  }

  func recordDisposal() {
    disposalCount.withLock { $0 += 1 }
  }

  var invalidations: Int {
    invalidationCount.withLock { $0 }
  }

  var sends: Int {
    sendCount.withLock { $0 }
  }

  var disposals: Int {
    disposalCount.withLock { $0 }
  }
}

private actor HIDSendCompletionHarness {
  typealias Completion = @Sendable (Error?) -> Void

  private var completions: [Completion] = []
  private var waiters: [CheckedContinuation<Completion, Never>] = []

  func enqueue(_ completion: @escaping Completion) {
    if waiters.isEmpty {
      completions.append(completion)
    } else {
      waiters.removeFirst().resume(returning: completion)
    }
  }

  func next() async -> Completion {
    if completions.isEmpty {
      return await withCheckedContinuation { continuation in
        waiters.append(continuation)
      }
    }
    return completions.removeFirst()
  }
}

@Suite
struct FBSimulatorHIDSessionCacheTests {
  private let firstBoot = FBSimulatorHIDBootIdentity(
    generation: .coreSimulatorLastBootedAt(
      Date(timeIntervalSinceReferenceDate: 1_000)
    )
  )
  private let secondBoot = FBSimulatorHIDBootIdentity(
    generation: .coreSimulatorLastBootedAt(
      Date(timeIntervalSinceReferenceDate: 2_000)
    )
  )

  @Test
  func reusedProcessIdentifierWithNewStartTimeIsANewBoot() {
    let first = FBSimulatorHIDBootIdentity(
      generation: .launchdProcess(
        processIdentifier: 100,
        startTimeMicroseconds: 1_000
      )
    )
    let reusedPID = FBSimulatorHIDBootIdentity(
      generation: .launchdProcess(
        processIdentifier: 100,
        startTimeMicroseconds: 2_000
      )
    )

    #expect(reusedPID != first)
  }

  @Test
  func coreSimulatorMetadataSucceedsWhenProcessInspectionIsDenied() throws {
    let lastBootedAt = Date(timeIntervalSinceReferenceDate: 1_000)

    let identity = try FBSimulatorHIDBootIdentityResolver.identity(
      lastBootedAt: lastBootedAt
    ) {
      throw HIDBootIdentityTestError.processInspectionDenied
    }

    #expect(
      identity == FBSimulatorHIDBootIdentity(
        generation: .coreSimulatorLastBootedAt(lastBootedAt)
      )
    )
  }

  @Test
  func deviceImplementingLastBootedAtProvidesBootDate() {
    let lastBootedAt = Date(timeIntervalSinceReferenceDate: 1_000)
    let device = HIDBootMetadataDeviceDouble(lastBootedAt: lastBootedAt)

    #expect(FBSimulatorHIDBootIdentityResolver.lastBootedAt(of: device) == lastBootedAt)
  }

  @Test
  func deviceMissingLastBootedAtSelectorRoutesToProcessFallback() {
    let fallback = FBSimulatorHIDBootIdentity(
      generation: .launchdProcess(
        processIdentifier: 100,
        startTimeMicroseconds: 1_000
      )
    )

    // NSObject has no `lastBootedAt` getter — the shape of a future CoreSimulator that removed the
    // private property. The guarded read must return nil instead of crashing, routing identity
    // resolution to the launchd_sim process fallback.
    let identity = FBSimulatorHIDBootIdentityResolver.identity(
      lastBootedAt: FBSimulatorHIDBootIdentityResolver.lastBootedAt(of: NSObject())
    ) {
      fallback
    }

    #expect(identity == fallback)
  }

  @Test
  func missingCoreSimulatorMetadataUsesExplicitProcessFallback() {
    let fallback = FBSimulatorHIDBootIdentity(
      generation: .launchdProcess(
        processIdentifier: 100,
        startTimeMicroseconds: 1_000
      )
    )

    let identity = FBSimulatorHIDBootIdentityResolver.identity(
      lastBootedAt: nil
    ) {
      fallback
    }

    #expect(identity == fallback)
  }

  @Test
  func changedCoreSimulatorBootDateIsANewBootWithSameProcess() {
    let first = FBSimulatorHIDBootIdentity(
      generation: .coreSimulatorLastBootedAt(
        Date(timeIntervalSinceReferenceDate: 1_000)
      )
    )
    let second = FBSimulatorHIDBootIdentity(
      generation: .coreSimulatorLastBootedAt(
        Date(timeIntervalSinceReferenceDate: 2_000)
      )
    )

    #expect(first != second)
  }

  @Test
  func sameBootReusesSession() throws {
    let recorder = HIDSessionTestRecorder()
    let cache = makeCache(recorder: recorder)

    let first = try cache.session(
      for: firstBoot,
      create: { _ in HIDSessionDouble(id: recorder.recordCreation()) },
      currentIdentity: { firstBoot }
    )
    let second = try cache.session(
      for: firstBoot,
      create: { _ in HIDSessionDouble(id: recorder.recordCreation()) },
      currentIdentity: { firstBoot }
    )

    #expect(first === second)
    #expect(recorder.creations == 1)
    #expect(recorder.disconnections.isEmpty)
  }

  @Test
  func newBootDisconnectsStaleSession() throws {
    let recorder = HIDSessionTestRecorder()
    let cache = makeCache(recorder: recorder)

    _ = try cache.session(
      for: firstBoot,
      create: { _ in HIDSessionDouble(id: recorder.recordCreation()) },
      currentIdentity: { firstBoot }
    )
    let second = try cache.session(
      for: secondBoot,
      create: { _ in HIDSessionDouble(id: recorder.recordCreation()) },
      currentIdentity: { secondBoot }
    )

    #expect(second.id == 2)
    #expect(recorder.disconnections == [1])
  }

  @Test
  func fastPathRevalidatesCurrentBoot() throws {
    let recorder = HIDSessionTestRecorder()
    let cache = makeCache(recorder: recorder)

    _ = try cache.session(
      for: firstBoot,
      create: { _ in HIDSessionDouble(id: recorder.recordCreation()) },
      currentIdentity: { firstBoot }
    )

    #expect(throws: FBSimulatorHIDSessionCacheError.bootChangedDuringConnection) {
      try cache.session(
        for: firstBoot,
        create: { _ in HIDSessionDouble(id: recorder.recordCreation()) },
        currentIdentity: { secondBoot }
      )
    }
    #expect(recorder.disconnections == [1])
  }

  @Test
  func bootChangeDuringConstructionRejectsSession() {
    let recorder = HIDSessionTestRecorder()
    let cache = makeCache(recorder: recorder)
    var identities = [firstBoot, secondBoot]

    #expect(throws: FBSimulatorHIDSessionCacheError.bootChangedDuringConnection) {
      try cache.session(
        for: firstBoot,
        create: { _ in HIDSessionDouble(id: recorder.recordCreation()) },
        currentIdentity: { identities.removeFirst() }
      )
    }
    #expect(recorder.creations == 1)
    #expect(recorder.disconnections == [1])
  }

  @Test
  func invalidateDisconnectsCachedSessionExactlyOnce() throws {
    let recorder = HIDSessionTestRecorder()
    let cache = makeCache(recorder: recorder)

    _ = try cache.session(
      for: firstBoot,
      create: { _ in HIDSessionDouble(id: recorder.recordCreation()) },
      currentIdentity: { firstBoot }
    )
    cache.invalidate()
    cache.invalidate()

    #expect(recorder.disconnections == [1])
  }

  @Test
  func staleConditionalInvalidationPreservesNewBootSession() throws {
    let recorder = HIDSessionTestRecorder()
    let cache = makeCache(recorder: recorder)

    _ = try cache.session(
      for: secondBoot,
      create: { _ in HIDSessionDouble(id: recorder.recordCreation()) },
      currentIdentity: { secondBoot }
    )
    cache.invalidate(ifMatching: firstBoot)

    #expect(cache.cachedIdentity == secondBoot)
    #expect(recorder.disconnections.isEmpty)
  }

  @Test
  func failedSessionIsRemovedAndNextRequestReconnects() throws {
    let recorder = HIDSessionTestRecorder()
    let cache = makeCache(recorder: recorder)
    let first = try cache.session(
      for: firstBoot,
      create: { invalidate in
        HIDSessionDouble(id: recorder.recordCreation(), invalidate: invalidate)
      },
      currentIdentity: { firstBoot }
    )

    first.invalidate()
    let replacement = try cache.session(
      for: firstBoot,
      create: { invalidate in
        HIDSessionDouble(id: recorder.recordCreation(), invalidate: invalidate)
      },
      currentIdentity: { firstBoot }
    )

    #expect(replacement !== first)
    #expect(replacement.id == 2)
    #expect(recorder.disconnections == [1])
  }

  @Test
  func delayedOldSessionFailurePreservesReplacementForSameBoot() throws {
    let recorder = HIDSessionTestRecorder()
    let cache = makeCache(recorder: recorder)
    let first = try cache.session(
      for: firstBoot,
      create: { invalidate in
        HIDSessionDouble(id: recorder.recordCreation(), invalidate: invalidate)
      },
      currentIdentity: { firstBoot }
    )
    cache.invalidate()
    let replacement = try cache.session(
      for: firstBoot,
      create: { invalidate in
        HIDSessionDouble(id: recorder.recordCreation(), invalidate: invalidate)
      },
      currentIdentity: { firstBoot }
    )

    first.invalidate()
    let reused = try cache.session(
      for: firstBoot,
      create: { invalidate in
        HIDSessionDouble(id: recorder.recordCreation(), invalidate: invalidate)
      },
      currentIdentity: { firstBoot }
    )

    #expect(reused === replacement)
    #expect(recorder.creations == 2)
    #expect(recorder.disconnections == [1])
  }

  @Test
  func delayedOldBootFailurePreservesNewBootSession() throws {
    let recorder = HIDSessionTestRecorder()
    let cache = makeCache(recorder: recorder)
    let first = try cache.session(
      for: firstBoot,
      create: { invalidate in
        HIDSessionDouble(id: recorder.recordCreation(), invalidate: invalidate)
      },
      currentIdentity: { firstBoot }
    )
    let replacement = try cache.session(
      for: secondBoot,
      create: { invalidate in
        HIDSessionDouble(id: recorder.recordCreation(), invalidate: invalidate)
      },
      currentIdentity: { secondBoot }
    )

    first.invalidate()

    #expect(cache.cachedIdentity == secondBoot)
    #expect(replacement.id == 2)
    #expect(recorder.disconnections == [1])
  }

  @Test
  func concurrentReconnectAfterFailureConstructsOneReplacement() async throws {
    let recorder = HIDSessionTestRecorder()
    let cache = makeCache(recorder: recorder)
    let identity = firstBoot
    let first = try cache.session(
      for: identity,
      create: { invalidate in
        HIDSessionDouble(id: recorder.recordCreation(), invalidate: invalidate)
      },
      currentIdentity: { identity }
    )
    first.invalidate()

    let ids = try await withThrowingTaskGroup(of: Int.self) { group in
      for _ in 0..<20 {
        group.addTask {
          try cache.session(
            for: identity,
            create: { invalidate in
              HIDSessionDouble(id: recorder.recordCreation(), invalidate: invalidate)
            },
            currentIdentity: { identity }
          ).id
        }
      }
      return try await group.reduce(into: []) { $0.append($1) }
    }

    #expect(Set(ids) == [2])
    #expect(recorder.creations == 2)
    #expect(recorder.disconnections == [1])
  }

  @Test
  func concurrentCallersConstructOneSession() async throws {
    let recorder = HIDSessionTestRecorder()
    let cache = makeCache(recorder: recorder)

    let ids = try await withThrowingTaskGroup(of: Int.self) { group in
      for _ in 0..<20 {
        group.addTask {
          try cache.session(
            for: firstBoot,
            create: { _ in HIDSessionDouble(id: recorder.recordCreation()) },
            currentIdentity: { firstBoot }
          ).id
        }
      }
      return try await group.reduce(into: []) { $0.append($1) }
    }

    #expect(Set(ids) == [1])
    #expect(recorder.creations == 1)
  }

  private func makeCache(
    recorder: HIDSessionTestRecorder
  ) -> FBSimulatorHIDSessionCache<HIDSessionDouble> {
    FBSimulatorHIDSessionCache { recorder.recordDisconnection($0) }
  }
}

@Suite
struct FBSimulatorIndigoHIDClientTests {
  private let boot = FBSimulatorHIDBootIdentity(
    generation: .coreSimulatorLastBootedAt(
      Date(timeIntervalSinceReferenceDate: 1_000)
    )
  )

  @Test
  func disconnectWaitsForPendingSendsAndDisposesExactlyOnce() async throws {
    let sendHarness = HIDSendCompletionHarness()
    let recorder = HIDClientTestRecorder()
    let queue = DispatchQueue(label: "FBSimulatorIndigoHIDClientTests.disconnect")
    let client = FBSimulatorIndigoHIDClient(
      client: NSObject(),
      queue: queue,
      onInvalidated: {},
      onDisposed: recorder.recordDisposal
    ) { _, completionQueue, completion in
      Task {
        await sendHarness.enqueue { error in
          completionQueue.async {
            completion(error)
          }
        }
      }
    }

    async let firstSend: Void = client.send(Data([1]))
    let firstCompletion = await sendHarness.next()
    async let secondSend: Void = client.send(Data([2]))
    let secondCompletion = await sendHarness.next()

    client.disconnect()
    do {
      try await client.send(Data([3]))
      Issue.record("Expected a send after disconnect to be rejected")
    } catch FBSimulatorHIDError.clientDisposed {
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
    #expect(recorder.disposals == 0)

    firstCompletion(nil)
    try await firstSend
    #expect(recorder.disposals == 0)

    secondCompletion(nil)
    try await secondSend
    #expect(recorder.disposals == 1)

    client.disconnect()
    do {
      try await client.send(Data([4]))
      Issue.record("Expected a send after disposal to be rejected")
    } catch FBSimulatorHIDError.clientDisposed {
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
    #expect(recorder.disposals == 1)
  }

  @Test
  func delayedOldClientFailurePreservesReplacementClient() async throws {
    let oldSendHarness = HIDSendCompletionHarness()
    let recorder = HIDSessionTestRecorder()
    let replacementRecorder = HIDClientTestRecorder()
    let cache = FBSimulatorHIDSessionCache<FBSimulatorIndigoHIDClient> { $0.disconnect() }
    let oldClient = try cache.session(
      for: boot,
      create: { invalidate in
        let id = recorder.recordCreation()
        return FBSimulatorIndigoHIDClient(
          client: NSObject(),
          queue: DispatchQueue(label: "FBSimulatorIndigoHIDClientTests.old.\(id)"),
          onInvalidated: invalidate
        ) { _, completionQueue, completion in
          Task {
            await oldSendHarness.enqueue { error in
              completionQueue.async {
                completion(error)
              }
            }
          }
        }
      },
      currentIdentity: { boot }
    )

    async let oldSend: Void = oldClient.send(Data([1]))
    let oldCompletion = await oldSendHarness.next()
    cache.invalidate()
    let replacement = try cache.session(
      for: boot,
      create: { invalidate in
        let id = recorder.recordCreation()
        return FBSimulatorIndigoHIDClient(
          client: NSObject(),
          queue: DispatchQueue(label: "FBSimulatorIndigoHIDClientTests.replacement.\(id)"),
          onInvalidated: invalidate
        ) { _, completionQueue, completion in
          replacementRecorder.recordSend()
          completionQueue.async {
            completion(nil)
          }
        }
      },
      currentIdentity: { boot }
    )

    oldCompletion(HIDClientTestError.sendFailed)
    do {
      try await oldSend
      Issue.record("Expected the delayed old-client failure")
    } catch let error as HIDClientTestError {
      #expect(error == .sendFailed)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let reused = try cache.session(
      for: boot,
      create: { _ in
        Issue.record("Delayed old-client failure evicted the replacement")
        return replacement
      },
      currentIdentity: { boot }
    )

    #expect(reused === replacement)
    #expect(recorder.creations == 2)
    try await reused.send(Data([2]))
    #expect(replacementRecorder.sends == 1)
  }

  @Test
  func sendFailureEvictsClientFromCacheAndReconnects() async throws {
    let recorder = HIDSessionTestRecorder()
    let cache = FBSimulatorHIDSessionCache<FBSimulatorIndigoHIDClient> { $0.disconnect() }
    let first = try cache.session(
      for: boot,
      create: { invalidate in
        let id = recorder.recordCreation()
        return FBSimulatorIndigoHIDClient(
          client: NSObject(),
          queue: DispatchQueue(label: "FBSimulatorIndigoHIDClientTests.cached.\(id)"),
          onInvalidated: invalidate
        ) { _, completionQueue, completion in
          completionQueue.async {
            completion(HIDClientTestError.sendFailed)
          }
        }
      },
      currentIdentity: { boot }
    )

    do {
      try await first.send(Data([1]))
      Issue.record("Expected the send completion error")
    } catch let error as HIDClientTestError {
      #expect(error == .sendFailed)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let replacement = try cache.session(
      for: boot,
      create: { invalidate in
        let id = recorder.recordCreation()
        return FBSimulatorIndigoHIDClient(
          client: NSObject(),
          queue: DispatchQueue(label: "FBSimulatorIndigoHIDClientTests.cached.\(id)"),
          onInvalidated: invalidate
        ) { _, completionQueue, completion in
          completionQueue.async {
            completion(nil)
          }
        }
      },
      currentIdentity: { boot }
    )

    #expect(replacement !== first)
    #expect(recorder.creations == 2)
    try await replacement.send(Data([2]))
  }

  @Test
  func sendFailureReturnsExactErrorAndInvalidatesOnce() async {
    let recorder = HIDClientTestRecorder()
    let queue = DispatchQueue(label: "FBSimulatorIndigoHIDClientTests.failure")
    let client = FBSimulatorIndigoHIDClient(
      client: NSObject(),
      queue: queue,
      onInvalidated: { recorder.recordInvalidation() }
    ) { _, completionQueue, completion in
      recorder.recordSend()
      completionQueue.async {
        completion(HIDClientTestError.sendFailed)
      }
    }

    do {
      try await client.send(Data([1]))
      Issue.record("Expected the send completion error")
    } catch let error as HIDClientTestError {
      #expect(error == .sendFailed)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(recorder.invalidations == 1)
    #expect(recorder.sends == 1)
  }

  @Test
  func sendOnAlreadyFailedClientReturnsClientDisposed() async {
    let recorder = HIDClientTestRecorder()
    let queue = DispatchQueue(label: "FBSimulatorIndigoHIDClientTests.alreadyFailed")
    let client = FBSimulatorIndigoHIDClient(
      client: NSObject(),
      queue: queue,
      onInvalidated: { recorder.recordInvalidation() },
      onDisposed: recorder.recordDisposal
    ) { _, completionQueue, completion in
      recorder.recordSend()
      completionQueue.async {
        completion(HIDClientTestError.sendFailed)
      }
    }

    do {
      try await client.send(Data([1]))
      Issue.record("Expected the send completion error")
    } catch let error as HIDClientTestError {
      #expect(error == .sendFailed)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
    #expect(recorder.disposals == 1)

    do {
      try await client.send(Data([2]))
      Issue.record("Expected a send on the failed client to be rejected")
    } catch FBSimulatorHIDError.clientDisposed {
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(recorder.sends == 1)
    #expect(recorder.invalidations == 1)
    #expect(recorder.disposals == 1)
  }

  @Test
  func successfulSendsKeepClientReusable() async throws {
    let recorder = HIDClientTestRecorder()
    let queue = DispatchQueue(label: "FBSimulatorIndigoHIDClientTests.success")
    let client = FBSimulatorIndigoHIDClient(
      client: NSObject(),
      queue: queue,
      onInvalidated: { recorder.recordInvalidation() }
    ) { _, completionQueue, completion in
      recorder.recordSend()
      completionQueue.async {
        completion(nil)
      }
    }

    try await client.send(Data([1]))
    try await client.send(Data([2]))

    #expect(recorder.invalidations == 0)
    #expect(recorder.sends == 2)
  }

  @Test
  func delayedFailureInvalidatesOnceAfterConcurrentSends() async throws {
    let recorder = HIDClientTestRecorder()
    let harness = HIDSendCompletionHarness()
    let queue = DispatchQueue(label: "FBSimulatorIndigoHIDClientTests.concurrent")
    let client = FBSimulatorIndigoHIDClient(
      client: NSObject(),
      queue: queue,
      onInvalidated: { recorder.recordInvalidation() }
    ) { _, completionQueue, completion in
      recorder.recordSend()
      Task {
        await harness.enqueue { error in
          completionQueue.async {
            completion(error)
          }
        }
      }
    }

    async let first: Void = client.send(Data([1]))
    async let second: Void = client.send(Data([2]))
    let firstCompletion = await harness.next()
    let secondCompletion = await harness.next()
    secondCompletion(nil)
    firstCompletion(HIDClientTestError.sendFailed)

    do {
      _ = try await (first, second)
      Issue.record("Expected one send to fail")
    } catch let error as HIDClientTestError {
      #expect(error == .sendFailed)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(recorder.invalidations == 1)
    #expect(recorder.sends == 2)
  }
}
