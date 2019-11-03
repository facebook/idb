/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Entry-Point for fbxctest.
 */
@interface FBXCTestBootstrapper : NSObject

/**
 Starts fbxctest.

 @return YES if successful, NO otherwise.
 */
- (BOOL)bootstrap;

@end

NS_ASSUME_NONNULL_END
