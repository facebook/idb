/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBDeviceControl.h>

#import <sys/socket.h>
#import <netinet/in.h>

#pragma mark - Test Doubles

/**
 A logger double that records log messages for verification.
 */
@interface FBDeviceDebugServerTestLogger : NSObject <FBControlCoreLogger>

@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *messages;

@end

@implementation FBDeviceDebugServerTestLogger

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _messages = [NSMutableArray array];
  return self;
}

- (id<FBControlCoreLogger>)log:(NSString *)message
{
  @synchronized (self.messages) {
    [self.messages addObject:message];
  }
  return self;
}

- (id<FBControlCoreLogger>)logFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  @synchronized (self.messages) {
    [self.messages addObject:message];
  }
  return self;
}

- (id<FBControlCoreLogger>)info
{
  return self;
}

- (id<FBControlCoreLogger>)debug
{
  return self;
}

- (id<FBControlCoreLogger>)error
{
  return self;
}

- (id<FBControlCoreLogger>)withName:(NSString *)name
{
  return self;
}

- (id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)enabled
{
  return self;
}

- (FBControlCoreLogLevel)level
{
  return FBControlCoreLogLevelDebug;
}

- (NSString *)name
{
  return @"test";
}

@end

#pragma mark - Private Interface Declarations

/**
 Expose the private initializer of FBDeviceDebugServer for testing.
 */
@interface FBDeviceDebugServer (Testing)

- (instancetype)initWithServiceConnection:(FBAMDServiceConnection *)serviceConnection
                                     port:(in_port_t)port
                    lldbBootstrapCommands:(NSArray<NSString *> *)lldbBootstrapCommands
                                    queue:(dispatch_queue_t)queue
                                   logger:(id<FBControlCoreLogger>)logger;

- (void)socketServer:(FBSocketServer *)server clientConnected:(struct in6_addr)address fileDescriptor:(int)fileDescriptor;

@property (nonatomic, strong, readwrite) FBMutableFuture<NSNull *> *teardown;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

/**
 Expose the private initializer of FBAMDServiceConnection for testing.
 */
@interface FBAMDServiceConnection (Testing)

- (instancetype)initWithName:(NSString *)name
                  connection:(AMDServiceConnectionRef)connection
                      device:(AMDeviceRef)device
                       calls:(AMDCalls)calls
                      logger:(id<FBControlCoreLogger>)logger;

@end

#pragma mark - Stub AMDCalls Functions

static int32_t StubServiceConnectionSend(CFTypeRef connection, const void *buffer, size_t bytes)
{
  return -1; // Simulate failure
}

static int32_t StubServiceConnectionReceive(CFTypeRef connection, void *buffer, size_t bytes)
{
  return -1; // Simulate failure
}

static AMSecureIOContext StubServiceConnectionGetSecureIOContext(CFTypeRef connection)
{
  return NULL;
}

#pragma mark - Test Class

@interface FBDeviceDebugServerTests : XCTestCase
{
  FBDeviceDebugServerTestLogger *_logger;
  dispatch_queue_t _queue;
}

@end

@implementation FBDeviceDebugServerTests

- (void)setUp
{
  [super setUp];
  _logger = [[FBDeviceDebugServerTestLogger alloc] init];
  _queue = dispatch_queue_create("com.facebook.fbdevicecontrol.debugserver.test", DISPATCH_QUEUE_SERIAL);
}

- (FBAMDServiceConnection *)createStubServiceConnection
{
  AMDCalls calls = {};
  calls.ServiceConnectionSend = StubServiceConnectionSend;
  calls.ServiceConnectionReceive = StubServiceConnectionReceive;
  calls.ServiceConnectionGetSecureIOContext = StubServiceConnectionGetSecureIOContext;
  return [[FBAMDServiceConnection alloc] initWithName:@"test_connection"
                                           connection:NULL
                                               device:NULL
                                                calls:calls
                                               logger:_logger];
}

- (FBDeviceDebugServer *)createServerWithPort:(in_port_t)port
                        lldbBootstrapCommands:(NSArray<NSString *> *)commands
{
  FBAMDServiceConnection *connection = [self createStubServiceConnection];
  FBDeviceDebugServer *server = [[FBDeviceDebugServer alloc] initWithServiceConnection:connection
                                                                                  port:port
                                                                 lldbBootstrapCommands:commands
                                                                                 queue:_queue
                                                                                logger:_logger];
  server.teardown = FBMutableFuture.future;
  return server;
}

#pragma mark - Completed Property Tests


- (void)testCompleted_ResolvesWhenTeardownResolves
{
  // Arrange
  FBDeviceDebugServer *server = [self createServerWithPort:12345 lldbBootstrapCommands:@[]];
  FBMutableFuture<NSNull *> *teardown = FBMutableFuture.future;
  server.teardown = teardown;

  // Act
  [teardown resolveWithResult:NSNull.null];

  // Assert
  XCTAssertEqual(server.completed.state, FBFutureStateDone, @"completed should resolve when teardown resolves");
}

#pragma mark - Client Connection Rejection Tests

- (void)testClientConnected_WhenExistingPair_RejectsWithErrorMessage
{
  // Arrange
  FBDeviceDebugServer *server = [self createServerWithPort:12345 lldbBootstrapCommands:@[]];

  // Set twistedPair to non-nil to simulate an existing connection
  // We use a dummy object since the actual type is private
  NSObject *dummyPair = [[NSObject alloc] init];
  [server setValue:dummyPair forKey:@"twistedPair"];

  // Create a socket pair for testing
  int fds[2];
  int result = socketpair(AF_UNIX, SOCK_STREAM, 0, fds);
  XCTAssertEqual(result, 0, @"socketpair should succeed");

  struct in6_addr address = {};

  // Act
  [server socketServer:nil clientConnected:address fileDescriptor:fds[1]];

  // Assert - Read the rejection message from the other end of the socket pair
  char buffer[256] = {0};
  ssize_t bytesRead = read(fds[0], buffer, sizeof(buffer) - 1);
  XCTAssertGreaterThan(bytesRead, 0, @"Should have received rejection data");

  NSString *receivedMessage = [NSString stringWithUTF8String:buffer];
  NSString *expectedMessage = @"$NEUnspecified#00";
  XCTAssertEqualObjects(receivedMessage, expectedMessage, @"Rejection message should be the GDB remote protocol error");

  // Cleanup
  close(fds[0]);
  // fds[1] should already be closed by the method
}

- (void)testClientConnected_WhenExistingPair_ClosesFileDescriptor
{
  // Arrange
  FBDeviceDebugServer *server = [self createServerWithPort:12345 lldbBootstrapCommands:@[]];

  NSObject *dummyPair = [[NSObject alloc] init];
  [server setValue:dummyPair forKey:@"twistedPair"];

  int fds[2];
  int result = socketpair(AF_UNIX, SOCK_STREAM, 0, fds);
  XCTAssertEqual(result, 0, @"socketpair should succeed");

  struct in6_addr address = {};

  // Act
  [server socketServer:nil clientConnected:address fileDescriptor:fds[1]];

  // Assert - The file descriptor should be closed by the rejection path.
  // Writing to a closed fd returns -1 with errno EBADF.
  char testByte = 'x';
  ssize_t writeResult = write(fds[1], &testByte, 1);
  XCTAssertEqual(writeResult, (ssize_t)-1, @"Write to rejected fd should fail because it was closed");
  XCTAssertEqual(errno, EBADF, @"errno should be EBADF for a closed file descriptor");

  // Cleanup
  close(fds[0]);
}

#pragma mark - Client Connection Success Tests

- (void)testClientConnected_WhenNoPair_StartsTwistedPairConnection
{
  // Arrange
  FBDeviceDebugServer *server = [self createServerWithPort:12345 lldbBootstrapCommands:@[]];

  int fds[2];
  int result = socketpair(AF_UNIX, SOCK_STREAM, 0, fds);
  XCTAssertEqual(result, 0, @"socketpair should succeed");

  // Close the read end so the socket read loop exits immediately
  close(fds[0]);

  struct in6_addr address = {};

  // Act
  [server socketServer:nil clientConnected:address fileDescriptor:fds[1]];

  // Assert - startWithError: succeeds and twistedPair is set immediately
  id twistedPair = [server valueForKey:@"twistedPair"];
  XCTAssertNotNil(twistedPair, @"twistedPair should be set immediately after client connects");

  // The teardown future should still be running (it resolves when the connection completes)
  XCTAssertEqual(server.completed.state, FBFutureStateRunning,
                 @"Teardown should still be running while connection is active");
}

- (void)testClientConnected_WhenNoPair_ClearsTwistedPairOnDisconnect
{
  // Arrange
  FBDeviceDebugServer *server = [self createServerWithPort:12345 lldbBootstrapCommands:@[]];

  int fds[2];
  int result = socketpair(AF_UNIX, SOCK_STREAM, 0, fds);
  XCTAssertEqual(result, 0, @"socketpair should succeed");

  // Close the read end so the socket read loop exits immediately
  close(fds[0]);

  struct in6_addr address = {};

  // Act
  [server socketServer:nil clientConnected:address fileDescriptor:fds[1]];

  // Wait for async operations to complete (the loops should exit quickly since fds[0] is closed)
  NSError *error = nil;
  [[FBFuture futureWithDelay:1.0 future:FBFuture.empty] await:&error];

  // Assert - After disconnect, twistedPair should be cleared
  // The completion handler sets self.twistedPair = nil
  id twistedPair = [server valueForKey:@"twistedPair"];
  XCTAssertNil(twistedPair, @"twistedPair should be cleared after client disconnects");
}

#pragma mark - Multiple Connection Tests

- (void)testSecondClientRejected_AfterFirstConnects
{
  // Arrange
  FBDeviceDebugServer *server = [self createServerWithPort:12345 lldbBootstrapCommands:@[]];

  // First connection - use a socket pair where we keep the other end open
  // so the twisted pair stays alive
  int firstFds[2];
  int result = socketpair(AF_UNIX, SOCK_STREAM, 0, firstFds);
  XCTAssertEqual(result, 0, @"first socketpair should succeed");

  struct in6_addr address = {};

  // Connect first client
  [server socketServer:nil clientConnected:address fileDescriptor:firstFds[1]];

  // Brief wait for async setup
  NSError *error = nil;
  [[FBFuture futureWithDelay:0.2 future:FBFuture.empty] await:&error];

  // Second connection
  int secondFds[2];
  result = socketpair(AF_UNIX, SOCK_STREAM, 0, secondFds);
  XCTAssertEqual(result, 0, @"second socketpair should succeed");

  // Act - Try to connect second client
  [server socketServer:nil clientConnected:address fileDescriptor:secondFds[1]];

  // Assert - Second connection should receive rejection message
  char buffer[256] = {0};
  ssize_t bytesRead = read(secondFds[0], buffer, sizeof(buffer) - 1);
  XCTAssertGreaterThan(bytesRead, 0, @"Second client should receive rejection data");

  NSString *receivedMessage = [NSString stringWithUTF8String:buffer];
  XCTAssertEqualObjects(receivedMessage, @"$NEUnspecified#00",
                        @"Second client should receive GDB remote protocol error");

  // Cleanup
  close(firstFds[0]);
  close(secondFds[0]);

  // Wait for cleanup
  [[FBFuture futureWithDelay:0.5 future:FBFuture.empty] await:&error];
}

@end
