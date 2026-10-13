package com.kpw3.frame;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.ArrayList;
import java.util.List;

/** Tiny SharedPreferences wrapper. */
public final class Prefs {

    private static final String NAME = "kpw3frame";

    private Prefs() {
    }

    public static SharedPreferences sp(Context c) {
        return c.getSharedPreferences(NAME, Context.MODE_PRIVATE);
    }

    public static int getInt(Context c, String k, int def) {
        return sp(c).getInt(k, def);
    }

    public static void putInt(Context c, String k, int v) {
        sp(c).edit().putInt(k, v).apply();
    }

    public static boolean getBool(Context c, String k, boolean def) {
        return sp(c).getBoolean(k, def);
    }

    public static void putBool(Context c, String k, boolean v) {
        sp(c).edit().putBoolean(k, v).apply();
    }

    public static String getStr(Context c, String k, String def) {
        String v = sp(c).getString(k, def);
        return v == null ? def : v;
    }

    public static void putStr(Context c, String k, String v) {
        sp(c).edit().putString(k, v).apply();
    }

    /** Selected images, one content-URI per line. */
    public static List<String> images(Context c) {
        List<String> out = new ArrayList<>();
        for (String line : getStr(c, "images", "").split("\n")) {
            String t = line.trim();
            if (!t.isEmpty()) {
                out.add(t);
            }
        }
        return out;
    }

    public static void images(Context c, List<String> list) {
        StringBuilder sb = new StringBuilder();
        for (int n = 0; n < list.size(); n++) {
            if (n > 0) {
                sb.append('\n');
            }
            sb.append(list.get(n));
        }
        putStr(c, "images", sb.toString());
    }

    // --- typed settings ---------------------------------------------------

    public static int port(Context c) {
        return getInt(c, "port", 8000);
    }

    public static void port(Context c, int v) {
        putInt(c, "port", v);
    }

    public static int rotate(Context c) {
        return getInt(c, "rotate", 90);
    }

    public static void rotate(Context c, int v) {
        putInt(c, "rotate", v);
    }

    public static boolean cover(Context c) {
        return getBool(c, "cover", true);
    }

    public static void cover(Context c, boolean v) {
        putBool(c, "cover", v);
    }

    public static int levels(Context c) {
        return getInt(c, "levels", 16);
    }

    public static void levels(Context c, int v) {
        putInt(c, "levels", v);
    }

    public static boolean rotateMode(Context c) {
        return getBool(c, "rotateMode", false);
    }

    public static void rotateMode(Context c, boolean v) {
        putBool(c, "rotateMode", v);
    }

    public static int interval(Context c) {
        return getInt(c, "interval", 900);
    }

    public static void interval(Context c, int v) {
        putInt(c, "interval", v);
    }
}
