/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBDynamicStoreTestRuntime : NSObject
@property (nonatomic) BOOL libraryAvailable;
@property (nonatomic) BOOL storeAvailable;
@property (nonatomic) BOOL writeSucceeds;
@property (nonatomic, copy) NSSet<NSString *> *missingSymbols;
/** What the store holds for the key under test; nil is an absent key. */
@property (nullable, nonatomic, copy) id value;
/** The value returned by every `SCError` call; 1004 (kSCStatusNoKey) denotes an absent key after a nil read. */
@property (nonatomic) int errorStatus;
/** Optional scripted reads; NSNull denotes an absent value or error, according to errorStatus. */
@property (nullable, nonatomic, copy) NSArray<id> *readValues;
@property (nonatomic, readonly) NSMutableArray<NSString *> *operations;
@property (nonatomic, readonly) NSMutableArray<NSString *> *keys;
@property (nonatomic, readonly, copy) NSData *output;
- (int)runAction:(NSString *)action arguments:(NSArray<NSString *> *)arguments input:(nullable NSData *)input
  NS_SWIFT_NAME(run(action:arguments:input:));
@end

NS_ASSUME_NONNULL_END
