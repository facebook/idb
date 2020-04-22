/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBiOSTargetDouble.h"
#import "FBiOSTargetFutureDouble.h"

NS_ASSUME_NONNULL_BEGIN

@interface FBiOSActionReaderTests : XCTestCase <FBiOSActionReaderDelegate>

@property (nonatomic, strong, readwrite) NSPipe *pipe;
@property (nonatomic, strong, readwrite) FBiOSTargetDouble *target;
@property (nonatomic, strong, readwrite) FBiOSActionRouter *router;
@property (nonatomic, strong, readwrite) FBiOSActionReader *reader;
@property (nonatomic, strong, nullable, readwrite) id<FBDataConsumer> consumer;

@property (nonatomic, strong, readwrite) NSMutableArray<id<FBiOSTargetFuture>> *startedActions;
@property (nonatomic, strong, readwrite) NSMutableArray<id<FBiOSTargetFuture>> *finishedActions;
@property (nonatomic, strong, readwrite) NSMutableArray<id<FBiOSTargetFuture>> *failedActions;
@property (nonatomic, strong, readwrite) NSMutableArray<FBUploadedDestination *> *uploads;
@property (nonatomic, strong, readwrite) NSMutableArray<NSString *> *badInput;

@end

@implementation FBiOSActionReaderTests

- (NSData *)actionLine:(id<FBiOSTargetFuture>)action
{
  NSMutableData *actionData = [[NSJSONSerialization dataWithJSONObject:[self.router jsonFromAction:action] options:0 error:nil] mutableCopy];
  [actionData appendData:[NSData dataWithBytes:"\n" length:1]];
  return actionData;
}

- (void)setUp
{
  [super setUp];

  NSArray<Class> *actionClasses = [FBiOSActionRouter.defaultActionClasses arrayByAddingObject:FBiOSTargetFutureDouble.class];
  self.target = [FBiOSTargetDouble new];
  self.target.auxillaryDirectory = NSTemporaryDirectory();
  self.router = [FBiOSActionRouter routerForTarget:self.target actionClasses:actionClasses];
  self.startedActions = [NSMutableArray array];
  self.finishedActions = [NSMutableArray array];
  self.failedActions = [NSMutableArray array];
  self.uploads = [NSMutableArray array];
  self.badInput = [NSMutableArray array];

  self.pipe = NSPipe.pipe;
  self.reader = [FBiOSActionReader fileReaderForRouter:self.router delegate:self readHandle:self.pipe.fileHandleForReading writeHandle:self.pipe.fileHandleForWriting];
  self.consumer = [FBFileWriter syncWriterWithFileDescriptor:self.pipe.fileHandleForWriting.fileDescriptor closeOnEndOfFile:YES];

  NSError *error;
  BOOL success = [[self.reader startListening] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (void)tearDown
{
  [super tearDown];

  NSError *error;
  BOOL success = [[self.reader stopListening] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (NSPredicate *)predicateForStarted:(id<FBiOSTargetFuture>)action
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBiOSActionReaderTests *tests, id __) {
    return [tests.startedActions containsObject:action];
  }];
}

- (NSPredicate *)predicateForFinished:(id<FBiOSTargetFuture>)action
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBiOSActionReaderTests *tests, id __) {
    return [tests.finishedActions containsObject:action];
  }];
}

- (NSPredicate *)predicateForFailed:(id<FBiOSTargetFuture>)action
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

#pragma mark Delegate

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

- (nullable NSString *)reader:(FBiOSActionReader *)reader willStartPerformingAction:(id<FBiOSTargetFuture>)action onTarget:(id<FBiOSTarget>)target
{
  [self.startedActions addObject:action];
  return nil;
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader didProcessAction:(id<FBiOSTargetFuture>)action onTarget:(id<FBiOSTarget>)target
{
  [self.finishedActions addObject:action];
  return nil;
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader didFailToProcessAction:(id<FBiOSTargetFuture>)action onTarget:(id<FBiOSTarget>)target error:(NSError *)error
{
  [self.failedActions addObject:action];
  return nil;
}

- (void)report:(id<FBEventReporterSubject>)subject
{

}

- (void)addMetadata:(NSDictionary<NSString *, NSString *> *)metadata
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

NS_ASSUME_NONNULL_END
