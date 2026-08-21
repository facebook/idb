/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
import FBControlCore
import Foundation

enum IDBConfiguration {

  // Set once at process startup before any request handling, so unsynchronized
  // access is safe.
  nonisolated(unsafe) static var eventReporter: FBEventReporter = EmptyEventReporter.shared
}
