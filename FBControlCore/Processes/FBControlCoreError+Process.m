/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreError+Process.h"

#import "FBProcessInfo.h"
#import "FBProcessFetcher.h"

@implementation FBControlCoreError (Process)

- (instancetype)attachProcessInfoForIdentifier:(pid_t)processIdentifier processFetcher:(FBProcessFetcher *)processFetcher
{
  return [self
    extraInfo:[NSString stringWithFormat:@"%d_process", processIdentifier]
    value:[processFetcher processInfoFor:processIdentifier] ?: @"No Process Info"];
}

@end
