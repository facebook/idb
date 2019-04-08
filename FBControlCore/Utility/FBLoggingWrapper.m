/**
 * Copyright (c) Facebook, Inc. and its affiliates.
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

@end

@implementation FBLoggingWrapper

#pragma mark Initializers

+ (instancetype)wrap:(id)wrappedObject eventReporter:(nullable id<FBEventReporter>)eventReporter logger:(nullable id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithWrappedObject:wrappedObject eventReporter:eventReporter logger:logger];
}

- (instancetype)initWithWrappedObject:(id)wrappedObject eventReporter:(nullable id<FBEventReporter>)eventReporter logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _wrappedObject = wrappedObject;
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
  NSDate *startDate = NSDate.date;
  NSString *methodName = [self.class methodName:invocation];
  NSArray<NSString *> *descriptionOfArguments = [self.class descriptionOfArguments:invocation];
  id<FBEventReporterSubject> beforeSubject = [self.class subjectForBeforeInvocation:methodName descriptionOfArguments:descriptionOfArguments logger:self.logger];
  // Invoke on the Future Handler on the appropriate queue.
  [invocation invokeWithTarget:self.wrappedObject];
  void *returnValue = NULL;
  [invocation getReturnValue:&returnValue];
  FBFuture *future = (__bridge FBFuture *)(returnValue);

  if ([future isKindOfClass:FBFuture.class]) {
    [future onQueue:self.queue notifyOfCompletion:^(FBFuture *completedFuture) {
      [self.eventReporter report:beforeSubject];
      id<FBEventReporterSubject> afterSubject = [self.class subjectAfterCompletion:completedFuture methodName:methodName descriptionOfArguments:descriptionOfArguments startDate:startDate logger:self.logger];
      [self.eventReporter report:afterSubject];
    }];
  }
}

#pragma mark - Subjects

+ (id<FBEventReporterSubject>)subjectForBeforeInvocation:(NSString *)methodName descriptionOfArguments:(NSArray<NSString *> *)descriptionOfArguments logger:(id<FBControlCoreLogger>)logger
{
  [logger.info logFormat:@"%@ called with: %@", methodName, descriptionOfArguments];
  return [FBEventReporterSubject subjectForStartedCall:methodName arguments:descriptionOfArguments];
}

+ (id<FBEventReporterSubject>)subjectAfterCompletion:(FBFuture *)future methodName:(NSString *)methodName descriptionOfArguments:(NSArray<NSString *> *)descriptionOfArguments startDate:(NSDate *)startDate logger:(id<FBControlCoreLogger>)logger
{
  NSTimeInterval duration = [NSDate.date timeIntervalSinceDate:startDate];
  if (future.error) {
    [logger.debug logFormat:@"%@ failed with: %@", methodName, future.error];
    return [FBEventReporterSubject subjectForFailingCall:methodName duration:duration message:future.error.description arguments:descriptionOfArguments];
  } else {
    [logger.debug logFormat:@"%@ succeeded", methodName];
    return [FBEventReporterSubject subjectForSuccessfulCall:methodName duration:duration arguments:descriptionOfArguments];
  }
}

#pragma mark - NSInvocation inspection

+ (NSString *)methodName:(NSInvocation *)invocation
{
  return [NSStringFromSelector(invocation.selector) stringByReplacingOccurrencesOfString:@":" withString:@""];
}

+ (NSArray<NSString *> *)descriptionOfArguments:(NSInvocation *)invocation
{
  NSMutableArray<NSString *> *descriptions = NSMutableArray.array;
  for (int index = 2; index < (int) invocation.methodSignature.numberOfArguments; index++) {
    NSString *description = [self descriptionForAgumentAtIndex:index inInvoation:invocation];
    if (description.length > 100) {
      description = [NSString stringWithFormat:@"%@...", [description substringToIndex:100]];
    }
    [descriptions addObject:[self descriptionForAgumentAtIndex:index inInvoation:invocation]];
  }
  return descriptions;
}

+ (NSString *)descriptionForAgumentAtIndex:(int)index inInvoation:(NSInvocation *)invocation
{
  NSString *type = [NSString stringWithUTF8String:[invocation.methodSignature getArgumentTypeAtIndex:(NSUInteger)index]];
  if ([type isEqualToString:@"c"]) {
    char argument = 0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%c", argument];
  }
  if ([type isEqualToString:@"i"]) {
    int argument = 0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%d", argument];
  }
  if ([type isEqualToString:@"s"]) {
    short argument = 0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%d", argument];
  }
  if ([type isEqualToString:@"l"]) {
    long argument = 0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%ld", argument];
  }
  if ([type isEqualToString:@"q"]) {
    long long argument = 0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%lld", argument];
  }
  if ([type isEqualToString:@"C"]) {
    unsigned char argument = 0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%c", argument];
  }
  if ([type isEqualToString:@"I"]) {
    unsigned int argument = 0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%d", argument];
  }
  if ([type isEqualToString:@"S"]) {
    unsigned short argument = 0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%d", argument];
  }
  if ([type isEqualToString:@"L"]) {
    unsigned long argument = 0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%ld", argument];
  }
  if ([type isEqualToString:@"Q"]) {
    unsigned long long argument = 0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%lld", argument];
  }
  if ([type isEqualToString:@"f"]) {
    float argument = 0.0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%f", argument];
  }
  if ([type isEqualToString:@"d"]) {
    double argument = 0.0;
    [invocation getArgument:&argument atIndex:index];
    return [NSString stringWithFormat:@"%f", argument];
  }
  if ([type isEqualToString:@"v"]) {
    return @"void";
  }
  if ([type isEqualToString:@"@"]) {
    __unsafe_unretained id argument = nil;
    [invocation getArgument:&argument atIndex:index];
    return [self descriptionForObject:argument];
  }
  return @"Unrecognised type";
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
    NSMutableString *description = NSMutableString.string;
    [description appendString:@"NSArray["];
    for (NSObject *inner in (NSArray<id> *)object) {
      [description appendString:[self descriptionForObject:inner]];
      [description appendString:@", "];
    }
    [description appendString:@"]"];
    return description;
  }
  if ([object isKindOfClass:NSSet.class]) {
    NSMutableString *description = NSMutableString.string;
    [description appendString:@"NSSet["];
    for (NSObject *inner in (NSSet<id> *)object) {
      [description appendString:[self descriptionForObject:inner]];
      [description appendString:@", "];
    }
    [description appendString:@"]"];
    return description;
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

@end
