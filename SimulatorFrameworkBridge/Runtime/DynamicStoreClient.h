/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** A successful read; nil value means the key is absent. */
@interface FBDynamicStoreSnapshot : NSObject
@property (nullable, nonatomic, readonly) id value;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/** Owns a configd session and its dynamically bound API. Values retain their property-list types. */
@interface FBDynamicStoreClient : NSObject
+ (nullable instancetype)openKey:(NSString *)key NS_SWIFT_NAME(open(key:));
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/** Nil means a failed read, distinct from a successful absent-key snapshot. */
- (nullable FBDynamicStoreSnapshot *)read;
- (BOOL)writeValue:(id)value;
- (BOOL)removeValue;
- (void)notifyChange;
@end

NS_ASSUME_NONNULL_END
