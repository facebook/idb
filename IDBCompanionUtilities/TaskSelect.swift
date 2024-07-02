/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

struct TaskSelectState<Success: Sendable, Failure: Error>: Sendable {
  var complete = false
  var tasks: [Task<Success, Failure>]? = []

  mutating func add(_ task: Task<Success, Failure>) -> Task<Success, Failure>? {
    if var tasks {
      tasks.append(task)
      self.tasks = tasks
      return nil
    } else {
      return task
    }
  }
}

extension Task {
  /// Determine the first task to complete of a sequence of tasks.
  ///
  /// - Parameters:
  ///   - tasks: The running tasks to obtain a result from
  /// - Returns: The first task to complete from the running tasks
  public static func select<Tasks: Sequence & Sendable>(
    _ tasks: Tasks
  ) async -> Task<Success, Failure>
  where Tasks.Element == Task<Success, Failure>, Success: Sendable {

    let state = Atomic<TaskSelectState<Success, Failure>>(wrappedValue: .init())
    return await withTaskCancellationHandler {
      await withUnsafeContinuation { continuation in
        for task in tasks {
          Task<Void, Never> {
            _ = await task.result
            let winner = state.sync { state -> Bool in
              defer { state.complete = true }
              return !state.complete
            }
            if winner {
              continuation.resume(returning: task)
            }
          }
          state.sync { state in
            state.add(task)
          }?.cancel()
        }
      }
    } onCancel: {

      let tasks = state.sync { state -> [Task<Success, Failure>] in
        defer { state.tasks = nil }
        return state.tasks ?? []
      }
      for task in tasks {
        task.cancel()
      }
    }
  }

  /// Determine the first task to complete of a list of tasks.
  ///
  /// - Parameters:
  ///   - tasks: The running tasks to obtain a result from
  /// - Returns: The first task to complete from the running tasks
  public static func select(
    _ tasks: Task<Success, Failure>...
  ) async -> Task<Success, Failure> where Success: Sendable {
    await select(tasks)
  }
}
