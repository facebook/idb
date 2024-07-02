/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Concrete Value of Process Information.
 */
@interface FBProcessInfo : NSObject <NSCopying>

/**
 The Designated Initializer.

 @param processIdentifier the process identifer.
 @param launchPath the path of the binary that the process was launched with.
 @param arguments the arguments that the process was launched with.
 @param environment the environment that the
 */
- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier launchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment;

/**
 The Process Identifier for the running process
 */
@property (nonatomic, assign, readonly) pid_t processIdentifier;

/**
 The Name of the Process.
 */
@property (nonatomic, copy, readonly) NSString *processName;

/**
 The Launch Path of the running process
 */
@property (nonatomic, copy, readonly) NSString *launchPath;

/**
 An NSArray<NSString *> of the launch arguments of the process.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;

/**
 An NSDictionary<NSString *, NSString *> of the environment of the process.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environment;

@end

NS_ASSUME_NONNULL_END
