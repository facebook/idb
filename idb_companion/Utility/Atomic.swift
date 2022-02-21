/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@propertyWrapper
struct Atomic<Value>: @unchecked Sendable {

  private var value: Value
  private let mutex: FBMutex

  init(wrappedValue: Value) {
    self.mutex = FBMutex()
    self.value = wrappedValue
  }

  var wrappedValue: Value {
    get { mutex.sync(execute: { value }) }
    set { mutex.sync(execute: { value = newValue }) }
  }

  mutating func sync<R>(execute work: (inout Value) -> R) -> R {
    mutex.sync(execute: { work(&value) })
  }
}
