/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBDeviceControl/FBDeviceControl.h>

@interface FBAMDeviceTests : XCTestCase

@property (nonatomic, strong, readwrite, class) NSMutableArray<NSString *> *events;
@property (nonatomic, strong, readwrite) FBAMDevice *device;

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

@implementation FBAMDeviceTests

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

- (AMDeviceRef)deviceRef
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
    .SecureStartService = SecureStartService,
    .CreateHouseArrestService = CreateHouseArrestService,
    .ServiceConnectionInvalidate = ServiceConnectionInvalidate,
  };
  return calls;
}

- (void)setUp
{
  FBAMDevice *device = [[FBAMDevice alloc] initWithUDID:@"foo" calls:self.stubbedCalls workQueue:dispatch_get_main_queue() logger:FBControlCoreGlobalConfiguration.defaultLogger];
  device.amDevice = self.deviceRef;
  [FBAMDeviceTests.events removeAllObjects];
  self.device = device;
}

- (void)tearDown
{
  self.device = nil;
}

- (void)testConnectToDeviceWithSuccess
{
  FBFuture<NSNull *> *future = [[self.device connectToDeviceWithPurpose:@"test"] onQueue:dispatch_get_main_queue() fmap:^(FBAMDeviceConnection *result) {
    return [FBFuture futureWithResult:NSNull.null];
  }];

  NSError *error = nil;
  id value = [future await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"start_session",
    @"stop_session",
    @"disconnect",
  ];

  XCTAssertEqualObjects(expected, actual);
}

- (void)testConnectToDeviceWithFailure
{
  FBFuture<NSNull *> *future = [[self.device connectToDeviceWithPurpose:@"test"] onQueue:dispatch_get_main_queue() fmap:^(FBAMDeviceConnection *result) {
    return [[FBDeviceControlError describeFormat:@"A bad thing"] failFuture];
  }];

  NSError *error = nil;
  id value = [future await:&error];
  XCTAssertNotNil(error);
  XCTAssertNil(value);

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"start_session",
    @"stop_session",
    @"disconnect",
  ];

  XCTAssertEqualObjects(expected, actual);
}

- (void)testStartAFCService
{
  FBFuture<FBAMDServiceConnection *> *future = [[self.device startAFCService] onQueue:dispatch_get_main_queue() fmap:^(FBAMDServiceConnection *result) {
    return [FBFuture futureWithResult:result];
  }];

  NSError *error = nil;
  id value = [future await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"start_session",
    @"secure_start_service",
    @"service_connection_invalidate",
    @"stop_session",
    @"disconnect",
  ];

  XCTAssertEqualObjects(expected, actual);
}

- (void)testHouseArrest
{
  AFCCalls afcCalls = {
    .ConnectionClose = ConnectionClose,
  };

  FBFuture<FBAFCConnection *> *future = [[self.device houseArrestAFCConnectionForBundleID:@"com.foo.bar" afcCalls:afcCalls] onQueue:dispatch_get_main_queue() fmap:^(FBAFCConnection *result) {
    return [FBFuture futureWithResult:result];
  }];

  NSError *error = nil;
  id value = [future await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"start_session",
    @"create_house_arrest_service",
    @"connection_close",
    @"stop_session",
    @"disconnect",
  ];

  XCTAssertEqualObjects(expected, actual);
}

- (void)testConcurrentUtilizationIsSerialized
{
  XCTestExpectation *call1Expectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Call1"];
  XCTestExpectation *call2Expectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Call2"];
  XCTestExpectation *call3Expectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Call3"];
  dispatch_queue_t schedule = dispatch_queue_create("com.facebook.fbdevicecontrol.amdevicetests.schedule", DISPATCH_QUEUE_CONCURRENT);
  dispatch_queue_t map = dispatch_queue_create("com.facebook.fbdevicecontrol.amdevicetests.map", DISPATCH_QUEUE_SERIAL);

  FBAMDevice *device = self.device;
  dispatch_async(schedule, ^{
    FBFuture<NSNull *> *future = [[device connectToDeviceWithPurpose:@"test"] onQueue:map fmap:^(FBAMDeviceConnection *result) {
      return [FBFuture futureWithResult:NSNull.null];
    }];
    NSError *error = nil;
    id value = [future await:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(value);
    [call1Expectation fulfill];
  });
  dispatch_async(schedule, ^{
    FBFuture<NSNull *> *future = [[device connectToDeviceWithPurpose:@"test"] onQueue:map fmap:^(FBAMDeviceConnection *result) {
      return [FBFuture futureWithResult:NSNull.null];
    }];
    NSError *error = nil;
    id value = [future await:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(value);
    [call2Expectation fulfill];
  });
  dispatch_async(schedule, ^{
    FBFuture<NSNull *> *future = [[device connectToDeviceWithPurpose:@"test"] onQueue:map fmap:^(FBAMDeviceConnection *result) {
      return [FBFuture futureWithResult:NSNull.null];
    }];
    NSError *error = nil;
    id value = [future await:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(value);
    [call3Expectation fulfill];
  });

  [self waitForExpectations:@[call1Expectation, call2Expectation, call3Expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"start_session",
    @"stop_session",
    @"disconnect",
  ];
  XCTAssertEqualObjects(expected, actual);
}

@end
