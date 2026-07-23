@testable import FBSimulatorControl
import Foundation
import Synchronization
import Testing

private enum HIDBootIdentityTestError: Error {
  case processInspectionDenied
}

private final class HIDSessionDouble: @unchecked Sendable {
  let id: Int

  init(id: Int) {
    self.id = id
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
      create: { HIDSessionDouble(id: recorder.recordCreation()) },
      currentIdentity: { firstBoot }
    )
    let second = try cache.session(
      for: firstBoot,
      create: { HIDSessionDouble(id: recorder.recordCreation()) },
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
      create: { HIDSessionDouble(id: recorder.recordCreation()) },
      currentIdentity: { firstBoot }
    )
    let second = try cache.session(
      for: secondBoot,
      create: { HIDSessionDouble(id: recorder.recordCreation()) },
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
      create: { HIDSessionDouble(id: recorder.recordCreation()) },
      currentIdentity: { firstBoot }
    )

    #expect(throws: FBSimulatorHIDSessionCacheError.bootChangedDuringConnection) {
      try cache.session(
        for: firstBoot,
        create: { HIDSessionDouble(id: recorder.recordCreation()) },
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
        create: { HIDSessionDouble(id: recorder.recordCreation()) },
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
      create: { HIDSessionDouble(id: recorder.recordCreation()) },
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
      create: { HIDSessionDouble(id: recorder.recordCreation()) },
      currentIdentity: { secondBoot }
    )
    cache.invalidate(ifMatching: firstBoot)

    #expect(cache.cachedIdentity == secondBoot)
    #expect(recorder.disconnections.isEmpty)
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
            create: { HIDSessionDouble(id: recorder.recordCreation()) },
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
