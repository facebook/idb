/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreGraphics/CoreGraphics.h>
#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/AccessibilityService.h>

@interface AccessibilityServiceTests : XCTestCase
@end

@implementation AccessibilityServiceTests

static NSDictionary *FBAXTestsFrameResponse(CGRect rect)
{
  NSDictionary *frame = (NSDictionary *)CFBridgingRelease(CGRectCreateDictionaryRepresentation(rect));
  return @{@"ok" : @YES, @"tree" : @{@"XC_kAXXCAttributeLabel" : @"icon", @"XC_kAXXCAttributeFrame" : frame}};
}

static NSDictionary *FBAXTestsParse(NSData *data)
{
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}

// An off-screen or still-laying-out element reports a non-finite frame coordinate. JSON cannot
// represent infinity, and `NSJSONSerialization` raises rather than returning an error — which would
// abort the reader process and drop the client's connection mid-read. The non-finite value must
// become null and the rest of the response must survive.
- (void)testInfiniteFrameValueSerializesAsNull
{
  NSData *data = FBAXBridgeSerializeResponse(FBAXTestsFrameResponse(CGRectMake(INFINITY, 0, 10, 20)));
  NSDictionary *parsed = FBAXTestsParse(data);
  XCTAssertNotNil(parsed, @"a non-finite frame must still produce parseable JSON");
  XCTAssertEqualObjects(parsed[@"ok"], @YES);

  NSDictionary *frame = parsed[@"tree"][@"XC_kAXXCAttributeFrame"];
  XCTAssertEqualObjects(frame[@"X"], NSNull.null, @"the non-finite member must be null, got: %@", frame[@"X"]);
  XCTAssertEqualObjects(frame[@"Height"], @20, @"finite members must be preserved");
  XCTAssertEqualObjects(parsed[@"tree"][@"XC_kAXXCAttributeLabel"], @"icon", @"the rest of the node must survive");
}

- (void)testNaNFrameValueSerializesAsNull
{
  NSData *data = FBAXBridgeSerializeResponse(FBAXTestsFrameResponse(CGRectMake(0, NAN, 10, 20)));
  NSDictionary *parsed = FBAXTestsParse(data);
  XCTAssertNotNil(parsed);
  XCTAssertEqualObjects(parsed[@"tree"][@"XC_kAXXCAttributeFrame"][@"Y"], NSNull.null);
}

- (void)testFiniteResponseIsUnchanged
{
  NSData *data = FBAXBridgeSerializeResponse(FBAXTestsFrameResponse(CGRectMake(16, 293, 370, 52)));
  NSDictionary *frame = FBAXTestsParse(data)[@"tree"][@"XC_kAXXCAttributeFrame"];
  XCTAssertEqualObjects(frame[@"X"], @16);
  XCTAssertEqualObjects(frame[@"Y"], @293);
  XCTAssertEqualObjects(frame[@"Width"], @370);
  XCTAssertEqualObjects(frame[@"Height"], @52);
}

// A value that cannot be represented at all must degrade to an error frame the client can read,
// rather than raising and terminating the reader.
- (void)testUnserializableValueYieldsAnErrorFrameRatherThanRaising
{
  NSDictionary *response = @{@"ok" : @YES, @"tree" : [NSDate date]};
  NSDictionary *parsed = FBAXTestsParse(FBAXBridgeSerializeResponse(response));
  XCTAssertEqualObjects(parsed[@"ok"], @NO);
  XCTAssertNotNil(parsed[@"error"]);
}

@end
