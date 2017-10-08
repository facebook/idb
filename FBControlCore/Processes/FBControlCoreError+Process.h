/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBControlCore/FBControlCoreError.h>

@class FBProcessFetcher;

@interface FBControlCoreError (Process)

/**
 Attaches Process Information to the error.

 @param processIdentifier the Process Identifier to find information for.
 @param processFetcher the Process Fetcher object to obtain process information from.
 @return the reciever, for chaining.
 */
- (instancetype)attachProcessInfoForIdentifier:(pid_t)processIdentifier processFetcher:(FBProcessFetcher *)processFetcher;

@end
