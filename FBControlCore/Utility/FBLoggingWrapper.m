/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBLoggingWrapper.h"

@interface FBLoggingWrapper ()

@property (nonatomic, strong, readonly) id wrappedObject;
@property (nonatomic, strong, readonly) id<FBEventReporter> eventReporter;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, assign, readonly) BOOL simplifiedNaming;

@end

@implementation FBLoggingWrapper

#pragma mark Initializers

+ (instancetype)wrap:(id)wrappedObject simplifiedNaming:(BOOL)simplifiedNaming eventReporter:(nullable id<FBEventReporter>)eventReporter logger:(nullable id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithWrappedObject:wrappedObject simplifiedNaming:simplifiedNaming eventReporter:eventReporter logger:logger];
}

- (instancetype)initWithWrappedObject:(id)wrappedObject simplifiedNaming:(BOOL)simplifiedNaming eventReporter:(nullable id<FBEventReporter>)eventReporter logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _wrappedObject = wrappedObject;
  _simplifiedNaming = simplifiedNaming;
  _queue = dispatch_queue_create("com.facebook.fbcontrolcore.logging_wrapper", DISPATCH_QUEUE_SERIAL);
  _eventReporter = eventReporter;
  _logger = logger;

  return self;
}

#pragma mark Forwarding

- (BOOL)respondsToSelector:(SEL)selector
{
  return [super respondsToSelector:selector] || [self.wrappedObject respondsToSelector:selector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
  return [super methodSignatureForSelector:selector] ?: [self.wrappedObject methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
  if ([self.wrappedObject respondsToSelector:invocation.selector]) {
    [self runInvocation:invocation];
  } else {
    [super forwardInvocation:invocation];
  }
}

- (void)runInvocation:(NSInvocation *)invocation
{
  // Extract information about the start of the call.
  NSDate *startDate = NSDate.date;
  NSString *methodName = [self.class methodName:invocation simplifiedNaming:self.simplifiedNaming];
  NSArray<NSString *> *descriptionOfArguments = [self.class descriptionOfArguments:invocation];
  FBEventReporterSubject *beforeSubject = [self.class subjectForBeforeInvocation:methodName descriptionOfArguments:descriptionOfArguments logger:self.logger];
  [self.eventReporter report:beforeSubject];

  // Extract the first method argument and retain it, if it exists
  id firstMethodArgument = nil;
  if (invocation.methodSignature.numberOfArguments > 2 && strcmp([invocation.methodSignature getArgumentTypeAtIndex:2], "@") == 0) {
      __unsafe_unretained id argument = nil;
    [invocation getArgument:&argument atIndex:2];
    firstMethodArgument = argument;
  }

  // Invoke on the Future Handler on the appropriate queue.
  [invocation invokeWithTarget:self.wrappedObject];
  void *returnValue = NULL;
  [invocation getReturnValue:&returnValue];
  FBFuture *future = (__bridge FBFuture *)(returnValue);

  // Log the end of the call when the future resolves.
  if ([future isKindOfClass:FBFuture.class]) {
    [future onQueue:self.queue notifyOfCompletion:^(FBFuture *completedFuture) {
      FBEventReporterSubject *afterSubject = [self.class subjectAfterCompletion:completedFuture methodName:methodName descriptionOfArguments:descriptionOfArguments startDate:startDate firstMethodArgument:firstMethodArgument logger:self.logger];
      [self.eventReporter report:afterSubject];
    }];
  }
}

#pragma mark - Subjects

+ (FBEventReporterSubject *)subjectForBeforeInvocation:(NSString *)methodName descriptionOfArguments:(NSArray<NSString *> *)descriptionOfArguments logger:(id<FBControlCoreLogger>)logger
{
  [logger.info logFormat:@"%@ called with: %@", methodName, [FBCollectionInformation oneLineDescriptionFromArray:descriptionOfArguments]];
  return [FBEventReporterSubject subjectForStartedCall:methodName arguments:descriptionOfArguments reportNativeSwiftMethodCall: NO];
}

+ (FBEventReporterSubject *)subjectAfterCompletion:(FBFuture *)future methodName:(NSString *)methodName descriptionOfArguments:(NSArray<NSString *> *)descriptionOfArguments startDate:(NSDate *)startDate firstMethodArgument:(id)firstMethodArgument logger:(id<FBControlCoreLogger>)logger
{
  NSTimeInterval duration = [NSDate.date timeIntervalSinceDate:startDate];
  NSError *error = future.error;
  NSNumber *size = nil;
  if ([firstMethodArgument respondsToSelector:@selector(bytesTransferred)]) {
    size = @([firstMethodArgument bytesTransferred]);
  }
  if (error) {
    NSString *message = error.localizedDescription;
    [logger.debug logFormat:@"%@ failed with: %@", methodName, message];
    return [FBEventReporterSubject subjectForFailingCall:methodName duration:duration message:message size:size arguments:descriptionOfArguments reportNativeSwiftMethodCall: NO];
  } else {
    [logger.debug logFormat:@"%@ succeeded", methodName];
    return [FBEventReporterSubject subjectForSuccessfulCall:methodName duration:duration size:size arguments:descriptionOfArguments reportNativeSwiftMethodCall: NO];
  }
}

#pragma mark - NSInvocation inspection

+ (NSString *)methodName:(NSInvocation *)invocation simplifiedNaming:(BOOL)simplifiedNaming
{
  // This will log the first argument in the method name, so method names should be unique relative to the first component within the selector
  if (simplifiedNaming) {
    return [NSStringFromSelector(invocation.selector) componentsSeparatedByString:@":"][0];
  }
  // Otherwise log the entire selector
  return NSStringFromSelector(invocation.selector);
}

+ (NSArray<NSString *> *)descriptionOfArguments:(NSInvocation *)invocation
{
  NSMutableArray<NSString *> *descriptions = NSMutableArray.array;
  for (int index = 2; index < (int) invocation.methodSignature.numberOfArguments; index++) {
    NSString *description = [self descriptionForAgumentAtIndex:index inInvoation:invocation];
    if (description.length > 100) {
      description = [NSString stringWithFormat:@"%@...", [description substringToIndex:100]];
    }
    [descriptions addObject:description];
  }
  return descriptions;
}

+ (NSString *)descriptionForAgumentAtIndex:(int)index inInvoation:(NSInvocation *)invocation
{
  const char *typeString = [invocation.methodSignature getArgumentTypeAtIndex:(NSUInteger)index];
  if (typeString == NULL) {
    return @"NULL Argument Type";
  }
  if (strlen(typeString) != 1) {
    return @"Unknown Multichar Type";
  }
  const char typeChar = *typeString;
  switch (typeChar) {
      case 'c': {
          char argument = 0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%c", argument];
      }
      case 'i': {
          int argument = 0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%d", argument];
      }
      case 's': {
          short argument = 0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%d", argument];
      }
      case 'l': {
          long argument = 0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%ld", argument];
      }
      case 'q': {
          long long argument = 0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%lld", argument];
      }
      case 'C': {
          unsigned char argument = 0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%c", argument];
      }
      case 'I': {
          unsigned int argument = 0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%d", argument];
      }
      case 'S': {
          unsigned short argument = 0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%d", argument];
      }
      case 'L': {
          unsigned long argument = 0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%ld", argument];
      }
      case 'Q': {
          unsigned long long argument = 0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%lld", argument];
      }
      case 'f': {
          float argument = 0.0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%f", argument];
      }
      case 'd': {
          double argument = 0.0;
          [invocation getArgument:&argument atIndex:index];
          return [NSString stringWithFormat:@"%f", argument];
      }
      case 'v':
          return @"void";
      case 'B': {
          BOOL argument = 0;
          [invocation getArgument:&argument atIndex:index];
          return argument ? @"YES" : @"NO";
      }
      case '@': {
          __unsafe_unretained id argument = nil;
          [invocation getArgument:&argument atIndex:index];
          return [self descriptionForObject:argument];
      }
      default:
          // Handle unknown type
          return @"Unrecognised type";
  }
}

+ (NSString *)descriptionForObject:(NSObject *)object
{
  if ([object isKindOfClass:NSString.class]) {
    return [(NSString *)object description];
  }
  if ([object isKindOfClass:NSData.class]) {
    NSData *data = (NSData *)object;
    return [NSString stringWithFormat:@"NSData of length %lu", (unsigned long)data.length];
  }
  if (object == nil || [object isKindOfClass:NSNull.class]) {
    return @"null";
  }
  if ([object isKindOfClass:NSArray.class]) {
    return [self implodeDescription:(NSSet<id> *)object prefix:@"NSArray"];
  }
  if ([object isKindOfClass:NSSet.class]) {
    return [self implodeDescription:(NSSet<id> *)object prefix:@"NSSet"];
  }
  if ([object isKindOfClass:NSDictionary.class]) {
    NSDictionary<id, id> *dict = (NSDictionary<id, id> *)object;
    NSMutableString *description = NSMutableString.string;
    [description appendString:@"NSDictionary{"];
    for (NSObject *key in dict) {
      [description appendFormat:@"%@: %@", [self descriptionForObject:key], [self descriptionForObject:dict[key]]];
      [description appendString:@", "];
    }
    [description appendString:@"}"];
    return description;
  }
  return object.description;
}

+ (NSString *)implodeDescription:(id<NSFastEnumeration>)container prefix:(NSString *)prefix
{
  NSMutableArray<NSString *> *descriptions = NSMutableArray.array;
  for (id inner in container) {
    [descriptions addObject:[self descriptionForObject:inner]];
  }
  return [NSString stringWithFormat:@"%@[%@]", prefix, [descriptions componentsJoinedByString:@", "]];
}

@end
