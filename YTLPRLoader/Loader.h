#import <Foundation/Foundation.h>

@interface YTLPRTweak : NSObject
@property (nonatomic, copy) NSString *file;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *about;
@property (nonatomic, copy) NSArray<NSString *> *needs;
@property (nonatomic, copy) NSArray<NSString *> *clashes;
@property (nonatomic) BOOL defaultOn;
@property (nonatomic) BOOL missing;
@property (nonatomic, copy) NSString *loadError;
@property (nonatomic) BOOL loaded;
@end

@interface YTLPRSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<YTLPRTweak *> *tweaks;
@end

FOUNDATION_EXPORT NSString *YTLPRTitle(void);
FOUNDATION_EXPORT NSArray<YTLPRSection *> *YTLPRSections(void);
FOUNDATION_EXPORT NSString *YTLPRConfigError(void);
FOUNDATION_EXPORT BOOL YTLPRSafeMode(void);

FOUNDATION_EXPORT BOOL YTLPRIsOn(YTLPRTweak *tweak);
FOUNDATION_EXPORT NSArray<NSString *> *YTLPRSetOn(YTLPRTweak *tweak, BOOL on);
FOUNDATION_EXPORT void YTLPRSetAll(BOOL on);
FOUNDATION_EXPORT void YTLPRResetAll(void);

FOUNDATION_EXPORT void YTLPRInstallMenu(void);
