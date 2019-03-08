/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcessStream.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Configuration for an FBTask.
 */
@interface FBTaskConfiguration : NSObject

/**
 Creates a Task Configuration with the provided parameters.
 */
- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment acceptableStatusCodes:(NSSet<NSNumber *> *)acceptableStatusCodes stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr stdIn:(nullable FBProcessInput *)stdIn;

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
 The FBProcessInput for stdin.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessInput *stdIn;

@end

NS_ASSUME_NONNULL_END
