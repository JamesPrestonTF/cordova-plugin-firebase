package org.apache.cordova.firebase;

import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Bundle;
import android.support.v4.app.NotificationCompat;
import android.util.Log;
import android.text.TextUtils;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import java.util.Map;
import java.util.Random;


public class FirebasePluginMessagingService extends FirebaseMessagingService {

    private static final String TAG = "FirebasePlugin";

    /** Called when message is received. The message can either be a notification message when the
     *  app is in the foreground, or a data message when the app is in either the foreground or background.
     *  @param remoteMessage Object representing the message received from Firebase Cloud Messaging. */
    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        // Extract the information from the message
        String id = remoteMessage.getMessageId();
        RemoteMessage.Notification remoteMessageNotification = remoteMessage.getNotification();
        Map<String, String> remoteMessageData = remoteMessage.getData();
        String title = remoteMessageNotification != null ? remoteMessageNotification.getTitle() : remoteMessageData.get("title");
        String body = remoteMessageNotification != null ? remoteMessageNotification.getBody() : remoteMessageData.get("body");
        Integer colour = getMessageColour(remoteMessageNotification, remoteMessageData);

        // Log the remote message information
        Log.d(TAG, "FirebasePluginMessagingService.onMessageReceived");
        Log.d(TAG, "From: " + remoteMessage.getFrom());
        Log.d(TAG, "Notification Message id: " + id);
        Log.d(TAG, "Notification Message Title: " + (TextUtils.isEmpty(title) ? "<No title>" : title));
        Log.d(TAG, "Notification Message Body: " + (TextUtils.isEmpty(body) ? "<No body>" : body));
        Log.d(TAG, "Notification Message Colour: " + (colour == null ? "<No colour>" : Integer.toHexString(colour.intValue())));

        // If there is any message content, display a local notification - otherwise send straight to the plugin as though it was tapped
        Bundle notificationData = compileNotificationData(id, title, body, remoteMessageData);
        if (!TextUtils.isEmpty(title) || !TextUtils.isEmpty(body)) {
            sendLocalNotification(id, title, body, colour, notificationData);
        }
        else {
            notificationData.putBoolean("tap", true);
            FirebasePlugin.sendNotification(notificationData);
        }
    }

    private static final String DefaultNotificationColourKey = "com.google.firebase.messaging.default_notification_color";

    private Integer getMessageColour(RemoteMessage.Notification remoteMessageNotification, Map<String, String> remoteMessageData) {
        // Check the notification for a specified colour
        Integer notificationColour = ParseColour(remoteMessageNotification != null ? remoteMessageNotification.getColor() : remoteMessageData.get("color"));
        if (notificationColour != null) {
            return notificationColour;
        }

        // Check the app metadata for a default colour
        try {
            ApplicationInfo applicationInfo = getPackageManager().getApplicationInfo(getPackageName(), PackageManager.GET_META_DATA);
            if (applicationInfo.metaData.containsKey(DefaultNotificationColourKey)) {
                return new Integer(applicationInfo.metaData.getInt(DefaultNotificationColourKey));
            }
        }
        catch (PackageManager.NameNotFoundException exception) {
            // Swallow errors getting the default colour - treat as though the colour has not been specified
        }

        // No colour specified
        return null;
    }

    private static Integer ParseColour(String colour) {
        if (!TextUtils.isEmpty(colour) && colour.length() == 7 && colour.startsWith("#")) {
            try {
                return new Integer(Integer.parseInt(colour.substring(1), 16));
            }
            catch (NumberFormatException exception) {
                // Return default value below
            }
        }
        return null;
    }

    private Bundle compileNotificationData(String id, String title, String body, Map<String, String> data) {
        // Start with the extra data sent with the notification
        Bundle bundle = new Bundle();
        for (String key : data.keySet()) {
            bundle.putString(key, data.get(key));
        }

        // Add specific data, overwriting existing data if necessary
        if (!TextUtils.isEmpty(id)) { bundle.putString("id", id); }
        if (!TextUtils.isEmpty(title)) { bundle.putString("title", title); }
        if (!TextUtils.isEmpty(body)) { bundle.putString("body", body); }

        // By default, say that the notification has not been tapped
        bundle.putBoolean("tap", false);

        return bundle;
    }

    private void sendLocalNotification(String id, String title, String body, Integer colour, Bundle notificationData) {
        // If we could not get an ID from the original message, generate a new ID from the current time
        if (id == null) {
            id = String.valueOf(System.currentTimeMillis());
        }

        // Setup the intent launched when the user clicks the local notification
        Intent intent = new Intent(this, OnNotificationOpenReceiver.class);
        intent.putExtras(notificationData);
        PendingIntent pendingIntent = PendingIntent.getBroadcast(this, id.hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT);

        // Create the local notification
        CharSequence notificationTitle = TextUtils.isEmpty(title) ? getPackageManager().getApplicationLabel(getApplicationInfo()) : title;
        Uri defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        NotificationCompat.Builder notificationBuilder = new NotificationCompat.Builder(this, "fcm_fallback_notification_channel")
                .setContentTitle(notificationTitle)
                .setContentText(body)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setSound(defaultSoundUri)
                .setContentIntent(pendingIntent);

        // Set the colour of the notification - make sure colour is fully opaque (alpha value of 0xff)
        if (colour != null) {
            notificationBuilder.setColor(0xff000000 | colour.intValue());
        }

        // Find a suitable icon for the local notification
        int notificationIconResourceId = getResources().getIdentifier("notification_icon", "drawable", getPackageName());
        if (notificationIconResourceId != 0) {
            notificationBuilder.setSmallIcon(notificationIconResourceId);
        } else {
            notificationBuilder.setSmallIcon(getApplicationInfo().icon);
        }

        // Send the local notification 
        NotificationManager notificationManager =
                (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (notificationManager != null) {
            notificationManager.notify(id.hashCode(), notificationBuilder.build());
        }
        else {
            Log.d(TAG, "FirebasePluginMessagingService.sendLocalNotification - could not find notification manager.");
        }
    }

}
