/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ServiceTestRuntime.h"

#import <dlfcn.h>
#import <objc/runtime.h>
#import <unistd.h>

#import <SimulatorFrameworkBridgeLib/AccessibilityRuntime_Private.h>
#import <SimulatorFrameworkBridgeLib/BulletinBoardPrivate.h>
#import <SimulatorFrameworkBridgeLib/HealthSettingsService.h>

@interface FakeNotificationSettingsGateway ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, BBSectionInfo *> *sections;
@end

@implementation FakeNotificationSettingsGateway
- (instancetype)init
{
  self = [super init];
  if (self) {
    _sections = [NSMutableDictionary dictionary];
  }
  return self;
}

- (id)sectionInfoForSectionID:(NSString *)sectionID
{
  return self.sections[sectionID];
}

- (void)setSectionInfo:(id)sectionInfo forSectionID:(NSString *)sectionID
{
  self.sections[sectionID] = sectionInfo;
}

- (NSArray<NSString *> *)allSectionIDs
{
  return self.sections.allKeys;
}

@end

Class FBHealthAuthorizationStoreClass(void)
{
  dlopen("/System/Library/Frameworks/HealthKit.framework/HealthKit", RTLD_NOW);
  return objc_lookUpClass("HKAuthorizationStore");
}

BOOL FBHealthRuntimeDeclaresSelector(NSString *selectorName)
{
  Class cls = FBHealthAuthorizationStoreClass();
  return cls != Nil && [cls instancesRespondToSelector:NSSelectorFromString(selectorName)];
}

NSException *FBHealthApproveException(NSArray<NSString *> *types)
{
  @try {
    handleHealthSettingsAction(@"approve", @"com.example.test", types);
    return nil;
  } @catch (NSException *exception) {
    return exception;
  }
}

@implementation FBSectionInfoWithOnlyNotificationCenterFlag
@end

@implementation FBSectionInfoWithoutEffectiveFlags
@end

BOOL FBNotificationAllowsNotifications(id sectionInfo)
{
  return [(BBSectionInfo *)sectionInfo allowsNotifications];
}

NSInteger FBNotificationAuthorizationStatus(id sectionInfo)
{
  return [(BBSectionInfo *)sectionInfo authorizationStatus];
}

BOOL FBNotificationShowsInNotificationCenter(id sectionInfo)
{
  return [(BBSectionInfo *)sectionInfo showsInNotificationCenter];
}

BOOL FBNotificationShowsInLockScreen(id sectionInfo)
{
  return [(BBSectionInfo *)sectionInfo showsInLockScreen];
}

NSString *FBStdoutWhileRunning(void (^block)(void))
{
  NSPipe *pipe = [NSPipe pipe];
  // Drained on another queue for as long as the block runs, rather than after it returns: a
  // pipe nobody is reading holds only a buffer's worth (16-64KB on Darwin), and the write that
  // fills it blocks forever inside `printf`. That would hang the whole test process rather
  // than fail one test, and what these services print is not bounded - `notifications list`
  // prints a record per section, and an accessibility read prints a hierarchy.
  NSMutableData *written = [NSMutableData data];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.idb.stdout-capture", DISPATCH_QUEUE_SERIAL);
  dispatch_group_t draining = dispatch_group_create();
  NSFileHandle *reader = pipe.fileHandleForReading;
  fflush(stdout);
  int original = dup(STDOUT_FILENO);
  dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO);
  dispatch_group_async(draining,
    queue, ^{
      // Ends when the write end is closed below, which is what makes this read return empty.
      while (true) {
        NSData *chunk = [reader availableData];
        if (chunk.length == 0) {
          break;
        }
        [written appendData:chunk];
      }
    });
  @try {
    block();
  } @finally {
    fflush(stdout);
    dup2(original, STDOUT_FILENO);
    close(original);
    [pipe.fileHandleForWriting closeFile];
  }
  dispatch_group_wait(draining, DISPATCH_TIME_FOREVER);
  return [[NSString alloc] initWithData:written encoding:NSUTF8StringEncoding];
}

NSDictionary<NSString *, id> *FBParsedJSONLine(NSString *output)
{
  return [NSJSONSerialization JSONObjectWithData:[output dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
}

NSDictionary<NSString *, NSNumber *> *FBAXRuntimeQueueProbe(BOOL raise)
{
  __block BOOL offMain = NO;
  __block NSUInteger calls = 0;
  NSException *expected = [NSException exceptionWithName:NSInternalInconsistencyException reason:@"worker failed" userInfo:nil];
  NSException *caught = nil;
  @try {
    FBAXBridgeRunOffMainQueue(^{
      offMain = !NSThread.isMainThread;
      calls++;
      if (raise) {
        @throw expected;
      }
    });
  } @catch (NSException *exception) {
    caught = exception;
  }
  return @{@"offMain" : @(offMain), @"calls" : @(calls), @"sameException" : @(caught == expected), @"caught" : @(caught != nil)};
}
