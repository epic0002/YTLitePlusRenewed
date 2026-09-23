#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "Loader.h"

@implementation YTLPRTweak
@end

@implementation YTLPRSection
@end

static NSString *const kBundleName = @"YTLPR";
static NSString *const kConfigName = @"Tweaks.json";
static NSString *const kOnPrefix = @"YTLPR.On.";
static const NSInteger kCrashLimit = 2;

static NSString *gTitle = @"Tweaks";
static NSArray<YTLPRSection *> *gSections;
static NSDictionary<NSString *, YTLPRTweak *> *gByFile;
static NSString *gConfigError;
static BOOL gSafeMode;

NSString *YTLPRTitle(void) { return gTitle; }
NSArray<YTLPRSection *> *YTLPRSections(void) { return gSections ?: @[]; }
NSString *YTLPRConfigError(void) { return gConfigError; }
BOOL YTLPRSafeMode(void) { return gSafeMode; }

static NSString *YTLPRBundlePath(void) {
    return [[NSBundle mainBundle] pathForResource:kBundleName ofType:@"bundle"];
}

static NSArray<YTLPRTweak *> *YTLPRAllTweaks(void) {
    NSMutableArray *all = [NSMutableArray array];
    for (YTLPRSection *section in YTLPRSections()) [all addObjectsFromArray:section.tweaks];
    return all;
}

static NSArray<NSString *> *YTLPRStrings(id value) {
    if ([value isKindOfClass:NSString.class]) return @[value];
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id item in value) if ([item isKindOfClass:NSString.class]) [out addObject:item];
    return out;
}

static void YTLPRReadConfig(void) {
    NSString *bundle = YTLPRBundlePath();
    if (bundle == nil) {
        gConfigError = @"YTLPR.bundle is missing from the app.";
        return;
    }
    NSData *data = [NSData dataWithContentsOfFile:[bundle stringByAppendingPathComponent:kConfigName]];
    if (data == nil) {
        gConfigError = @"Tweaks.json is missing from YTLPR.bundle.";
        return;
    }
    NSError *error = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![root isKindOfClass:NSDictionary.class]) {
        gConfigError = [NSString stringWithFormat:@"Tweaks.json has a typo: %@",
                        error.userInfo[@"NSDebugDescription"] ?: error.localizedDescription ?: @"not a JSON object"];
        return;
    }
    if ([root[@"title"] isKindOfClass:NSString.class]) gTitle = root[@"title"];

    NSMutableArray *sections = [NSMutableArray array];
    NSMutableDictionary *byFile = [NSMutableDictionary dictionary];
    NSMutableArray *problems = [NSMutableArray array];
    NSFileManager *files = NSFileManager.defaultManager;

    for (NSDictionary *rawSection in root[@"sections"]) {
        if (![rawSection isKindOfClass:NSDictionary.class]) continue;
        YTLPRSection *section = [YTLPRSection new];
        section.title = [rawSection[@"title"] isKindOfClass:NSString.class] ? rawSection[@"title"] : @"";
        NSMutableArray *tweaks = [NSMutableArray array];
        for (NSDictionary *raw in rawSection[@"tweaks"]) {
            if (![raw isKindOfClass:NSDictionary.class]) continue;
            NSString *file = raw[@"file"];
            if (![file isKindOfClass:NSString.class] || file.length == 0) {
                [problems addObject:@"A tweak has no \"file\"."];
                continue;
            }
            if (byFile[file] != nil) {
                [problems addObject:[NSString stringWithFormat:@"%@ is listed twice.", file]];
                continue;
            }
            YTLPRTweak *tweak = [YTLPRTweak new];
            tweak.file = file;
            tweak.name = [raw[@"name"] isKindOfClass:NSString.class] ? raw[@"name"] : file.stringByDeletingPathExtension;
            tweak.about = [raw[@"about"] isKindOfClass:NSString.class] ? raw[@"about"] : @"";
            tweak.defaultOn = [raw[@"on"] boolValue];
            tweak.needs = YTLPRStrings(raw[@"needs"]);
            tweak.clashes = YTLPRStrings(raw[@"clashes"]);
            tweak.missing = ![files fileExistsAtPath:[bundle stringByAppendingPathComponent:file]];
            byFile[file] = tweak;
            [tweaks addObject:tweak];
        }
        section.tweaks = tweaks;
        [sections addObject:section];
    }

    for (YTLPRTweak *tweak in [byFile allValues]) {
        for (NSString *other in [tweak.needs arrayByAddingObjectsFromArray:tweak.clashes]) {
            if (byFile[other] == nil) {
                [problems addObject:[NSString stringWithFormat:@"%@ mentions %@, which isn't in Tweaks.json.",
                                     tweak.name, other]];
            }
        }
    }

    gSections = sections;
    gByFile = byFile;
    if (problems.count != 0) gConfigError = [problems componentsJoinedByString:@"\n"];
}

static NSString *YTLPRKey(YTLPRTweak *tweak) {
    return [kOnPrefix stringByAppendingString:tweak.file];
}

BOOL YTLPRIsOn(YTLPRTweak *tweak) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:YTLPRKey(tweak)];
    return value == nil ? tweak.defaultOn : [value boolValue];
}

static void YTLPRStore(YTLPRTweak *tweak, BOOL on) {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:YTLPRKey(tweak)];
}

static BOOL YTLPRClash(YTLPRTweak *a, YTLPRTweak *b) {
    return [a.clashes containsObject:b.file] || [b.clashes containsObject:a.file];
}

static void YTLPRTurnOff(YTLPRTweak *tweak, YTLPRTweak *root, NSMutableSet *seen, NSMutableArray *notes);

static void YTLPRTurnOn(YTLPRTweak *tweak, YTLPRTweak *root, NSMutableSet *seen, NSMutableArray *notes) {
    if ([seen containsObject:tweak.file]) return;
    [seen addObject:tweak.file];
    if (tweak != root && YTLPRIsOn(tweak)) return;
    YTLPRStore(tweak, YES);
    if (tweak != root) [notes addObject:[NSString stringWithFormat:@"Turned on %@ (needed)", tweak.name]];
    for (NSString *need in tweak.needs) {
        YTLPRTweak *dependency = gByFile[need];
        if (dependency != nil) YTLPRTurnOn(dependency, root, seen, notes);
    }
    for (YTLPRTweak *other in YTLPRAllTweaks()) {
        if (other != tweak && YTLPRIsOn(other) && YTLPRClash(tweak, other)) {
            YTLPRTurnOff(other, root, seen, notes);
        }
    }
}

static void YTLPRTurnOff(YTLPRTweak *tweak, YTLPRTweak *root, NSMutableSet *seen, NSMutableArray *notes) {
    if (tweak != root && !YTLPRIsOn(tweak)) return;
    YTLPRStore(tweak, NO);
    if (tweak != root) [notes addObject:[NSString stringWithFormat:@"Turned off %@", tweak.name]];
    for (YTLPRTweak *other in YTLPRAllTweaks()) {
        if ([other.needs containsObject:tweak.file] && YTLPRIsOn(other)) {
            YTLPRTurnOff(other, root, seen, notes);
        }
    }
}

NSArray<NSString *> *YTLPRSetOn(YTLPRTweak *tweak, BOOL on) {
    NSMutableArray *notes = [NSMutableArray array];
    if (on) {
        YTLPRTurnOn(tweak, tweak, [NSMutableSet set], notes);
    } else {
        YTLPRTurnOff(tweak, tweak, [NSMutableSet set], notes);
    }
    return notes;
}

void YTLPRSetAll(BOOL on) {
    for (YTLPRTweak *tweak in YTLPRAllTweaks()) YTLPRStore(tweak, NO);
    if (!on) return;
    for (YTLPRTweak *tweak in YTLPRAllTweaks()) {
        BOOL blocked = NO;
        for (YTLPRTweak *other in YTLPRAllTweaks()) {
            if (other != tweak && YTLPRIsOn(other) && YTLPRClash(tweak, other)) blocked = YES;
        }
        if (!blocked) YTLPRSetOn(tweak, YES);
    }
}

void YTLPRResetAll(void) {
    for (YTLPRTweak *tweak in YTLPRAllTweaks()) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:YTLPRKey(tweak)];
    }
}

static NSString *YTLPRLaunchFile(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/YTLPRLoader.launches"];
}

static NSInteger YTLPRReadLaunches(void) {
    return [[NSString stringWithContentsOfFile:YTLPRLaunchFile() encoding:NSUTF8StringEncoding error:nil] integerValue];
}

static void YTLPRWriteLaunches(NSInteger count) {
    [[NSString stringWithFormat:@"%ld", (long)count] writeToFile:YTLPRLaunchFile()
                                                      atomically:YES
                                                        encoding:NSUTF8StringEncoding
                                                           error:nil];
}

static void YTLPRWatchForCleanLaunch(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                         queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ YTLPRWriteLaunches(0); });
    }];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
                         queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        YTLPRWriteLaunches(0);
    }];
}

static void YTLPRLoad(YTLPRTweak *tweak, NSMutableSet *visiting) {
    if (tweak.loaded || tweak.loadError != nil || [visiting containsObject:tweak.file]) return;
    [visiting addObject:tweak.file];
    for (NSString *need in tweak.needs) {
        YTLPRTweak *dependency = gByFile[need];
        if (dependency != nil && YTLPRIsOn(dependency)) YTLPRLoad(dependency, visiting);
    }
    if (tweak.missing) {
        tweak.loadError = @"File not found in YTLPR.bundle";
        NSLog(@"[YTLPR] missing %@", tweak.file);
        return;
    }
    NSString *path = [YTLPRBundlePath() stringByAppendingPathComponent:tweak.file];
    if (dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL) != NULL) {
        tweak.loaded = YES;
        NSLog(@"[YTLPR] loaded %@", tweak.file);
    } else {
        const char *reason = dlerror();
        NSString *full = reason != NULL ? @(reason) : @"Unknown error";
        if ([full containsString:@"incompatible architecture"]) {
            tweak.loadError = @"Not built for this device (rebuild with ARCHS = arm64 arm64e)";
        } else if ([full containsString:@"Symbol not found"]) {
            tweak.loadError = @"Needs another tweak or library that isn't loaded";
        } else if ([full containsString:@"Library not loaded"]) {
            NSRange range = [full rangeOfString:@"Library not loaded: "];
            NSString *rest = [full substringFromIndex:NSMaxRange(range)];
            tweak.loadError = [NSString stringWithFormat:@"Missing library %@",
                               [[rest componentsSeparatedByString:@"\n"].firstObject lastPathComponent]];
        } else {
            tweak.loadError = full.length > 120 ? [[full substringToIndex:120] stringByAppendingString:@"…"] : full;
        }
        NSLog(@"[YTLPR] failed %@: %@", tweak.file, tweak.loadError);
    }
}

__attribute__((constructor)) static void YTLPRInit(void) {
    @autoreleasepool {
        YTLPRReadConfig();
        NSInteger launches = YTLPRReadLaunches();
        gSafeMode = launches >= kCrashLimit;
        YTLPRWriteLaunches(launches + 1);
        YTLPRWatchForCleanLaunch();
        if (gSafeMode) {
            NSLog(@"[YTLPR] safe mode: %ld launches crashed, loading nothing", (long)launches);
        } else {
            NSMutableSet *visiting = [NSMutableSet set];
            for (YTLPRTweak *tweak in YTLPRAllTweaks()) {
                if (YTLPRIsOn(tweak)) YTLPRLoad(tweak, visiting);
            }
        }
        YTLPRInstallMenu();
    }
}
