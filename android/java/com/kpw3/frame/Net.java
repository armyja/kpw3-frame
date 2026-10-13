package com.kpw3.frame;

import android.content.Context;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.Collections;

/** Works out which LAN address the Kindle should be pointed at. */
public final class Net {

    private Net() {
    }

    public static String lanIp() {
        String fallback = null;
        try {
            for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!ni.isUp() || ni.isLoopback()) {
                    continue;
                }
                for (InetAddress addr : Collections.list(ni.getInetAddresses())) {
                    if (!(addr instanceof Inet4Address) || addr.isLoopbackAddress()) {
                        continue;
                    }
                    String ip = addr.getHostAddress();
                    if (ip.startsWith("192.168.") || ip.startsWith("10.") || ip.startsWith("172.")) {
                        return ip;
                    }
                    if (fallback == null) {
                        fallback = ip;
                    }
                }
            }
        } catch (Exception ignored) {
            // fall through to the loopback address
        }
        return fallback != null ? fallback : "127.0.0.1";
    }

    public static String frameUrl(Context c) {
        return "http://" + lanIp() + ":" + Prefs.port(c) + "/frame";
    }
}
