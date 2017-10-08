/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBSocketConsumer_Double : NSObject <FBSocketConsumer>

@property (nonatomic, copy, nullable, readwrite) NSData *send;
@property (nonatomic, strong, readonly) NSMutableData *recieve;
@property (nonatomic, assign, readwrite) BOOL eof;

@end

@implementation FBSocketConsumer_Double

- (instancetype)initWithSend:(NSData *)send
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _send = send;
  _recieve = [NSMutableData data];
  _eof = NO;

  return self;
}

- (void)writeBackAvailable:(id<FBFileConsumer>)writeBack
{
  if (!self.send) {
    return;
  }
  [writeBack consumeData:self.send];
  [writeBack consumeEndOfFile];
  self.send = nil;
}

- (void)consumeData:(NSData *)data
{
  [self.recieve appendData:data];
}

- (void)consumeEndOfFile
{
  self.eof = YES;
}

@end

@interface FBSocketReaderDelegate_Double : NSObject <FBSocketReaderDelegate>

@property (nonatomic, copy, readwrite) NSData *send;
@property (nonatomic, strong, readwrite) FBSocketConsumer_Double *consumer;

@end

@implementation FBSocketReaderDelegate_Double

- (instancetype)initWithSend:(NSData *)send
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _send = send;

  return self;
}

- (id<FBSocketConsumer>)consumerWithClientAddress:(struct in6_addr)clientAddress
{
  self.consumer = [[FBSocketConsumer_Double alloc] initWithSend:self.send];
  return self.consumer;
}

@end

@interface FBSocketIntegrationTests : XCTestCase

@end

@implementation FBSocketIntegrationTests

+ (in_port_t)portNumber
{
  return 11047;
}

- (void)testSendAndRecieve
{
  NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
  in_port_t portNumber = FBSocketIntegrationTests.portNumber;

  FBSocketReaderDelegate_Double *delegate = [FBSocketReaderDelegate_Double new];
  FBSocketReader *reader = [FBSocketReader socketReaderOnPort:portNumber delegate:delegate];
  NSError *error = nil;
  BOOL success = [reader startListeningWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  id<FBSocketConsumer> consumer = [[FBSocketConsumer_Double alloc] initWithSend:data];
  FBSocketWriter *writer = [FBSocketWriter writerForHost:@"localhost" port:portNumber consumer:consumer];
  success = [writer startWritingWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (id _, id __) {
    return [delegate.consumer.recieve isEqualToData:data];
  }];
  XCTestExpectation *expectation = [self expectationForPredicate:predicate evaluatedWithObject:self handler:nil];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertTrue(success);
}

@end
