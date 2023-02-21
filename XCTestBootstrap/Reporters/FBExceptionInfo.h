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

@property (nonnull, nonatomic, copy, readonly) NSString *message;
@property (nullable, nonatomic, copy, readonly) NSString *file;
@property (nonatomic, assign, readonly) NSUInteger line;

- (instancetype _Nonnull)initWithMessage:(nonnull NSString *)message file:(nullable NSString *)file line:(NSUInteger)line;

- (instancetype _Nonnull)initWithMessage:(nonnull NSString *)message;

@end
