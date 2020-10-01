/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSpringboardServicesClient.h"

#import "FBAMDServiceConnection.h"

NSString *const FBSpringboardServiceName = @"com.apple.springboardservices";

@interface FBSpringboardServicesClient ()

@property (nonatomic, strong, readonly) FBAMDServiceConnection *connection;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBSpringboardServicesClient

#pragma mark Initializers

+ (instancetype)springboardServicesClientWithConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBDeviceControl.springboard_services", DISPATCH_QUEUE_SERIAL);
  return [[self alloc] initWithConnection:connection queue:queue logger:logger];
}

- (instancetype)initWithConnection:(FBAMDServiceConnection *)connection queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark Public Methods


- (FBFuture<IconLayoutType> *)getIconLayout
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ IconLayoutType (NSError **error) {
      NSArray<id> *result = [self.connection sendAndReceiveMessage:@{@"command": @"getIconState", @"formatVersion": @"2"} error:error];
      if (!result) {
        return nil;
      }
      return [FBCollectionOperations recursiveFilteredJSONSerializableRepresentationOfArray:result];
    }];
}

@end
