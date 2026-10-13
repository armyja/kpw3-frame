package com.kpw3.frame;

/**
 * Floyd-Steinberg dithering to N grey levels. Pure Java (no Android APIs) so it
 * can be unit-tested on a plain JVM.
 */
public final class Dither {

    private Dither() {
    }

    /** @return a new array with values quantised to {@code levels} grey steps. */
    public static byte[] floydSteinberg(byte[] gray, int width, int height, int levels) {
        int lv = Math.max(2, Math.min(256, levels));
        int step = 255 / (lv - 1);

        int[] buf = new int[gray.length];
        for (int n = 0; n < gray.length; n++) {
            buf[n] = gray[n] & 0xFF;
        }

        for (int y = 0; y < height; y++) {
            int row = y * width;
            for (int x = 0; x < width; x++) {
                int idx = row + x;
                int old = buf[idx];
                int q;
                if (old <= 0) {
                    q = 0;
                } else if (old >= 255) {
                    q = 255;
                } else {
                    q = Math.round((float) old / step) * step;
                    if (q > 255) {
                        q = 255;
                    }
                }
                int err = old - q;
                buf[idx] = q;

                if (x + 1 < width) {
                    buf[idx + 1] += (err * 7) >> 4;
                }
                if (y + 1 < height) {
                    if (x > 0) {
                        buf[idx + width - 1] += (err * 3) >> 4;
                    }
                    buf[idx + width] += (err * 5) >> 4;
                    if (x + 1 < width) {
                        buf[idx + width + 1] += (err * 1) >> 4;
                    }
                }
            }
        }

        byte[] out = new byte[gray.length];
        for (int n = 0; n < gray.length; n++) {
            int v = buf[n];
            out[n] = (byte) (v < 0 ? 0 : (v > 255 ? 255 : v));
        }
        return out;
    }
}
