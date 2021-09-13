/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A value object that contains configuration for idb's xctest reporter.
 */
@interface FBXCTestReporterConfiguration : NSObject

/**
 The Result Bundle Path (if any)
 */
@property (nonatomic, copy, nullable, readonly) NSString *resultBundlePath;

/**
 Coverage file path
 */
@property (nonatomic, copy, nullable, readonly) NSString *coveragePath;

/**
 Log directory path
 */
@property (nonatomic, copy, nullable, readonly) NSString *logDirectoryPath;

/**
 App binary path
 */
@property (nonatomic, copy, nullable, readonly) NSArray<NSString *> *binariesPaths;

/**
 Whether to report attachments or not.
 */
@property (nonatomic, assign, readonly) BOOL reportAttachments;

- (instancetype)initWithResultBundlePath:(nullable NSString *)resultBundlePath coveragePath:(nullable NSString *)coveragePath logDirectoryPath:(nullable NSString *)logDirectoryPath binariesPaths:(nullable NSArray<NSString *> *)binariesPaths reportAttachments:(BOOL)reportAttachments;

@end

NS_ASSUME_NONNULL_END
