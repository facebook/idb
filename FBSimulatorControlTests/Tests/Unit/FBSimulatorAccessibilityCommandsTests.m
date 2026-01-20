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
// Child element references for property access assertions
@property (nonatomic, strong) FBSimulatorControlTests_AXPMacPlatformElement_Double *titleLabel;
@property (nonatomic, strong) FBSimulatorControlTests_AXPMacPlatformElement_Double *okButton;
@property (nonatomic, strong) FBSimulatorControlTests_AXPMacPlatformElement_Double *cancelButton;

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

#pragma mark - Setup/Teardown

- (void)setUp
{
  [super setUp];

  // Create a mock element hierarchy representing a typical UI
  self.okButton =
    [FBAccessibilityTestElementBuilder buttonWithLabel:@"OK"
                                            identifier:@"ok_button"
                                                 frame:NSMakeRect(20, 750, 150, 44)];

  self.cancelButton =
    [FBAccessibilityTestElementBuilder buttonWithLabel:@"Cancel"
                                            identifier:@"cancel_button"
                                                 frame:NSMakeRect(200, 750, 150, 44)];

  self.titleLabel =
    [FBAccessibilityTestElementBuilder staticTextWithLabel:@"Confirm Action"
                                                     frame:NSMakeRect(20, 100, 350, 30)];

  FBSimulatorControlTests_AXPMacPlatformElement_Double *root =
    [FBAccessibilityTestElementBuilder applicationWithLabel:@"App Window"
                                                      frame:NSMakeRect(0, 0, 390, 844)
                                                   children:@[self.titleLabel, self.okButton, self.cancelButton]];

  // Create fixture with the element tree
  self.fixture = [FBAccessibilityTestFixture bootedSimulatorFixture];
  self.fixture.rootElement = root;
  [self.fixture setUp];
}

- (void)tearDown
{
  [self.fixture tearDown];
  self.fixture = nil;
  self.titleLabel = nil;
  self.okButton = nil;
  self.cancelButton = nil;
  [super tearDown];
}

- (void)testAccessibilityCommandsProducesCorrectFlatOutput
{
  FBSimulatorAccessibilityCommands *commands = [self commands];
  XCTAssertNotNil(commands);

  NSError *error = nil;
  NSArray *result = [[commands accessibilityElementsWithNestedFormat:NO keys:nil] awaitWithTimeout:5.0 error:&error];

  XCTAssertNil(error, @"Should not have error: %@", error);
  XCTAssertNotNil(result);
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
    },
  ];

  XCTAssertEqualObjects(result, expected);
  XCTAssertTrue([NSJSONSerialization isValidJSONObject:result]);

  // Verify property access tracking - all serialization properties should be accessed
  XCTAssertEqualObjects(self.fixture.rootElement.accessedProperties, [self allSerializationProperties],
    @"All serialization properties should be accessed for root element");
  XCTAssertEqualObjects(self.titleLabel.accessedProperties, [self allSerializationProperties],
    @"All serialization properties should be accessed for title label");
  XCTAssertEqualObjects(self.okButton.accessedProperties, [self allSerializationProperties],
    @"All serialization properties should be accessed for OK button");
  XCTAssertEqualObjects(self.cancelButton.accessedProperties, [self allSerializationProperties],
    @"All serialization properties should be accessed for Cancel button");
}

- (void)testAccessibilityCommandsProducesCorrectNestedOutput
{
  FBSimulatorAccessibilityCommands *commands = [self commands];

  NSError *error = nil;
  NSArray *result = [[commands accessibilityElementsWithNestedFormat:YES keys:nil] awaitWithTimeout:5.0 error:&error];

  XCTAssertNil(error, @"Should not have error: %@", error);
  XCTAssertNotNil(result);
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
  XCTAssertEqualObjects(self.titleLabel.accessedProperties, [self allSerializationProperties],
    @"All serialization properties should be accessed for title label");
  XCTAssertEqualObjects(self.okButton.accessedProperties, [self allSerializationProperties],
    @"All serialization properties should be accessed for OK button");
  XCTAssertEqualObjects(self.cancelButton.accessedProperties, [self allSerializationProperties],
    @"All serialization properties should be accessed for Cancel button");
}

- (void)testAccessibilityCommandsRespectsKeyFiltering
{
  FBSimulatorAccessibilityCommands *commands = [self commands];

  NSSet *keys = [NSSet setWithArray:@[@"AXLabel", @"frame"]];
  NSError *error = nil;
  NSArray *result = [[commands accessibilityElementsWithNestedFormat:NO keys:keys] awaitWithTimeout:5.0 error:&error];

  XCTAssertNil(error, @"Should not have error: %@", error);
  XCTAssertNotNil(result);
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
    @"Only label, frame, children, and translation properties should be accessed for root element");
  XCTAssertEqualObjects(self.titleLabel.accessedProperties, [self labelAndFrameFilteredProperties],
    @"Only label, frame, children, and translation properties should be accessed for title label");
  XCTAssertEqualObjects(self.okButton.accessedProperties, [self labelAndFrameFilteredProperties],
    @"Only label, frame, children, and translation properties should be accessed for OK button");
  XCTAssertEqualObjects(self.cancelButton.accessedProperties, [self labelAndFrameFilteredProperties],
    @"Only label, frame, children, and translation properties should be accessed for Cancel button");
}

- (void)testAccessibilityPerformTapOnButtonSucceeds
{
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
  // Configure objectAtPointResult to return the Cancel button element
  FBSimulatorControlTests_AXPMacPlatformElement_Double *cancelButton =
    [FBAccessibilityTestElementBuilder buttonWithLabel:@"Cancel"
                                            identifier:@"cancel_button"
                                                 frame:NSMakeRect(200, 750, 150, 44)];
  self.fixture.translator.macPlatformElementResult = cancelButton;

  FBSimulatorAccessibilityCommands *commands = [self commands];

  NSError *error = nil;
  NSDictionary *result = [[commands accessibilityElementAtPoint:CGPointMake(275, 772) nestedFormat:NO keys:nil] awaitWithTimeout:5.0 error:&error];

  XCTAssertNil(error, @"Should not have error: %@", error);
  XCTAssertNotNil(result);

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
  };

  XCTAssertEqualObjects(result, expected);
  XCTAssertTrue([NSJSONSerialization isValidJSONObject:result]);

  // Verify property access tracking - single element doesn't recurse children
  XCTAssertEqualObjects(cancelButton.accessedProperties, [self singleElementSerializationProperties],
    @"Single element at point should access all properties except children");
}

- (void)testAccessibilityElementAtPointRespectsKeyFiltering
{
  // Configure objectAtPointResult to return the title label element
  FBSimulatorControlTests_AXPMacPlatformElement_Double *titleLabel =
    [FBAccessibilityTestElementBuilder staticTextWithLabel:@"Confirm Action"
                                                     frame:NSMakeRect(20, 100, 350, 30)];
  self.fixture.translator.macPlatformElementResult = titleLabel;

  FBSimulatorAccessibilityCommands *commands = [self commands];

  NSSet *keys = [NSSet setWithArray:@[@"AXLabel", @"type", @"frame"]];
  NSError *error = nil;
  NSDictionary *result = [[commands accessibilityElementAtPoint:CGPointMake(100, 115) nestedFormat:NO keys:keys] awaitWithTimeout:5.0 error:&error];

  XCTAssertNil(error, @"Should not have error: %@", error);
  XCTAssertNotNil(result);

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
}

@end
