/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

enum FBTeardownContextError: Error {
  case emptyContext
  case cleanupAlreadyPerformed
}

private final class FBTeardownContextImpl {

  @Atomic private var cleanupList: [() async throws -> Void] = []
  @Atomic var cleanupPerformed = false

  func add(cleanup: @escaping () async throws -> Void) throws {
    guard !cleanupPerformed else {
      throw FBTeardownContextError.cleanupAlreadyPerformed
    }
    cleanupList.append(cleanup)
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

private struct CodeLocation: CustomStringConvertible {
  let function: String?
  let file: String
  let line: Int
  let column: Int

  var description: String {
    "Located at file: \(file), line: \(line), column: \(column)" + (function.map { ", function: " + $0 } ?? "")
  }

}

/// Use this class to coordinate cleanup of the tasks.
///
/// ```
///
/// func automaticCleanup() async throws -> Response {
///   return FBTeardownContext.withAutocleanup {
///     doSomeStuff()
///   }
/// }
///
/// func doSomeStuff() {
///   let tmpDir = createTemporaryDirectory()
///   FBTeardownContext.current.addCleanup {
///     FileManager.default.remove(tmpDir)
///   }
///   addFiles(to: tmpDir)
/// }
///
/// ```
final class FBTeardownContext {

  /// Current context that binded to swift concurrency Task. For more info read about `@TaskLocal`
  @TaskLocal static var current: FBTeardownContext = .init(emptyContext: ())

  private let contextImpl: FBTeardownContextImpl?
  private let codeLocation: CodeLocation
  private var isAutocleanup = false

  private init(emptyContext: ()) {
    self.contextImpl = nil
    self.codeLocation = .init(function: nil, file: "", line: 0, column: 0)
  }

  /// Initializer is private intentionally to restrict to `withAutocleanup` usage
  private init(function: String = #function, file: String = #file, line: Int = #line, column: Int = #column) {
    self.contextImpl = FBTeardownContextImpl()
    self.codeLocation = .init(function: function, file: file, line: line, column: column)
  }

  /// Creates `FBContext` and executes operation with it
  /// - Parameter operation: Inside the operation you have `FBTeardownContext.current` available that will be cleaned up on scoping out
  /// - Returns: Operation result
  static func withAutocleanup<T>(function: String = #function, file: String = #file, line: Int = #line, column: Int = #column, operation: @Sendable () async throws -> T) async throws -> T {
    let context = FBTeardownContext(function: function, file: file, line: line, column: column)
    context.isAutocleanup = true
    let result = try await FBTeardownContext.$current.withValue(context, operation: operation)
    try await context.performCleanup()
    return result
  }

  /// Adds cleanup closure to the stack. All cleanup jobs will be called in LIFO order
  /// - Parameter cleanup: Task with cleanup job. There is no enforcement that job *should* throw an error on failure. This is optional.
  func addCleanup(_ cleanup: @escaping () async throws -> Void) throws {
    guard let contextImpl = contextImpl else {
      throw FBTeardownContextError.emptyContext
    }
    try contextImpl.add(cleanup: cleanup)
  }

  /// This method should be called explicitly. Relying on deinit is programmer error.
  func performCleanup() async throws {
    guard let contextImpl = contextImpl else {
      throw FBTeardownContextError.emptyContext
    }
    try await contextImpl.performCleanup()
  }

  deinit {
    if let contextImpl = contextImpl, contextImpl.cleanupPerformed == false {

      if !Task.isCancelled && !isAutocleanup {
        // Despite that we can cleanup automatically, this should be done explicitly

        // Note:
        // When current task is cancelled, we may not reach explicit cleanup.
        // Then cleanup in deinit is ok, bacause task cancellation means that we exceeded client
        // request timeout and error propagation is not required anymore.
        // But Task.isCancelled not always correctly represents cancellation in deinit (concurrency bug?)
        // so there are possibility of false-failure report.
        // To reduce false failures `isAutocleanup` introduced in contexts that used within 100% safe
        // env with automatic cleanup error propagation.
        assertionFailure("Context was not cleaned up explicitly. \(codeLocation)")
      }

      Task {
        try await contextImpl.performCleanup()
      }
    }
  }

}
