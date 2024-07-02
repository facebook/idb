/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "FBCrashLogParser.h"
#import "FBConcatedJsonParser.h"
#import "FBCrashLog.h"

@implementation FBConcatedJSONCrashLogParser

-(void)parseCrashLogFromString:(NSString *)str executablePathOut:(NSString *_Nonnull * _Nonnull)executablePathOut identifierOut:(NSString *_Nonnull * _Nonnull)identifierOut processNameOut:(NSString *_Nonnull * _Nonnull)processNameOut parentProcessNameOut:(NSString *_Nonnull * _Nonnull)parentProcessNameOut processIdentifierOut:(pid_t *)processIdentifierOut parentProcessIdentifierOut:(pid_t *)parentProcessIdentifierOut dateOut:(NSDate *_Nonnull * _Nonnull)dateOut  exceptionDescription:(NSString *_Nonnull * _Nonnull)exceptionDescription crashedThreadDescription:(NSString *_Nonnull * _Nonnull)crashedThreadDescription error:(NSError **)error {
  NSDictionary<NSString *, id> *parsedReport = [FBConcatedJsonParser parseConcatenatedJSONFromString:str error:error];
  if (!parsedReport) {
    return;
  }

  *executablePathOut = parsedReport[@"procPath"];

  // Name and identifier is the same thing
  *processNameOut = parsedReport[@"procName"];
  *identifierOut = parsedReport[@"procName"];
  if ([parsedReport valueForKey:@"pid"]) {
    *processIdentifierOut = ((NSNumber *)parsedReport[@"pid"]).intValue;
  }

  *parentProcessNameOut = parsedReport[@"parentProc"];
  if ([parsedReport valueForKey:@"parentPid"]) {
    *parentProcessIdentifierOut = ((NSNumber *)parsedReport[@"parentPid"]).intValue;
  }
  if ([parsedReport valueForKey:@"captureTime"]) {
    NSString *dateString = parsedReport[@"captureTime"];
    *dateOut = [FBCrashLog.dateFormatter dateFromString:dateString];
  }

  NSDictionary *exceptionDictionary = parsedReport[@"exception"];
  if ([exceptionDictionary isKindOfClass:[NSDictionary class]]) {
    NSMutableString *exceptionDescriptionMutable = [NSMutableString new];
    NSString *exceptionType = [exceptionDictionary objectForKey:@"type"];
    NSString *exceptionSignal = [exceptionDictionary objectForKey:@"signal"];
    NSString *exceptionSubtype = [exceptionDictionary objectForKey:@"subtype"];

    if ([exceptionType isKindOfClass:[NSString class]]) {
      [exceptionDescriptionMutable appendString:exceptionType];
    }
    if ([exceptionSignal isKindOfClass:[NSString class]]) {
      [exceptionDescriptionMutable appendString:@" "];
      [exceptionDescriptionMutable appendString:exceptionSignal];
    }
    if ([exceptionSubtype isKindOfClass:[NSString class]]) {
      [exceptionDescriptionMutable appendString:@" "];
      [exceptionDescriptionMutable appendString:exceptionSubtype];
    }
    *exceptionDescription = [NSString stringWithString:exceptionDescriptionMutable];
  }

  NSMutableArray *imageNames = [NSMutableArray new];
  NSArray<NSDictionary*> *imageDictionaries = parsedReport[@"usedImages"];
  if ([imageDictionaries isKindOfClass:[NSArray class]]) {
    for (NSDictionary *imageDictionary in imageDictionaries) {
      NSString *imageName = imageDictionary[@"name"];
      if ([imageName isKindOfClass:[NSString class]]) {
        [imageNames addObject:imageName];
      }
    }
  }

  NSArray<NSDictionary*> *threads = parsedReport[@"threads"];

  if ([threads isKindOfClass:[NSArray class]]) {
    for (NSDictionary *threadDictionary in threads) {
      if ([threadDictionary isKindOfClass:[NSDictionary class]] == NO) {
        continue;
      }
      // This thread crashed
      if ([[threadDictionary objectForKey:@"triggered"] boolValue]) {
        NSArray<NSDictionary*> *frames = threadDictionary[@"frames"];
        if ([frames isKindOfClass:[NSArray class]]) {
          NSMutableString *crashedThreadDescriptionMutable = [NSMutableString new];
          for (NSDictionary *frameDictionary in frames) {
            if ([frameDictionary isKindOfClass:[NSDictionary class]]) {
              NSUInteger imageIndex = [frameDictionary[@"imageIndex"]unsignedIntegerValue];
              if (imageNames.count > imageIndex) {
                NSString *imageNameString = imageNames[imageIndex];
                if (imageNameString.length < 30) {
                  imageNameString = [imageNameString stringByPaddingToLength:30
                                                                  withString:@" "
                                                             startingAtIndex:0];
                }
                [crashedThreadDescriptionMutable appendString:imageNameString];
                [crashedThreadDescriptionMutable appendString:@"\t"];
              }
              NSString *symbol = frameDictionary[@"symbol"];
              if ([symbol isKindOfClass:[NSString class]]) {
                [crashedThreadDescriptionMutable appendString:symbol];
                [crashedThreadDescriptionMutable appendString:@"\n"];
              }
           }
         }
         *crashedThreadDescription = [NSString stringWithString:[crashedThreadDescriptionMutable stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
       }
       break;
     }
   }
  }

}

@end


@implementation FBPlainTextCrashLogParser

static NSUInteger MaxLineSearch = 20;

-(void)parseCrashLogFromString:(NSString *)str executablePathOut:(NSString *_Nonnull * _Nonnull)executablePathOut identifierOut:(NSString *_Nonnull * _Nonnull)identifierOut processNameOut:(NSString *_Nonnull * _Nonnull)processNameOut parentProcessNameOut:(NSString *_Nonnull * _Nonnull)parentProcessNameOut processIdentifierOut:(pid_t *)processIdentifierOut parentProcessIdentifierOut:(pid_t *)parentProcessIdentifierOut dateOut:(NSDate *_Nonnull * _Nonnull)dateOut  exceptionDescription:(NSString *_Nonnull * _Nonnull)exceptionDescription crashedThreadDescription:(NSString *_Nonnull * _Nonnull)crashedThreadDescription error:(NSError **)error {

  // Buffers for the sscanf
  size_t lineSize = sizeof(char) * 4098;
  const char *line = malloc(lineSize);
  char value[lineSize];

  NSUInteger length = [str length];
  NSUInteger paraStart = 0, paraEnd = 0, contentsEnd = 0;
  NSRange currentRange;
  NSUInteger linesParsed = 0;

  while (paraEnd < length && linesParsed < MaxLineSearch)
  {
    linesParsed += 1;
    [str getParagraphStart:&paraStart end:&paraEnd contentsEnd:&contentsEnd forRange:NSMakeRange(paraEnd, 0)];
    currentRange = NSMakeRange(paraStart, contentsEnd - paraStart);
    line = [[str substringWithRange:currentRange] UTF8String];

    if (sscanf(line, "Process: %s [%d]", value, processIdentifierOut) > 0) {
      *processNameOut = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
    if (sscanf(line, "Identifier: %s", value) > 0) {
      *identifierOut = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
    if (sscanf(line, "Parent Process: %s [%d]", value, parentProcessIdentifierOut) > 0) {
      *parentProcessNameOut = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
    if (sscanf(line, "Path: %s", value) > 0) {
      *executablePathOut = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
    if (sscanf(line, "Date/Time: %[^\n]", value) > 0) {
      NSString *dateString = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      *dateOut = [FBCrashLog.dateFormatter dateFromString:dateString];
      continue;
    }
  }
}

@end
