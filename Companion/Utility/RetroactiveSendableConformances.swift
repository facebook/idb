/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl

// These reference types are thread-safe shared services / process handles that the
// companion passes across Swift Concurrency domains (returned from Tasks, captured
// in @Sendable closures) but which predate Sendable annotations. Assert the
// conformance here; the ones this module does not own are retroactive.
extension FBSubprocess: @retroactive @unchecked Sendable {}
extension FBProcessInput: @retroactive @unchecked Sendable {}
extension DeviceSet: @retroactive @unchecked Sendable {}
extension IDBLogger: @unchecked Sendable {}
extension IDBCommandExecutor: @unchecked Sendable {}
