/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBManagedConfigClient.h"

#import "FBAMDServiceConnection.h"

NSString *const FBManagedConfigService = @"com.apple.mobile.MCInstall";

@interface FBManagedConfigClient ()

@property (nonatomic, strong, readonly) FBAMDServiceConnection *connection;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBManagedConfigClient

#pragma mark Initializers

+ (instancetype)managedConfigClientWithConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBDeviceControl.managed_config", DISPATCH_QUEUE_SERIAL);
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

- (FBFuture<NSDictionary<NSString *, id> *> *)getCloudConfiguration
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSDictionary<NSString *, id> * (NSError **error) {
      NSDictionary<NSString *, id> *result = [self.connection sendAndReceiveMessage:@{@"RequestType": @"GetCloudConfiguration"} error:error];
      if (!result) {
        return nil;
      }
      return [FBCollectionOperations recursiveFilteredJSONSerializableRepresentationOfDictionary:result];
    }];
}

@end
