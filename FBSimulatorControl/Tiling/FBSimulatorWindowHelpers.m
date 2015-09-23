/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorWindowHelpers.h"

#import "FBSimulator.h"
#import "FBSimulatorPredicates.h"
#import "FBSimulatorPool.h"

// See https://github.com/appium/screen_recording/pull/6
extern void CGSInitialize(void);
static void EnsureCGIsInitialized(void)
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    CGSInitialize();
  });
}

@implementation FBSimulatorWindowHelpers

+ (NSArray *)obtainBoundsOfOtherSimulators:(FBSimulator *)simulator
{
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBSimulatorPredicates launched],
    [NSCompoundPredicate notPredicateWithSubpredicate:[FBSimulatorPredicates only:simulator]],
  ]];
  NSOrderedSet *simulators = [simulator.pool.allSimulators filteredOrderedSetUsingPredicate:predicate];
  NSArray *windows = [self windowsForSimulators:simulators];

  NSMutableArray *boundsValues = [NSMutableArray array];
  for (NSDictionary *window in windows) {
    NSDictionary *boundsDictionary = window[(NSString *)kCGWindowBounds];
    CGRect windowBounds = CGRectZero;
    if (!CGRectMakeWithDictionaryRepresentation((CFDictionaryRef) boundsDictionary, &windowBounds)) {
      continue;
    }
    [boundsValues addObject:[NSValue valueWithRect:windowBounds]];
  }
  return [boundsValues copy];
}

+ (NSArray *)windowsForSimulators:(NSOrderedSet *)simulators
{
  NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));

  // Filtering by PID first will knock out all non-Simulator processes.
  NSOrderedSet *pids = [simulators valueForKey:@"processIdentifier"];
  NSPredicate *pidPredicate = [NSPredicate predicateWithBlock:^ BOOL (NSDictionary *window, NSDictionary *_) {
    NSNumber *processIdentifier = window[(NSString *)kCGWindowOwnerPID];
    return [pids containsObject:processIdentifier];
  }];
  // Each Simulator Process appears to have multiple Windows, with strange bounds.
  // We just care about the named one, which is the Simulator.app window with the Simulator's canvas.
  NSPredicate *namePredicate = [NSPredicate predicateWithBlock:^ BOOL (NSDictionary *window, NSDictionary *_) {
    NSString *windowName = window[(NSString *)kCGWindowName];
    return windowName.length > 0;
  }];
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    pidPredicate,
    namePredicate
  ]];

  return [windows filteredArrayUsingPredicate:predicate];
}

+ (CGDirectDisplayID)displayIDForSimulator:(FBSimulator *)simulator cropRect:(CGRect *)cropRect screenSize:(CGSize *)screenSize
{
  EnsureCGIsInitialized();

  NSDictionary *window = [[self windowsForSimulators:[NSOrderedSet orderedSetWithObject:simulator]] firstObject];
  if (!window) {
    return 0;
  }

  NSDictionary *boundsDictionary = window[(NSString *)kCGWindowBounds];
  CGRect windowBounds = CGRectZero;
  if (!CGRectMakeWithDictionaryRepresentation((CFDictionaryRef) boundsDictionary, &windowBounds)) {
    return 0;
  }

  CGDirectDisplayID displayID = 0;
  CGGetDisplaysWithRect(windowBounds, 1, &displayID, NULL);
  CGRect displayBounds = CGDisplayBounds(displayID);

  if (cropRect) {
    CGRect displayBounds = CGDisplayBounds(displayID);
    *cropRect = CGRectMake(
      CGRectGetMinX(windowBounds) - CGRectGetMinX(displayBounds),
      CGRectGetMaxY(displayBounds) - CGRectGetHeight(windowBounds),
      CGRectGetWidth(windowBounds),
      CGRectGetHeight(windowBounds)
    );
  }
  if (screenSize) {
    *screenSize = CGDisplayScreenSize(displayID);
  }

  return displayID;
}

@end
