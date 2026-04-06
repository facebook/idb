/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessTerminationStrategy.h"

#import "FBControlCoreError.h"
#import "FBProcessFetcher.h"
#import "FBProcessInfo.h"

@implementation FBControlCoreError (FBProcessTerminationStrategy)

- (instancetype)attachProcessInfoForIdentifier:(pid_t)processIdentifier processFetcher:(FBProcessFetcher *)processFetcher
{
  return [self
          extraInfo:[NSString stringWithFormat:@"%d_process", processIdentifier]
          value:[processFetcher processInfoFor:processIdentifier] ?: @"No Process Info"];
}

@end
