@testable import FBSimulatorControl
import Synchronization
import Testing

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
    processIdentifier: 100,
    startTimeMicroseconds: 1_000
  )
  private let secondBoot = FBSimulatorHIDBootIdentity(
    processIdentifier: 101,
    startTimeMicroseconds: 2_000
  )

  @Test
  func reusedProcessIdentifierWithNewStartTimeIsANewBoot() {
    let reusedPID = FBSimulatorHIDBootIdentity(
      processIdentifier: firstBoot.processIdentifier,
      startTimeMicroseconds: secondBoot.startTimeMicroseconds
    )

    #expect(reusedPID != firstBoot)
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
