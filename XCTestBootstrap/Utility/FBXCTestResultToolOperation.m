/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestResultToolOperation.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const XcrunPath = @"/usr/bin/xcrun";

@implementation FBXCTestResultToolOperation

#pragma mark Private

+ (FBFuture<FBTask *> *)internalOperationWithArguments:(NSArray<NSString *> *)arguments queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  NSArray<NSString *> *xcrunArguments = [@[@"xcresulttool"] arrayByAddingObjectsFromArray:arguments];
  return [[[[[FBTaskBuilder
    withLaunchPath:XcrunPath]
    withArguments:xcrunArguments]
    withStdErrToLogger:logger]
    runUntilCompletion]
    onQueue:queue map:^(FBTask *task) {
      return task;
    }];
}

+ (FBFuture<FBTask *> *)exportFrom:(NSString *)path to:(NSString *)destination forId:(NSString *)bundleObjectId withType:(NSString *)exportType queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  NSArray<NSString *> *arguments = @[@"export", @"--path", path, @"--output-path", destination, @"--id", bundleObjectId, @"--type", exportType];
  return [FBXCTestResultToolOperation internalOperationWithArguments:arguments queue:queue logger:logger];
}

+ (NSDictionary<NSString *, NSDictionary<NSString *, id> *> *)getJSONFromTask:(FBTask *)task
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
    onQueue:queue map:^(FBTask *task) {
      return [FBXCTestResultToolOperation getJSONFromTask:task];
    }];
}

+ (FBFuture<FBTask *> *)exportFileFrom:(NSString *)path to:(NSString *)destination forId:(NSString *)bundleObjectId queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  return [FBXCTestResultToolOperation exportFrom:path to:destination forId:bundleObjectId withType:@"file" queue:queue logger:logger];
}

+ (FBFuture<FBTask *> *)exportDirectoryFrom:(NSString *)path to:(NSString *)destination forId:(NSString *)bundleObjectId queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  return [FBXCTestResultToolOperation exportFrom:path to:destination forId:bundleObjectId withType:@"directory" queue:queue logger:logger];
}

+ (FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> *)describeFormat:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  NSArray<NSString *> *arguments = @[@"formatDescription"];
  return [[FBXCTestResultToolOperation internalOperationWithArguments:arguments queue:queue logger:logger]
    onQueue:queue map:^(FBTask *task) {
      return [FBXCTestResultToolOperation getJSONFromTask:task];
    }];
}

@end

NS_ASSUME_NONNULL_END
