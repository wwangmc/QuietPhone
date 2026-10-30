#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface QPRootListController : PSListController
@end

@implementation QPRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    CFStringRef domain = (__bridge CFStringRef)[specifier propertyForKey:@"defaults"];
    CFPreferencesAppSynchronize(domain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)[specifier propertyForKey:@"key"], domain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    CFStringRef domain = (__bridge CFStringRef)[specifier propertyForKey:@"defaults"];
    CFPreferencesSetAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"],
                             (__bridge CFPropertyListRef)value, domain);
    CFPreferencesAppSynchronize(domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.example.quietphone/preferences-changed"), NULL, NULL, YES);
}
@end
