/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBAXRuntime;

/** One named attribute, preserving the runtime's iteration order before value coercion. */
@interface FBAXSnapshotAttribute : NSObject

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) id value;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

/** A lazily inspected snapshot node that retains the snapshot owning its private element. */
@interface FBAXSnapshotNode : NSObject

- (nullable NSNumber *)validWithError:(NSError **)error;
- (nullable NSArray<FBAXSnapshotAttribute *> *)attributesWithError:(NSError **)error;
- (nullable NSArray<FBAXSnapshotNode *> *)childrenWithError:(NSError **)error;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

/** An ordinary fetch failure is a result, distinct from a private exception thrown by the client. */
@interface FBAXSnapshotRead : NSObject

@property (nullable, nonatomic, readonly) FBAXSnapshotNode *root;
@property (nullable, nonatomic, readonly) NSError *error;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

/** Owns snapshot fetches, private keys, numeric attribute mappings, and element lifetimes. */
@interface FBAXSnapshotClient : NSObject

- (instancetype)initWithRuntime:(id<FBAXRuntime>)runtime NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** Returns a result even when the runtime cannot fetch a tree. Only a private exception throws. */
- (nullable FBAXSnapshotRead *)readElement:(id)element
                            attributeNames:(NSArray<NSString *> *)names
                                     error:(NSError **)error;

/** Continues a snapshot at a node's private element, preserving its owning snapshot until completion. */
- (nullable FBAXSnapshotRead *)readContinuation:(FBAXSnapshotNode *)node
                                 attributeNames:(NSArray<NSString *> *)names
                                          error:(NSError **)error;

/** Zero means the runtime could not attribute the node, or the node has no element. */
- (nullable NSNumber *)processIdentifierForNode:(FBAXSnapshotNode *)node error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
