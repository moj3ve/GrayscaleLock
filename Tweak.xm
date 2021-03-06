#include <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreFoundation/CFNotificationCenter.h>
extern "C" CFNotificationCenterRef CFNotificationCenterGetDistributedCenter();
#include "GrayscaleLock.h"
#import <sys/utsname.h>

extern "C" BOOL _AXSGrayscaleEnabled();
extern "C" void _AXSGrayscaleSetEnabled(BOOL);

@interface SBApplication
-(id)bundleIdentifier;
@end

static bool enabled = NO;
static bool grayscaleDefault = NO;
static bool springboardGray = NO;
static NSMutableArray* appsToInvert = nil;
static NSString* lockIdentifier = @"";

static NSMutableDictionary *getDefaults() {
  NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
  [defaults setObject:@NO forKey:@"enabled"];
  [defaults setObject:@NO forKey:@"springboardGray"];
  [defaults setObject:@NO forKey:@"grayscaleDefault"];

  return defaults;
}

// static void log(NSString *toLog) {
// 	NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:@"/var/mobile/log.txt"];
// 	[fileHandle seekToEndOfFile];
// 	[fileHandle writeData:[[NSString stringWithFormat:@"%@\n", toLog] dataUsingEncoding:NSUTF8StringEncoding]];
// 	[fileHandle closeFile];
// }

static void tripleClickHome() {
	UIHBClickGestureRecognizer* tripleClick = [[[(SpringBoard *)[%c(SpringBoard) sharedApplication] homeHardwareButton] gestureRecognizerConfiguration] triplePressUpGestureRecognizer];
	// Succeed base
	MSHookIvar<long long>(tripleClick, "_state") = UIGestureRecognizerStateEnded;

	[[(SpringBoard *)[%c(SpringBoard) sharedApplication] homeHardwareButton] triplePressUp:tripleClick];

	MSHookIvar<long long>(tripleClick, "_state") = UIGestureRecognizerStatePossible;
}

static void tripleClickLock() {
	// Trigger the triple click
	SBClickGestureRecognizer* tripleClick = [[(SpringBoard *)[%c(SpringBoard) sharedApplication] lockHardwareButton] triplePressGestureRecognizer];

	// Succeed base
	MSHookIvar<long long>(tripleClick, "_state") = UIGestureRecognizerStateEnded;

	// Invoke triple press (to toggle colorFilter)
	[[(SpringBoard *)[%c(SpringBoard) sharedApplication] lockHardwareButton] triplePress:tripleClick];

	// Reset the base
	MSHookIvar<long long>(tripleClick, "_state") = UIGestureRecognizerStatePossible;
}

static void setGrayscale(BOOL status) {
	// If you want it to be enabled and it is, don't do anything
	if (_AXSGrayscaleEnabled() && status) {
		return;
	}

	_AXSGrayscaleSetEnabled(false); // doesn't work setting it to true on iOS 11, iPhone X

	struct utsname systemInfo;
	uname(&systemInfo);
	NSString *modelName = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];

	if (status) {
		// Save the current assistive touch option
		NSArray *oldOptions = [[%c(AXSettings) sharedInstance] tripleClickOptions];
		// Set it to grayscale
		[[%c(AXSettings) sharedInstance] setTripleClickOptions:@[@10]]; // 10 = color filters

		// iPhone X
		if ([modelName isEqualToString:@"iPhone10,3"] || [modelName isEqualToString:@"iPhone10,6"]) {
			tripleClickLock();
		} else {
			tripleClickHome();
		}

		// Reset the assistive touch options
		[[%c(AXSettings) sharedInstance] setTripleClickOptions:oldOptions];
	}
}

static void loadPreferences() {
	NSString* plist = @"/var/mobile/Library/Preferences/com.hackingdartmouth.grayscalelock.plist";
	NSMutableDictionary* settings = [[NSMutableDictionary alloc] initWithContentsOfFile:plist];
	if (settings == nil) {
		settings = getDefaults();
	}

	if ([appsToInvert count]) {
	  [appsToInvert removeAllObjects];
	}

	NSNumber* value = [settings valueForKey:@"enabled"];
	if (value != nil) {
		enabled = [value boolValue];
	}
	NSNumber* grayscale = [settings valueForKey:@"grayscaleDefault"];
	if (grayscale != nil) {
		grayscaleDefault = [grayscale boolValue];
	}
	NSNumber* springboard = [settings valueForKey:@"springboardGray"];
	if (springboard != nil) {
		springboardGray = [springboard boolValue];
	}

	if (!enabled) {
		return;
	}

	NSString* identifier;
	for (NSString* key in [settings allKeys]) {
		if ([[settings valueForKey:key] boolValue]) {
			if ([key hasPrefix:@"invert-"]) {
				identifier = [key substringFromIndex:7];
				
				[appsToInvert addObject:identifier];
			}
		}
	}
}

static void updateSettings(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
  loadPreferences();

	// Handle it currently
	if (!enabled) {
		setGrayscale(false);
	} else {
		NSString *identifier = @"com.apple.Preferences";

		if (
			(grayscaleDefault && ![appsToInvert containsObject:identifier]) ||
			(!grayscaleDefault && [appsToInvert containsObject:identifier])
		) {
			setGrayscale(true);
		} else {
			setGrayscale(false);
		}
	}
}

%hook SBApplication
%group ios10
-(void)willActivate {
	if (enabled) {
		NSString* identifier = [self bundleIdentifier];

		// If grayscaleDefault and no app, then set it to grayscale
		// If grayscaleDefault and yes app, then set it to normal
		// If NOT grayscaleDefault and no app, then set it to normal
		// If NOT grayscaleDefault and yes app, then set it to grayscale
		if (
			(grayscaleDefault && ![appsToInvert containsObject:identifier]) ||
			(!grayscaleDefault && [appsToInvert containsObject:identifier])
		) {
			setGrayscale(true);
		} else {
			setGrayscale(false);
		}

		lockIdentifier = identifier;
	}
	return %orig;
}

-(void)didDeactivateForEventsOnly:(bool)arg1 {
	// Going to springboard
	if (enabled && [lockIdentifier isEqualToString:[self bundleIdentifier]]) {
		lockIdentifier = @"";
		setGrayscale(springboardGray);
	}
	%orig;
}
%end

%group ios11
-(void)_updateProcess:(id)arg1 withState:(FBProcessState *)state {
	// App is launching
	if (enabled && [state visibility] == kForeground && ![[self bundleIdentifier] isEqualToString:lockIdentifier]) {
		NSString* identifier = [self bundleIdentifier];

		// If grayscaleDefault and no app, then set it to grayscale
		// If grayscaleDefault and yes app, then set it to normal
		// If NOT grayscaleDefault and no app, then set it to normal
		// If NOT grayscaleDefault and yes app, then set it to grayscale
		
		if (
			(grayscaleDefault && ![appsToInvert containsObject:identifier]) ||
			(!grayscaleDefault && [appsToInvert containsObject:identifier])
		) {
			setGrayscale(true);
		} else {
			setGrayscale(false);
		}

		lockIdentifier = identifier;
	}
	return %orig;
}

-(void)saveSnapshotForSceneHandle:(id)arg1 context:(id)arg2 completion:(/*^block*/id)arg3 {
	if (enabled && [lockIdentifier isEqualToString:[self bundleIdentifier]]) {
		lockIdentifier = @"";
		setGrayscale(springboardGray);
	}
	%orig;
}
%end
%end

%ctor {
	CFNotificationCenterAddObserver(
		CFNotificationCenterGetDistributedCenter(),
		NULL,
		&updateSettings,
		CFSTR("com.hackingdartmouth.grayscalelock/settingschanged"),
		NULL,
		CFNotificationSuspensionBehaviorDeliverImmediately);

	appsToInvert = [[NSMutableArray alloc] init];

	loadPreferences();

	if (kCFCoreFoundationVersionNumber > 1400) {
		%init(ios11);
	} else {
		%init(ios10);
	}

	%init;
}