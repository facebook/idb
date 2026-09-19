/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import CoreGraphics
@preconcurrency import FBControlCore
@preconcurrency import FBSimulatorControl
import Foundation
import IDBGRPCSwift
import Testing

/// Records what the handler hands the command executor, so a test can read it without a simulator.
/// `IDBCommandExecutor` is a `public final class`; `AccessibilityActing` is the seam the handler is
/// written against, and this double stands in for it.
private final class RecordingAccessibilityActor: AccessibilityActing {
  private(set) var waitedBackend: UIAutomationBackend?
  private(set) var tapped: AccessibilityElementQuery?
  private(set) var scrolled: AccessibilityElementQuery?
  private(set) var scrolledDirection: AccessibilityScrollDirection?
  private(set) var valueSetOn: AccessibilityElementQuery?
  private(set) var valueSet: String?
  private(set) var draggedFrom: AccessibilityElementQuery?
  private(set) var draggedTo: AccessibilityElementQuery?

  func accessibility_wait(
    query: AccessibilityElementQuery,
    backend: UIAutomationBackend,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws {
    waitedBackend = backend
  }

  func accessibility_tap(
    query: AccessibilityElementQuery,
    expectedValue: String?,
    expectedKey: AXSearchableKey
  ) async throws {
    tapped = query
  }

  func accessibility_scroll(query: AccessibilityElementQuery, direction: AccessibilityScrollDirection) async throws {
    scrolled = query
    scrolledDirection = direction
  }

  func accessibility_set_value(query: AccessibilityElementQuery, value: String) async throws {
    valueSetOn = query
    valueSet = value
  }

  func accessibility_drag(
    from source: AccessibilityElementQuery,
    to destination: AccessibilityElementQuery,
    options: DragOptions
  ) async throws {
    draggedFrom = source
    draggedTo = destination
  }
}

/// Asserts what the *handler* hands the executor. The four mutating verbs reach the executor with no
/// backend at all -- pinned here so the commit that gives them one has something to flip.
@Suite
struct AccessibilityActionMethodHandlerTests {

  private func respond(
    _ mutate: (inout Idb_AccessibilityActionRequest) -> Void
  ) async throws -> RecordingAccessibilityActor {
    var request = Idb_AccessibilityActionRequest()
    mutate(&request)
    let executor = RecordingAccessibilityActor()
    _ = try await AccessibilityActionMethodHandler.respond(to: request, using: executor)
    return executor
  }

  @Test
  func tapReachesTheExecutor() async throws {
    let executor = try await respond {
      $0.backend = .axbridge
      $0.marker = "GETTING STARTED"
      $0.tap = .init()
    }
    #expect(executor.tapped == .marker(value: "GETTING STARTED", key: .label, depth: 0))
  }

  @Test
  func scrollReachesTheExecutor() async throws {
    let executor = try await respond {
      $0.backend = .axbridge
      $0.marker = "Notification Center"
      $0.scroll = .with { $0.direction = .down }
    }
    #expect(executor.scrolled == .marker(value: "Notification Center", key: .label, depth: 0))
    #expect(executor.scrolledDirection == .down)
  }

  /// A scroll with no target is the common invocation, and the one the frontmost query comes from.
  @Test
  func anUntargetedScrollReachesTheExecutorAsFrontmost() async throws {
    let executor = try await respond {
      $0.backend = .axbridge
      $0.scroll = .with { $0.direction = .down }
    }
    #expect(executor.scrolled == .frontmost)
  }

  @Test
  func setValueReachesTheExecutor() async throws {
    let executor = try await respond {
      $0.backend = .axbridge
      $0.marker = "Search"
      $0.setValue = .with { $0.value = "hello" }
    }
    #expect(executor.valueSetOn == .marker(value: "Search", key: .label, depth: 0))
    #expect(executor.valueSet == "hello")
  }

  @Test
  func dragReachesTheExecutor() async throws {
    let executor = try await respond {
      $0.backend = .axbridge
      $0.point = .with { point in
        point.x = 10
        point.y = 20
      }
      $0.drag = .with { drag in
        drag.point = .with { point in
          point.x = 200
          point.y = 20
        }
      }
    }
    #expect(executor.draggedFrom == .point(CGPoint(x: 10, y: 20)))
    #expect(executor.draggedTo == .point(CGPoint(x: 200, y: 20)))
  }

  /// Wait is the one action that already selects a backend, through its own deprecated field.
  @Test
  func waitCarriesItsOwnBackendToTheExecutor() async throws {
    let executor = try await respond {
      $0.marker = "Settings"
      $0.wait = .with {
        $0.backend = .axbridge
        $0.timeout = 10
        $0.pollInterval = 0.5
      }
    }
    #expect(executor.waitedBackend == UIAutomationBackend(resolvedName: .axBridgeExclusive))
  }

  // BUG: the request-level backend never reaches the executor -- flipped in the following commit.
  @Test
  func waitIgnoresTheRequestLevelBackend() async throws {
    let executor = try await respond {
      $0.backend = .axbridge
      $0.marker = "Settings"
      $0.wait = .with {
        $0.timeout = 10
        $0.pollInterval = 0.5
      }
    }
    #expect(executor.waitedBackend == .accessibility)
  }
}
