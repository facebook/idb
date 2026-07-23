/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import FBDeviceControl

// These reference types are thread-safe shared services / process handles that the
// companion passes across Swift Concurrency domains (returned from Tasks, captured
// in @Sendable closures) but which predate Sendable annotations. Assert conformance
// retroactively.
extension FBSubprocess: @retroactive @unchecked Sendable {}
extension FBProcessInput: @retroactive @unchecked Sendable {}
extension FBDeviceSet: @retroactive @unchecked Sendable {}
extension FBIDBLogger: @retroactive @unchecked Sendable {}
extension FBIDBCommandExecutor: @retroactive @unchecked Sendable {}
