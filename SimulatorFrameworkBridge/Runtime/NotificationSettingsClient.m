/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NotificationSettingsClient.h"

#import <dlfcn.h>

#import "BulletinBoardPrivate.h"

@protocol NotificationSettingsGateway <NSObject>
- (BBSectionInfo *)sectionInfoForSectionID:(NSString *)sectionID;
- (void)setSectionInfo:(BBSectionInfo *)sectionInfo forSectionID:(NSString *)sectionID;
- (NSArray<NSString *> *)allSectionIDs;
@end

static BOOL performNotificationOperation(void (^operation)(void), NSError **error)
{
  @try {
    operation();
    return YES;
  } @catch (NSException *exception) {
    NSLog(@"[NotificationSettings] Command raised: %@", exception);
    if (error) {
      *error = [NSError errorWithDomain:@"FBNotificationSettingsException" code:1 userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: exception.name}];
    }
    return NO;
  }
}

@implementation FBNotificationSectionValues
- (instancetype)initWithAllowsNotifications:(BOOL)allowed
                        authorizationStatus:(NSUInteger)status
                  showsInNotificationCenter:(NSNumber *)center
                          showsInLockScreen:(NSNumber *)lockScreen
{
  self = [super init];
  if (self) {
    _allowsNotifications = allowed;
    _authorizationStatus = status;
    _showsInNotificationCenter = center;
    _showsInLockScreen = lockScreen;
  }
  return self;
}

@end

@interface FBNotificationSection ()
@property (nullable, nonatomic, strong) BBSectionInfo *sectionInfo;
@end

@implementation FBNotificationSection
- (instancetype)initWithSectionInfo:(BBSectionInfo *)sectionInfo
{
  self = [super init];
  if (self) {
    _sectionInfo = sectionInfo;
  }
  return self;
}

- (BOOL)isFound
{
  return self.sectionInfo != nil;
}

- (FBNotificationSectionValues *)readValuesWithError:(NSError **)error
{
  __block FBNotificationSectionValues *values = nil;
  if (!performNotificationOperation(^{
    NSNumber *center = [self.sectionInfo respondsToSelector:@selector(showsInNotificationCenter)]
    ? @([self.sectionInfo showsInNotificationCenter]) : nil;
    NSNumber *lockScreen = [self.sectionInfo respondsToSelector:@selector(showsInLockScreen)]
    ? @([self.sectionInfo showsInLockScreen]) : nil;
    BOOL allowed = [self.sectionInfo allowsNotifications];
    NSUInteger status = [self.sectionInfo authorizationStatus];
    values = [[FBNotificationSectionValues alloc] initWithAllowsNotifications:allowed
                                                          authorizationStatus:status
                                                    showsInNotificationCenter:center
                                                            showsInLockScreen:lockScreen];
  }, error)) {
    return nil;
  }
  return values;
}

- (BOOL)setAllowsNotifications:(BOOL)allowed error:(NSError **)error
{
  return performNotificationOperation(^{ [self.sectionInfo setAllowsNotifications:allowed]; }, error);
}

- (BOOL)setAuthorizationStatus:(NSUInteger)status error:(NSError **)error
{
  return performNotificationOperation(^{ [self.sectionInfo setAuthorizationStatus:status]; }, error);
}

- (BOOL)setAlertType:(NSUInteger)type error:(NSError **)error
{
  return performNotificationOperation(^{ [self.sectionInfo setAlertType:type]; }, error);
}

- (BOOL)setLockScreenSetting:(NSUInteger)setting error:(NSError **)error
{
  return performNotificationOperation(^{ [self.sectionInfo setLockScreenSetting:setting]; }, error);
}

- (BOOL)setNotificationCenterSetting:(NSUInteger)setting error:(NSError **)error
{
  return performNotificationOperation(^{ [self.sectionInfo setNotificationCenterSetting:setting]; }, error);
}

- (NSArray<NSString *> *)setEffectiveVisibility:(BOOL)visible error:(NSError **)error
{
  NSMutableArray<NSString *> *absent = [NSMutableArray array];
  if (!performNotificationOperation(^{
    if ([self.sectionInfo respondsToSelector:@selector(setShowsInNotificationCenter:)]) {
      [self.sectionInfo setShowsInNotificationCenter:visible];
    } else {
      [absent addObject:@"showsInNotificationCenter"];
    }
    if ([self.sectionInfo respondsToSelector:@selector(setShowsInLockScreen:)]) {
      [self.sectionInfo setShowsInLockScreen:visible];
    } else {
      [absent addObject:@"showsInLockScreen"];
    }
  }, error)) {
    return nil;
  }
  return absent;
}

@end

@implementation FBNotificationSettingsClient
{
  id<NotificationSettingsGateway> _gateway;
}

+ (instancetype)liveClient
{
  __block FBNotificationSettingsClient *client = nil;
  performNotificationOperation(^{
    if (!dlopen("/System/Library/PrivateFrameworks/BulletinBoard.framework/BulletinBoard", RTLD_NOW)) {
      NSLog(@"[NotificationSettings] Failed to load BulletinBoard.framework: %s", dlerror());
      return;
    }
    Class cls = NSClassFromString(@"BBSettingsGateway");
    if (!cls) {
      NSLog(@"[NotificationSettings] BBSettingsGateway class not found");
      return;
    }
    id gateway = [[cls alloc] init];
    if (gateway) {
      client = [[self alloc] initWithGateway:gateway];
    }
  }, nil);
  return client;
}

- (instancetype)initWithGateway:(id)gateway
{
  self = [super init];
  if (self) {
    _gateway = gateway;
  }
  return self;
}

- (NSArray<NSString *> *)allSectionIDsWithError:(NSError **)error
{
  __block NSArray<NSString *> *identifiers = nil;
  if (!performNotificationOperation(^{ identifiers = [self->_gateway allSectionIDs] ?: @[]; }, error)) {
    return nil;
  }
  return identifiers;
}

- (FBNotificationSection *)sectionForIdentifier:(NSString *)identifier error:(NSError **)error
{
  __block FBNotificationSection *section = nil;
  if (!performNotificationOperation(^{
    section = [[FBNotificationSection alloc] initWithSectionInfo:[self->_gateway sectionInfoForSectionID:identifier]];
  }, error)) {
    return nil;
  }
  return section;
}

- (FBNotificationSection *)createSectionForIdentifier:(NSString *)identifier error:(NSError **)error
{
  __block FBNotificationSection *section = nil;
  if (!performNotificationOperation(^{
    BBSectionInfo *info = [NSClassFromString(@"BBSectionInfo") defaultSectionInfoForType:0];
    info.sectionID = identifier;
    section = [[FBNotificationSection alloc] initWithSectionInfo:info];
  }, error)) {
    return nil;
  }
  return section;
}

- (BOOL)writeSection:(FBNotificationSection *)section forIdentifier:(NSString *)identifier error:(NSError **)error
{
  return performNotificationOperation(^{ [self->_gateway setSectionInfo:section.sectionInfo forSectionID:identifier]; }, error);
}

@end
