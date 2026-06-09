/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorControl-Swift.h>

#pragma mark - Test Doubles

// Stub for SimDeviceType, providing productFamilyID and screen info.
@interface _FBTestSimDeviceType : NSObject
@property (nonatomic, assign) int productFamilyID;
@property (nonatomic, assign) CGSize mainScreenSize;
@property (nonatomic, assign) float mainScreenScale;
@property (nonatomic, copy) NSString *name;
@end

@implementation _FBTestSimDeviceType
@end

// Stub for SimRuntime, providing root path.
@interface _FBTestSimRuntime : NSObject
@property (nonatomic, copy) NSString *root;
@property (nonatomic, copy) NSString *name;
@end

@implementation _FBTestSimRuntime
@end

// Stub for SimDeviceSet, providing setPath.
@interface _FBTestSimDeviceSet : NSObject
@property (nonatomic, copy) NSString *setPath;
@end

@implementation _FBTestSimDeviceSet
@end

// Comprehensive stub for SimDevice used by FBSimulator.
@interface _FBTestSimDevice : NSObject
@property (nonatomic, strong) NSUUID *UDID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSUInteger state;
@property (nonatomic, copy) NSString *dataPath;
@property (nonatomic, strong) _FBTestSimDeviceType *deviceType;
@property (nonatomic, strong) _FBTestSimRuntime *runtime;
@property (nonatomic, strong) _FBTestSimDeviceSet *deviceSet;
@property (nonatomic, assign) mach_port_t lookupPort;
@property (nonatomic, assign) BOOL lookupShouldFail;
@end

@implementation _FBTestSimDevice

- (instancetype)init
{
  self = [super init];
  if (self) {
    _UDID = [NSUUID UUID];
    _name = @"TestSimulator";
    _state = FBiOSTargetStateBooted;
    _dataPath = @"/tmp/test-sim-data";
    _deviceType = [[_FBTestSimDeviceType alloc] init];
    _deviceType.productFamilyID = 1;
    _deviceType.mainScreenSize = CGSizeMake(750, 1334);
    _deviceType.mainScreenScale = 2.0;
    _deviceType.name = @"iPhone 14";
    _runtime = [[_FBTestSimRuntime alloc] init];
    _runtime.root = @"/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot";
    _runtime.name = @"iOS 17.0";
    _deviceSet = [[_FBTestSimDeviceSet alloc] init];
    _deviceSet.setPath = [@"~/Library/Developer/CoreSimulator/Devices" stringByExpandingTildeInPath];
    _lookupPort = MACH_PORT_NULL;
    _lookupShouldFail = NO;
  }
  return self;
}

- (mach_port_t)lookup:(NSString *)name error:(NSError **)error
{
  if (_lookupShouldFail) {
    if (error) {
      *error = [NSError errorWithDomain:@"FBSimulatorTestDomain" code:1 userInfo:@{NSLocalizedDescriptionKey : @"Port not found"}];
    }
    return MACH_PORT_NULL;
  }
  return _lookupPort;
}

@end

// Minimal event reporter stub.
@interface _FBTestEventReporter : NSObject
@end

@implementation _FBTestEventReporter
@end

#pragma mark - Helper

static FBSimulator *_createSimulatorWithDevice(_FBTestSimDevice *device)
{
  id<FBControlCoreLogger> logger = [FBControlCoreLoggerFactory loggerToConsumer:[FBNullDataConsumer new]];
  id reporter = [_FBTestEventReporter new];
  return [[FBSimulator alloc] initWithDevice:(id)device
                               configuration:FBSimulatorConfiguration.defaultConfiguration
                                         set:nil
                          auxillaryDirectory:@"/tmp/test-aux"
                                      logger:logger
                                    reporter:reporter];
}

#pragma mark - Test Class

@interface FBSimulatorTests : XCTestCase
@end

@implementation FBSimulatorTests
{
  _FBTestSimDevice *_stubDevice;
  FBSimulator *_simulator;
}

- (void)setUp
{
  [super setUp];
  _stubDevice = [[_FBTestSimDevice alloc] init];
  _simulator = _createSimulatorWithDevice(_stubDevice);
}

#pragma mark - Product Family

- (void)testProductFamily_WhenFamilyIDIs1_ReturnsiPhone
{
  _stubDevice.deviceType.productFamilyID = 1;
  FBSimulator *sim = _createSimulatorWithDevice(_stubDevice);
  XCTAssertEqual(
    sim.productFamily,
    FBControlCoreProductFamilyiPhone,
    @"productFamilyID 1 should map to iPhone"
  );
}

- (void)testProductFamily_WhenFamilyIDIs2_ReturnsiPad
{
  _stubDevice.deviceType.productFamilyID = 2;
  FBSimulator *sim = _createSimulatorWithDevice(_stubDevice);
  XCTAssertEqual(
    sim.productFamily,
    FBControlCoreProductFamilyiPad,
    @"productFamilyID 2 should map to iPad"
  );
}

- (void)testProductFamily_WhenFamilyIDIs3_ReturnsAppleTV
{
  _stubDevice.deviceType.productFamilyID = 3;
  FBSimulator *sim = _createSimulatorWithDevice(_stubDevice);
  XCTAssertEqual(
    sim.productFamily,
    FBControlCoreProductFamilyAppleTV,
    @"productFamilyID 3 should map to AppleTV"
  );
}

- (void)testProductFamily_WhenFamilyIDIs4_ReturnsAppleWatch
{
  _stubDevice.deviceType.productFamilyID = 4;
  FBSimulator *sim = _createSimulatorWithDevice(_stubDevice);
  XCTAssertEqual(
    sim.productFamily,
    FBControlCoreProductFamilyAppleWatch,
    @"productFamilyID 4 should map to AppleWatch"
  );
}

- (void)testProductFamily_WhenFamilyIDIsUnknown_ReturnsUnknown
{
  _stubDevice.deviceType.productFamilyID = 99;
  FBSimulator *sim = _createSimulatorWithDevice(_stubDevice);
  XCTAssertEqual(
    sim.productFamily,
    FBControlCoreProductFamilyUnknown,
    @"Unrecognized productFamilyID should map to Unknown"
  );
}

#pragma mark - Custom Device Set Path

- (void)testCustomDeviceSetPath_WhenDefaultPath_ReturnsNil
{
  _stubDevice.deviceSet.setPath = [@"~/Library/Developer/CoreSimulator/Devices" stringByExpandingTildeInPath];
  FBSimulator *sim = _createSimulatorWithDevice(_stubDevice);
  XCTAssertNil(
    sim.customDeviceSetPath,
    @"customDeviceSetPath should be nil when using the default device set path"
  );
}

- (void)testCustomDeviceSetPath_WhenCustomPath_ReturnsPath
{
  NSString *customPath = @"/custom/simulator/devices";
  _stubDevice.deviceSet.setPath = customPath;
  FBSimulator *sim = _createSimulatorWithDevice(_stubDevice);
  XCTAssertEqualObjects(
    sim.customDeviceSetPath,
    customPath,
    @"customDeviceSetPath should return the custom path when not using the default"
  );
}

#pragma mark - Auxiliary Directory From SimDevice

- (void)testAuxillaryDirectoryFromSimDevice_AppendsSubdirectory
{
  _stubDevice.dataPath = @"/path/to/sim/data";
  NSString *expected = @"/path/to/sim/data/fbsimulatorcontrol";
  // The auxillaryDirectory was set in setUp via the init parameter, so test the class method indirectly
  // by creating a simulator using the convenience init that calls auxillaryDirectoryFromSimDevice:
  id<FBControlCoreLogger> logger = [FBControlCoreLoggerFactory loggerToConsumer:[FBNullDataConsumer new]];
  id reporter = [_FBTestEventReporter new];
  FBSimulator *simViaConvenienceInit = [[FBSimulator alloc] initWithDevice:(id)_stubDevice
                                                                    logger:logger
                                                                  reporter:reporter];
  XCTAssertEqualObjects(
    simViaConvenienceInit.auxillaryDirectory,
    expected,
    @"auxillaryDirectory should be dataPath + /fbsimulatorcontrol"
  );
}

#pragma mark - Screen Info

- (void)testScreenInfo_ReturnsDeviceTypeScreenDimensions
{
  _stubDevice.deviceType.mainScreenSize = CGSizeMake(1170, 2532);
  _stubDevice.deviceType.mainScreenScale = 3.0f;
  FBSimulator *sim = _createSimulatorWithDevice(_stubDevice);
  FBiOSTargetScreenInfo *screenInfo = sim.screenInfo;
  XCTAssertNotNil(screenInfo, @"screenInfo should not be nil");
  XCTAssertEqual(
    screenInfo.widthPixels,
    (NSUInteger)1170,
    @"widthPixels should match device type mainScreenSize.width"
  );
  XCTAssertEqual(
    screenInfo.heightPixels,
    (NSUInteger)2532,
    @"heightPixels should match device type mainScreenSize.height"
  );
  XCTAssertEqualWithAccuracy(screenInfo.scale, 3.0f, 0.001f, @"scale should match device type mainScreenScale");
}

#pragma mark - Equality and Hashing

- (void)testIsEqual_WhenSameDevice_ReturnsYES
{
  FBSimulator *sim1 = _createSimulatorWithDevice(_stubDevice);
  FBSimulator *sim2 = _createSimulatorWithDevice(_stubDevice);
  XCTAssertEqualObjects(
    sim1,
    sim2,
    @"Two simulators wrapping the same device should be equal"
  );
}

- (void)testIsEqual_WhenDifferentDevice_ReturnsNO
{
  _FBTestSimDevice *otherDevice = [[_FBTestSimDevice alloc] init];
  FBSimulator *sim2 = _createSimulatorWithDevice(otherDevice);
  XCTAssertNotEqualObjects(
    _simulator,
    sim2,
    @"Two simulators wrapping different devices should not be equal"
  );
}

- (void)testIsEqual_WhenDifferentClass_ReturnsNO
{
  XCTAssertFalse(
    [_simulator isEqual:@"not a simulator"],
    @"isEqual should return NO for objects of a different class"
  );
}

- (void)testHash_MatchesDeviceHash
{
  NSUInteger expected = [_stubDevice hash];
  XCTAssertEqual(
    _simulator.hash,
    expected,
    @"Simulator hash should match the underlying device hash"
  );
}

#pragma mark - Temporary Directory (Lazy Init)

- (void)testTemporaryDirectory_ReturnsSameInstanceOnSubsequentAccess
{
  FBTemporaryDirectory *first = _simulator.temporaryDirectory;
  FBTemporaryDirectory *second = _simulator.temporaryDirectory;
  XCTAssertTrue(
    first == second,
    @"temporaryDirectory should return the same cached instance on subsequent access"
  );
}

#pragma mark - Healthcheck Helpers

- (void)testLookupBootstrapPortNamed_WhenPortExists_ReturnsPortNumber
{
  _stubDevice.lookupPort = 12345;
  _stubDevice.lookupShouldFail = NO;
  FBSimulator *sim = _createSimulatorWithDevice(_stubDevice);
  NSError *error = nil;
  NSNumber *port = [sim lookupBootstrapPortNamed:@"com.apple.testservice" error:&error];
  XCTAssertNil(error, @"Error should be nil when port lookup succeeds");
  XCTAssertNotNil(port, @"Port should not be nil when lookup succeeds");
  XCTAssertEqual(
    port.unsignedIntValue,
    12345u,
    @"Returned port number should match the looked-up port"
  );
}

- (void)testLookupBootstrapPortNamed_WhenPortIsNull_ReturnsNil
{
  _stubDevice.lookupPort = MACH_PORT_NULL;
  _stubDevice.lookupShouldFail = NO;
  FBSimulator *sim = _createSimulatorWithDevice(_stubDevice);
  NSError *error = nil;
  NSNumber *port = [sim lookupBootstrapPortNamed:@"com.apple.nonexistent" error:&error];
  XCTAssertNil(port, @"Port should be nil when MACH_PORT_NULL is returned");
}

- (void)testLookupBootstrapPortNamed_WhenLookupFails_ReturnsNilWithError
{
  _stubDevice.lookupShouldFail = YES;
  FBSimulator *sim = _createSimulatorWithDevice(_stubDevice);
  NSError *error = nil;
  NSNumber *port = [sim lookupBootstrapPortNamed:@"com.apple.failing" error:&error];
  XCTAssertNil(port, @"Port should be nil when lookup fails");
  XCTAssertNotNil(error, @"Error should be populated when lookup fails");
}

@end
