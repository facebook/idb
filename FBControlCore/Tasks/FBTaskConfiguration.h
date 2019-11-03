/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessIO;

@protocol FBControlCoreLogger;

/**
 A Configuration for an FBTask.
 */
@interface FBTaskConfiguration : NSObject

/**
 Creates a Task Configuration with the provided parameters.
 */
- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment acceptableStatusCodes:(NSSet<NSNumber *> *)acceptableStatusCode io:(FBProcessIO *)io logger:(nullable id<FBControlCoreLogger>)logger programName:(NSString *)programName;

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
The FBProcessIO object.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessIO *io;

/**
 The logger to log to.
 */
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

/**
 The program display name for logging.
 */
@property (nonatomic, copy, readonly) NSString *programName;

@end

NS_ASSUME_NONNULL_END
