#import <XCTest/XCTest.h>

@interface SampleUITests : XCTestCase

@end

@implementation SampleUITests

- (void)setUp
{
    [super setUp];

    self.continueAfterFailure = NO;
    [[[XCUIApplication alloc] init] launch];
}

- (void)testInSampleUITestsThatSucceeds
{
    XCTAssertTrue(YES);
}

- (void)testInSampleUITestsThatFails
{
    XCTAssertTrue(NO);
}

@end
