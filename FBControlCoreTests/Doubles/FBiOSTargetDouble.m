/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSTargetDouble.h"

@implementation FBiOSTargetDouble

@synthesize architecture;
@synthesize deviceOperator;
@synthesize logger;
@synthesize screenInfo;

+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target
{
  return nil;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [self debugDescription];
}

- (NSString *)debugDescription
{
  return [FBiOSTargetFormat.fullFormat format:self];
}

- (NSString *)shortDescription
{
  return [FBiOSTargetFormat.defaultFormat format:self];
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

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return [FBiOSTargetFormat.fullFormat extractFrom:self];
}

#pragma mark Protocol Inheritance

- (FBFuture<NSNull *> *)installApplicationWithPath:(NSString *)path
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSNull *> *)uninstallApplicationWithBundleID:(NSString *)bundleID
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSNumber *> *)isApplicationInstalledWithBundleID:(NSString *)bundleID
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSNull *> *)killApplicationWithBundleID:(NSString *)bundleID
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<id<FBVideoRecordingSession>> *)startRecordingToFile:(NSString *)filePath
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSNull *> *)stopRecording
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<id<FBBitmapStream>> *)createStreamWithConfiguration:(FBBitmapStreamConfiguration *)configuration
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

- (FBFuture<id<FBiOSTargetContinuation>> *)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  return nil;
}

- (NSArray<id<FBiOSTargetContinuation>> *)testOperations
{
  return @[];
}

- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout
{
  return nil;
}

- (FBFuture<NSArray<NSString *> *> *)logLinesWithArguments:(NSArray<NSString *> *)arguments
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<id<FBiOSTargetContinuation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBFileConsumer>)consumer
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

- (FBFuture<NSData *> *)takeScreenshot:(FBScreenshotFormat)format
{
  return [FBFuture futureWithError:[[FBControlCoreError describe:@"Unimplemented"] build]];
}

@end
