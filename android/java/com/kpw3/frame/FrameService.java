package com.kpw3.frame;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.net.Uri;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;

import java.util.ArrayList;
import java.util.List;

/** Foreground service that keeps the little HTTP server alive. */
public class FrameService extends Service {

    private static final String TAG = "Kpw3Frame";
    private static final String CHANNEL = "kpw3frame";

    public static volatile boolean running = false;

    private HttpServerThread server;
    private PowerManager.WakeLock wakeLock;
    private WifiManager.WifiLock wifiLock;

    private final byte[][] cacheRef = new byte[1][];
    private String cacheKey = "";
    private int rotatePointer = 0;

    private final HttpServerThread.Provider provider = new HttpServerThread.Provider() {

        @Override
        public byte[] framePng() throws Exception {
            List<String> images = Prefs.images(FrameService.this);
            if (images.isEmpty()) {
                return null;
            }

            int index;
            if (Prefs.rotateMode(FrameService.this) && images.size() > 1) {
                index = rotatePointer % images.size();
                rotatePointer = (index + 1) % images.size();
            } else {
                index = 0;
            }

            String uriString = images.get(index);
            String key = uriString + "|" + Prefs.rotate(FrameService.this) + "|"
                    + Prefs.cover(FrameService.this) + "|" + Prefs.levels(FrameService.this);
            if (key.equals(cacheKey) && cacheRef[0] != null) {
                return cacheRef[0];
            }

            long t0 = System.currentTimeMillis();
            byte[] png = EinkConverter.toEinkPng(FrameService.this, Uri.parse(uriString),
                    Prefs.rotate(FrameService.this), Prefs.cover(FrameService.this),
                    Prefs.levels(FrameService.this));
            Log.i(TAG, "converted " + uriString + " in " + (System.currentTimeMillis() - t0)
                    + "ms, " + png.length + " bytes");

            cacheKey = key;
            cacheRef[0] = png;
            return png;
        }

        @Override
        public List<String> imageNames() {
            List<String> out = new ArrayList<>();
            for (String uri : Prefs.images(FrameService.this)) {
                out.add(Uri.parse(uri).getLastPathSegment() == null ? uri : Uri.parse(uri).getLastPathSegment());
            }
            return out;
        }

        @Override
        public int intervalSeconds() {
            return Prefs.interval(FrameService.this);
        }
    };

    public static void start(Context c) {
        Intent i = new Intent(c, FrameService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            c.startForegroundService(i);
        } else {
            c.startService(i);
        }
    }

    public static void stop(Context c) {
        c.stopService(new Intent(c, FrameService.class));
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (server == null || !server.isRunning()) {
            // forget the cache when (re)starting, settings may have changed
            cacheKey = "";
            cacheRef[0] = null;

            server = new HttpServerThread(Prefs.port(this), provider);
            server.start();
            running = true;

            acquireLocks();
        }

        String url = Net.frameUrl(this);
        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) {
                NotificationChannel ch = new NotificationChannel(CHANNEL, "Frame server",
                        NotificationManager.IMPORTANCE_LOW);
                ch.setShowBadge(false);
                nm.createNotificationChannel(ch);
            }
            b = new Notification.Builder(this, CHANNEL);
        } else {
            b = new Notification.Builder(this);
        }
        Notification n = b
                .setContentTitle("KPW3 Frame server")
                .setContentText(url)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setOngoing(true)
                .build();

        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
        } else {
            startForeground(1, n);
        }

        return START_STICKY;
    }

    @SuppressWarnings("deprecation")
    private void acquireLocks() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null) {
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "kpw3frame:cpu");
                wakeLock.setReferenceCounted(false);
                wakeLock.acquire();
            }
        } catch (Exception e) {
            Log.w(TAG, "wakelock failed", e);
        }
        try {
            WifiManager wm = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            if (wm != null) {
                wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "kpw3frame:wifi");
                wifiLock.setReferenceCounted(false);
                wifiLock.acquire();
            }
        } catch (Exception e) {
            Log.w(TAG, "wifilock failed", e);
        }
    }

    private void releaseLocks() {
        try {
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
            }
        } catch (Exception ignored) {
        }
        try {
            if (wifiLock != null && wifiLock.isHeld()) {
                wifiLock.release();
            }
        } catch (Exception ignored) {
        }
        wakeLock = null;
        wifiLock = null;
    }

    @Override
    public void onDestroy() {
        running = false;
        if (server != null) {
            server.shutdown();
            server = null;
        }
        releaseLocks();
        super.onDestroy();
    }
}
