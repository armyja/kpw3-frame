package com.kpw3.frame;

import java.io.FileOutputStream;

/**
 * Runs the pure-Java part of the image pipeline (dithering + PNG encoding) on a
 * normal JVM, so it can be checked without a phone.
 *
 * Usage: PngDitherTest <out.png> [levels]
 */
public class PngDitherTest {

    public static void main(String[] args) throws Exception {
        int w = 1072;
        int h = 1448;
        int levels = args.length > 1 ? Integer.parseInt(args[1]) : 16;

        byte[] gray = new byte[w * h];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                // smooth radial gradient plus two flat patches, so banding and
                // dithering artefacts are both visible
                double d = Math.hypot(x - w / 2.0, y - h / 2.0);
                int v = (int) Math.max(0, Math.min(255, 255 - d / 6));
                if (x > w * 0.62 && y > h * 0.55) {
                    v = 200;
                }
                if (x < w * 0.25 && y < h * 0.25) {
                    v = 40;
                }
                gray[y * w + x] = (byte) v;
            }
        }

        byte[] png = PngEncoder.encodeGray(Dither.floydSteinberg(gray, w, h, levels), w, h);
        try (FileOutputStream out = new FileOutputStream(args[0])) {
            out.write(png);
        }
        System.out.println("wrote " + args[0] + " (" + png.length + " bytes, " + levels + " levels)");
    }
}
