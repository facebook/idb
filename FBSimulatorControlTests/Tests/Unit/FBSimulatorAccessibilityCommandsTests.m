/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "AccessibilityDoubles.h"

#pragma mark - End-to-End Accessibility Commands Tests

/**
 End-to-end unit tests that exercise the full accessibility flow using mocks.
 These tests call the real FBSimulatorAccessibilityCommands API with a doubled simulator
 to verify the complete flow from input to JSON output.
 */
@interface FBSimulatorAccessibilityCommandsTests : XCTestCase

@property (nonatomic, strong) FBAccessibilityTestFixture *fixture;

@end

@implementation FBSimulatorAccessibilityCommandsTests

#pragma mark - Helpers

- (FBSimulatorAccessibilityCommands *)commands
{
  return [FBSimulatorAccessibilityCommands commandsWithTarget:(FBSimulator *)self.fixture.simulator];
}

/// All properties accessed during full serialization (no key filtering)
- (NSSet<NSString *> *)allSerializationProperties
{
  return [NSSet setWithArray:@[
    @"accessibilityLabel",
    @"accessibilityIdentifier",
    @"accessibilityValue",
    @"accessibilityTitle",
    @"accessibilityHelp",
    @"accessibilityRole",
    @"accessibilityRoleDescription",
    @"accessibilitySubrole",
    @"accessibilityFrame",
    @"accessibilityEnabled",
    @"accessibilityRequired",
    @"accessibilityCustomActions",
    @"accessibilityChildren",
    @"translation",
  ]];
}

/// Properties accessed for single-element serialization (no children recursion)
- (NSSet<NSString *> *)singleElementSerializationProperties
{
  return [NSSet setWithArray:@[
    @"accessibilityLabel",
    @"accessibilityIdentifier",
    @"accessibilityValue",
    @"accessibilityTitle",
    @"accessibilityHelp",
    @"accessibilityRole",
    @"accessibilityRoleDescription",
    @"accessibilitySubrole",
    @"accessibilityFrame",
    @"accessibilityEnabled",
    @"accessibilityRequired",
    @"accessibilityCustomActions",
    @"translation",
  ]];
}

/// Properties accessed for AXLabel and frame key filtering
- (NSSet<NSString *> *)labelAndFrameFilteredProperties
{
  return [NSSet setWithArray:@[
    @"accessibilityLabel",
    @"accessibilityFrame",
    @"accessibilityChildren",  // Always accessed for recursion
    @"translation",  // Always accessed for pid
  ]];
}

/// Properties accessed for AXLabel, type, and frame key filtering
- (NSSet<NSString *> *)labelTypeFrameFilteredProperties
{
  return [NSSet setWithArray:@[
    @"accessibilityLabel",
    @"accessibilityRole",  // Needed for "type" derivation
    @"accessibilityFrame",
    @"translation",  // Always accessed for pid
  ]];
}

/// Properties accessed during tap operation (includes action validation)
- (NSSet<NSString *> *)tapOperationProperties
{
  return [NSSet setWithArray:@[
    @"accessibilityLabel",
    @"accessibilityIdentifier",
    @"accessibilityValue",
    @"accessibilityTitle",
    @"accessibilityHelp",
    @"accessibilityRole",
    @"accessibilityRoleDescription",
    @"accessibilitySubrole",
    @"accessibilityFrame",
    @"accessibilityEnabled",
    @"accessibilityRequired",
    @"accessibilityCustomActions",
    @"accessibilityChildren",
    @"accessibilityActionNames",  // Accessed for action validation
    @"translation",
  ]];
}

/// Asserts profiling data metrics with expected counts
- (void)assertProfilingData:(FBAccessibilityProfilingData *)profilingData
           expectedElements:(NSUInteger)expectedElementCount
     expectedAttributeFetches:(NSUInteger)expectedAttributeFetchCount
{
  XCTAssertNotNil(profilingData, @"Profiling data should be present");
  XCTAssertEqual(profilingData.elementCount, expectedElementCount, @"Element count mismatch");
  XCTAssertEqual(profilingData.attributeFetchCount, expectedAttributeFetchCount, @"Attribute fetch count mismatch");
  XCTAssertGreaterThanOrEqual(profilingData.xpcCallCount, 0, @"XPC call count should be non-negative");
  XCTAssertGreaterThanOrEqual(profilingData.translationDuration, 0, @"Translation duration should be non-negative");
  XCTAssertGreaterThanOrEqual(profilingData.elementConversionDuration, 0, @"Element conversion duration should be non-negative");
  XCTAssertGreaterThanOrEqual(profilingData.serializationDuration, 0, @"Serialization duration should be non-negative");
}

#pragma mark - Core Test Helpers

/// Core test for flat output - returns response for optional profiling assertions
- (FBAccessibilityElementsResponse *)assertFlatOutputWithProfiling:(BOOL)enableProfiling
                                                     childElements:(NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)childElements
{
  FBSimulatorAccessibilityCommands *commands = [self commands];
  XCTAssertNotNil(commands);

  FBAccessibilityRequestOptions *options = [FBAccessibilityRequestOptions defaultOptions];
  options.nestedFormat = NO;
  options.enableLogging = YES;
  options.enableProfiling = enableProfiling;

  NSError *error = nil;
  FBAccessibilityElementsResponse *response = [[commands accessibilityElementsWithOptions:options] awaitWithTimeout:5.0 error:&error];

  XCTAssertNil(error, @"Should not have error: %@", error);
  XCTAssertNotNil(response);

  NSArray *result = (NSArray *)response.elements;
  XCTAssertEqual(result.count, 4, @"Flat format should have 4 elements (root + 3 children)");

  // Expected full output for all 4 elements
  NSArray *expected = @[
    @{
      @"AXLabel": @"App Window",
      @"AXFrame": @"{{0, 0}, {390, 844}}",
      @"AXValue": [NSNull null],
      @"AXUniqueId": [NSNull null],
      @"type": @"Application",
      @"title": [NSNull null],
      @"frame": @{@"x": @0, @"y": @0, @"width": @390, @"height": @844},
      @"help": [NSNull null],
      @"enabled": @YES,
      @"custom_actions": @[],
      @"role": @"AXApplication",
      @"role_description": [NSNull null],
      @"subrole": [NSNull null],
      @"content_required": @NO,
      @"pid": @12345,
      @"traits": [NSNull null],
    },
    @{
      @"AXLabel": @"Confirm Action",
      @"AXFrame": @"{{20, 100}, {350, 30}}",
      @"AXValue": [NSNull null],
      @"AXUniqueId": [NSNull null],
      @"type": @"StaticText",
      @"title": [NSNull null],
      @"frame": @{@"x": @20, @"y": @100, @"width": @350, @"height": @30},
      @"help": [NSNull null],
      @"enabled": @YES,
      @"custom_actions": @[],
      @"role": @"AXStaticText",
      @"role_description": [NSNull null],
      @"subrole": [NSNull null],
      @"content_required": @NO,
      @"pid": @12345,
      @"traits": [NSNull null],
    },
    @{
      @"AXLabel": @"OK",
      @"AXFrame": @"{{20, 750}, {150, 44}}",
      @"AXValue": [NSNull null],
      @"AXUniqueId": @"ok_button",
      @"type": @"Button",
      @"title": [NSNull null],
      @"frame": @{@"x": @20, @"y": @750, @"width": @150, @"height": @44},
      @"help": [NSNull null],
      @"enabled": @YES,
      @"custom_actions": @[],
      @"role": @"AXButton",
      @"role_description": [NSNull null],
      @"subrole": [NSNull null],
      @"content_required": @NO,
      @"pid": @12345,
      @"traits": [NSNull null],
    },
    @{
      @"AXLabel": @"Cancel",
      @"AXFrame": @"{{200, 750}, {150, 44}}",
      @"AXValue": [NSNull null],
      @"AXUniqueId": @"cancel_button",
      @"type": @"Button",
      @"title": [NSNull null],
      @"frame": @{@"x": @200, @"y": @750, @"width": @150, @"height": @44},
      @"help": [NSNull null],
      @"enabled": @YES,
      @"custom_actions": @[],
      @"role": @"AXButton",
      @"role_description": [NSNull null],
      @"subrole": [NSNull null],
      @"content_required": @NO,
      @"pid": @12345,
      @"traits": [NSNull null],
    },
  ];

  XCTAssertEqualObjects(result, expected);
  XCTAssertTrue([NSJSONSerialization isValidJSONObject:result]);

  // Verify property access tracking - all serialization properties should be accessed
  XCTAssertEqualObjects(self.fixture.rootElement.accessedProperties, [self allSerializationProperties],
    @"All serialization properties should be accessed for root element");
  for (FBSimulatorControlTests_AXPMacPlatformElement_Double *child in childElements) {
    XCTAssertEqualObjects(child.accessedProperties, [self allSerializationProperties],
      @"All serialization properties should be accessed for child element");
  }

  return response;
}

/// Core test for element at point - returns response for optional profiling assertions
- (FBAccessibilityElementsResponse *)assertElementAtPointWithProfiling:(BOOL)enableProfiling
                                                                  point:(CGPoint)point
                                                                element:(FBSimulatorControlTests_AXPMacPlatformElement_Double *)element
                                                               expected:(NSDictionary *)expected
{
  self.fixture.translator.macPlatformElementResult = element;

  FBSimulatorAccessibilityCommands *commands = [self commands];

  FBAccessibilityRequestOptions *options = [FBAccessibilityRequestOptions defaultOptions];
  options.nestedFormat = NO;
  options.enableLogging = YES;
  options.enableProfiling = enableProfiling;

  NSError *error = nil;
  FBAccessibilityElementsResponse *response = [[commands accessibilityElementAtPoint:point options:options] awaitWithTimeout:5.0 error:&error];

  XCTAssertNil(error, @"Should not have error: %@", error);
  XCTAssertNotNil(response);

  NSDictionary *result = (NSDictionary *)response.elements;
  XCTAssertEqualObjects(result, expected);
  XCTAssertTrue([NSJSONSerialization isValidJSONObject:result]);

  // Verify property access tracking - single element doesn't recurse children
  XCTAssertEqualObjects(element.accessedProperties, [self singleElementSerializationProperties],
    @"Single element at point should access all properties except children");

  return response;
}

/// Core test for nested output - returns response for optional profiling assertions
- (FBAccessibilityElementsResponse *)assertNestedOutputWithProfiling:(BOOL)enableProfiling
                                                       childElements:(NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)childElements
{
  FBSimulatorAccessibilityCommands *commands = [self commands];

  FBAccessibilityRequestOptions *options = [FBAccessibilityRequestOptions defaultOptions];
  options.nestedFormat = YES;
  options.enableLogging = YES;
  options.enableProfiling = enableProfiling;

  NSError *error = nil;
  FBAccessibilityElementsResponse *response = [[commands accessibilityElementsWithOptions:options] awaitWithTimeout:5.0 error:&error];

  XCTAssertNil(error, @"Should not have error: %@", error);
  XCTAssertNotNil(response);

  NSArray *result = (NSArray *)response.elements;
  XCTAssertEqual(result.count, 1, @"Nested format should have 1 root element");

  // Expected full nested output
  NSArray *expected = @[
    @{
      @"AXLabel": @"App Window",
      @"AXFrame": @"{{0, 0}, {390, 844}}",
      @"AXValue": [NSNull null],
      @"AXUniqueId": [NSNull null],
      @"type": @"Application",
      @"title": [NSNull null],
      @"frame": @{@"x": @0, @"y": @0, @"width": @390, @"height": @844},
      @"help": [NSNull null],
      @"enabled": @YES,
      @"custom_actions": @[],
      @"role": @"AXApplication",
      @"role_description": [NSNull null],
      @"subrole": [NSNull null],
      @"content_required": @NO,
      @"pid": @12345,
      @"traits": [NSNull null],
      @"children": @[
        @{
          @"AXLabel": @"Confirm Action",
          @"AXFrame": @"{{20, 100}, {350, 30}}",
          @"AXValue": [NSNull null],
          @"AXUniqueId": [NSNull null],
          @"type": @"StaticText",
          @"title": [NSNull null],
          @"frame": @{@"x": @20, @"y": @100, @"width": @350, @"height": @30},
          @"help": [NSNull null],
          @"enabled": @YES,
          @"custom_actions": @[],
          @"role": @"AXStaticText",
          @"role_description": [NSNull null],
          @"subrole": [NSNull null],
          @"content_required": @NO,
          @"pid": @12345,
          @"traits": [NSNull null],
          @"children": @[],
        },
        @{
          @"AXLabel": @"OK",
          @"AXFrame": @"{{20, 750}, {150, 44}}",
          @"AXValue": [NSNull null],
          @"AXUniqueId": @"ok_button",
          @"type": @"Button",
          @"title": [NSNull null],
          @"frame": @{@"x": @20, @"y": @750, @"width": @150, @"height": @44},
          @"help": [NSNull null],
          @"enabled": @YES,
          @"custom_actions": @[],
          @"role": @"AXButton",
          @"role_description": [NSNull null],
          @"subrole": [NSNull null],
          @"content_required": @NO,
          @"pid": @12345,
          @"traits": [NSNull null],
          @"children": @[],
        },
        @{
          @"AXLabel": @"Cancel",
          @"AXFrame": @"{{200, 750}, {150, 44}}",
          @"AXValue": [NSNull null],
          @"AXUniqueId": @"cancel_button",
          @"type": @"Button",
          @"title": [NSNull null],
          @"frame": @{@"x": @200, @"y": @750, @"width": @150, @"height": @44},
          @"help": [NSNull null],
          @"enabled": @YES,
          @"custom_actions": @[],
          @"role": @"AXButton",
          @"role_description": [NSNull null],
          @"subrole": [NSNull null],
          @"content_required": @NO,
          @"pid": @12345,
          @"traits": [NSNull null],
          @"children": @[],
        },
      ],
    },
  ];

  XCTAssertEqualObjects(result, expected);
  XCTAssertTrue([NSJSONSerialization isValidJSONObject:result]);

  // Verify property access tracking - all serialization properties should be accessed
  XCTAssertEqualObjects(self.fixture.rootElement.accessedProperties, [self allSerializationProperties],
    @"All serialization properties should be accessed for root element");
  for (FBSimulatorControlTests_AXPMacPlatformElement_Double *child in childElements) {
    XCTAssertEqualObjects(child.accessedProperties, [self allSerializationProperties],
      @"All serialization properties should be accessed for child element");
  }

  return response;
}

/// Core test for key filtering - returns response for optional profiling assertions
- (FBAccessibilityElementsResponse *)assertKeyFilteringWithProfiling:(BOOL)enableProfiling
                                                       childElements:(NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)childElements
{
  FBSimulatorAccessibilityCommands *commands = [self commands];

  FBAccessibilityRequestOptions *options = [FBAccessibilityRequestOptions defaultOptions];
  options.nestedFormat = NO;
  options.keys = [NSSet setWithArray:@[@"AXLabel", @"frame"]];
  options.enableLogging = YES;
  options.enableProfiling = enableProfiling;

  NSError *error = nil;
  FBAccessibilityElementsResponse *response = [[commands accessibilityElementsWithOptions:options] awaitWithTimeout:5.0 error:&error];

  XCTAssertNil(error, @"Should not have error: %@", error);
  XCTAssertNotNil(response);

  NSArray *result = (NSArray *)response.elements;
  XCTAssertEqual(result.count, 4, @"Should have 4 elements");

  // Expected output with only the requested keys
  NSArray *expected = @[
    @{
      @"AXLabel": @"App Window",
      @"frame": @{@"x": @0, @"y": @0, @"width": @390, @"height": @844},
    },
    @{
      @"AXLabel": @"Confirm Action",
      @"frame": @{@"x": @20, @"y": @100, @"width": @350, @"height": @30},
    },
    @{
      @"AXLabel": @"OK",
      @"frame": @{@"x": @20, @"y": @750, @"width": @150, @"height": @44},
    },
    @{
      @"AXLabel": @"Cancel",
      @"frame": @{@"x": @200, @"y": @750, @"width": @150, @"height": @44},
    },
  ];

  XCTAssertEqualObjects(result, expected);
  XCTAssertTrue([NSJSONSerialization isValidJSONObject:result]);

  // Verify property access tracking - only filtered properties should be accessed
  XCTAssertEqualObjects(self.fixture.rootElement.accessedProperties, [self labelAndFrameFilteredProperties],
    @"Only label and frame properties should be accessed for root element");
  for (FBSimulatorControlTests_AXPMacPlatformElement_Double *child in childElements) {
    XCTAssertEqualObjects(child.accessedProperties, [self labelAndFrameFilteredProperties],
      @"Only label and frame properties should be accessed for child element");
  }

  return response;
}

/// Core test for element at point with key filtering - returns response for optional profiling assertions
- (FBAccessibilityElementsResponse *)assertElementAtPointKeyFilteringWithProfiling:(BOOL)enableProfiling
{
  // Configure objectAtPointResult to return the title label element
  FBSimulatorControlTests_AXPMacPlatformElement_Double *titleLabel =
    [FBAccessibilityTestElementBuilder staticTextWithLabel:@"Confirm Action"
                                                     frame:NSMakeRect(20, 100, 350, 30)];
  self.fixture.translator.macPlatformElementResult = titleLabel;

  FBSimulatorAccessibilityCommands *commands = [self commands];

  FBAccessibilityRequestOptions *options = [FBAccessibilityRequestOptions defaultOptions];
  options.nestedFormat = NO;
  options.keys = [NSSet setWithArray:@[@"AXLabel", @"type", @"frame"]];
  options.enableLogging = YES;
  options.enableProfiling = enableProfiling;

  NSError *error = nil;
  FBAccessibilityElementsResponse *response = [[commands accessibilityElementAtPoint:CGPointMake(100, 115) options:options] awaitWithTimeout:5.0 error:&error];

  XCTAssertNil(error, @"Should not have error: %@", error);
  XCTAssertNotNil(response);

  NSDictionary *result = (NSDictionary *)response.elements;

  NSDictionary *expected = @{
    @"AXLabel": @"Confirm Action",
    @"type": @"StaticText",
    @"frame": @{@"x": @20, @"y": @100, @"width": @350, @"height": @30},
  };

  XCTAssertEqualObjects(result, expected);
  XCTAssertTrue([NSJSONSerialization isValidJSONObject:result]);

  // Verify property access tracking - only filtered properties should be accessed
  XCTAssertEqualObjects(titleLabel.accessedProperties, [self labelTypeFrameFilteredProperties],
    @"Only label, role (for type), and frame properties should be accessed with key filtering");

  return response;
}

#pragma mark - Setup/Teardown

- (void)tearDown
{
  [self.fixture tearDown];
  self.fixture = nil;
  [super tearDown];
}

/// Creates and activates the fixture with the given root element tree.
/// Call this at the start of each test method.
- (void)setUpWithRootElement:(FBSimulatorControlTests_AXPMacPlatformElement_Double *)rootElement
{
  self.fixture = [FBAccessibilityTestFixture bootedSimulatorFixture];
  self.fixture.rootElement = rootElement;
  [self.fixture setUp];
}

#pragma mark - Default Element Factories

/// Returns a default title label element.
- (FBSimulatorControlTests_AXPMacPlatformElement_Double *)defaultTitleLabel
{
  return [FBAccessibilityTestElementBuilder staticTextWithLabel:@"Confirm Action"
                                                          frame:NSMakeRect(20, 100, 350, 30)];
}

/// Returns a default OK button element.
- (FBSimulatorControlTests_AXPMacPlatformElement_Double *)defaultOkButton
{
  return [FBAccessibilityTestElementBuilder buttonWithLabel:@"OK"
                                                 identifier:@"ok_button"
                                                      frame:NSMakeRect(20, 750, 150, 44)];
}

/// Returns a default Cancel button element.
- (FBSimulatorControlTests_AXPMacPlatformElement_Double *)defaultCancelButton
{
  return [FBAccessibilityTestElementBuilder buttonWithLabel:@"Cancel"
                                                 identifier:@"cancel_button"
                                                      frame:NSMakeRect(200, 750, 150, 44)];
}

/// Returns the default root element tree with the given children.
- (FBSimulatorControlTests_AXPMacPlatformElement_Double *)defaultRootWithChildren:(NSArray *)children
{
  return [FBAccessibilityTestElementBuilder applicationWithLabel:@"App Window"
                                                           frame:NSMakeRect(0, 0, 390, 844)
                                                        children:children];
}

/// Returns the default element tree (root with titleLabel, okButton, cancelButton).
- (FBSimulatorControlTests_AXPMacPlatformElement_Double *)defaultElementTree
{
  return [self defaultRootWithChildren:@[[self defaultTitleLabel], [self defaultOkButton], [self defaultCancelButton]]];
}

- (void)testAccessibilityCommandsProducesCorrectFlatOutput
{
  NSArray *children = @[[self defaultTitleLabel], [self defaultOkButton], [self defaultCancelButton]];
  [self setUpWithRootElement:[self defaultRootWithChildren:children]];
  [self assertFlatOutputWithProfiling:NO childElements:children];
}

- (void)testAccessibilityCommandsProducesCorrectFlatOutputWithProfiling
{
  NSArray *children = @[[self defaultTitleLabel], [self defaultOkButton], [self defaultCancelButton]];
  [self setUpWithRootElement:[self defaultRootWithChildren:children]];
  FBAccessibilityElementsResponse *response = [self assertFlatOutputWithProfiling:YES childElements:children];
  // 4 elements × 14 properties (all except actionNames) = 56 attribute fetches
  [self assertProfilingData:response.profilingData expectedElements:4 expectedAttributeFetches:56];
}

- (void)testAccessibilityCommandsProducesCorrectNestedOutput
{
  NSArray *children = @[[self defaultTitleLabel], [self defaultOkButton], [self defaultCancelButton]];
  [self setUpWithRootElement:[self defaultRootWithChildren:children]];
  [self assertNestedOutputWithProfiling:NO childElements:children];
}

- (void)testAccessibilityCommandsProducesCorrectNestedOutputWithProfiling
{
  NSArray *children = @[[self defaultTitleLabel], [self defaultOkButton], [self defaultCancelButton]];
  [self setUpWithRootElement:[self defaultRootWithChildren:children]];
  FBAccessibilityElementsResponse *response = [self assertNestedOutputWithProfiling:YES childElements:children];
  // 4 elements × 14 properties (all except actionNames) = 56 attribute fetches
  [self assertProfilingData:response.profilingData expectedElements:4 expectedAttributeFetches:56];
}

- (void)testAccessibilityCommandsRespectsKeyFiltering
{
  NSArray *children = @[[self defaultTitleLabel], [self defaultOkButton], [self defaultCancelButton]];
  [self setUpWithRootElement:[self defaultRootWithChildren:children]];
  [self assertKeyFilteringWithProfiling:NO childElements:children];
}

- (void)testAccessibilityCommandsRespectsKeyFilteringWithProfiling
{
  NSArray *children = @[[self defaultTitleLabel], [self defaultOkButton], [self defaultCancelButton]];
  [self setUpWithRootElement:[self defaultRootWithChildren:children]];
  FBAccessibilityElementsResponse *response = [self assertKeyFilteringWithProfiling:YES childElements:children];
  // 4 elements × 2 properties (label, frame) = 8 attribute fetches (children/translation not tracked for leaf elements)
  [self assertProfilingData:response.profilingData expectedElements:4 expectedAttributeFetches:8];
}

- (void)testAccessibilityPerformTapOnButtonSucceeds
{
  [self setUpWithRootElement:[self defaultElementTree]];

  // Configure objectAtPointResult to return the OK button element
  FBSimulatorControlTests_AXPMacPlatformElement_Double *okButton =
    [FBAccessibilityTestElementBuilder buttonWithLabel:@"OK"
                                            identifier:@"ok_button"
                                                 frame:NSMakeRect(20, 750, 150, 44)];
  self.fixture.translator.macPlatformElementResult = okButton;

  FBSimulatorAccessibilityCommands *commands = [self commands];

  // Perform tap at the OK button center, expecting the "OK" label
  NSError *error = nil;
  NSDictionary *result = [[commands accessibilityPerformTapOnElementAtPoint:CGPointMake(95, 772) expectedLabel:@"OK"] awaitWithTimeout:5.0 error:&error];

  XCTAssertNil(error, @"Should not have error: %@", error);
  XCTAssertNotNil(result);

  // Verify the returned element is the button with expected properties
  // Note: tap returns nested format which includes children
  NSDictionary *expected = @{
    @"AXLabel": @"OK",
    @"AXFrame": @"{{20, 750}, {150, 44}}",
    @"AXValue": [NSNull null],
    @"AXUniqueId": @"ok_button",
    @"type": @"Button",
    @"title": [NSNull null],
    @"frame": @{@"x": @20, @"y": @750, @"width": @150, @"height": @44},
    @"help": [NSNull null],
    @"enabled": @YES,
    @"custom_actions": @[],
    @"role": @"AXButton",
    @"role_description": [NSNull null],
    @"subrole": [NSNull null],
    @"content_required": @NO,
    @"pid": @12345,
    @"traits": [NSNull null],
    @"children": @[],
  };

  XCTAssertEqualObjects(result, expected);
  XCTAssertTrue([NSJSONSerialization isValidJSONObject:result]);

  // Verify property access tracking - tap operation accesses all properties including action names
  XCTAssertEqualObjects(okButton.accessedProperties, [self tapOperationProperties],
    @"Tap operation should access all serialization properties including action names");
}

- (void)testAccessibilityElementAtPointReturnsElement
{
  [self setUpWithRootElement:[self defaultElementTree]];

  FBSimulatorControlTests_AXPMacPlatformElement_Double *cancelButton =
    [FBAccessibilityTestElementBuilder buttonWithLabel:@"Cancel"
                                            identifier:@"cancel_button"
                                                 frame:NSMakeRect(200, 750, 150, 44)];

  NSDictionary *expected = @{
    @"AXLabel": @"Cancel",
    @"AXFrame": @"{{200, 750}, {150, 44}}",
    @"AXValue": [NSNull null],
    @"AXUniqueId": @"cancel_button",
    @"type": @"Button",
    @"title": [NSNull null],
    @"frame": @{@"x": @200, @"y": @750, @"width": @150, @"height": @44},
    @"help": [NSNull null],
    @"enabled": @YES,
    @"custom_actions": @[],
    @"role": @"AXButton",
    @"role_description": [NSNull null],
    @"subrole": [NSNull null],
    @"content_required": @NO,
    @"pid": @12345,
    @"traits": [NSNull null],
  };

  [self assertElementAtPointWithProfiling:NO point:CGPointMake(275, 772) element:cancelButton expected:expected];
}

- (void)testAccessibilityElementAtPointReturnsElementWithProfiling
{
  [self setUpWithRootElement:[self defaultElementTree]];

  FBSimulatorControlTests_AXPMacPlatformElement_Double *cancelButton =
    [FBAccessibilityTestElementBuilder buttonWithLabel:@"Cancel"
                                            identifier:@"cancel_button"
                                                 frame:NSMakeRect(200, 750, 150, 44)];

  NSDictionary *expected = @{
    @"AXLabel": @"Cancel",
    @"AXFrame": @"{{200, 750}, {150, 44}}",
    @"AXValue": [NSNull null],
    @"AXUniqueId": @"cancel_button",
    @"type": @"Button",
    @"title": [NSNull null],
    @"frame": @{@"x": @200, @"y": @750, @"width": @150, @"height": @44},
    @"help": [NSNull null],
    @"enabled": @YES,
    @"custom_actions": @[],
    @"role": @"AXButton",
    @"role_description": [NSNull null],
    @"subrole": [NSNull null],
    @"content_required": @NO,
    @"pid": @12345,
    @"traits": [NSNull null],
  };

  FBAccessibilityElementsResponse *response = [self assertElementAtPointWithProfiling:YES point:CGPointMake(275, 772) element:cancelButton expected:expected];
  // 1 element × 14 properties (no children) = 14 attribute fetches
  [self assertProfilingData:response.profilingData expectedElements:1 expectedAttributeFetches:14];
}

- (void)testAccessibilityElementAtPointRespectsKeyFiltering
{
  [self setUpWithRootElement:[self defaultElementTree]];
  [self assertElementAtPointKeyFilteringWithProfiling:NO];
}

- (void)testAccessibilityElementAtPointRespectsKeyFilteringWithProfiling
{
  [self setUpWithRootElement:[self defaultElementTree]];
  FBAccessibilityElementsResponse *response = [self assertElementAtPointKeyFilteringWithProfiling:YES];
  // 1 element × 3 properties (label, role, frame) = 3 attribute fetches (translation not tracked)
  [self assertProfilingData:response.profilingData expectedElements:1 expectedAttributeFetches:3];
}

@end
