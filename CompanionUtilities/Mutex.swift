/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// Helper wrapper around `pthread_mutex`
final class FBMutex: @unchecked Sendable {

  private var underlyingMutex = pthread_mutex_t()

  init() {
    var attr = pthread_mutexattr_t()
    guard pthread_mutexattr_init(&attr) == 0 else {
      preconditionFailure()
    }
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_NORMAL)
    guard pthread_mutex_init(&underlyingMutex, &attr) == 0 else {
      preconditionFailure()
    }
    pthread_mutexattr_destroy(&attr)
  }

  func sync<R>(execute work: () throws -> R) rethrows -> R {
    pthread_mutex_lock(&underlyingMutex)
    defer { pthread_mutex_unlock(&underlyingMutex) }
    return try work()
  }

  deinit {
    pthread_mutex_destroy(&underlyingMutex)
  }
}
