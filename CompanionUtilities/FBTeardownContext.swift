/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

enum FBTeardownContextError: Error, Sendable {
  case emptyContext
  case cleanupAlreadyPerformed
}

private final class FBTeardownContextImpl: @unchecked Sendable {

  @Atomic private var cleanupList: [() async throws -> Void] = []
  @Atomic var cleanupPerformed = false

  func add(cleanup: @escaping () async throws -> Void) throws {
    guard !cleanupPerformed else {
      throw FBTeardownContextError.cleanupAlreadyPerformed
    }
    _cleanupList.sync { $0.append(cleanup) }
  }

  func performCleanup() async throws {
    let cleanupAlreadyPerformed = _cleanupPerformed.sync { cleanupPerformed -> Bool in
      defer { cleanupPerformed = true }
      return cleanupPerformed
    }
    guard !cleanupAlreadyPerformed else {
      throw FBTeardownContextError.cleanupAlreadyPerformed
    }
    for cleanup in cleanupList.reversed() {
      try await cleanup()
    }
  }
}

/// Coordinates LIFO cleanup of resources created inside a task scope:
///
/// ```
/// try await FBTeardownContext.withAutocleanup {
///   let tmpDir = createTemporaryDirectory()
///   try FBTeardownContext.current.addCleanup { try FileManager.default.removeItem(atPath: tmpDir) }
///   addFiles(to: tmpDir)
/// }
/// ```
public final class FBTeardownContext: Sendable {

  @TaskLocal public static var current: FBTeardownContext = .init(emptyContext: ())

  private let contextImpl: FBTeardownContextImpl?
  private let codeLocation: CodeLocation
  private let isAutocleanup: Bool

  private init(emptyContext: ()) {
    self.contextImpl = nil
    self.isAutocleanup = false
    self.codeLocation = .init(function: nil, file: "", line: 0, column: 0)
  }

  private init(isAutocleanup: Bool, function: String = #function, file: String = #file, line: Int = #line, column: Int = #column) {
    self.contextImpl = FBTeardownContextImpl()
    self.isAutocleanup = isAutocleanup
    self.codeLocation = .init(function: function, file: file, line: line, column: column)
  }

  /// Runs `operation` with a fresh `FBTeardownContext.current`, then performs its cleanups.
  public static func withAutocleanup<T>(function: String = #function, file: String = #file, line: Int = #line, column: Int = #column, operation: nonisolated(nonsending) () async throws -> T) async throws -> T {
    let context = FBTeardownContext(isAutocleanup: true, function: function, file: file, line: line, column: column)
    let result = try await FBTeardownContext.$current.withValue(context, operation: operation)
    try await context.performCleanup()
    return result
  }

  /// Cleanups run in LIFO order when the context is torn down.
  public func addCleanup(_ cleanup: @escaping () async throws -> Void) throws {
    guard let contextImpl else {
      throw FBTeardownContextError.emptyContext
    }
    try contextImpl.add(cleanup: cleanup)
  }

  /// This method should be called explicitly. Relying on deinit is programmer error.
  func performCleanup() async throws {
    guard let contextImpl else {
      throw FBTeardownContextError.emptyContext
    }
    try await contextImpl.performCleanup()
  }

  deinit {
    if let contextImpl, !contextImpl.cleanupPerformed {

      if !Task.isCancelled && !isAutocleanup {
        // A cancelled task may never reach its explicit cleanup, so only a live, non-autocleanup context
        // left uncleaned is a programmer error. `Task.isCancelled` is unreliable in deinit, which is why
        // `isAutocleanup` narrows the assertion further.
        assertionFailure("Context was not cleaned up explicitly. \(codeLocation)")
      }

      Task {
        try? await contextImpl.performCleanup()
      }
    }
  }
}
