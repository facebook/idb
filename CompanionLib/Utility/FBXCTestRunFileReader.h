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
 Read and expand contents of a xctestrun file
 */
@interface FBXCTestRunFileReader : NSObject

#pragma mark Public Methods

/**
 Read a xctestrun file and expand placeholders

 @param xctestrunURL URL of a xctestrun file
 @param path auxiliary directory for the test target
 @param error an error out for any oeeor that occurs
 @return a dictionary with expanded xctestrun contents if the xctestrun file could be read successfully
 */
+ (nullable NSDictionary<NSString *, id> *)readContentsOf:(NSURL *)xctestrunURL expandPlaceholderWithPath:(NSString *)path error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
