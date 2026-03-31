/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

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
- (nonnull instancetype)initWithProcessIdentifier:(pid_t)processIdentifier launchPath:(nonnull NSString *)launchPath arguments:(nonnull NSArray<NSString *> *)arguments environment:(nonnull NSDictionary<NSString *, NSString *> *)environment;

/**
 The Process Identifier for the running process
 */
@property (nonatomic, readonly, assign) pid_t processIdentifier;

/**
 The Name of the Process.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *processName;

/**
 The Launch Path of the running process
 */
@property (nonnull, nonatomic, readonly, copy) NSString *launchPath;

/**
 An NSArray<NSString *> of the launch arguments of the process.
 */
@property (nonnull, nonatomic, readonly, copy) NSArray<NSString *> *arguments;

/**
 An NSDictionary<NSString *, NSString *> of the environment of the process.
 */
@property (nonnull, nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *environment;

@end
