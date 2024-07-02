/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestResultToolOperation.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const XcrunPath = @"/usr/bin/xcrun";
NSString *const SipsPath = @"/usr/bin/sips";
NSString *const HEIC = @"public.heic";
NSString *const JPEG = @"public.jpeg";

@implementation FBXCTestResultToolOperation

#pragma mark Private

+ (FBFuture<FBProcess *> *)internalOperationWithArguments:(NSArray<NSString *> *)arguments queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  NSArray<NSString *> *xcrunArguments = [@[@"xcresulttool"] arrayByAddingObjectsFromArray:arguments];
  return [[[[[[FBProcessBuilder
    withLaunchPath:XcrunPath]
    withArguments:xcrunArguments]
    withStdErrToLogger:logger]
    withTaskLifecycleLoggingTo:logger]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    onQueue:queue map:^(FBProcess *task) {
      return task;
    }];
}

+ (FBFuture<FBProcess *> *)exportFrom:(NSString *)path to:(NSString *)destination forId:(NSString *)bundleObjectId withType:(NSString *)exportType queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  NSArray<NSString *> *arguments = @[@"export", @"--path", path, @"--output-path", destination, @"--id", bundleObjectId, @"--type", exportType];
  return [FBXCTestResultToolOperation internalOperationWithArguments:arguments queue:queue logger:logger];
}

+ (NSDictionary<NSString *, NSDictionary<NSString *, id> *> *)getJSONFromTask:(FBProcess *)task
{
  NSData *data = [task.stdOut dataUsingEncoding:NSUTF8StringEncoding];
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

# pragma mark Public

+ (FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> *)getJSONFrom:(NSString *)path forId:(nullable NSString *)bundleObjectId queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  [logger logFormat:@"Getting json for id %@", bundleObjectId];
  NSMutableArray<NSString *> *arguments = [[NSMutableArray alloc] init];
  [arguments addObjectsFromArray:@[@"get", @"--path", path, @"--format", @"json"]];
  if (bundleObjectId && bundleObjectId.length > 0) {
    [arguments addObjectsFromArray:@[@"--id", bundleObjectId]];
  }
  return [[FBXCTestResultToolOperation internalOperationWithArguments:arguments queue:queue logger:logger]
    onQueue:queue map:^(FBProcess *task) {
      return [FBXCTestResultToolOperation getJSONFromTask:task];
    }];
}

+ (FBFuture<FBProcess *> *)exportFileFrom:(NSString *)path to:(NSString *)destination forId:(NSString *)bundleObjectId queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  return [FBXCTestResultToolOperation exportFrom:path to:destination forId:bundleObjectId withType:@"file" queue:queue logger:logger];
}

+ (FBFuture<FBProcess *> *)exportJPEGFrom:(NSString *)path to:(NSString *)destination forId:(NSString *)bundleObjectId type:(NSString *)encodeType queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  return [[FBXCTestResultToolOperation
   exportFileFrom:path to:destination forId:bundleObjectId queue:queue logger:logger]
   onQueue:queue fmap:^ FBFuture * (FBProcess *task) {
     if ([encodeType isEqualToString:HEIC]) {
       NSArray<NSString *> *arguments = @[@"-s", @"format", @"jpeg", destination, @"--out", destination];
       return [[[[[FBProcessBuilder
         withLaunchPath:SipsPath]
         withArguments:arguments]
         withStdErrToLogger:logger]
         withTaskLifecycleLoggingTo:logger]
         runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]];
     } else if ([encodeType isEqualToString:JPEG]) {
       return [FBFuture futureWithResult:task];
     } else {
       return [[FBControlCoreError describeFormat:@"Unrecognized XCTest screenshot encoding: %@", encodeType] failFuture];
     }
  }];
}

+ (FBFuture<FBProcess *> *)exportDirectoryFrom:(NSString *)path to:(NSString *)destination forId:(NSString *)bundleObjectId queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  return [FBXCTestResultToolOperation exportFrom:path to:destination forId:bundleObjectId withType:@"directory" queue:queue logger:logger];
}

+ (FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> *)describeFormat:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  NSArray<NSString *> *arguments = @[@"formatDescription"];
  return [[FBXCTestResultToolOperation internalOperationWithArguments:arguments queue:queue logger:logger]
    onQueue:queue map:^(FBProcess *task) {
      return [FBXCTestResultToolOperation getJSONFromTask:task];
    }];
}

@end

NS_ASSUME_NONNULL_END
