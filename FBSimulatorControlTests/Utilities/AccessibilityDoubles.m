/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityDoubles.h"

#import <objc/runtime.h>

#import "FBSimulator.h"

@implementation FBSimulatorControlTests_AXPTranslationObject_Double

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }
  // Default pid for testing - matches the value set in FBAccessibilityTestFixture
  _pid = 12345;
  return self;
}

@end

@implementation FBSimulatorControlTests_AXPMacPlatformElement_Double
{
  // Backing ivars for tracking
  NSString *_label;
  NSString *_identifier;
  NSString *_role;
  NSRect _frame;
  BOOL _enabled;
  BOOL _required;
  NSArray<NSString *> *_actionNames;
  NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *_children;
  FBSimulatorControlTests_AXPTranslationObject_Double *_translation;
  NSMutableSet<NSString *> *_accessedProperties;
}

- (instancetype)initWithLabel:(NSString *)label
                   identifier:(NSString *)identifier
                         role:(NSString *)role
                        frame:(NSRect)frame
                      enabled:(BOOL)enabled
                  actionNames:(NSArray<NSString *> *)actionNames
                     children:(NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)children
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _label = [label copy];
  _identifier = [identifier copy];
  _role = [role copy];
  _frame = frame;
  _enabled = enabled;
  _actionNames = [actionNames copy] ?: @[];
  _children = [children copy] ?: @[];
  _required = NO;
  _translation = [[FBSimulatorControlTests_AXPTranslationObject_Double alloc] init];
  _accessedProperties = [NSMutableSet set];

  return self;
}

#pragma mark - Tracked Accessibility Properties

- (NSString *)accessibilityLabel
{
  [_accessedProperties addObject:@"accessibilityLabel"];
  return _label;
}

- (NSString *)accessibilityIdentifier
{
  [_accessedProperties addObject:@"accessibilityIdentifier"];
  return _identifier;
}

- (id)accessibilityValue
{
  [_accessedProperties addObject:@"accessibilityValue"];
  return nil; // Not set in initializer
}

- (NSString *)accessibilityTitle
{
  [_accessedProperties addObject:@"accessibilityTitle"];
  return nil; // Not set in initializer
}

- (NSString *)accessibilityHelp
{
  [_accessedProperties addObject:@"accessibilityHelp"];
  return nil; // Not set in initializer
}

- (NSString *)accessibilityRole
{
  [_accessedProperties addObject:@"accessibilityRole"];
  return _role;
}

- (NSString *)accessibilityRoleDescription
{
  [_accessedProperties addObject:@"accessibilityRoleDescription"];
  return nil; // Not set in initializer
}

- (NSString *)accessibilitySubrole
{
  [_accessedProperties addObject:@"accessibilitySubrole"];
  return nil; // Not set in initializer
}

- (NSRect)accessibilityFrame
{
  [_accessedProperties addObject:@"accessibilityFrame"];
  return _frame;
}

- (BOOL)accessibilityEnabled
{
  [_accessedProperties addObject:@"accessibilityEnabled"];
  return _enabled;
}

- (BOOL)accessibilityRequired
{
  [_accessedProperties addObject:@"accessibilityRequired"];
  return _required;
}

- (NSArray<id> *)accessibilityCustomActions
{
  [_accessedProperties addObject:@"accessibilityCustomActions"];
  return nil; // Not set in initializer
}

- (NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)accessibilityChildren
{
  [_accessedProperties addObject:@"accessibilityChildren"];
  return _children;
}

- (NSArray<NSString *> *)accessibilityActionNames
{
  [_accessedProperties addObject:@"accessibilityActionNames"];
  return _actionNames;
}

- (FBSimulatorControlTests_AXPTranslationObject_Double *)translation
{
  [_accessedProperties addObject:@"translation"];
  return _translation;
}

- (void)setTranslation:(FBSimulatorControlTests_AXPTranslationObject_Double *)translation
{
  _translation = translation;
}

#pragma mark - NSAccessibility Aliases

// Alias for isAccessibilityEnabled (used by NSAccessibility)
- (BOOL)isAccessibilityEnabled
{
  return [self accessibilityEnabled];
}

// Alias for isAccessibilityRequired (used by NSAccessibility)
- (BOOL)isAccessibilityRequired
{
  return [self accessibilityRequired];
}

- (BOOL)accessibilityPerformPress
{
  return YES;
}

@end

@implementation FBSimulatorControlTests_AXPTranslator_Double

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _methodCalls = [NSMutableArray array];

  return self;
}

- (FBSimulatorControlTests_AXPTranslationObject_Double *)frontmostApplicationWithDisplayId:(int)displayId bridgeDelegateToken:(NSString *)token
{
  [_methodCalls addObject:[NSString stringWithFormat:@"frontmostApplicationWithDisplayId:%d token:%@", displayId, token]];
  FBSimulatorControlTests_AXPTranslationObject_Double *result = self.frontmostApplicationResult;
  result.bridgeDelegateToken = token;
  return result;
}

- (FBSimulatorControlTests_AXPTranslationObject_Double *)objectAtPoint:(CGPoint)point displayId:(int)displayId bridgeDelegateToken:(NSString *)token
{
  [_methodCalls addObject:[NSString stringWithFormat:@"objectAtPoint:{%.1f,%.1f} displayId:%d token:%@", point.x, point.y, displayId, token]];
  FBSimulatorControlTests_AXPTranslationObject_Double *result = self.objectAtPointResult;
  result.bridgeDelegateToken = token;
  return result;
}

- (FBSimulatorControlTests_AXPMacPlatformElement_Double *)macPlatformElementFromTranslation:(FBSimulatorControlTests_AXPTranslationObject_Double *)translation
{
  [_methodCalls addObject:@"macPlatformElementFromTranslation"];
  FBSimulatorControlTests_AXPMacPlatformElement_Double *result = self.macPlatformElementResult;
  result.translation = translation;
  return result;
}

- (void)resetTracking
{
  [_methodCalls removeAllObjects];
}

@end

@implementation FBSimulatorControlTests_SimDevice_Accessibility_Double

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _UDID = [NSUUID UUID];
  _accessibilityRequests = [NSMutableArray array];

  return self;
}

- (void)sendAccessibilityRequestAsync:(id)request
                      completionQueue:(dispatch_queue_t)queue
                    completionHandler:(void (^)(id))handler
{
  [_accessibilityRequests addObject:request];

  if (self.accessibilityResponseHandler) {
    self.accessibilityResponseHandler(request, ^(id response) {
      dispatch_async(queue, ^{
        handler(response);
      });
    });
  } else {
    // Default: return empty response
    dispatch_async(queue, ^{
      handler(nil);
    });
  }
}

- (void)resetAccessibilityTracking
{
  [_accessibilityRequests removeAllObjects];
}

- (NSString *)stateString
{
  // Required for FBSimulator compatibility
  return @"Booted";
}

@end

@implementation FBAccessibilityTestElementBuilder

+ (FBSimulatorControlTests_AXPMacPlatformElement_Double *)elementWithLabel:(NSString *)label
                                                                     frame:(NSRect)frame
                                                                  children:(NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)children
{
  return [[FBSimulatorControlTests_AXPMacPlatformElement_Double alloc]
    initWithLabel:label
       identifier:nil
             role:@"AXButton"
            frame:frame
          enabled:YES
      actionNames:@[@"AXPress"]
         children:children];
}

+ (FBSimulatorControlTests_AXPMacPlatformElement_Double *)rootElementWithChildren:(NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)children
{
  return [self applicationWithLabel:@"Root" frame:NSMakeRect(0, 0, 390, 844) children:children];
}

+ (FBSimulatorControlTests_AXPMacPlatformElement_Double *)applicationWithLabel:(NSString *)label
                                                                         frame:(NSRect)frame
                                                                      children:(NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)children
{
  return [[FBSimulatorControlTests_AXPMacPlatformElement_Double alloc]
    initWithLabel:label
       identifier:nil
             role:@"AXApplication"
            frame:frame
          enabled:YES
      actionNames:nil
         children:children];
}

+ (FBSimulatorControlTests_AXPMacPlatformElement_Double *)buttonWithLabel:(NSString *)label
                                                               identifier:(NSString *)identifier
                                                                    frame:(NSRect)frame
{
  return [[FBSimulatorControlTests_AXPMacPlatformElement_Double alloc]
    initWithLabel:label
       identifier:identifier
             role:@"AXButton"
            frame:frame
          enabled:YES
      actionNames:@[@"AXPress"]
         children:nil];
}

+ (FBSimulatorControlTests_AXPMacPlatformElement_Double *)staticTextWithLabel:(NSString *)label
                                                                        frame:(NSRect)frame
{
  return [[FBSimulatorControlTests_AXPMacPlatformElement_Double alloc]
    initWithLabel:label
       identifier:nil
             role:@"AXStaticText"
            frame:frame
          enabled:YES
      actionNames:nil
         children:nil];
}

@end

#pragma mark - AXPTranslator Swizzling

static FBSimulatorControlTests_AXPTranslator_Double *sInstalledMockTranslator = nil;
static IMP sOriginalSharedInstanceIMP = NULL;
static BOOL sSwizzleInstalled = NO;

// Replacement implementation for +[AXPTranslator sharedInstance]
static id FBMockTranslatorSharedInstance(id self, SEL _cmd) {
  return sInstalledMockTranslator;
}

@implementation FBAccessibilityTranslatorSwizzler

+ (void)installMockTranslator:(FBSimulatorControlTests_AXPTranslator_Double *)mockTranslator
{
  NSParameterAssert(mockTranslator != nil);
  NSAssert(!sSwizzleInstalled, @"Mock translator already installed. Call uninstall first.");

  sInstalledMockTranslator = mockTranslator;

  // @lint-ignore FBOBJCDISCOURAGEDFUNCTION
  Class axpTranslatorClass = objc_getClass("AXPTranslator");
  NSAssert(axpTranslatorClass != nil, @"AXPTranslator class not found. Ensure AccessibilityPlatformTranslation framework is loaded.");

  Method originalMethod = class_getClassMethod(axpTranslatorClass, @selector(sharedInstance));
  NSAssert(originalMethod != NULL, @"+[AXPTranslator sharedInstance] method not found");

  // Save original implementation
  sOriginalSharedInstanceIMP = method_getImplementation(originalMethod);

  // Replace with our mock implementation
  method_setImplementation(originalMethod, (IMP)FBMockTranslatorSharedInstance);

  sSwizzleInstalled = YES;
}

+ (void)uninstallMockTranslator
{
  if (!sSwizzleInstalled) {
    return;
  }

  // @lint-ignore FBOBJCDISCOURAGEDFUNCTION
  Class axpTranslatorClass = objc_getClass("AXPTranslator");
  Method originalMethod = class_getClassMethod(axpTranslatorClass, @selector(sharedInstance));

  // Restore original implementation
  method_setImplementation(originalMethod, sOriginalSharedInstanceIMP);

  sInstalledMockTranslator = nil;
  sOriginalSharedInstanceIMP = NULL;
  sSwizzleInstalled = NO;
}

@end

#pragma mark - FBSimulator Double

// FBiOSTargetStateBooted = 3
static const unsigned long long FBiOSTargetStateBooted_Value = 3;

@implementation FBSimulatorControlTests_FBSimulator_Double

- (instancetype)initWithDevice:(FBSimulatorControlTests_SimDevice_Accessibility_Double *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _workQueue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.tests.workqueue", DISPATCH_QUEUE_SERIAL);
  _asyncQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  _state = FBiOSTargetStateBooted_Value;

  return self;
}

- (id)accessibilityTranslationDispatcher
{
  return self.mockTranslationDispatcher;
}

@end

#pragma mark - Test Fixture

@implementation FBAccessibilityTestFixture

+ (instancetype)bootedSimulatorFixture
{
  FBAccessibilityTestFixture *fixture = [[FBAccessibilityTestFixture alloc] init];

  // Create device double
  FBSimulatorControlTests_SimDevice_Accessibility_Double *device =
    [[FBSimulatorControlTests_SimDevice_Accessibility_Double alloc] init];

  // Create simulator double wrapping device
  fixture->_simulator = [[FBSimulatorControlTests_FBSimulator_Double alloc] initWithDevice:device];
  fixture->_simulator.state = FBiOSTargetStateBooted_Value;

  // Create translator double
  fixture->_translator = [[FBSimulatorControlTests_AXPTranslator_Double alloc] init];

  return fixture;
}

- (void)setUp
{
  // Configure the translator with default results
  FBSimulatorControlTests_AXPTranslationObject_Double *translation =
    [[FBSimulatorControlTests_AXPTranslationObject_Double alloc] init];
  translation.pid = 12345;

  self.translator.frontmostApplicationResult = translation;
  self.translator.objectAtPointResult = translation;

  if (self.rootElement) {
    self.translator.macPlatformElementResult = self.rootElement;
  } else {
    // Create a default root element
    self.translator.macPlatformElementResult =
      [FBAccessibilityTestElementBuilder rootElementWithChildren:@[]];
  }

  // Install the translator swizzle
  [FBAccessibilityTranslatorSwizzler installMockTranslator:self.translator];

  // Create dispatcher using the factory method - no runtime hackery needed
  id dispatcher = [FBSimulator createAccessibilityTranslationDispatcherWithTranslator:(id)self.translator];

  // Set the dispatcher on the simulator double (for instance method injection)
  self.simulator.mockTranslationDispatcher = dispatcher;
}

- (void)tearDown
{
  // Clear the dispatcher on the simulator double
  self.simulator.mockTranslationDispatcher = nil;
  [FBAccessibilityTranslatorSwizzler uninstallMockTranslator];
}

@end
