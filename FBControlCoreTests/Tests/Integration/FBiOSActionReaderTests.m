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

#import "FBiOSTargetDouble.h"
#import "FBiOSTargetActionDouble.h"

NS_ASSUME_NONNULL_BEGIN

@interface FBiOSActionReaderTests : XCTestCase <FBiOSActionReaderDelegate>

@property (nonatomic, strong, readwrite) FBiOSTargetDouble *target;
@property (nonatomic, strong, readwrite) FBiOSActionRouter *router;
@property (nonatomic, strong, readwrite) FBiOSActionReader *reader;
@property (nonatomic, strong, nullable, readwrite) id<FBFileConsumer> consumer;

@property (nonatomic, strong, readwrite) NSMutableArray<id<FBiOSTargetAction>> *startedActions;
@property (nonatomic, strong, readwrite) NSMutableArray<id<FBiOSTargetAction>> *finishedActions;
@property (nonatomic, strong, readwrite) NSMutableArray<id<FBiOSTargetAction>> *failedActions;
@property (nonatomic, strong, readwrite) NSMutableArray<FBUploadedDestination *> *uploads;
@property (nonatomic, strong, readwrite) NSMutableArray<NSString *> *badInput;

@end

@interface FBiOSActionReaderSocketTests : FBiOSActionReaderTests <FBSocketConsumer>

@property (nonatomic, strong, readwrite) FBSocketWriter *writer;

@end

@interface FBiOSActionReaderFileTests : FBiOSActionReaderTests

@property (nonatomic, strong, readwrite) NSPipe *pipe;

@end

@implementation FBiOSActionReaderTests

- (NSData *)actionLine:(id<FBiOSTargetAction>)action
{
  NSMutableData *actionData = [[NSJSONSerialization dataWithJSONObject:[self.router jsonFromAction:action] options:0 error:nil] mutableCopy];
  [actionData appendData:[NSData dataWithBytes:"\n" length:1]];
  return actionData;
}

- (void)setUp
{
  [super setUp];
  NSArray<Class> *actionClasses = [FBiOSActionRouter.defaultActionClasses arrayByAddingObject:FBiOSTargetActionDouble.class];
  self.target = [FBiOSTargetDouble new];
  self.target.auxillaryDirectory = NSTemporaryDirectory();
  self.router = [FBiOSActionRouter routerForTarget:self.target actionClasses:actionClasses];
  self.startedActions = [NSMutableArray array];
  self.finishedActions = [NSMutableArray array];
  self.failedActions = [NSMutableArray array];
  self.uploads = [NSMutableArray array];
  self.badInput = [NSMutableArray array];
}

- (void)tearDown
{
  [super tearDown];

  NSError *error;
  BOOL success = [self.reader stopListeningWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

+ (XCTestSuite *)defaultTestSuite
{
  return [XCTestSuite testSuiteWithName:@"Ignoring Base Class"];
}

- (NSPredicate *)predicateForStarted:(id<FBiOSTargetAction>)action
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBiOSActionReaderTests *tests, id __) {
    return [tests.startedActions containsObject:action];
  }];
}

- (NSPredicate *)predicateForFinished:(id<FBiOSTargetAction>)action
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBiOSActionReaderTests *tests, id __) {
    return [tests.finishedActions containsObject:action];
  }];
}

- (NSPredicate *)predicateForFailed:(id<FBiOSTargetAction>)action
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBiOSActionReaderTests *tests, id __) {
    return [tests.failedActions containsObject:action];
  }];
}

- (NSPredicate *)predicateForBadInputCount:(NSUInteger)count
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBiOSActionReaderTests *tests, id __) {
    return tests.badInput.count == count;
  }];
}

- (NSPredicate *)predicateForUploadCount:(NSUInteger)count
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBiOSActionReaderTests *tests, id __) {
    return tests.uploads.count == count;
  }];
}

- (void)waitForPredicates:(NSArray<NSPredicate *> *)predicates
{
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:predicates];
  XCTestExpectation *expectation = [self expectationForPredicate:predicate evaluatedWithObject:self handler:nil];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testPassingAction
{
  FBiOSTargetActionDouble *inputAction = [[FBiOSTargetActionDouble alloc] initWithIdentifier:@"Foo" succeed:YES];
  [self.consumer consumeData:[self actionLine:inputAction]];

  [self waitForPredicates:@[
    [self predicateForStarted:inputAction],
    [self predicateForFinished:inputAction],
  ]];
}

- (void)testFailingAction
{
  FBiOSTargetActionDouble *inputAction = [[FBiOSTargetActionDouble alloc] initWithIdentifier:@"Foo" succeed:NO];
  [self.consumer consumeData:[self actionLine:inputAction]];

  [self waitForPredicates:@[
    [self predicateForStarted:inputAction],
    [self predicateForFailed:inputAction],
  ]];
}

- (void)testInterpretedInputWithGarbageInput
{
  NSData *data = [@"asdaad asasd asda d\n" dataUsingEncoding:NSUTF8StringEncoding];
  [self.consumer consumeData:data];

  [self waitForPredicates:@[
    [self predicateForBadInputCount:1],
  ]];
}

- (void)testCanUploadBinary
{
  NSData *transmit = [@"foo bar baz" dataUsingEncoding:NSUTF8StringEncoding];
  NSData *header = [self actionLine:[FBUploadHeader headerWithPathExtension:@"txt" size:transmit.length]];

  [self.consumer consumeData:header];
  [self.consumer consumeData:transmit];

  [self waitForPredicates:@[
    [self predicateForUploadCount:1],
  ]];

  NSData *fileData = [NSData dataWithContentsOfFile:self.uploads.firstObject.path];
  XCTAssertEqualObjects(transmit, fileData);
}

- (void)testCanUploadBinaryThenRunAnAction
{
  NSData *transmit = [@"foo bar baz" dataUsingEncoding:NSUTF8StringEncoding];
  NSData *header = [self actionLine:[FBUploadHeader headerWithPathExtension:@"txt" size:transmit.length]];
  FBiOSTargetActionDouble *inputAction = [[FBiOSTargetActionDouble alloc] initWithIdentifier:@"Foo" succeed:YES];

  [self.consumer consumeData:header];
  [self.consumer consumeData:transmit];
  [self.consumer consumeData:[self actionLine:inputAction]];

  [self waitForPredicates:@[
    [self predicateForUploadCount:1],
  ]];

  NSData *fileData = [NSData dataWithContentsOfFile:self.uploads.firstObject.path];
  XCTAssertEqualObjects(transmit, fileData);

  [self waitForPredicates:@[
    [self predicateForStarted:inputAction],
    [self predicateForFinished:inputAction],
  ]];
}

#pragma mark Delegate

- (void)action:(id<FBiOSTargetAction>)action target:(id<FBiOSTarget>)target didGenerateTerminationHandle:(id<FBTerminationHandle>)terminationHandle
{

}

- (id<FBFileConsumer>)obtainConsumerForAction:(id<FBiOSTargetAction>)action target:(id<FBiOSTarget>)target
{
  return [FBFileWriter nullWriter];
}

- (void)readerDidFinishReading:(FBiOSActionReader *)reader
{
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader failedToInterpretInput:(NSString *)input error:(NSError *)error
{
  [self.badInput addObject:input];
  return nil;
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader willStartReadingUpload:(FBUploadHeader *)header
{
  return nil;
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader didFinishUpload:(FBUploadedDestination *)binary
{
  [self.uploads addObject:binary];
  return nil;
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader willStartPerformingAction:(id<FBiOSTargetAction>)action onTarget:(id<FBiOSTarget>)target
{
  [self.startedActions addObject:action];
  return nil;
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader didProcessAction:(id<FBiOSTargetAction>)action onTarget:(id<FBiOSTarget>)target
{
  [self.finishedActions addObject:action];
  return nil;
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader didFailToProcessAction:(id<FBiOSTargetAction>)action onTarget:(id<FBiOSTarget>)target error:(NSError *)error
{
  [self.failedActions addObject:action];
  return nil;
}

- (void)report:(id<FBEventReporterSubject>)subject
{

}

- (id<FBEventInterpreter>)interpreter
{
  return nil;
}

- (id<FBEventReporter>)reporter
{
  return nil;
}

@end

@implementation FBiOSActionReaderFileTests

- (void)setUp
{
  [super setUp];

  self.pipe = NSPipe.pipe;
  self.reader = [FBiOSActionReader fileReaderForRouter:self.router delegate:self readHandle:self.pipe.fileHandleForReading writeHandle:self.pipe.fileHandleForWriting];
  self.consumer = [FBFileWriter syncWriterWithFileHandle:self.pipe.fileHandleForWriting];

  NSError *error;
  BOOL success = [self.reader startListeningWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

+ (XCTestSuite *)defaultTestSuite
{
  return [XCTestSuite testSuiteForTestCaseClass:self.class];
}

@end

@implementation FBiOSActionReaderSocketTests

- (void)setUp
{
  [super setUp];

  self.reader = [FBiOSActionReader socketReaderForRouter:self.router delegate:self port:FBiOSActionReaderSocketTests.readerPort];
  self.writer = [FBSocketWriter writerForHost:@"localhost" port:FBiOSActionReaderSocketTests.readerPort consumer:self];

  NSError *error;
  BOOL success = [self.reader startListeningWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  success = [self.writer startWritingWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (void)tearDown
{
  [super tearDown];

  NSError *error;
  BOOL success = [self.writer stopWritingWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

+ (in_port_t)readerPort
{
  return 4232;
}

+ (XCTestSuite *)defaultTestSuite
{
  return [XCTestSuite testSuiteForTestCaseClass:self.class];
}

- (void)writeBackAvailable:(id<FBFileConsumer>)writeBack
{
  self.consumer = writeBack;
}

- (void)consumeData:(NSData *)data
{

}

- (void)consumeEndOfFile
{
  self.consumer = nil;
}

@end

NS_ASSUME_NONNULL_END
