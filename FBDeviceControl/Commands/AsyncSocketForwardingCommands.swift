/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol AsyncSocketForwardingCommands: AnyObject {

  func drainLocalFileInput(_ localFileDescriptorInput: Int32, localFileOutput localFileDescriptorOutput: Int32, remotePort: Int32) async throws
}
