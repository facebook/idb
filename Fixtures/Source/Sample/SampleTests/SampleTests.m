#import <XCTest/XCTest.h>

@interface SampleTests : XCTestCase

@end

@implementation SampleTests

- (void)testInSampleTestsThatSucceeds
{
    XCTAssertTrue(YES);
}

- (void)testInSampleTestsThatFails
{
    XCTAssertTrue(NO);
}

- (void)testSkipped
{
    XCTAssertTrue(YES);
}

@end
