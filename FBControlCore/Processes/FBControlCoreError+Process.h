/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBControlCore/FBControlCoreError.h>

@class FBProcessFetcher;

@interface FBControlCoreError (Process)

/**
 Attaches Process Information to the error.

 @param processIdentifier the Process Identifier to find information for.
 @param processFetcher the Process Fetcher object to obtain process information from.
 @return the receiver, for chaining.
 */
- (instancetype)attachProcessInfoForIdentifier:(pid_t)processIdentifier processFetcher:(FBProcessFetcher *)processFetcher;

@end
