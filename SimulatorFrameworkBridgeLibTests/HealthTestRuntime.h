/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface FBHealthTestRuntime : NSObject
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *typeFactories;
@property (nonatomic, copy) NSSet<NSString *> *missingClasses;
@property (nonatomic) NSUInteger setterVariants;
@property (nonatomic) BOOL asyncCompletions;
@property (nonatomic) BOOL seedOK;
@property (nonatomic) BOOL setOK;
@property (nonatomic) BOOL clearOK;
@property (nullable, nonatomic, copy) NSString *seedError;
@property (nullable, nonatomic, copy) NSString *setError;
@property (nullable, nonatomic, copy) NSString *clearError;
@property (nullable, nonatomic, copy) NSString *fetchError;
@property (nonatomic, copy) NSString *omittedCompletion;
@property (nonatomic, copy) NSString *raisedOperation;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *records;
@property (nonatomic, readonly) NSMutableArray<NSString *> *operations;
@property (nonatomic, readonly) NSMutableArray<NSString *> *factoryCalls;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, id> *arguments;
- (NSDictionary<NSString *, id> *)runAction:(NSString *)action bundleID:(nullable NSString *)bundleID types:(NSArray<NSString *> *)types;
@end
NS_ASSUME_NONNULL_END
