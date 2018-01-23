/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcessOutput.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Configuration for an FBTask.
 */
@interface FBTaskConfiguration : NSObject

/**
 Creates a Task Configuration with the provided parameters.
 */
- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment acceptableStatusCodes:(NSSet<NSNumber *> *)acceptableStatusCodes stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr stdIn:(nullable FBProcessOutput<id<FBFileConsumer>> *)stdIn;

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
The FBProcessOutput for stdout.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessOutput *stdOut;

/**
 The FBProcessOutput for stderr.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessOutput *stdErr;

/**
 The FBProcessOutput for stdin.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessOutput<id<FBFileConsumer>> *stdIn;

@end

NS_ASSUME_NONNULL_END
