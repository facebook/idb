/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Resolves HealthKit classes through `lookup` instead of the runtime, or restores the runtime with nil. */
void FBHealthSetClassLookupForTesting(Class _Nullable (^_Nullable lookup)(NSString *name));

typedef NS_ENUM(NSUInteger, FBHealthCompletionStatus) {
  FBHealthCompletionStatusCompleted,
  FBHealthCompletionStatusTimedOut,
};

/** A fixed result of waiting for one operation; late callbacks cannot update it. */
@interface FBHealthOperationResult : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) BOOL success;
@property (nonatomic, readonly) FBHealthCompletionStatus status;
@property (nonatomic, readonly) BOOL hasError;
/** Returns NSNull for no callback error, its localized description otherwise, or nil if reading it raises. */
- (nullable id)readErrorValueWithError:(NSError **)error;
@end

@interface FBHealthAuthorizationWrite : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nullable, nonatomic, readonly, strong) FBHealthOperationResult *operation;
@end

/** Each field is absent or an NSString/NSNumber value normalized from the private record. */
@interface FBHealthAuthorizationRecord : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nullable, nonatomic, readonly, strong) id identifier;
@property (nullable, nonatomic, readonly, strong) id sharingAuthorizationAllowed;
@property (nullable, nonatomic, readonly, strong) id readingAuthorizationAllowed;
@end

@interface FBHealthRecordsResult : FBHealthOperationResult
- (nullable NSArray<FBHealthAuthorizationRecord *> *)readRecordsWithError:(NSError **)error;
@end

@interface FBHealthTypeSelection : NSObject
@property (nonatomic, readonly, getter = isEmpty) BOOL empty;
- (nullable NSNumber *)resolveIdentifier:(NSString *)identifier error:(NSError **)error;
@end

@interface FBHealthSettingsClient : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
+ (nullable instancetype)liveClient;
- (nullable FBHealthOperationResult *)seedAuthorizationForBundleIdentifier:(NSString *)bundleID selection:(FBHealthTypeSelection *)selection error:(NSError **)error;
- (nullable FBHealthAuthorizationWrite *)setAuthorizationForBundleIdentifier:(NSString *)bundleID selection:(FBHealthTypeSelection *)selection status:(NSUInteger)status error:(NSError **)error;
- (nullable FBHealthOperationResult *)clearAuthorizationForBundleIdentifier:(NSString *)bundleID error:(NSError **)error;
- (nullable FBHealthRecordsResult *)fetchRecordsForBundleIdentifier:(NSString *)bundleID error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
