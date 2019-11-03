/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
