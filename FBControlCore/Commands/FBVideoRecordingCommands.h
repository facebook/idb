/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Defines an interface for Video Recording.
 */
@protocol FBVideoRecordingCommands <NSObject>

/**
 Starts the Recording of Video.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)startRecordingWithError:(NSError **)error;

/**
 Stops the Recording of Video.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)stopRecordingWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
