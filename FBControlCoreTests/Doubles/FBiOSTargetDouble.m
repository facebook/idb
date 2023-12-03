/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetDouble.h"

@implementation FBiOSTargetDouble

@synthesize architectures;
@synthesize logger;
@synthesize platformRootDirectory;
@synthesize runtimeRootDirectory;
@synthesize screenInfo;
@synthesize temporaryDirectory;

+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target
{
  return nil;
}

- (dispatch_queue_t)workQueue
{
  return dispatch_get_main_queue();
}

- (dispatch_queue_t)asyncQueue
{
  return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
}

- (NSComparisonResult)compare:(id<FBiOSTarget>)target
{
  return FBiOSTargetComparison(self, target);
}

- (NSDictionary<NSString *, id> *)extendedInformation
{
  return @{};
}

#pragma mark Protocol Inheritance

- (NSDictionary<NSString *, NSString *> *)replacementMapping
{
  return @{};
}

- (FBFuture<NSNull *> *)installApplicationWithPath:(NSString *)path
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSNull *> *)uninstallApplicationWithBundleID:(NSString *)bundleID
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<FBProcess *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSNull *> *)killApplicationWithBundleID:(NSString *)bundleID
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<id<FBiOSTargetOperation>> *)startRecordingToFile:(NSString *)filePath
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSNull *> *)stopRecording
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<id<FBVideoStream>> *)createStreamWithConfiguration:(FBVideoStreamConfiguration *)configuration
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSArray<FBInstalledApplication *> *> *)installedApplications
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<FBInstalledApplication *> *)installedApplicationWithBundleID:(NSString *)bundleID
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSDictionary<NSString *, FBProcessInfo *> *> *)runningApplications
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSNumber *> *)processIDWithBundleID:(NSString *)bundleID
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSNull *> *)runTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  return nil;
}

- (NSArray<id<FBiOSTargetOperation>> *)testOperations
{
  return @[];
}

- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout withAppAtPath:(NSString *)appPath
{
  return nil;
}

- (FBFutureContext<NSNumber *> *)transportForTestManagerService
{
  return [FBFutureContext futureContextWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSArray<NSString *> *> *)logLinesWithArguments:(NSArray<NSString *> *)arguments
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<id<FBiOSTargetOperation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSData *> *)takeScreenshot:(FBScreenshotFormat)format
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crashes:(NSPredicate *)predicate useCache:(BOOL)useCache
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<FBCrashLogInfo *> *)notifyOfCrash:(NSPredicate *)predicate
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)pruneCrashes:(NSPredicate *)predicate
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (nonnull FBFutureContext<id<FBFileContainer>> *)crashLogFiles
{
  return [FBFutureContext futureContextWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<FBInstrumentsOperation *> *)startInstruments:(FBInstrumentsConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<FBXCTraceRecordOperation *> *)startXctraceRecord:(FBXCTraceRecordConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (BOOL) requiresBundlesToBeSigned
{
  return NO;
}

- (FBFuture<NSNull *> *)resolveState:(FBiOSTargetState)state
{
  return FBMutableFuture.future;
}

- (FBFuture<NSNull *> *)resolveLeavesState:(FBiOSTargetState)state
{
  return FBMutableFuture.future;
}

@end
