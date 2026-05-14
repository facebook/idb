/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBCodeCoverageConfiguration;

/**
 A value object that contains configuration for idb's xctest reporter.
 */
@interface FBXCTestReporterConfiguration : NSObject

/**
 The Result Bundle Path (if any)
 */
@property (nullable, nonatomic, readonly, copy) NSString *resultBundlePath;

/**
 Coverage directory path
 */
@property (nullable, nonatomic, readonly, retain) FBCodeCoverageConfiguration *coverageConfiguration;

/**
 Log directory path
 */
@property (nullable, nonatomic, readonly, copy) NSString *logDirectoryPath;

/**
 App binary path
 */
@property (nullable, nonatomic, readonly, copy) NSArray<NSString *> *binariesPaths;

/**
 Whether to report attachments or not.
 */
@property (nonatomic, readonly, assign) BOOL reportAttachments;

/**
 Whether to report return result bundle or not.
 */
@property (nonatomic, readonly, assign) BOOL reportResultBundle;

- (instancetype)initWithResultBundlePath:(nullable NSString *)resultBundlePath coverageConfiguration:(nullable FBCodeCoverageConfiguration *)coverageConfiguration logDirectoryPath:(nullable NSString *)logDirectoryPath binariesPaths:(nullable NSArray<NSString *> *)binariesPaths reportAttachments:(BOOL)reportAttachments reportResultBundle:(BOOL)reportResultBundle;

@end

NS_ASSUME_NONNULL_END
