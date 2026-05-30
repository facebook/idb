/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension Task where Success: Sendable {

  /// Returns the first task to complete out of a sequence of tasks.
  ///
  /// Once a winner is determined, the remaining tasks are left to finish on
  /// their own (matching prior behavior). If the surrounding task is
  /// cancelled before a winner is selected, cancellation is propagated to
  /// every input task.
  ///
  /// - Parameter tasks: The running tasks to await.
  /// - Returns: The first task to complete, whether by success or failure.
  /// - Precondition: `tasks` must not be empty.
  public static func select<Tasks: Sequence & Sendable>(
    _ tasks: Tasks
  ) async -> Task<Success, Failure>
  where Tasks.Element == Task<Success, Failure> {

    // Snapshot once so the cancellation handler observes the exact same set
    // of tasks that the task group is racing, without sharing mutable state.
    let snapshot = Array(tasks)
    precondition(!snapshot.isEmpty, "Task.select requires at least one task")

    return await withTaskCancellationHandler {
      await withTaskGroup(of: Task<Success, Failure>.self) { group in
        for task in snapshot {
          group.addTask {
            _ = await task.result
            return task
          }
        }

        // The first child observer to finish carries our winner. Leaving the
        // group implicitly cancels the remaining observer tasks via
        // structured concurrency; the input tasks themselves are deliberately
        // left running so callers can decide their fate.
        return await group.next()!
      }
    } onCancel: {
      for task in snapshot {
        task.cancel()
      }
    }
  }

  /// Returns the first task to complete out of a list of tasks.
  ///
  /// Once a winner is determined, the remaining tasks are left to finish on
  /// their own (matching prior behavior). If the surrounding task is
  /// cancelled before a winner is selected, cancellation is propagated to
  /// every input task.
  ///
  /// - Parameter tasks: The running tasks to await.
  /// - Returns: The first task to complete, whether by success or failure.
  public static func select(
    _ tasks: Task<Success, Failure>...
  ) async -> Task<Success, Failure> {
    await select(tasks)
  }
}
