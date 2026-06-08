/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// @lint-ignore-every UNCRUSTIFY
#import "FBSimulatorAccessibilityCommands.h"

#import <objc/runtime.h>
#import <stdatomic.h>

#import <CoreSimulator/SimDevice.h>
#import <AccessibilityPlatformTranslation/AXPMacPlatformElement.h>
#import <AccessibilityPlatformTranslation/AXPTranslationObject.h>
#import <AccessibilityPlatformTranslation/AXPTranslator.h>
#import <AccessibilityPlatformTranslation/AXPTranslatorRequest.h>
#import <AccessibilityPlatformTranslation/AXPTranslatorResponse.h>
#import <FBControlCore/FBAccessibilityTraits.h>
#import <FBControlCore/FBControlCore-Swift.h>

#import "FBSimulator.h"
#import "FBSimulatorControl-Swift.h"
#import "FBSimulatorControlFrameworkLoader.h"

// FBAccessibilityProfilingCollector is now implemented in Swift
// (FBAccessibilityProfilingCollector.swift), visible here via FBSimulatorControl-Swift.h.

//
// # About the implementation of Accessibility within CoreSimulator
//
// Accessibility is bridged via CoreSimulator and the Private Framework AccessibilityPlatformTranslation.
// In Simulator.app, SimulatorKit uses NSView semantics for obtaining information about a Simulator; in FBSimulatorControl we aren't necessarily view-backed.
// As a result we are using a reverse-engineered implementation of how SimulatorKit functions, based on inputs to this API.
//
// For this to work the process is as follows:
// - The AXPTranslator is used to do all of the wiring for providing high-level objects that can be interrogated.
// - To do this AXPTranslator uses delegation for performing the underlying accessibility request.
// - The delegation can be tokenized (optionally)
// - The requests are implemented by bridging to CoreSimulator. This is essentially the glue between high-level Accessibility APIs and CoreSimulator's implementation of them.
// - CoreSimulator doesn't actually implement the Accessibility fetches itself. Instead it calls out to an XPC service that is running inside the Simulator.
// - CoreSimulator's API for doing this fetch is Asynchronous, but AXPTranslator's delegation & fetching is not. To smooth over the gaps we have to wait on the result.
// - The reason for non-async APIs here is that AXMacPlatformElement has lazy property access; over time each of the values that are referenced will be filled out with this delegation.
// - The lazy property access can be seen in the logging here, where the AXPTranslatorRequest has a nice description of the object.
// - Additional methods are required in the delegation, depending on whether there needs to be additional transformation, as is in the case with translating co-ordinate systems.
// - We smooth over the differences in the values returned by calling the appropriate methods on AXMacPlatformElement.
// - To get an idea of what methods are usable, take a look at NSAccessibilityElement which is a supertype of AXMacPlatformElement.
// - The tokenized method appears to be the more recent one. The token isn't significant for us so in this case we can just pass a meaningless token that will be received from all delegate callbacks.
//
// All of the above could be implemented without the delegation system. However, this requires dumping large enums and going much lower in the protocol level.
// Instead having the higher level object, liberated from SimulatorKit (and therefore views) is the best compromise and the lightest touch.
//
// The only exception here is the usage of -[NSAccessibility accessibilityParent] which calls a delegate method with an unknown implementation.
// Since all values are enumerated recursively downwards, this is fine for the time being.
//
// We must also remember to set the `bridgeDelegateToken` on all created `AXPTranslationObject`s.
// This applies to those created by us when the `AXPTranslationObject` as well`AXPMacPlatformElement`'s that are created inside `AccessibilityPlatformTranslation`
// This is needed so that we know which Simulator the request belongs to, since the Translator is a singleton object, we need to be able to de-duplicate here.
//

// The following are now implemented in Swift, visible here via
// FBSimulatorControl-Swift.h:
//   - FBAccessibilityCoverageGrid (FBAccessibilityCoverageGrid.swift)
//   - FBSimulatorAccessibilitySerializer (FBSimulatorAccessibilitySerializer.swift)
//   - the FBAccessibilityElementsResponse response-builder logic and the
//     FBAXTranslationRequest hierarchy (FBAXTranslationRequest.swift)
//   - FBAXTranslationDispatcher (FBAXTranslationDispatcher.swift)

@interface FBAccessibilityElement ()
- (instancetype)initWithElement:(AXPMacPlatformElement *)element
                        request:(FBAXTranslationRequest *)request
                     dispatcher:(FBAXTranslationDispatcher *)dispatcher
                      simulator:(FBSimulator *)simulator;
@end


#pragma mark - FBSimulator Instance Method for Translation Dispatcher

@implementation FBSimulator (FBAccessibilityDispatcher)

+ (id)createAccessibilityTranslationDispatcherWithTranslator:(id)translator
{
  FBAXTranslationDispatcher *dispatcher =
  [[FBAXTranslationDispatcher alloc] initWithTranslator:translator logger:nil];
  ((AXPTranslator *)translator).bridgeTokenDelegate = dispatcher;
  return dispatcher;
}

- (id)accessibilityTranslationDispatcher
{
  static dispatch_once_t onceToken;
  static FBAXTranslationDispatcher *dispatcher;
  dispatch_once(&onceToken, ^{
    AXPTranslator *translator = [objc_getClass("AXPTranslator") sharedInstance];
    dispatcher = [FBSimulator createAccessibilityTranslationDispatcherWithTranslator:translator];
  });
  return dispatcher;
}

@end

#pragma mark - FBAccessibilityElement

@interface FBAccessibilityElement ()
@property (nonatomic, readonly, strong) AXPMacPlatformElement *element;
@property (nonatomic, readonly, strong) FBAXTranslationRequest *request;
@property (nonatomic, readonly, strong) FBAXTranslationDispatcher *dispatcher;
@property (nonatomic, readonly, weak) FBSimulator *simulator;
@property (nonatomic, assign) BOOL closed;
@end

@implementation FBAccessibilityElement

- (instancetype)initWithElement:(AXPMacPlatformElement *)element
                        request:(FBAXTranslationRequest *)request
                     dispatcher:(FBAXTranslationDispatcher *)dispatcher
                      simulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _element = element;
  _request = request;
  _dispatcher = dispatcher;
  _simulator = simulator;
  _closed = NO;
  return self;
}

+ (nullable NSString *)stringValueForKey:(FBAXSearchableKey)key fromElement:(AXPMacPlatformElement *)element
{
  if ([key isEqualToString:FBAXKeysLabel]) {
    return element.accessibilityLabel;
  } else if ([key isEqualToString:FBAXKeysUniqueID]) {
    return element.accessibilityIdentifier;
  } else if ([key isEqualToString:FBAXKeysValue]) {
    id value = element.accessibilityValue;
    return [value isKindOfClass:NSString.class] ? value : nil;
  } else if ([key isEqualToString:FBAXKeysTitle]) {
    return element.accessibilityTitle;
  } else if ([key isEqualToString:FBAXKeysRole]) {
    return element.accessibilityRole;
  } else if ([key isEqualToString:FBAXKeysRoleDescription]) {
    return element.accessibilityRoleDescription;
  } else if ([key isEqualToString:FBAXKeysSubrole]) {
    return element.accessibilitySubrole;
  } else if ([key isEqualToString:FBAXKeysHelp]) {
    return element.accessibilityHelp;
  } else if ([key isEqualToString:FBAXKeysPlaceholder]) {
    return element.accessibilityPlaceholderValue;
  }
  return nil;
}

+ (nullable AXPMacPlatformElement *)findElementWithValue:(NSString *)value
                                                  forKey:(FBAXSearchableKey)key
                                               inElement:(AXPMacPlatformElement *)element
                                                   token:(NSString *)token
                                          remainingDepth:(NSUInteger)remainingDepth
{
  element.translation.bridgeDelegateToken = token;
  NSString *propertyValue = [self stringValueForKey:key fromElement:element];
  if (propertyValue != nil && [propertyValue containsString:value]) {
    return element;
  }
  if (remainingDepth == 0) {
    return nil;
  }
  for (AXPMacPlatformElement *child in element.accessibilityChildren) {
    child.translation.bridgeDelegateToken = token;
    AXPMacPlatformElement *found = [self findElementWithValue:value forKey:key inElement:child token:token remainingDepth:remainingDepth - 1];
    if (found != nil) {
      return found;
    }
  }
  return nil;
}

// Searches the accessibility tree rooted at this element for a descendant matching the given value/key.
// If found, ownership of the request token is transferred to a new handle wrapping the found element,
// and the receiver is closed without popping. If not found, the receiver is closed and an error is set.
- (nullable FBAccessibilityElement *)findElementWithValue:(NSString *)value
                                                   forKey:(FBAXSearchableKey)key
                                                    depth:(NSUInteger)depth
                                                    error:(NSError **)error
{
  AXPMacPlatformElement *found = [FBAccessibilityElement
                                  findElementWithValue:value
                                  forKey:key
                                  inElement:_element
                                  token:_request.token
                                  remainingDepth:depth];
  if (found == nil) {
    [self close];
    return [[FBSimulatorError
             describe:[NSString stringWithFormat:@"Element with %@ containing '%@' not found within depth %lu",
             key, value, (unsigned long)depth]]
            fail:error];
  }
  NSAssert(!_closed, @"Cannot transfer ownership from a closed element");
  FBAccessibilityElement *newHandle = [[FBAccessibilityElement alloc]
                                       initWithElement:found
                                       request:_request
                                       dispatcher:_dispatcher
                                       simulator:_simulator];
  _closed = YES;
  return newHandle;
}

- (void)close
{
  if (!_closed) {
    _closed = YES;
    [_dispatcher popRequest:_request];
  }
}

- (void)dealloc
{
  [self close];
}

- (nullable FBAccessibilityElementsResponse *)serializeWithOptions:(FBAccessibilityRequestOptions *)options
                                                             error:(NSError **)error
{
  if (_closed) {
    return [[FBSimulatorError describe:@"Cannot serialize a closed element"] fail:error];
  }
  FBAXTranslationRequest *request = self.request;
  if (options.enableProfiling && !request.collector) {
    request.collector = [[FBAccessibilityProfilingCollector alloc] init];
  }
  return [request run:self.element options:options error:error];
}

- (nullable NSString *)stringValueForSearchableKey:(FBAXSearchableKey)key error:(NSError **)error
{
  if (_closed) {
    return [[FBSimulatorError describe:@"Cannot read from a closed element"] fail:error];
  }
  return [FBAccessibilityElement stringValueForKey:key fromElement:self.element];
}

- (BOOL)tapWithError:(NSError **)error
{
  if (_closed) {
    return [[FBSimulatorError describe:@"Cannot tap a closed element"] failBool:error];
  }
  AXPMacPlatformElement *element = self.element;

  NSArray<NSString *> *actionNames = element.accessibilityActionNames;
  if (![actionNames containsObject:@"AXPress"]) {
    return [[FBSimulatorError
             describe:[NSString stringWithFormat:@"Element does not support pressing. Supported: %@",
             [FBCollectionInformation oneLineDescriptionFromArray:actionNames]]]
            failBool:error];
  }

  if (![element accessibilityPerformPress]) {
    return [[FBSimulatorError
             describe:@"accessibilityPerformPress did not succeed"]
            failBool:error];
  }

  return YES;
}

- (BOOL)scrollWithDirection:(FBAccessibilityScrollDirection)direction error:(NSError **)error
{
  if (_closed) {
    return [[FBSimulatorError describe:@"Cannot scroll a closed element"] failBool:error];
  }
  AXPMacPlatformElement *element = self.element;
  switch (direction) {
    case FBAccessibilityScrollDirectionDown:
      [element performScrollDownByPageAction];
      return YES;
    case FBAccessibilityScrollDirectionUp:
      [element performScrollUpByPageAction];
      return YES;
    case FBAccessibilityScrollDirectionLeft:
      [element performScrollLeftByPageAction];
      return YES;
    case FBAccessibilityScrollDirectionRight:
      [element performScrollRightByPageAction];
      return YES;
    case FBAccessibilityScrollDirectionToVisible:
      [element performScrollToVisible];
      return YES;
    default:
      return [[FBSimulatorError
               describe:[NSString stringWithFormat:@"Unknown scroll direction %lu", (unsigned long)direction]]
              failBool:error];
  }
}

- (BOOL)setValue:(id)value error:(NSError **)error
{
  if (_closed) {
    return [[FBSimulatorError describe:@"Cannot set value on a closed element"] failBool:error];
  }
  AXPMacPlatformElement *element = self.element;
  [element setAccessibilityValue:value];
  return YES;
}

@end

static NSString *const CoreSimulatorBridgeServiceName = @"com.apple.CoreSimulator.bridge";

@interface FBSimulatorAccessibilityCommands ()

@property (nonatomic, readonly, weak) FBSimulator *simulator;

@end

@implementation FBSimulatorAccessibilityCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)targets
{
  return [[self alloc] initWithSimulator:targets];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark FBSimulatorAccessibilityCommands Protocol Implementation

- (FBFuture<FBAccessibilityElement *> *)accessibilityElementAtPoint:(CGPoint)point
{
  NSError *error = nil;
  if (![self validateAccessibilityWithError:&error]) {
    return [FBFuture futureWithError:error];
  }
  FBAXTranslationRequest *request = [[FBAXTranslationRequest_Point alloc] initWithPoint:point];
  return [self accessibilityElementWithRequest:request remediationPermitted:NO];
}

- (FBFuture<FBAccessibilityElement *> *)accessibilityElementForFrontmostApplication
{
  NSError *error = nil;
  if (![self validateAccessibilityWithError:&error]) {
    return [FBFuture futureWithError:error];
  }
  FBAXTranslationRequest *request = [[FBAXTranslationRequest_FrontmostApplication alloc] init];
  return [self accessibilityElementWithRequest:request remediationPermitted:YES];
}

- (FBFuture<FBAccessibilityElement *> *)accessibilityElementMatchingValue:(NSString *)value
                                                                   forKey:(FBAXSearchableKey)key
                                                                    depth:(NSUInteger)depth
{
  NSError *error = nil;
  if (![self validateAccessibilityWithError:&error]) {
    return [FBFuture futureWithError:error];
  }
  FBAXTranslationRequest *request = [[FBAXTranslationRequest_FrontmostApplication alloc] init];
  return [[self accessibilityElementWithRequest:request remediationPermitted:YES]
          onQueue:dispatch_get_main_queue()
          fmap:^FBFuture *(FBAccessibilityElement *rootElement) {
            NSError *innerError = nil;
            FBAccessibilityElement *found = [rootElement findElementWithValue:value forKey:key depth:depth error:&innerError];
            if (found == nil) {
              return [FBFuture futureWithError:innerError];
            }
            return [FBFuture futureWithResult:found];
          }];
}

#pragma mark Translation Dispatcher Hook

- (id)translationDispatcher
{
  return self.simulator.accessibilityTranslationDispatcher;
}

#pragma mark Private

// Uses the CoreSimulator accessibility API via -[SimDevice sendAccessibilityRequestAsync:completionQueue:completionHandler:]
// This API requires Xcode 12+ to have been installed on the host at some point.
- (BOOL)validateAccessibilityWithError:(NSError **)error
{
  FBSimulator *simulator = self.simulator;
  if (simulator.state != FBiOSTargetStateBooted) {
    return [[FBControlCoreError
             describe:[NSString stringWithFormat:@"Cannot run accessibility commands against %@ as it is not booted", simulator]]
            failBool:error];
  }
  SimDevice *device = simulator.device;
  if (![device respondsToSelector:@selector(sendAccessibilityRequestAsync:completionQueue:completionHandler:)]) {
    return [[FBControlCoreError
             describe:[NSString stringWithFormat:@"-[SimDevice %@] is not present on this host, you must install and/or use Xcode 12 to use accessibility.", NSStringFromSelector(@selector(sendAccessibilityRequestAsync:completionQueue:completionHandler:))]]
            failBool:error];
  }
  if (![FBSimulatorControlFrameworkLoader.accessibilityFrameworks loadPrivateFrameworks:simulator.logger error:error]) {
    return NO;
  }
  return YES;
}

// Returns an FBAccessibilityElement wrapping the platform element for the given request.
// The handle owns the request's token and will pop it on close.
//
// When remediationPermitted=YES and a stale SpringBoard is detected (zero accessibility frame + dead pid),
// the original request's token is manually popped (it's not wrapped in a handle yet at that point),
// CoreSimulatorBridge is restarted, and the method recurses with a fresh request.
// The recursion is bounded: the retry passes remediationPermitted=NO, so at most one remediation attempt occurs.
- (FBFuture<FBAccessibilityElement *> *)accessibilityElementWithRequest:(FBAXTranslationRequest *)request
                                                   remediationPermitted:(BOOL)remediationPermitted
{
  FBSimulator *simulator = self.simulator;
  FBAXTranslationDispatcher *dispatcher = (FBAXTranslationDispatcher *)self.translationDispatcher;
  return [[dispatcher platformElementWithRequest:request simulator:simulator]
          onQueue:simulator.workQueue
          fmap:^FBFuture<FBAccessibilityElement *> *(AXPMacPlatformElement *element) {
            if (!remediationPermitted) {
              return [FBFuture futureWithResult:[[FBAccessibilityElement alloc]
                                                 initWithElement:element
                                                 request:request
                                                 dispatcher:dispatcher
                                                 simulator:simulator]];
            }
            return [[FBSimulatorAccessibilityCommands
                     remediationRequiredForSimulator:simulator
                     element:element]
                    onQueue:simulator.workQueue
                    fmap:^FBFuture<FBAccessibilityElement *> *(NSNumber *remediationRequired) {
                      if (!remediationRequired.boolValue) {
                        return [FBFuture futureWithResult:[[FBAccessibilityElement alloc]
                                                           initWithElement:element
                                                           request:request
                                                           dispatcher:dispatcher
                                                           simulator:simulator]];
                      }
                      // The request's token was pushed by the dispatcher but is not yet wrapped in an
                      // FBAccessibilityElement, so we must pop it manually before discarding the request.
                      [dispatcher popRequest:request];
                      FBAXTranslationRequest *nextRequest = [request cloneWithNewToken];
                      return [[FBSimulatorAccessibilityCommands remediateSpringBoardForSimulator:simulator]
                              onQueue:simulator.workQueue
                              fmap:^FBFuture<FBAccessibilityElement *> *(id _) {
                                // remediationPermitted:NO ensures at most one retry and avoids infinite recursion.
                                return [self accessibilityElementWithRequest:nextRequest remediationPermitted:NO];
                              }];
                    }];
          }];
}

+ (FBFuture<NSNumber *> *)remediationRequiredForSimulator:(FBSimulator *)simulator element:(AXPMacPlatformElement *)element
{
  // First perform a quick check, if the accessibility frame is zero, then this is indicative of the problem
  if (CGRectEqualToRect(element.accessibilityFrame, CGRectZero) == NO) {
    return [FBFuture futureWithResult:@NO];
  }
  // Then confirm whether the pid of the translation object represents a real pid within the simulator.
  // If it does not, then it likely means that we got the pid of the crashed SpringBoard.
  // A crashed SpringBoard, means that there is a new one running (or else the Simulator is completely hosed).
  // In this case, the remediation is to restart CoreSimulatorBridge, since the CoreSimulatorBridge needs restarting upon a crash.
  // In all likelihood CoreSimulatorBridge contains a constant reference to the pid of SpringBoard and the most effective way of resolving this is to stop it.
  // The Simulator's launchctl will then make sure that the SimulatorBridge is restarted (just like it does for SpringBoard itself).
  pid_t processIdentifier = element.translation.pid;
  return [[[simulator
            serviceNameForProcessIdentifier:processIdentifier]
           mapReplace:@NO]
          onQueue:simulator.workQueue
          handleError:^(NSError *error) {
            [simulator.logger log:[NSString stringWithFormat:@"pid %d does not exist, this likely means that SpringBoard has restarted, %@ should be restarted", processIdentifier, CoreSimulatorBridgeServiceName]];
            return [FBFuture futureWithResult:@YES];
          }];
}

+ (FBFuture<NSNull *> *)remediateSpringBoardForSimulator:(FBSimulator *)simulator
{
  return [[[simulator
            stopServiceWithName:CoreSimulatorBridgeServiceName]
           mapReplace:NSNull.null]
          rephraseFailure:[NSString stringWithFormat:@"Could not restart %@ bridge when attempting to remediate SpringBoard Crash", CoreSimulatorBridgeServiceName]];
}

@end
