/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 A summary of an exception.
 */
@interface FBExceptionInfo : NSObject

@property (nonnull, nonatomic, readonly, copy) NSString *message;
@property (nullable, nonatomic, readonly, copy) NSString *file;
@property (nonatomic, readonly, assign) NSUInteger line;

- (instancetype _Nonnull)initWithMessage:(nonnull NSString *)message file:(nullable NSString *)file line:(NSUInteger)line;

- (instancetype _Nonnull)initWithMessage:(nonnull NSString *)message;

@end
