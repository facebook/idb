/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Queues collection to bring objc and async-swift worlds together
public enum BridgeQueues {

  /// Plain serial queue that is primarily used to convert *all* FBFuture calls to swift awaitable values
  public static let futureSerialFullfillmentQueue = DispatchQueue(label: "com.facebook.fbfuture.fullfilment")

  /// Concurrent queue handed to command-executor callbacks that need a queue to deliver results on.
  public static let miscEventReaderQueue = DispatchQueue(label: "com.facebook.miscellaneous.reader", qos: .userInitiated, attributes: .concurrent)
}
