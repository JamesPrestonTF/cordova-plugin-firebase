#import "AppDelegate+FirebasePlugin.h"
#import "FirebasePlugin.h"
#import "Firebase.h"
#import <objc/runtime.h>

#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
@import UserNotifications;
#endif

// Implement UNUserNotificationCenterDelegate to receive display notification via APNS for devices
// running iOS 10 and above. Implement FIRMessagingDelegate to receive data message via FCM for
// devices running iOS 10 and above.
#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
@interface AppDelegate () <UNUserNotificationCenterDelegate, FIRMessagingDelegate>
@end
#endif

@implementation AppDelegate (FirebasePlugin)

+ (void)load {
    Method original = class_getInstanceMethod(self, @selector(application:didFinishLaunchingWithOptions:));
    Method swizzled = class_getInstanceMethod(self, @selector(application:swizzledDidFinishLaunchingWithOptions:));
    method_exchangeImplementations(original, swizzled);
}

- (BOOL)application:(UIApplication *)application swizzledDidFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self application:application swizzledDidFinishLaunchingWithOptions:launchOptions];
    
    [FIRApp configure];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tokenRefreshNotification:)
                                                 name:kFIRInstanceIDTokenRefreshNotification object:nil];
    
    UILocalNotification *localNotification = [launchOptions objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];
    if (localNotification) {
        NSLog(@"FirebasePlugin: Starting with local notification");
        [self handleLocalNotification:localNotification.userInfo];
    }
    
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    NSLog(@"FirebasePlugin: Application did become active.");
    [self connectToFcm];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    NSLog(@"FirebasePlugin: Application will enter background.");
    [self disconnectFromFcm];
}

- (void)tokenRefreshNotification:(NSNotification *)notification {
    // Note that this callback will be fired everytime a new token is generated, including the first
    // time. So if you need to retrieve the token as soon as it is available this is where that
    // should be done.
    NSString *refreshedToken = [[FIRInstanceID instanceID] token];
    NSLog(@"FirebasePlugin: InstanceID token: %@", refreshedToken);
    
    // Connect to FCM since connection may have failed when attempted before having a token.
    [self connectToFcm];

    [FirebasePlugin.firebasePlugin sendToken:refreshedToken];
}

- (void)connectToFcm {
    [[FIRMessaging messaging] connectWithCompletion:^(NSError * _Nullable error) {
        if (error != nil) {
            NSLog(@"FirebasePlugin: Unable to connect to FCM. %@", error);
        } else {
            NSLog(@"FirebasePlugin: Connected to FCM.");
            NSString *refreshedToken = [[FIRInstanceID instanceID] token];
            NSLog(@"FirebasePlugin: InstanceID token: %@", refreshedToken);
        }
    }];
}

- (void)disconnectFromFcm {
    [[FIRMessaging messaging] disconnect];
    NSLog(@"FirebasePlugin: Disconnected from FCM");
}

+ (BOOL)notificationIsDisplayable:(NSDictionary*)notificationData {
    NSString *title = notificationData[@"title"];
    NSString *body = notificationData[@"body"];
    return (title != nil || body != nil);
}

- (void)sendLocalNotification:(NSMutableDictionary *)notificationData {
    // If the notification does not contain a visible message, forward it to the app
    if (![AppDelegate notificationIsDisplayable:notificationData]) {
        [self sendFirebaseNotification:notificationData];
        return;
    }
    
    // The notification contains a visible message, so send a local notification to the OS
    NSLog(@"FirebasePlugin: Sending local notification to OS: %@", notificationData);
    
    // Make sure the notification has a title
    UILocalNotification *localNotification = [[UILocalNotification alloc] init];
    localNotification.alertTitle = notificationData[@"title"];
    localNotification.alertBody = notificationData[@"body"];
    localNotification.userInfo = notificationData;
    [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
}
    
- (void)sendFirebaseNotification:(NSMutableDictionary *)notificationData {
    // Treat non-displayable notifications as a special case and send as though the user had tapped them
    if (![AppDelegate notificationIsDisplayable:notificationData]) {
        [notificationData setObject:[NSNumber numberWithBool:YES] forKey:@"tap"];
    }
    
    // Send the notification
    NSLog(@"FirebasePlugin: Sending Firebase notification to app: %@", notificationData);
    [FirebasePlugin.firebasePlugin sendNotification:notificationData];
}
    
+ (void)appendToNotificationData:(NSMutableDictionary*)notificationData fromApsAlertInfo:(id)apsAlert {
    if (apsAlert != nil) {
        // Depending on whether the notification title is set, the "alert" field may be a dictionary, or it may be a string containing the body text of the notification
        if ([apsAlert isKindOfClass:[NSDictionary class]]) {
            for (id sourceKey in apsAlert) {
                id value = [apsAlert objectForKey:sourceKey];
                id destinationKey = sourceKey;
                [notificationData setObject:value forKey:destinationKey];
            }
        }
        else {
            [notificationData setObject:apsAlert forKey:@"body"];
        }
    }
}
    
+ (void)appendToNotificationData:(NSMutableDictionary *)data fromApsData:(NSDictionary *)aps {
    if (aps != nil) {
        for (id sourceKey in aps) {
            id value = [aps objectForKey:sourceKey];
            id destinationKey = nil;
            if ([sourceKey isEqualToString:@"alert"]) {
                [AppDelegate appendToNotificationData:data fromApsAlertInfo:value];
            }
            else {
                destinationKey = sourceKey;
            }
            
            if (destinationKey != nil) {
                [data setObject:value forKey:destinationKey];
            }
        }
    }
}

+ (NSMutableDictionary *)compileNotificationDataFromNotificationUserInfo:(NSDictionary *)userInfo {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    
    for (id sourceKey in userInfo) {
        id value = [userInfo objectForKey:sourceKey];
        
        id destinationKey = nil;
        if ([sourceKey isEqualToString:@"gcm.message_id"]) {
            destinationKey = @"id";
        }
        else if ([sourceKey isEqualToString:@"aps"]) {
            [AppDelegate appendToNotificationData:data fromApsData:value];
        }
        else {
            destinationKey = sourceKey;
        }
        
        if (destinationKey != nil) {
            [data setObject:value forKey:destinationKey];
        }
    }
    
    // By default, say that the notification has not been tapped
    [data setObject:[NSNumber numberWithBool:NO] forKey:@"tap"];

    // Check that the notification has an ID
    id notificationId = data[@"id"];
    if (notificationId == nil) {
        NSTimeInterval timeSince1970 = [[[NSDate alloc] init] timeIntervalSince1970];
        data[@"id"] = [@(timeSince1970) stringValue];
    }
    
    return data;
}

- (void)handleRemoteNotification:(NSDictionary *)userInfo {
    NSMutableDictionary *notificationData = [AppDelegate compileNotificationDataFromNotificationUserInfo:userInfo];
    switch ([[UIApplication sharedApplication] applicationState]) {
        case UIApplicationStateActive:
            // Received notification while in foreground - let the app handle and display the notification
            [self sendFirebaseNotification:notificationData];
            break;
        case UIApplicationStateBackground:
            // Received notification while in background - display a local notification in the OS
            [self sendLocalNotification:notificationData];
            break;
        case UIApplicationStateInactive:
            // Received notification while between foreground and background, probably due to the user tapping an OS-supplied notification - tell the app that the notification has been clicked
            [notificationData setObject:[NSNumber numberWithBool:YES] forKey:@"tap"];
            [self sendFirebaseNotification:notificationData];
            break;
    }
}
    
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    NSLog(@"FirebasePlugin: application:didReceiveRemoteNotification");
    [self handleRemoteNotification:userInfo];
}
    
    
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
    fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    NSLog(@"FirebasePlugin: application:didReceiveRemoteNotification:fetchCompletionHandler");
    [self handleRemoteNotification:userInfo];
    completionHandler(UIBackgroundFetchResultNoData);
}

#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    NSLog(@"FirebasePlugin: userNotificationCenter:willPresentNotification:withCompletionHandler");
    [self handleRemoteNotification:notification.request.content.userInfo];
    completionHandler(UNNotificationPresentationOptionNone);
}
    
// Receive data message on iOS 10 devices.
- (void)applicationReceivedRemoteMessage:(FIRMessagingRemoteMessage *)remoteMessage {
    NSLog(@"FirebasePlugin: applicationReceivedRemoteMessage");
    [self handleRemoteNotification:remoteMessage.appData];
}
    
#endif
    
- (void)handleLocalNotification:(NSDictionary *)notificationData {
    NSMutableDictionary *mutableNotificationData = [notificationData mutableCopy];
    [mutableNotificationData setObject:[NSNumber numberWithBool:YES] forKey:@"tap"];
    [self sendFirebaseNotification:mutableNotificationData];
}

- (void)application:(UIApplication*)application didReceiveLocalNotification:(nonnull UILocalNotification *)notification {
    NSLog(@"FirebasePlugin: application:didReceiveLocalNotification");
    [self handleLocalNotification:notification.userInfo];
}

@end
