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
 A Configuration for an FBTask.
 */
@interface FBTaskConfiguration : NSObject

/**
 Creates a Task Configuration with the provided parameters.
 */
- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment acceptableStatusCodes:(NSSet<NSNumber *> *)acceptableStatusCodes stdOut:(nullable id)stdOut stdErr:(nullable id)stdErr;

/**
 The Launch Path of the Process to launch.
 */
@property (nonatomic, copy, readonly) NSString *launchPath;

/**
 The Arguments to launch with.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;

/**
 The Environment of the process.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environment;

/**
 The Status Codes that indicate success.
 */
@property (nonatomic, copy, readonly) NSSet<NSNumber *> *acceptableStatusCodes;

/**
 Where to write stdout to:
 - If nil, then stdout will be written to /dev/null
 - If is a NSMutableData, stdout will be written to the NSMutableData.
 - If is a NSString representing a file path, then stdout will be written to the file path
 - If is a FBFileDataConsumer then output data will be forwarded to it.
 */
@property (nonatomic, strong, nullable, readonly) id stdOut;

/**
 Where to write stderr to:
 - If nil, then stderr will be written to /dev/null
 - If is a NSMutableData, stderr will be written to the NSMutableData.
 - If is a NSString representing a file path, then stderrr will be written to the file path
 - If is a FBFileDataConsumer then output data will be forwarded to it.
 */
@property (nonatomic, strong, nullable, readonly) id stdErr;

@end

NS_ASSUME_NONNULL_END
