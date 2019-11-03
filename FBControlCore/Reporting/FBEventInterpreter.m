/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBEventInterpreter.h"

#import "FBCollectionInformation.h"
#import "FBEventReporterSubject.h"
#import "FBEventConstants.h"

@interface FBJSONEventInterpreter : FBEventInterpreter

@property (nonatomic, assign, readonly) BOOL pretty;

- (instancetype)initWithPrettyFormatting:(BOOL)pretty;

@end

@interface FBHumanReadableEventInterpreter : FBEventInterpreter

@end

@implementation FBEventInterpreter

#pragma mark Initializers

+ (instancetype)jsonEventInterpreter:(BOOL)pretty
{
  return [[FBJSONEventInterpreter alloc] initWithPrettyFormatting:pretty];
}

+ (instancetype)humanReadableInterpreter
{
  return [[FBHumanReadableEventInterpreter alloc] init];
}

#pragma mark Public

- (NSString *)interpret:(id<FBEventReporterSubject>)subject
{
  NSArray<NSString *> *lines = [self interpretLines:subject];
  return [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}

- (NSArray<NSString *> *)interpretLines:(id<FBEventReporterSubject>)eventReporterSubject
{
  NSMutableArray<NSString *> *results = [[NSMutableArray alloc] init];
  for (id<FBEventReporterSubject> subject in eventReporterSubject.subSubjects) {
    NSString *line = [self renderSubjectLine:subject];
    [results addObject:line];
  }
  return [results copy];
}

#pragma mark Private

- (NSString *)renderSubjectLine:(id<FBEventReporterSubject>)subject
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBJSONEventInterpreter

- (instancetype)initWithPrettyFormatting:(BOOL)pretty
{
  self = [super init];

  if (!self) {
    return nil;
  }

  _pretty = pretty;

  return self;
}

- (NSString *)renderSubjectLine:(id<FBEventReporterSubject>)subject
{
  // Get the Representation.
  NSDictionary<NSString *, id> *representation = [subject jsonSerializableRepresentation];
  NSAssert(
     [FBCollectionInformation isDictionaryHeterogeneous:representation keyClass:NSString.class valueClass:NSObject.class],
     @"When rendering a subject, the subject must be a Dictionary<String, String> but it is not %@",
     [FBCollectionInformation oneLineDescriptionFromDictionary:representation]
  );

  // Check it has an eventName string
  if (!representation[FBJSONKeyEventName]) {
    NSAssert(NO, ([NSString stringWithFormat:@"%@ does not have a %@", subject, FBJSONKeyEventName]));
    return nil;
  }
  //Check it has an eventType string
  if (!representation[FBJSONKeyEventType]) {
    NSAssert(NO, ([NSString stringWithFormat:@"%@ does not have a %@", subject, FBJSONKeyEventType]));
    return nil;
  }

  NSJSONWritingOptions writingOptions = self.pretty ? NSJSONWritingPrettyPrinted : 0;
  NSError *error = nil;

  NSData *data = [NSJSONSerialization dataWithJSONObject:representation options:writingOptions error:&error];
  NSString *serialized = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

  if (error) {
    NSAssert(NO, ([NSString stringWithFormat:@"Failed to Serialize %@ to string: %@", representation, error]));
    return nil;
  }

  return serialized;
}

@end

@implementation FBHumanReadableEventInterpreter

- (NSString *)renderSubjectLine:(id<FBEventReporterSubject>)subject
{
  return subject.description;
}

@end
