#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Loader.h"

static const NSUInteger kCategory = 0x6c707200;
static const NSUInteger kGroup = 0x6c707267;
static NSString *const kLoaderRepo = @"https://github.com/itzzace";
static NSString *const kModRepo = @"https://github.com/AppropriateNet2928/YTLitePlusRenewed";

static IMP gCategoryOrder;
static IMP gUpdateSection;
static IMP gOrderedGroups;
static IMP gGroupTitle;
static IMP gGroupCategories;

static BOOL YTLPRHook(Class cls, NSString *name, IMP replacement, IMP *original) {
    if (cls == Nil || *original != NULL) return *original != NULL;
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (method == NULL) return NO;
    *original = method_setImplementation(method, replacement);
    return YES;
}

static void YTLPRCloseApp(void) {
    [UIApplication.sharedApplication performSelector:@selector(suspend)];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ exit(0); });
}

static UIViewController *YTLPRTopController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) window = candidate;
        }
    }
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController != nil) top = top.presentedViewController;
    return top;
}

static void YTLPRAlert(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [YTLPRTopController() presentViewController:alert animated:YES completion:nil];
}

static void YTLPRRestartPrompt(NSArray<NSString *> *notes) {
    NSString *message = @"Restart YouTube for your changes to take effect.";
    if (notes.count != 0) {
        message = [NSString stringWithFormat:@"%@\n\n%@", [notes componentsJoinedByString:@"\n"], message];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart Required" message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart Now" style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) { YTLPRCloseApp(); }]];
    [YTLPRTopController() presentViewController:alert animated:YES completion:nil];
}

static void YTLPROpen(NSString *link) {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:link] options:@{} completionHandler:nil];
}

static id YTLPRPlainItem(NSString *title, NSString *description, BOOL (^select)(id, NSUInteger)) {
    Class itemClass = NSClassFromString(@"YTSettingsSectionItem");
    SEL selector = NSSelectorFromString(
        @"itemWithTitle:titleDescription:accessibilityIdentifier:detailTextBlock:selectBlock:");
    if (![itemClass respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
        itemClass, selector, title, description, @"YTLPRItem", nil, select);
}

static id YTLPRHeaderItem(NSString *title) {
    id item = YTLPRPlainItem(title.uppercaseString, nil, nil);
    for (NSString *name in @[@"setInkEnabled:", @"setEnabled:", @"setSettingEnabled:"]) {
        SEL selector = NSSelectorFromString(name);
        if ([item respondsToSelector:selector]) ((void (*)(id, SEL, BOOL))objc_msgSend)(item, selector, NO);
    }
    return item;
}

static id YTLPRSwitchItem(NSString *title, NSString *description, BOOL on, BOOL (^change)(id, BOOL)) {
    Class itemClass = NSClassFromString(@"YTSettingsSectionItem");
    SEL selector = NSSelectorFromString(
        @"switchItemWithTitle:titleDescription:accessibilityIdentifier:switchOn:switchBlock:settingItemId:");
    if (![itemClass respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id, id, id, BOOL, id, int))objc_msgSend)(
        itemClass, selector, title, description, @"YTLPRSwitch", on, change, 0);
}

static NSString *YTLPRDescription(YTLPRTweak *tweak) {
    if (tweak.missing) return [NSString stringWithFormat:@"Missing file: %@", tweak.file];
    if (tweak.loadError != nil) return [NSString stringWithFormat:@"Couldn't load: %@", tweak.loadError];
    if (!YTLPRSafeMode() && YTLPRIsOn(tweak) != tweak.loaded) {
        return tweak.about.length ? [tweak.about stringByAppendingString:@" • restart to apply"] : @"Restart to apply";
    }
    return tweak.about;
}

static void YTLPRBuildSection(id manager, id controller, NSUInteger category);

static void YTLPRRefreshAll(id manager, id controller) {
    YTLPRBuildSection(manager, controller, kCategory);
}

static NSArray *YTLPRNoticeItems(void) {
    NSMutableArray *items = [NSMutableArray array];
    if (YTLPRSafeMode()) {
        id item = YTLPRPlainItem(@"⚠️ Safe Mode",
            @"YouTube crashed twice while loading tweaks, so none were loaded. Turn off the one causing it, then restart.",
            nil);
        if (item) [items addObject:item];
    }
    if (YTLPRConfigError().length != 0) {
        id item = YTLPRPlainItem(@"⚠️ Problem with Tweaks.json", YTLPRConfigError(), nil);
        if (item) [items addObject:item];
    }
    return items;
}

static NSArray *YTLPRTweakItems(YTLPRSection *section, id manager, id controller) {
    NSMutableArray *items = [NSMutableArray array];
    __weak id weakManager = manager;
    __weak id weakController = controller;
    for (YTLPRTweak *tweak in section.tweaks) {
        id item = YTLPRSwitchItem(tweak.name, YTLPRDescription(tweak), YTLPRIsOn(tweak),
                                  ^BOOL(__unused id cell, BOOL enabled) {
            NSArray<NSString *> *notes = YTLPRSetOn(tweak, enabled);
            YTLPRRefreshAll(weakManager, weakController);
            YTLPRRestartPrompt(notes);
            return YES;
        });
        if (item) [items addObject:item];
    }
    return items;
}

static NSArray *YTLPRLoaderItems(id manager, id controller) {
    NSMutableArray *items = [NSMutableArray array];
    __weak id weakManager = manager;
    __weak id weakController = controller;
    NSUInteger total = 0, on = 0, loaded = 0;
    for (YTLPRSection *section in YTLPRSections()) {
        for (YTLPRTweak *tweak in section.tweaks) {
            total++;
            if (YTLPRIsOn(tweak)) on++;
            if (tweak.loaded) loaded++;
        }
    }
    id status = YTLPRPlainItem(@"Status",
        [NSString stringWithFormat:@"%lu of %lu tweaks on • %lu running now%@",
         (unsigned long)on, (unsigned long)total, (unsigned long)loaded,
         YTLPRSafeMode() ? @" • safe mode" : @""], nil);
    if (status) [items addObject:status];

    id restart = YTLPRPlainItem(@"Restart YouTube", @"Close YouTube so your changes take effect",
                                ^BOOL(__unused id cell, __unused NSUInteger index) {
        YTLPRCloseApp();
        return YES;
    });
    if (restart) [items addObject:restart];

    id reset = YTLPRPlainItem(@"Reset to Defaults", @"Restore settings to recommended",
                              ^BOOL(__unused id cell, __unused NSUInteger index) {
        YTLPRResetAll();
        YTLPRRefreshAll(weakManager, weakController);
        YTLPRRestartPrompt(@[]);
        return YES;
    });
    if (reset) [items addObject:reset];

    id loader = YTLPRPlainItem(@"Loader by itzzace", @"Made by itzzace, creator of YTKACE",
                               ^BOOL(__unused id cell, __unused NSUInteger index) {
        YTLPROpen(kLoaderRepo);
        return YES;
    });
    if (loader) [items addObject:loader];

    id mod = YTLPRPlainItem(@"YTLitePlusRenewed", @"By AppropriateNet2928",
                            ^BOOL(__unused id cell, __unused NSUInteger index) {
        YTLPROpen(kModRepo);
        return YES;
    });
    if (mod) [items addObject:mod];
    return items;
}

static void YTLPRBuildSection(id manager, id controller, NSUInteger category) {
    if (controller == nil) return;
    NSMutableArray *items = [NSMutableArray arrayWithArray:YTLPRNoticeItems()];
    for (YTLPRSection *section in YTLPRSections()) {
        id header = section.title.length ? YTLPRHeaderItem(section.title) : nil;
        if (header) [items addObject:header];
        [items addObjectsFromArray:YTLPRTweakItems(section, manager, controller)];
    }
    id loaderHeader = YTLPRHeaderItem(@"Loader");
    if (loaderHeader) [items addObject:loaderHeader];
    [items addObjectsFromArray:YTLPRLoaderItems(manager, controller)];
    NSString *title = YTLPRTitle();
    NSString *description = @"Changes apply after restarting YouTube";
    SEL modern = NSSelectorFromString(@"setSectionItems:forCategory:title:icon:titleDescription:headerHidden:");
    SEL legacy = NSSelectorFromString(@"setSectionItems:forCategory:title:titleDescription:headerHidden:");
    if ([controller respondsToSelector:modern]) {
        id icon = [NSClassFromString(@"YTIIcon") new];
        SEL setIconType = NSSelectorFromString(@"setIconType:");
        if ([icon respondsToSelector:setIconType]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(icon, setIconType, 44);
        }
        ((void (*)(id, SEL, id, NSUInteger, id, id, id, BOOL))objc_msgSend)(
            controller, modern, items, category, title, icon, description, NO);
    } else if ([controller respondsToSelector:legacy]) {
        ((void (*)(id, SEL, id, NSUInteger, id, id, BOOL))objc_msgSend)(
            controller, legacy, items, category, title, description, NO);
    }
}

static void YTLPRUpdateSection(id self, SEL _cmd, NSUInteger category, id entry) {
    if (category != kCategory) {
        ((void (*)(id, SEL, NSUInteger, id))gUpdateSection)(self, _cmd, category, entry);
        return;
    }
    id controller = nil;
    @try {
        controller = [self valueForKey:@"_settingsViewControllerDelegate"];
    } @catch (__unused NSException *exception) {
        return;
    }
    YTLPRBuildSection(self, controller, category);
}

static NSArray *YTLPRCategoryOrder(id self, SEL _cmd) {
    NSArray *order = ((id (*)(id, SEL))gCategoryOrder)(self, _cmd);
    if ([order containsObject:@(kCategory)]) return order;
    NSMutableArray *updated = [order mutableCopy] ?: [NSMutableArray array];
    NSUInteger index = [updated indexOfObject:@1];
    [updated insertObject:@(kCategory) atIndex:index == NSNotFound ? updated.count : index + 1];
    return updated;
}

static NSArray *YTLPROrderedGroups(id self, SEL _cmd) {
    NSArray *groups = ((id (*)(id, SEL))gOrderedGroups)(self, _cmd);
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    SEL initializer = NSSelectorFromString(@"initWithGroupType:");
    if (![groupClass instancesRespondToSelector:initializer]) return groups;
    id group = ((id (*)(id, SEL, NSUInteger))objc_msgSend)([groupClass alloc], initializer, kGroup);
    if (group == nil) return groups;
    NSMutableArray *updated = [groups mutableCopy] ?: [NSMutableArray array];
    [updated insertObject:group atIndex:0];
    return updated;
}

static NSString *YTLPRGroupTitle(id self, SEL _cmd, NSUInteger type) {
    if (type == kGroup) return YTLPRTitle();
    return ((id (*)(id, SEL, NSUInteger))gGroupTitle)(self, _cmd, type);
}

static NSArray *YTLPRGroupCategories(id self, SEL _cmd, NSUInteger type) {
    if (type == kGroup) return @[@(kCategory)];
    return ((id (*)(id, SEL, NSUInteger))gGroupCategories)(self, _cmd, type);
}

static BOOL YTLPRInstallHooks(void) {
    BOOL ok = YES;
    ok &= YTLPRHook(object_getClass(NSClassFromString(@"YTAppSettingsPresentationData")),
                    @"settingsCategoryOrder", (IMP)YTLPRCategoryOrder, &gCategoryOrder);
    ok &= YTLPRHook(NSClassFromString(@"YTSettingsSectionItemManager"),
                    @"updateSectionForCategory:withEntry:", (IMP)YTLPRUpdateSection, &gUpdateSection);
    YTLPRHook(object_getClass(NSClassFromString(@"YTAppSettingsGroupPresentationData")),
              @"orderedGroups", (IMP)YTLPROrderedGroups, &gOrderedGroups);
    YTLPRHook(NSClassFromString(@"YTSettingsGroupData"),
              @"titleForSettingGroupType:", (IMP)YTLPRGroupTitle, &gGroupTitle);
    YTLPRHook(NSClassFromString(@"YTSettingsGroupData"),
              @"orderedCategoriesForGroupType:", (IMP)YTLPRGroupCategories, &gGroupCategories);
    return ok;
}

void YTLPRInstallMenu(void) {
    if (!YTLPRInstallHooks()) {
        for (int attempt = 1; attempt <= 30; attempt++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(attempt * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ YTLPRInstallHooks(); });
        }
    }
    if (!YTLPRSafeMode()) return;
    __block id observer = [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                     queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        observer = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            YTLPRAlert(@"Tweaks not loaded",
                       [NSString stringWithFormat:@"YouTube crashed twice while loading tweaks. "
                        "Go to Settings > %@ and turn off the one causing it.", YTLPRTitle()]);
        });
    }];
}
