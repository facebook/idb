/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A mock translation object that can be configured with test data.
 */
@interface FBSimulatorControlTests_AXPTranslationObject_Double : NSObject

@property (nullable, nonatomic, readwrite, copy) NSString *bridgeDelegateToken;
@property (nonatomic, readwrite, assign) pid_t pid;

@end

/**
 A mock platform element that returns configurable accessibility properties.
 Immutable - all values are set at construction time.
 Tracks property accesses for test assertions.
 */
@interface FBSimulatorControlTests_AXPMacPlatformElement_Double : NSObject

/// Designated initializer with all accessibility properties
- (instancetype)initWithLabel:(nullable NSString *)label
                   identifier:(nullable NSString *)identifier
                         role:(nullable NSString *)role
                        frame:(NSRect)frame
                      enabled:(BOOL)enabled
                  actionNames:(nullable NSArray<NSString *> *)actionNames
                     children:(nullable NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)children;

// The translation object for this element (readwrite for test infrastructure use)
@property (nonatomic, readwrite, strong) FBSimulatorControlTests_AXPTranslationObject_Double *translation;

// Property access tracking for test assertions
@property (nonatomic, readonly) NSMutableSet<NSString *> *accessedProperties;

// Accessibility properties - all readonly
@property (nullable, nonatomic, readonly, copy) NSString *accessibilityLabel;
@property (nullable, nonatomic, readonly, copy) NSString *accessibilityIdentifier;
@property (nullable, nonatomic, readonly, copy) id accessibilityValue;
@property (nullable, nonatomic, readonly, copy) NSString *accessibilityTitle;
@property (nullable, nonatomic, readonly, copy) NSString *accessibilityHelp;
@property (nullable, nonatomic, readonly, copy) NSString *accessibilityRole;
@property (nullable, nonatomic, readonly, copy) NSString *accessibilityRoleDescription;
@property (nullable, nonatomic, readonly, copy) NSString *accessibilitySubrole;
@property (nonatomic, readonly, assign) NSRect accessibilityFrame;
@property (nonatomic, readonly, assign) BOOL accessibilityEnabled;
@property (nonatomic, readonly, assign) BOOL accessibilityRequired;
@property (nullable, nonatomic, readonly, copy) NSArray<id> *accessibilityCustomActions;
@property (nullable, nonatomic, readonly, copy) NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *accessibilityChildren;
@property (nonnull, nonatomic, readonly, copy) NSArray<NSString *> *accessibilityActionNames;

@end

/**
 A mock translator that returns configured responses.
 */
@interface FBSimulatorControlTests_AXPTranslator_Double : NSObject

// Configure what frontmostApplication returns
@property (nullable, nonatomic, readwrite, strong) FBSimulatorControlTests_AXPTranslationObject_Double *frontmostApplicationResult;

// Configure what objectAtPoint returns
@property (nullable, nonatomic, readwrite, strong) FBSimulatorControlTests_AXPTranslationObject_Double *objectAtPointResult;

// Configure what macPlatformElementFromTranslation returns
@property (nullable, nonatomic, readwrite, strong) FBSimulatorControlTests_AXPMacPlatformElement_Double *macPlatformElementResult;

// The delegate that production code sets (captured for proper callback routing)
@property (nullable, nonatomic, readwrite, weak) id bridgeTokenDelegate;

// Tracking
@property (nonatomic, readonly) NSMutableArray<NSString *> *methodCalls;

- (FBSimulatorControlTests_AXPTranslationObject_Double *)frontmostApplicationWithDisplayId:(int)displayId bridgeDelegateToken:(NSString *)token;
- (FBSimulatorControlTests_AXPTranslationObject_Double *)objectAtPoint:(CGPoint)point displayId:(int)displayId bridgeDelegateToken:(NSString *)token;
- (FBSimulatorControlTests_AXPMacPlatformElement_Double *)macPlatformElementFromTranslation:(FBSimulatorControlTests_AXPTranslationObject_Double *)translation;

- (void)resetTracking;

@end

/**
 Typedef for the accessibility response handler block.
 Uses id types to avoid dependence on AXP framework types.
 */
typedef void (^FBAccessibilityResponseHandler)(id request, void (^completion)(id response));

/**
 Extension to SimDevice double for accessibility support.
 */
@interface FBSimulatorControlTests_SimDevice_Accessibility_Double : NSObject

@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSUUID *UDID;
@property (nonatomic, readwrite, assign) unsigned long long state;

// Accessibility support
@property (nullable, nonatomic, readwrite, copy) FBAccessibilityResponseHandler accessibilityResponseHandler;
@property (nonatomic, readonly) NSMutableArray<id> *accessibilityRequests;

- (void)sendAccessibilityRequestAsync:(id)request
                      completionQueue:(dispatch_queue_t)queue
                    completionHandler:(void (^)(id))handler;

- (void)resetAccessibilityTracking;

@end

/**
 Helper to create a tree of mock accessibility elements.
 */
@interface FBAccessibilityTestElementBuilder : NSObject

/// Create a generic element with specified properties
+ (FBSimulatorControlTests_AXPMacPlatformElement_Double *)elementWithLabel:(NSString *)label
                                                                     frame:(NSRect)frame
                                                                  children:(nullable NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)children;

/// Create a root application element with default iPhone-sized frame
+ (FBSimulatorControlTests_AXPMacPlatformElement_Double *)rootElementWithChildren:(NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)children;

/// Create an application element (root) with custom label, frame, and children
+ (FBSimulatorControlTests_AXPMacPlatformElement_Double *)applicationWithLabel:(NSString *)label
                                                                         frame:(NSRect)frame
                                                                      children:(NSArray<FBSimulatorControlTests_AXPMacPlatformElement_Double *> *)children;

/// Create a button element with label, identifier, and frame
+ (FBSimulatorControlTests_AXPMacPlatformElement_Double *)buttonWithLabel:(NSString *)label
                                                               identifier:(nullable NSString *)identifier
                                                                    frame:(NSRect)frame;

/// Create a static text element with label and frame
+ (FBSimulatorControlTests_AXPMacPlatformElement_Double *)staticTextWithLabel:(NSString *)label
                                                                        frame:(NSRect)frame;

@end

#pragma mark - AXPTranslator Swizzling

/**
 Manages swizzling of +[AXPTranslator sharedInstance] for testing.
 Allows tests to inject a mock translator without dependency injection.
 */
@interface FBAccessibilityTranslatorSwizzler : NSObject

/**
 Install the mock translator as the return value of +[AXPTranslator sharedInstance].
 Must be balanced with a call to uninstall.
 @param mockTranslator The translator double to return from sharedInstance.
 */
+ (void)installMockTranslator:(FBSimulatorControlTests_AXPTranslator_Double *)mockTranslator;

/**
 Remove the mock translator and restore original behavior.
 */
+ (void)uninstallMockTranslator;

@end

#pragma mark - FBSimulator Double

@protocol FBControlCoreLogger;

/**
 A test double for FBSimulator that provides the minimum interface needed
 for accessibility command testing.
 */
@interface FBSimulatorControlTests_FBSimulator_Double : NSObject

/// The mock device for XPC calls
@property (nonatomic, strong) FBSimulatorControlTests_SimDevice_Accessibility_Double *device;

/// Work queue (defaults to a serial queue)
@property (nonatomic, strong) dispatch_queue_t workQueue;

/// Async queue (defaults to global queue)
@property (nonatomic, strong) dispatch_queue_t asyncQueue;

/// Simulated state (defaults to FBiOSTargetStateBooted)
@property (nonatomic, assign) unsigned long long state;

/// Logger for debugging (optional)
@property (nullable, nonatomic, strong) id<FBControlCoreLogger> logger;

/// Mock translation dispatcher for accessibility operations (set by test fixture)
@property (nullable, nonatomic, strong) id mockTranslationDispatcher;

/// Designated initializer
- (instancetype)initWithDevice:(FBSimulatorControlTests_SimDevice_Accessibility_Double *)device;

@end

#pragma mark - Test Fixture

/**
 Builds complete test fixtures with pre-configured mocks.
 Simplifies test setup for accessibility command testing.
 */
@interface FBAccessibilityTestFixture : NSObject

/// The mock translator (uses existing FBSimulatorControlTests_AXPTranslator_Double)
@property (nonatomic, readonly, strong) FBSimulatorControlTests_AXPTranslator_Double *translator;

/// The mock simulator
@property (nonatomic, readonly, strong) FBSimulatorControlTests_FBSimulator_Double *simulator;

/// The root element tree for serialization (configure before setUp)
@property (nullable, nonatomic, strong) FBSimulatorControlTests_AXPMacPlatformElement_Double *rootElement;

/// Create fixture with default booted simulator
+ (instancetype)bootedSimulatorFixture;

/// Install mocks and prepare for testing
- (void)setUp;

/// Uninstall mocks and clean up
- (void)tearDown;

@end

NS_ASSUME_NONNULL_END
