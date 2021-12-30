/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Converts a data download into the input of a process
 */
@interface FBDataDownloadInput : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param url the url to download
 @param logger the logger to use.
 @return a data download instance.
 */
+ (instancetype)dataDownloadWithURL:(NSURL *)url logger:(id<FBControlCoreLogger>)logger;

#pragma mark Properties

/**
 The process input that will be bridged.
 */
@property (nonatomic, strong, readonly) FBProcessInput<id<FBDataConsumer>> *input;

@end

NS_ASSUME_NONNULL_END
