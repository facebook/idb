/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore

// Protocol conformance extensions for ObjC test doubles.
// These are needed because Swift requires explicit protocol conformance
// declarations, which cannot be expressed in ObjC headers when the
// protocol is defined in Swift.

extension FBControlCoreLoggerDouble: FBControlCoreLogger {}
