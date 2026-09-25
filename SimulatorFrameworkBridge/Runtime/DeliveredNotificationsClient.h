/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <TargetConditionals.h>

#import <Foundation/Foundation.h>

#if !TARGET_OS_TV

 #import <UserNotifications/UserNotifications.h>

NS_ASSUME_NONNULL_BEGIN

/** The part of `UNUserNotificationCenter` a read uses; the real center satisfies it as-is. */
@protocol FBDeliveredNotificationsCenter <NSObject>
- (void)getDeliveredNotificationsWithCompletionHandler:(void (^)(NSArray<UNNotification *> *notifications))completionHandler;
@end

/** The part of `UNUserNotificationServiceConnection` a clear uses; the real connection satisfies it as-is. */
@protocol FBDeliveredNotificationsRemover <NSObject>
- (void)removeAllDeliveredNotificationsForBundleIdentifier:(NSString *)bundleIdentifier
                                         completionHandler:(void (^)(BOOL success))completionHandler;
@end

typedef NS_ENUM(NSInteger, FBDeliveredNotificationsReadStatus) {
  FBDeliveredNotificationsReadStatusReceived,
  FBDeliveredNotificationsReadStatusTimedOut,
  FBDeliveredNotificationsReadStatusRaised,
};

@interface FBDeliveredNotificationValues : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nullable, nonatomic, readonly, copy) NSString *identifier;
@property (nullable, nonatomic, readonly, copy) NSString *title;
@property (nullable, nonatomic, readonly, copy) NSString *subtitle;
@property (nullable, nonatomic, readonly, copy) NSString *body;
@property (nullable, nonatomic, readonly, copy) NSString *threadIdentifier;
@property (nullable, nonatomic, readonly) NSNumber *date;
@property (nullable, nonatomic, readonly, copy) NSString *readError;
@end

@interface FBDeliveredNotificationsReadResult : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) FBDeliveredNotificationsReadStatus status;
@property (nonatomic, readonly, copy) NSArray<FBDeliveredNotificationValues *> *notifications;
@property (nullable, nonatomic, readonly, copy) NSString *exceptionDescription;
@end

@interface FBDeliveredNotificationsClient : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
+ (nullable instancetype)liveClientForBundleID:(NSString *)bundleID NS_SWIFT_NAME(live(bundleID:));
- (instancetype)initWithCenter:(nullable id)center;
/** Late callbacks retain their own storage after a timed-out read returns. */
- (FBDeliveredNotificationsReadResult *)readWithTimeout:(NSTimeInterval)timeout NS_SWIFT_NAME(read(timeout:));
@end

typedef NS_ENUM(NSInteger, FBDeliveredNotificationsRemovalStatus) {
  FBDeliveredNotificationsRemovalStatusRemoved,
  FBDeliveredNotificationsRemovalStatusRefused,
  FBDeliveredNotificationsRemovalStatusTimedOut,
  FBDeliveredNotificationsRemovalStatusRaised,
};

@interface FBDeliveredNotificationsRemovalResult : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) FBDeliveredNotificationsRemovalStatus status;
@property (nullable, nonatomic, readonly, copy) NSString *exceptionDescription;
@end

@interface FBDeliveredNotificationsRemovalClient : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/** Nil where this runtime has no connection to `usernotificationsd` to vend. */
+ (nullable instancetype)liveClient NS_SWIFT_NAME(live());
- (instancetype)initWithRemover:(id)remover;
/** Late callbacks retain their own storage after a timed-out removal returns. */
- (FBDeliveredNotificationsRemovalResult *)removeAllForBundleID:(NSString *)bundleID
                                                        timeout:(NSTimeInterval)timeout NS_SWIFT_NAME(removeAll(bundleID:timeout:));
@end

NS_ASSUME_NONNULL_END

#endif
