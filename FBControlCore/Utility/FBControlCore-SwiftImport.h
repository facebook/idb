/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// This header imports all ObjC types referenced by Swift code,
// then imports FBControlCore-Swift.h. The module's implementation
// files import it to see the Swift class declarations with all
// required types defined first. It is not part of the module's
// interface: consumers get the Swift declarations from the module
// map's Swift submodule, so the umbrella header does not list it.

#import <Foundation/Foundation.h>

#import <FBControlCore/FBArchiveOperations.h>
#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBTargetConstants.h>
#import <FBControlCore/FileReader.h>

#import "FBControlCore-Swift.h"
