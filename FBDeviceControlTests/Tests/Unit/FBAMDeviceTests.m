/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBDeviceControl/FBDeviceControl.h>

@interface FBAMDeviceTests : XCTestCase

@property (nonatomic, strong, readwrite, class) NSMutableArray<NSString *> *events;
@property (nonatomic, strong, readonly) FBAMDevice *device;

@end

static void Retain(AMDeviceRef ref)
{

}

static void Release(AMDeviceRef ref)
{

}

static int Connect(AMDeviceRef ref)
{
  [FBAMDeviceTests.events addObject:@"connect"];
  return 0;
}

static int Disconnect(AMDeviceRef ref)
{
  [FBAMDeviceTests.events addObject:@"disconnect"];
  return 0;
}

static int StartSession(AMDeviceRef ref)
{
  [FBAMDeviceTests.events addObject:@"start_session"];
  return 0;
}

static int StopSession(AMDeviceRef ref)
{
  [FBAMDeviceTests.events addObject:@"stop_session"];
  return 0;
}

static int SecureStartService(AMDeviceRef device, CFStringRef service_name, CFDictionaryRef userinfo, CFTypeRef *serviceOut)
{
  [FBAMDeviceTests.events addObject:@"secure_start_service"];
  *serviceOut = CFSTR("A Service");
  return 0;
}

static int ServiceConnectionInvalidate(CFTypeRef connection)
{
  [FBAMDeviceTests.events addObject:@"service_connection_invalidate"];
  return 0;
}

static CFStringRef CopyValue(AMDeviceRef device, CFStringRef domain, CFStringRef name)
{
  return name;
}

static int CreateHouseArrestService(AMDeviceRef device, CFStringRef bundleID, void *unused, AFCConnectionRef *connectionOut)
{
  [FBAMDeviceTests.events addObject:@"create_house_arrest_service"];
  *connectionOut = (AFCConnectionRef) CFSTR("A HOUSE ARREST");
  return 0;
}

static int ConnectionClose(AFCConnectionRef connection)
{
  [FBAMDeviceTests.events addObject:@"connection_close"];
  return 0;
}

static int IsPaired(AMDeviceRef device)
{
  [FBAMDeviceTests.events addObject:@"is_paired"];
  return YES;
}

static int ValidatePairing(AMDeviceRef device)
{
  [FBAMDeviceTests.events addObject:@"validate_pairing"];
  return 0;
}

@implementation FBAMDeviceTests

@synthesize device = _device;

static NSMutableArray<NSString *> *sEvents;

+ (NSMutableArray<NSString *> *)events
{
  if (!sEvents){
    sEvents = [NSMutableArray array];
  }
  return sEvents;
}

+ (void)setEvents:(NSMutableArray<NSString *> *)events
{
  sEvents = events;
}

- (AMDeviceRef)amDeviceRef
{
  return (AMDeviceRef) CFSTR("A DEVICE");
}

- (AMDCalls)stubbedCalls
{
  AMDCalls calls = {
    .Retain = Retain,
    .Release = Release,
    .Connect = Connect,
    .Disconnect = Disconnect,
    .StartSession = StartSession,
    .StopSession = StopSession,
    .CopyValue = CopyValue,
    .IsPaired = IsPaired,
    .ValidatePairing = ValidatePairing,
    .SecureStartService = SecureStartService,
    .CreateHouseArrestService = CreateHouseArrestService,
    .ServiceConnectionInvalidate = ServiceConnectionInvalidate,
  };
  return calls;
}

- (void)tearDown
{
  _device = nil;
}

- (FBAMDevice *)deviceWithConnectionReuseTimeout:(NSNumber *)connectionReuseTimeout serviceReuseTimeout:(NSNumber *)serviceReuseTimeout
{
  [FBAMDeviceTests.events removeAllObjects];

  NSArray<NSString *> *events = [FBAMDeviceTests.events copy];
  XCTAssertEqualObjects(events, @[]);

  FBAMDevice *device = [[FBAMDevice alloc] initWithAllValues:@{@"UniqueDeviceID": @"foo"} calls:self.stubbedCalls connectionReuseTimeout:connectionReuseTimeout serviceReuseTimeout:serviceReuseTimeout workQueue:dispatch_get_main_queue() logger:FBControlCoreGlobalConfiguration.defaultLogger];
  device.amDeviceRef = self.amDeviceRef;
  events = [FBAMDeviceTests.events copy];
  XCTAssertEqualObjects(events, @[]);
  [FBAMDeviceTests.events removeAllObjects];
  return device;
}

- (FBAMDevice *)device
{
  if (!_device) {
    _device = [self deviceWithConnectionReuseTimeout:nil serviceReuseTimeout:nil];
  }
  return _device;
}

- (void)testConnectToDeviceWithSuccess
{
  FBFuture<NSNull *> *future = [[self.device connectToDeviceWithPurpose:@"test"] onQueue:dispatch_get_main_queue() pop:^(id<FBDeviceCommands> result) {
    return FBFuture.empty;
  }];

  NSError *error = nil;
  id value = [future await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"is_paired",
    @"validate_pairing",
    @"start_session",
    @"stop_session",
    @"disconnect",
  ];

  XCTAssertEqualObjects(expected, actual);
}

- (void)testConnectToDeviceWithFailure
{
  FBFuture<NSNull *> *future = [[self.device connectToDeviceWithPurpose:@"test"] onQueue:dispatch_get_main_queue() pop:^(id<FBDeviceCommands> result) {
    return [[FBDeviceControlError describeFormat:@"A bad thing"] failFuture];
  }];

  NSError *error = nil;
  id value = [future await:&error];
  XCTAssertNotNil(error);
  XCTAssertNil(value);

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"is_paired",
    @"validate_pairing",
    @"start_session",
    @"stop_session",
    @"disconnect",
  ];

  XCTAssertEqualObjects(expected, actual);
}

- (void)testConcurrentHouseArrest
{
  AFCCalls afcCalls = {
    .ConnectionClose = ConnectionClose,
  };

  dispatch_queue_t schedule = dispatch_queue_create("com.facebook.fbdevicecontrol.amdevicetests.schedule", DISPATCH_QUEUE_CONCURRENT);
  dispatch_queue_t map = dispatch_queue_create("com.facebook.fbdevicecontrol.amdevicetests.map", DISPATCH_QUEUE_SERIAL);
  FBAMDevice *device = [self deviceWithConnectionReuseTimeout:@0.5 serviceReuseTimeout:@0.3];
  FBMutableFuture<NSNumber *> *future0 = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *future1 = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *future2 = FBMutableFuture.future;

  dispatch_async(schedule, ^{
    FBFuture<NSNull *> *inner = [[device houseArrestAFCConnectionForBundleID:@"com.foo.bar" afcCalls:afcCalls] onQueue:map pop:^(FBAFCConnection *result) {
      return [FBFuture futureWithResult:@0];
    }];
    [future0 resolveFromFuture:inner];
  });
  dispatch_async(schedule, ^{
    FBFuture<NSNull *> *inner = [[device houseArrestAFCConnectionForBundleID:@"com.foo.bar" afcCalls:afcCalls] onQueue:map pop:^(FBAFCConnection *result) {
      return [FBFuture futureWithResult:@1];
    }];
    [future1 resolveFromFuture:inner];
  });
  dispatch_async(schedule, ^{
    FBFuture<NSNull *> *inner = [[device houseArrestAFCConnectionForBundleID:@"com.foo.bar" afcCalls:afcCalls] onQueue:map pop:^(FBAFCConnection *result) {
      return [FBFuture futureWithResult:@2];
    }];
    [future2 resolveFromFuture:inner];
  });

  NSError *error = nil;
  id value = [[FBFuture futureWithFutures:@[future0, future1, future2]] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"is_paired",
    @"validate_pairing",
    @"start_session",
    @"create_house_arrest_service",
  ];
  XCTAssertEqualObjects(expected, actual);

  [[FBFuture futureWithDelay:0.5 future:FBFuture.empty] await:nil];
  actual = [FBAMDeviceTests.events copy];
  expected = @[
    @"connect",
    @"is_paired",
    @"validate_pairing",
    @"start_session",
    @"create_house_arrest_service",
    @"connection_close",
    @"stop_session",
    @"disconnect",
  ];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testConcurrentUtilizationHasSharedConnection
{
  dispatch_queue_t schedule = dispatch_queue_create("com.facebook.fbdevicecontrol.amdevicetests.schedule", DISPATCH_QUEUE_CONCURRENT);
  dispatch_queue_t map = dispatch_queue_create("com.facebook.fbdevicecontrol.amdevicetests.map", DISPATCH_QUEUE_SERIAL);
  FBMutableFuture<NSNumber *> *future0 = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *future1 = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *future2 = FBMutableFuture.future;

  FBAMDevice *device = self.device;

  dispatch_async(schedule, ^{
    FBFuture<NSNumber *> *future = [[device connectToDeviceWithPurpose:@"test"] onQueue:map pop:^(id<FBDeviceCommands> result) {
      return [FBFuture futureWithResult:@0];
    }];
    [future0 resolveFromFuture:future];
  });
  dispatch_async(schedule, ^{
    FBFuture<NSNumber *> *future = [[device connectToDeviceWithPurpose:@"test"] onQueue:map pop:^(id<FBDeviceCommands> result) {
      return [FBFuture futureWithResult:@1];
    }];
    [future1 resolveFromFuture:future];
  });
  dispatch_async(schedule, ^{
    FBFuture<NSNumber *> *future = [[device connectToDeviceWithPurpose:@"test"] onQueue:map pop:^(id<FBDeviceCommands> result) {
      return [FBFuture futureWithResult:@2];
    }];
    [future2 resolveFromFuture:future];
  });


  NSError *error = nil;
  NSArray<NSNumber *> *value = [[FBFuture futureWithFutures:@[future0, future1, future2]] await:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, (@[@0, @1, @2]));

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"is_paired",
    @"validate_pairing",
    @"start_session",
    @"stop_session",
    @"disconnect",
  ];
  XCTAssertEqualObjects(expected, actual);
}

@end
