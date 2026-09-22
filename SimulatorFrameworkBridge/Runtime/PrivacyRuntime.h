/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, FBPrivacyStatus) {
  FBPrivacyStatusCompleted,
  FBPrivacyStatusUnavailable,
  FBPrivacyStatusFailed,
};

/** The daemon accepted every requested operation, or the first failure with its diagnostic. */
@interface FBPrivacyOutcome : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) FBPrivacyStatus status;
/** Non-nil exactly when status is not Completed. */
@property (nullable, nonatomic, readonly, copy) NSString *failureReason;
+ (instancetype)completed;
+ (instancetype)unavailable:(NSString *)reason;
+ (instancetype)failed:(NSString *)reason;
@end

/** Resolves borrowed addresses whose lifetime covers the complete operation. */
typedef void *_Nullable (^FBPrivacySymbolResolver)(const char *name);

/** TCC binding behind the FBAXRuntime seam; no private references escape this boundary. */
@interface FBPrivacyBinding : NSObject
+ (FBPrivacyOutcome *)updateBundleID:(NSString *)bundleID services:(NSArray<NSString *> *)services approved:(BOOL)approved;
/** Injects symbol availability and daemon responses without modifying simulator permissions. */
+ (FBPrivacyOutcome *)updateBundleID:(NSString *)bundleID services:(NSArray<NSString *> *)services approved:(BOOL)approved resolver:(FBPrivacySymbolResolver)resolver;
@end

NS_ASSUME_NONNULL_END
