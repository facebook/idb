/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DeliveredNotificationsClient.h"

#import <TargetConditionals.h>

#if !TARGET_OS_TV
 #import "UserNotificationsPrivate.h"

@protocol FBNotificationCenterReading <NSObject>
- (void)getDeliveredNotificationsWithCompletionHandler:(void (^)(NSArray<UNNotification *> *notifications))completionHandler;
@end

@protocol FBNotificationServiceConnectionRemoving <NSObject>
- (void)removeAllDeliveredNotificationsForBundleIdentifier:(NSString *)bundleIdentifier
                                         completionHandler:(void (^)(BOOL success))completionHandler;
@end

static id CenterForBundleID(NSString *bundleID)
{
  Class centerClass = NSClassFromString(@"UNUserNotificationCenter");
  if (!centerClass) {
    NSLog(@"[DeliveredNotifications] UNUserNotificationCenter class not found");
    return nil;
  }
  if (![centerClass instancesRespondToSelector:@selector(initWithBundleIdentifier:)]) {
    NSLog(@"[DeliveredNotifications] UNUserNotificationCenter has no initWithBundleIdentifier:");
    return nil;
  }
  // Declaring the selector says what its signature is if the runtime has it, not that the
  // runtime will accept this bundle: it raises for one with no registered notification
  // settings, and nothing above this has a handler, so an uncaught raise ends the guest
  // before the store fallback the caller has for exactly that case.
  UNUserNotificationCenter *center = nil;
  @try {
    center = [[centerClass alloc] initWithBundleIdentifier:bundleID];
  } @catch (NSException *exception) {
    NSLog(@"[DeliveredNotifications] initWithBundleIdentifier: raised for %@: %@", bundleID, exception);
    return nil;
  }
  if (!center) {
    NSLog(@"[DeliveredNotifications] No notification center for %@", bundleID);
    return nil;
  }
  return (id)center;
}

/**
 * The shared connection to `usernotificationsd`, or nil where this runtime has none to vend.
 *
 * Unlike a center, it is not scoped to a bundle: which app's notifications it may remove is
 * decided by the daemon from who is asking, not by anything this process tells it.
 */
static id DaemonConnection(void)
{
  Class connectionClass = NSClassFromString(@"UNUserNotificationServiceConnection");
  if (!connectionClass) {
    NSLog(@"[DeliveredNotifications] UNUserNotificationServiceConnection class not found");
    return nil;
  }
  if (![connectionClass respondsToSelector:@selector(sharedInstance)]
      || ![connectionClass instancesRespondToSelector:@selector(removeAllDeliveredNotificationsForBundleIdentifier:completionHandler:)]) {
    NSLog(@"[DeliveredNotifications] UNUserNotificationServiceConnection cannot remove delivered notifications");
    return nil;
  }
  return [connectionClass sharedInstance];
}

@implementation FBDeliveredNotificationValues
- (instancetype)initWithNotification:(UNNotification *)notification
{
  self = [super init];
  if (self) {
    UNNotificationRequest *request = notification.request;
    UNNotificationContent *content = request.content;
    _identifier = [request.identifier copy];
    _title = [content.title copy];
    _subtitle = [content.subtitle copy];
    _body = [content.body copy];
    _threadIdentifier = [content.threadIdentifier copy];
    if (notification.date) {
      _date = @([notification.date timeIntervalSince1970]);
    }
  }
  return self;
}

@end

@implementation FBDeliveredNotificationsReadResult
- (instancetype)initWithStatus:(FBDeliveredNotificationsReadStatus)status
                 notifications:(NSArray<FBDeliveredNotificationValues *> *)notifications
          exceptionDescription:(NSString *)exceptionDescription
{
  self = [super init];
  if (self) {
    _status = status;
    _notifications = [notifications copy];
    _exceptionDescription = [exceptionDescription copy];
  }
  return self;
}

@end

@implementation FBDeliveredNotificationsClient
{
  id<FBNotificationCenterReading> _center;
}

+ (instancetype)liveClientForBundleID:(NSString *)bundleID
{
  id center = CenterForBundleID(bundleID);
  return center ? [[self alloc] initWithCenter:center] : nil;
}

- (instancetype)initWithCenter:(id)center
{
  self = [super init];
  if (self) {
    _center = center;
  }
  return self;
}

- (FBDeliveredNotificationsReadResult *)readWithTimeout:(NSTimeInterval)timeout
{
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  NSMutableArray<UNNotification *> *received = [NSMutableArray array];
  @try {
    [_center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
      if (notifications.count > 0) {
        [received addObjectsFromArray:notifications];
      }
      dispatch_semaphore_signal(semaphore);
    }];
  } @catch (NSException *exception) {
    return [[FBDeliveredNotificationsReadResult alloc] initWithStatus:FBDeliveredNotificationsReadStatusRaised
                                                        notifications:@[]
                                                 exceptionDescription:[NSString stringWithFormat:@"%@", exception]];
  }
  if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
    return [[FBDeliveredNotificationsReadResult alloc] initWithStatus:FBDeliveredNotificationsReadStatusTimedOut
                                                        notifications:@[]
                                                 exceptionDescription:nil];
  }
  NSMutableArray<FBDeliveredNotificationValues *> *values = [NSMutableArray arrayWithCapacity:received.count];
  for (UNNotification *notification in received) {
    [values addObject:[[FBDeliveredNotificationValues alloc] initWithNotification:notification]];
  }
  return [[FBDeliveredNotificationsReadResult alloc] initWithStatus:FBDeliveredNotificationsReadStatusReceived
                                                      notifications:values
                                               exceptionDescription:nil];
}

@end

@implementation FBDeliveredNotificationsRemovalResult
- (instancetype)initWithStatus:(FBDeliveredNotificationsRemovalStatus)status exceptionDescription:(NSString *)exceptionDescription
{
  self = [super init];
  if (self) {
    _status = status;
    _exceptionDescription = [exceptionDescription copy];
  }
  return self;
}

@end

@implementation FBDeliveredNotificationsRemovalClient
{
  id<FBNotificationServiceConnectionRemoving> _remover;
}

+ (instancetype)liveClient
{
  id connection = DaemonConnection();
  return connection ? [[self alloc] initWithRemover:connection] : nil;
}

- (instancetype)initWithRemover:(id)remover
{
  self = [super init];
  if (self) {
    _remover = remover;
  }
  return self;
}

- (FBDeliveredNotificationsRemovalResult *)removeAllForBundleID:(NSString *)bundleID timeout:(NSTimeInterval)timeout
{
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  NSMutableArray<NSNumber *> *answer = [NSMutableArray array];
  @try {
    [_remover removeAllDeliveredNotificationsForBundleIdentifier:bundleID
                                               completionHandler:^(BOOL success) {
                                                 [answer addObject:@(success)];
                                                 dispatch_semaphore_signal(semaphore);
                                               }];
  } @catch (NSException *exception) {
    return [[FBDeliveredNotificationsRemovalResult alloc] initWithStatus:FBDeliveredNotificationsRemovalStatusRaised
                                                    exceptionDescription:[NSString stringWithFormat:@"%@", exception]];
  }
  if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
    return [[FBDeliveredNotificationsRemovalResult alloc] initWithStatus:FBDeliveredNotificationsRemovalStatusTimedOut exceptionDescription:nil];
  }
  FBDeliveredNotificationsRemovalStatus status = [answer.firstObject boolValue]
  ? FBDeliveredNotificationsRemovalStatusRemoved
  : FBDeliveredNotificationsRemovalStatusRefused;
  return [[FBDeliveredNotificationsRemovalResult alloc] initWithStatus:status exceptionDescription:nil];
}

@end
#endif
