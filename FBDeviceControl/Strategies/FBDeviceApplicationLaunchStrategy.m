/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceApplicationLaunchStrategy.h"

#import "FBAMDServiceConnection.h"
#import "FBDeviceControlError.h"

// Uses sending of GDB packets against the debug server to start an application.
// A lot of the information here comes from the gdb remote protocol spec from the llvm project https://github.com/llvm-mirror/lldb/blob/master/docs/lldb-gdb-remote.txt
// There's also more information in the GDB protocol spec https://sourceware.org/gdb/onlinedocs/gdb/General-Query-Packets.html
// We can replacate what Xcode does by logging the lldb output by setting in ~/.lldbinit `log enable -f /tmp/gdb_remote_packets.log gdb-remote packets`

static NSString *const Terminator = @"#";
static NSTimeInterval LaunchTimeout = 60;

static NSString *hexEncode(NSString *input)
{
  NSMutableString *output = [NSMutableString string];
  for (NSUInteger index = 0; index < input.length; index++) {
    unichar character = [input characterAtIndex:index];
    [output appendFormat:@"%02x", character];
  }
  return output;
}

static NSString *launchStringWithArguments(NSArray<NSString *> *arguments)
{
  NSMutableString *string = [NSMutableString stringWithString:@"A"];
  for (NSUInteger index = 0; index < arguments.count; index++) {
    NSString *argument = arguments[index];
    NSString *hex = hexEncode(argument);
    [string appendFormat:@"%lu,%lu,%@", (unsigned long)hex.length, (unsigned long)index, hex];
  }
  return string;
}

static NSData *wrapCommandInSums(NSString *input)
{
  NSInteger checksum = 0;
  for (NSUInteger index = 0; index < input.length; index++) {
    checksum += [input characterAtIndex:index];
  }
  NSString *output = [NSString stringWithFormat:@"$%@#%02lx", input, (checksum & 0xff)];
  return [output dataUsingEncoding:NSASCIIStringEncoding];
}

static NSArray<NSString *> *environmentCommands(NSDictionary<NSString *, NSString *> *environment)
{
  NSMutableArray<NSString *> *commands = [NSMutableArray array];
  for (NSString *key in environment) {
    NSString *value = environment[key];
    [commands addObject:[NSString stringWithFormat:@"QEnvironment:%@=%@", key, value]];
  }
  return commands;
}

static NSString *trimResponse(NSString *response)
{
  NSError *error = NULL;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[0-9a-f$\\+]" options:NSRegularExpressionAnchorsMatchLines error:&error];
  NSCAssert(regex, @"Could not create regex %@", error);
  return [regex stringByReplacingMatchesInString:response options:NSMatchingAnchored range:NSMakeRange(0, response.length) withTemplate:@""];
}

static NSDictionary<NSString *, NSString *> *keyValuePairs(NSString *response)
{
  NSArray<NSString *> *pairs = [response componentsSeparatedByString:@";"];
  NSMutableDictionary<NSString *, NSString *> *dictionary = [NSMutableDictionary dictionary];
  for (NSString *pair in pairs) {
    NSArray<NSString *> *tuple = [pair componentsSeparatedByString:@":"];
    if (tuple.count < 2) {
      continue;
    }
    NSString *key = tuple[0];
    NSString *value = tuple[1];
    dictionary[key] = value;
  }
  return dictionary;
}

static NSNumber *processIdentifierFromResponse(NSString *response, NSError **error)
{
  NSDictionary<NSString *, NSString *> *pairs = keyValuePairs(response);
  NSString *pidHex = pairs[@"pid"];
  if (!pidHex) {
    return [[FBDeviceControlError
      describeFormat:@"Could not obtain pid from %@", response]
      fail:error];
  }
  NSScanner *scanner = [NSScanner scannerWithString:pidHex];
  unsigned int value = 0;
  if (![scanner scanHexInt:&value])
  {
    return [[FBDeviceControlError
      describeFormat:@"Could not coerce %@ from a hex int", pidHex]
      fail:error];
  }

  return @(value);
}

@interface FBDeviceApplicationLaunchStrategy_GDBClient : NSObject

@property (nonatomic, readonly, strong) id<FBDataConsumer> writer;
@property (nonatomic, readonly, strong) FBFileReader *reader;
@property (nonatomic, readonly, strong) id<FBConsumableBuffer> buffer;
@property (nonatomic, readonly, strong) dispatch_queue_t queue;
@property (nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

@end

@implementation FBDeviceApplicationLaunchStrategy_GDBClient

- (instancetype)initWithWriter:(id<FBDataConsumer>)writer reader:(FBFileReader *)reader buffer:(id<FBConsumableBuffer>)buffer queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _writer = writer;
  _reader = reader;
  _buffer = buffer;
  _queue = queue;
  _logger = logger;

  return self;
}

- (FBFuture<NSNull *> *)noAckMode
{
  NSData *ack = [@"+" dataUsingEncoding:NSASCIIStringEncoding];
  [self.writer consumeData:ack];
  return [[self
    sendUntilOK:@"QStartNoAckMode"]
    onQueue:self.queue map:^(id _) {
      [self.writer consumeData:ack];
      return NSNull.null;
    }];
}

- (FBFuture<NSNull *> *)sendUntilOK:(NSString *)command
{
  return [[self
    sendAndGetResponse:command]
    onQueue:self.queue fmap:^(NSString *response) {
      if (![response isEqualToString:@"OK"]) {
        return [[FBDeviceControlError
          describeFormat:@"Response '%@' is not equal to 'OK'", response]
          failFuture];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

- (FBFuture<NSString *> *)sendAndGetResponse:(NSString *)command
{
  [self.logger logFormat:@"SEND: %@", command];
  [self.writer consumeData:wrapCommandInSums(command)];
  return [[self.buffer
    consumeAndNotifyWhen:[Terminator dataUsingEncoding:NSASCIIStringEncoding]]
    onQueue:self.queue map:^(NSData *data) {
      NSString *response = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
      return trimResponse(response);
    }];
}

- (FBFuture<NSNull *> *)sendMultiUntilOK:(NSArray<NSString *> *)commands
{
  if (commands.count == 0) {
    return [FBFuture futureWithResult:NSNull.null];
  }
  NSString *command = [commands firstObject];
  return [[self
    sendUntilOK:command]
    onQueue:self.queue fmap:^(id _) {
      NSArray<NSString *> *next = [commands subarrayWithRange:NSMakeRange(1, commands.count - 1)];
      return [self sendMultiUntilOK:next];
    }];
}

@end

@interface FBDeviceApplicationLaunchStrategy ()

@property (nonatomic, strong, readonly) FBAMDServiceConnection *connection;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;

@end

@implementation FBDeviceApplicationLaunchStrategy

#pragma mark Initializers

+ (instancetype)strategyWithDebugConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithDebugConnection:connection logger:logger];
}

- (instancetype)initWithDebugConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _logger = logger;
  _writeQueue = dispatch_queue_create("com.facebook.fbdevicecontrol.app_launch_commands", DISPATCH_QUEUE_SERIAL);

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)launch remoteAppPath:(NSString *)remoteAppPath
{
  return [[FBDeviceApplicationLaunchStrategy
    clientForServiceConnection:self.connection queue:self.writeQueue logger:self.logger]
    onQueue:self.writeQueue fmap:^(FBDeviceApplicationLaunchStrategy_GDBClient *client) {
      return [FBDeviceApplicationLaunchStrategy launchApplication:launch remoteAppPath:remoteAppPath client:client queue:self.writeQueue logger:self.logger];
    }];
}

#pragma mark Private

+ (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)launch remoteAppPath:(NSString *)remoteAppPath client:(FBDeviceApplicationLaunchStrategy_GDBClient *)client queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  [logger logFormat:@"Launching with remote path %@", remoteAppPath];
  return [[[[[[client
    noAckMode]
    onQueue:queue fmap:^(id _) {
      return [client sendMultiUntilOK:environmentCommands(launch.environment)];
    }]
    onQueue:queue fmap:^(id _) {
      return [client sendMultiUntilOK:@[
        launchStringWithArguments([@[remoteAppPath] arrayByAddingObjectsFromArray:launch.arguments]),
        @"qLaunchSuccess",
      ]];
    }]
    onQueue:queue fmap:^(id _) {
      return [client sendAndGetResponse:@"qProcessInfo"];
    }]
    onQueue:queue fmap:^(NSString *response) {
      NSError *error = nil;
      NSNumber *pid = processIdentifierFromResponse(response, &error);
      if (!pid) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:pid];
    }]
    timeout:LaunchTimeout waitingFor:@"Timed out waiting for launch to complete"];
}

+ (FBFuture<FBDeviceApplicationLaunchStrategy_GDBClient *> *)clientForServiceConnection:(FBAMDServiceConnection *)connection queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  NSFileHandle *fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:connection.socket closeOnDealloc:NO];
  id<FBDataConsumer> writer = [FBFileWriter asyncWriterWithFileHandle:fileHandle error:&error];
  if (!writer) {
    return [FBFuture futureWithError:error];
  }
  id<FBConsumableBuffer> outputBuffer = FBLineBuffer.consumableBuffer;
  id<FBDataConsumer> output = [FBCompositeDataConsumer consumerWithConsumers:@[
    outputBuffer,
    [FBLoggingDataConsumer consumerWithLogger:[logger withName:@"RECV"]],
  ]];
  FBFileReader *reader = [FBFileReader readerWithFileHandle:fileHandle consumer:output logger:nil];
  return [[reader
    startReading]
    onQueue:queue map:^(id _) {
      return [[FBDeviceApplicationLaunchStrategy_GDBClient alloc] initWithWriter:writer reader:reader buffer:outputBuffer queue:queue logger:logger];
    }];
}

@end
