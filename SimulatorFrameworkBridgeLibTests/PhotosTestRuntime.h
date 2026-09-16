/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface FBPhotosTestRuntime : NSObject
@property (nonatomic) NSUInteger assetCount;
@property (nonatomic, copy) NSString *failure;
@property (nonatomic) BOOL saveSucceeds;
@property (nonatomic, readonly) NSMutableArray<NSString *> *operations;
@property (nonatomic, readonly) BOOL allMutationsInsideTransaction;
- (int)run;
- (NSDictionary<NSString *, id> *)runCatchingException;
@end
NS_ASSUME_NONNULL_END
