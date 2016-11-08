package org.apache.cordova.firebase;
import android.util.Log;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;

public class OnNotificationOpenReceiver extends BroadcastReceiver {
    private static final String TAG = "FirebasePlugin";

    @Override
    public void onReceive(Context context, Intent intent) {
        Log.d(TAG, "OnNotificationOpenReceiver.onReceive");

        Bundle data = intent.getExtras();
        if (FirebasePlugin.inBackground()) {
            PackageManager pm = context.getPackageManager();
            Intent launchIntent = pm.getLaunchIntentForPackage(context.getPackageName());

            launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
            launchIntent.putExtras(data);
            context.startActivity(launchIntent);
        }

        FirebasePlugin.sendNotification(data);
    }
}
