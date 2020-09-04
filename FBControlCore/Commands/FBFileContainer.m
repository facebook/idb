/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFileContainer.h"

#import "FBProvisioningProfileCommands.h"
#import "FBControlCoreError.h"

@interface FBFileContainer_ProvisioningProfile : NSObject <FBFileContainer>

@property (nonatomic, strong, readonly) id<FBProvisioningProfileCommands> commands;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBFileContainer_ProvisioningProfile

- (instancetype)initWithCommands:(id<FBProvisioningProfileCommands>)commands queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _commands = commands;
  _queue = queue;

  return self;
}

#pragma mark FBFileContainer Implementation

- (FBFuture<NSNull *> *)copyPathOnHost:(NSURL *)path toDestination:(NSString *)destinationPath
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      NSError *error = nil;
      NSData *data = [NSData dataWithContentsOfURL:path options:0 error:&error];
      if (!data) {
        return [FBFuture futureWithError:error];
      }
      return [[self.commands installProvisioningProfile:data] mapReplace:NSNull.null];
    }];
}

- (FBFuture<NSString *> *)copyItemInContainer:(NSString *)containerPath toDestinationOnHost:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)movePath:(NSString *)originPath toDestinationPath:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)removePath:(NSString *)path
{
  return [[self.commands removeProvisioningProfile:path] mapReplace:NSNull.null];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [[self.commands
    allProvisioningProfiles]
    onQueue:self.queue map:^(NSArray<NSDictionary<NSString *,id> *> *profiles) {
      NSMutableArray<NSString *> *files = NSMutableArray.array;
      for (NSDictionary<NSString *,id> *profile in profiles) {
        [files addObject:profile[@"UUID"]];
      }
      return files;
    }];
}

@end

@implementation FBFileContainer

+ (id<FBFileContainer>)fileContainerForProvisioningProfileCommands:(id<FBProvisioningProfileCommands>)commands queue:(dispatch_queue_t)queue
{
  return [[FBFileContainer_ProvisioningProfile alloc] initWithCommands:commands queue:queue];
}

@end
