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
@property (nonatomic, copy, nullable, readonly) NSString *resultBundlePath;

/**
 Coverage directory path
 */
@property (nonatomic, retain, nullable, readonly) FBCodeCoverageConfiguration *coverageConfiguration;

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

/**
 Whether to report return result bundle or not.
 */
@property (nonatomic, assign, readonly) BOOL reportResultBundle;

- (instancetype)initWithResultBundlePath:(nullable NSString *)resultBundlePath coverageConfiguration:(nullable FBCodeCoverageConfiguration *)coverageConfiguration logDirectoryPath:(nullable NSString *)logDirectoryPath binariesPaths:(nullable NSArray<NSString *> *)binariesPaths reportAttachments:(BOOL)reportAttachments reportResultBundle:(BOOL)reportResultBundle;

@end

NS_ASSUME_NONNULL_END
