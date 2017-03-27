/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlAssertions.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlTestCase.h"

@implementation XCTestCase (FBSimulatorControlAssertions)

#pragma mark Sessions

- (void)assertShutdownSimulatorAndTerminateSession:(FBSimulator *)simulator
{
  NSError *error = nil;
  BOOL success = [simulator shutdownSimulatorWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [simulator.pool freeSimulator:simulator error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
  [self assertSimulatorShutdown:simulator];
}

#pragma mark Strings

- (void)assertNeedle:(NSString *)needle inHaystack:(NSString *)haystack
{
  XCTAssertNotNil(needle);
  XCTAssertNotNil(haystack);
  if ([haystack rangeOfString:needle].location != NSNotFound) {
    return;
  }
  XCTFail(@"needle '%@' to be contained in haystack '%@'", needle, haystack);
}

#pragma mark Simulators

- (void)assertSimulatorBooted:(FBSimulator *)simulator
{
  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertNotNil(simulator.launchdProcess);
  if (self.expectContainerProcesses) {
    XCTAssertNotNil(simulator.containerApplication);
  } else {
    XCTAssertNil(simulator.containerApplication);
  }
}

- (void)assertSimulatorShutdown:(FBSimulator *)simulator
{
  XCTAssertEqual(simulator.state, FBSimulatorStateShutdown);
  XCTAssertNil(simulator.launchdProcess);
  XCTAssertNil(simulator.containerApplication);
}

#pragma mark Processes

- (void)assertLastLaunchedApplicationIsRunning:(FBSimulator *)simulator
{
  FBProcessInfo *process = simulator.history.lastLaunchedApplicationProcess;
  XCTAssertTrue(process.processIdentifier);
  NSError *error = nil;
  BOOL isRunning = [simulator.launchctl processIsRunningOnSimulator:process error:nil];
  XCTAssertTrue(isRunning);
  XCTAssertNil(error);
}

#pragma mark Private

- (BOOL)expectContainerProcesses
{
  return !FBSimulatorControlTestCase.useDirectLaunching;
}

@end

@implementation FBSimulatorControlTestCase (FBSimulatorControlAssertions)

- (nullable FBSimulator *)assertObtainsSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration
{
  NSError *error = nil;
  if (![configuration checkRuntimeRequirementsReturningError:&error]) {
    NSLog(@"Configuration %@ does not meet the runtime requirements with error %@", configuration, error);
    return nil;
  }
  FBSimulator *simulator = [self.control.pool allocateSimulatorWithConfiguration:configuration options:self.allocationOptions error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(simulator);
  return simulator;
}

- (nullable FBSimulator *)assertObtainsSimulator
{
  return [self assertObtainsSimulatorWithConfiguration:self.simulatorConfiguration];
}

- (nullable FBSimulator *)assertObtainsBootedSimulator
{
  return [self assertObtainsBootedSimulatorWithConfiguration:self.simulatorConfiguration launchConfiguration:self.simulatorLaunchConfiguration];
}

- (nullable FBSimulator *)assertObtainsBootedSimulatorWithInstalledApplication:(FBApplicationDescriptor *)application
{
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  if (!simulator) {
    return nil;
  }
  NSError *error = nil;
  BOOL success = [simulator installApplicationWithPath:application.path error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
  return simulator;
}

- (nullable FBSimulator *)assertObtainsBootedSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration launchConfiguration:(FBSimulatorBootConfiguration *)launchConfiguration
{
  FBSimulator *simulator = [self assertObtainsSimulatorWithConfiguration:configuration];
  if (!simulator) {
    return nil;
  }
  [self.assert consumeAllNotifications];

  NSError *error = nil;
  BOOL success = [simulator bootSimulator:launchConfiguration error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
  [self.assert bootingNotificationsFired:launchConfiguration];
  [self.assert consumeAllNotifications];
  return simulator;
}

- (nullable FBSimulator *)assertSimulator:(FBSimulator *)simulator launchesApplication:(FBApplicationDescriptor *)application withApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration
{
  NSError *error = nil;
  BOOL success = [simulator installApplicationWithPath:application.path error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
  success = [simulator launchApplication:applicationLaunchConfiguration error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertLastLaunchedApplicationIsRunning:simulator];

  [self.assert consumeNotification:FBSimulatorNotificationNameApplicationProcessDidLaunch];
  [self.assert noNotificationsToConsume];
  [self assertSimulatorBooted:simulator];

  success = [simulator launchApplication:applicationLaunchConfiguration error:&error];
  XCTAssertFalse(success);

  return simulator;
}

- (nullable FBSimulator *)assertSimulatorWithConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration launches:(FBSimulatorBootConfiguration *)simulatorLaunchConfiguration thenLaunchesApplication:(FBApplicationDescriptor *)application withApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration
{
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithConfiguration:simulatorConfiguration launchConfiguration:simulatorLaunchConfiguration];
  return [self assertSimulator:simulator launchesApplication:application withApplicationLaunchConfiguration:applicationLaunchConfiguration];
}

- (nullable FBSimulator *)assertSimulatorWithConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration relaunches:(FBSimulatorBootConfiguration *)simulatorLaunchConfiguration thenLaunchesApplication:(FBApplicationDescriptor *)application withApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration
{
  FBSimulator *simulator = [self assertSimulatorWithConfiguration:simulatorConfiguration launches:simulatorLaunchConfiguration thenLaunchesApplication:application  withApplicationLaunchConfiguration:applicationLaunchConfiguration];
  FBProcessInfo *firstLaunch = simulator.history.lastLaunchedApplicationProcess;

  NSError *error = nil;
  BOOL success = [simulator relaunchLastLaunchedApplicationWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self.assert consumeNotification:FBSimulatorNotificationNameApplicationProcessDidTerminate];
  [self.assert consumeNotification:FBSimulatorNotificationNameApplicationProcessDidLaunch];
  [self.assert noNotificationsToConsume];
  FBProcessInfo *secondLaunch = simulator.history.lastLaunchedApplicationProcess;

  XCTAssertNotEqualObjects(firstLaunch, secondLaunch);

  return simulator;
}

@end

@interface FBSimulatorControlNotificationAssertions ()

@property (nonatomic, strong, readonly) NSMutableArray *notificationsRecieved;
@property (nonatomic, weak, readonly) XCTestCase *testCase;
@property (nonatomic, weak, readonly) FBSimulatorPool *pool;

@end

@implementation FBSimulatorControlNotificationAssertions

+ (instancetype)withTestCase:(XCTestCase *)testCase pool:(FBSimulatorPool *)pool
{
  return [[self alloc] initWithTestCase:testCase pool:pool];
}

- (instancetype)initWithTestCase:(XCTestCase *)testCase  pool:(FBSimulatorPool *)pool
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _pool = pool;
  _testCase = testCase;
  _notificationsRecieved = [NSMutableArray array];
  [self registerNotificationObservers];

  return self;
}

- (void)registerNotificationObservers
{
  NSArray *notificationNames = @[
    FBSimulatorNotificationNameDidLaunch,
    FBSimulatorNotificationNameDidTerminate,
    FBSimulatorNotificationNameConnectionDidConnect,
    FBSimulatorNotificationNameConnectionDidDisconnect,
    FBSimulatorNotificationNameSimulatorApplicationDidLaunch,
    FBSimulatorNotificationNameSimulatorApplicationDidTerminate,
    FBSimulatorNotificationNameApplicationProcessDidLaunch,
    FBSimulatorNotificationNameApplicationProcessDidTerminate,
    FBSimulatorNotificationNameAgentProcessDidLaunch,
    FBSimulatorNotificationNameAgentProcessDidTerminate,
  ];
  for (NSString *notificationName in notificationNames) {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(simulatorNotificationRecieved:) name:notificationName object:nil];
  }
}

- (void)tearDown
{
  [NSNotificationCenter.defaultCenter removeObserver:self];
  [self.notificationsRecieved removeAllObjects];
}

- (void)dealloc
{
  [self tearDown];
}

#pragma mark Notifications

- (void)simulatorNotificationRecieved:(NSNotification *)notification
{
  FBSimulator *simulator = notification.object;
  if (simulator.pool != self.pool) {
    return;
  }
  [self.notificationsRecieved addObject:notification];
}

- (NSNotification *)consumeNotification:(NSString *)notificationName
{
  if (self.notificationsRecieved.count == 0) {
    [self failOnLine:__LINE__ withFormat:@"There was no notification to recieve for %@", notificationName];
    return nil;
  }
  NSNotification *actual = self.notificationsRecieved.firstObject;
  [self failIfFalse:[notificationName isEqualToString:actual.name] line:__LINE__ withFormat:@"Expected Notification %@ to be sent but got %@", notificationName, [self.notificationsRecieved valueForKey:@"name"]];
  [self.notificationsRecieved removeObjectAtIndex:0];
  return actual;
}

- (NSNotification *)consumeNotification:(NSString *)notificationName timeout:(NSTimeInterval)timeout
{
  NSNotification *actual = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilExists:^ NSString * {
    if (self.notificationsRecieved == 0) {
      return nil;
    }
    return self.notificationsRecieved.firstObject;
  }];

  if (!actual) {
    [self failOnLine:__LINE__ withFormat:@"There were notifications recieved before timing out when waiting for %@", notificationName];
    return nil;
  }

  [self failIfFalse:[notificationName isEqualToString:actual.name] line:__LINE__ withFormat:@"Expected Notification %@ to be sent but got %@", notificationName, [self.notificationsRecieved valueForKey:@"name"]];
  [self.notificationsRecieved removeObjectAtIndex:0];
  return actual;
}

- (NSArray *)consumeNotifications:(NSArray *)notificationNames
{
  if (notificationNames.count > self.notificationsRecieved.count) {
    [self failOnLine:__LINE__ withFormat:@"Expected to be able to consume %@ but there were only %d notifications to consume", notificationNames, self.notificationsRecieved.count];
    return nil;
  }

  NSRange sliceRange = NSMakeRange(0, notificationNames.count);

  NSArray *toConsumeSlice = [[[self.notificationsRecieved valueForKey:@"name"] subarrayWithRange:sliceRange] sortedArrayUsingSelector:@selector(compare:)];
  notificationNames = [notificationNames sortedArrayUsingSelector:@selector(compare:)];
  if (![toConsumeSlice isEqualToArray:notificationNames]) {
    [self failOnLine:__LINE__ withFormat:@"Expected notifications named %@ but got %@", notificationNames, toConsumeSlice];
  }

  NSArray *actual = [self.notificationsRecieved subarrayWithRange:sliceRange];
  [self.notificationsRecieved removeObjectsInRange:sliceRange];
  return actual;
}

- (void)consumeAllNotifications
{
  // Spin run loop to filter out any pending notifications.
  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilTrue:^{
    return NO;
  }];
  [self.notificationsRecieved removeAllObjects];
}

- (void)noNotificationsToConsume
{
  // Spin run loop to filter out any pending notifications.
  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilTrue:^{
    return NO;
  }];
  [self failIfFalse:(self.notificationsRecieved.count == 0) line:__LINE__ withFormat:@"Expected no notifications but got %@", [self.notificationsRecieved valueForKey:@"name"]];
}

- (void)bootingNotificationsFired:(FBSimulatorBootConfiguration *)launchConfiguration
{
  [self consumeNotifications:[FBSimulatorControlNotificationAssertions expectedBootNotificationNamesForConfiguration:launchConfiguration]];
}

- (void)shutdownNotificationsFired:(FBSimulatorBootConfiguration *)launchConfiguration
{
  [self consumeNotifications:[FBSimulatorControlNotificationAssertions expectedShutdownNotificationNamesForConfiguration:launchConfiguration]];
}

#pragma mark Helpers

- (void)failIfFalse:(BOOL)value line:(NSUInteger)line withFormat:(NSString *)format, ...
{
  if (value) {
    return;
  }

  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  [self.testCase recordFailureWithDescription:string inFile:@(__FILE__) atLine:line expected:YES];
}

- (void)failOnLine:(NSUInteger)line withFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  [self.testCase recordFailureWithDescription:string inFile:@(__FILE__) atLine:line expected:YES];
}

+ (NSArray<NSString *> *)expectedBootNotificationNamesForConfiguration:(FBSimulatorBootConfiguration *)configuration
{
  NSMutableArray<NSString *> *notificationNames = [NSMutableArray array];
  if (configuration.shouldConnectBridge) {
    [notificationNames addObject:FBSimulatorNotificationNameConnectionDidConnect];
  }
  [notificationNames addObject:FBSimulatorNotificationNameDidLaunch];
  if (!configuration.shouldUseDirectLaunch) {
    [notificationNames addObject:FBSimulatorNotificationNameSimulatorApplicationDidLaunch];
  }
  return [notificationNames copy];
}

+ (NSArray<NSString *> *)expectedShutdownNotificationNamesForConfiguration:(FBSimulatorBootConfiguration *)configuration
{
  if (configuration.shouldUseDirectLaunch) {
    return @[FBSimulatorNotificationNameDidTerminate, FBSimulatorNotificationNameConnectionDidDisconnect];
  }
  return @[FBSimulatorNotificationNameDidTerminate, FBSimulatorNotificationNameConnectionDidDisconnect, FBSimulatorNotificationNameSimulatorApplicationDidTerminate];
}

@end
