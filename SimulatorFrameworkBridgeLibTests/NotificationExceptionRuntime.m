/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NotificationExceptionRuntime.h"

#import "ServiceTestRuntime.h"

@interface FBNotificationFailureProbe : NSObject
@property (nonatomic, copy) NSString *operation;
@end

@implementation FBNotificationFailureProbe
- (void)raiseForOperation:(NSString *)operation
{
  if ([self.operation isEqualToString:operation]) {
    [NSException raise:@"NotificationTest" format:@"%@ failed", operation];
  }
}

- (id)sectionInfoForSectionID:(NSString *)sectionID
{
  [self raiseForOperation:@"lookup"];
  return self;
}

- (void)setSectionInfo:(id)section forSectionID:(NSString *)sectionID
{
  [self raiseForOperation:@"write"];
}

- (NSArray<NSString *> *)allSectionIDs
{
  [self raiseForOperation:@"list"];
  return @[@"com.example.notification"];
}

- (BOOL)allowsNotifications
{
  [self raiseForOperation:@"allowsNotifications"];
  return YES;
}

- (NSUInteger)authorizationStatus
{
  [self raiseForOperation:@"authorizationStatus"];
  return 2;
}

- (void)setAllowsNotifications:(BOOL)enabled { [self raiseForOperation:@"setAllowsNotifications"]; }

- (void)setAuthorizationStatus:(NSUInteger)value { [self raiseForOperation:@"setAuthorizationStatus"]; }

- (void)setAlertType:(NSUInteger)value { [self raiseForOperation:@"setAlertType"]; }

- (void)setLockScreenSetting:(NSUInteger)value { [self raiseForOperation:@"setLockScreenSetting"]; }

- (void)setNotificationCenterSetting:(NSUInteger)value { [self raiseForOperation:@"setNotificationCenterSetting"]; }

@end

NSDictionary<NSString *, id> *FBNotificationCommandExceptionResult(NSString *operation)
{
  FBNotificationFailureProbe *gateway = [FBNotificationFailureProbe new];
  gateway.operation = operation;
  NSString *action = [@[@"allowsNotifications", @"authorizationStatus"] containsObject:operation] ? @"check" : @"approve";
  NSString *bundleID = @"com.example.notification";
  if ([operation isEqualToString:@"list"]) {
    action = @"list";
    bundleID = nil;
  }
  @try {
    return @{@"status" : @(handleNotificationSettingsActionWithGateway(action, bundleID, gateway))};
  } @catch (NSException *exception) {
    return @{@"exception" : exception.name};
  }
}
