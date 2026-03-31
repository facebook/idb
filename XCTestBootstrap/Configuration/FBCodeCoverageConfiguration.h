/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, FBCodeCoverageFormat) {
  FBCodeCoverageExported,
  FBCodeCoverageRaw,
};

/**
 Represents the code coverage configuration used to execute the tests and report results
*/
@interface FBCodeCoverageConfiguration : NSObject

/**
 The path to the coverage directory
*/
@property (nonnull, nonatomic, readonly, strong) NSString *coverageDirectory;

/**
  Format in which code coverge data should be returned
*/
@property (nonatomic, readonly, assign) FBCodeCoverageFormat format;

/**
 Determines whether should enable continuous coverage collection
 */
@property (nonatomic, readonly, assign) BOOL shouldEnableContinuousCoverageCollection;

- (nonnull instancetype)initWithDirectory:(nonnull NSString *)coverageDirectory format:(FBCodeCoverageFormat)format enableContinuousCoverageCollection:(BOOL)enableContinuousCoverageCollection;

@end
