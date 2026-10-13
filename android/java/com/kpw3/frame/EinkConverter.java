package com.kpw3.frame;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.RectF;
import android.net.Uri;

import java.io.IOException;
import java.io.InputStream;

/**
 * Turns any picture into what the Kindle wants: 1072x1448, 8-bit greyscale,
 * Floyd-Steinberg dithered - the same output the PC server produced.
 */
public final class EinkConverter {

    public static final int WIDTH = 1072;
    public static final int HEIGHT = 1448;

    private EinkConverter() {
    }

    public static byte[] toEinkPng(Context ctx, Uri uri, int rotateDeg, boolean cover, int levels)
            throws IOException {
        Bitmap src;
        try (InputStream in = ctx.getContentResolver().openInputStream(uri)) {
            if (in == null) {
                throw new IOException("cannot open " + uri);
            }
            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inPreferredConfig = Bitmap.Config.ARGB_8888;
            src = BitmapFactory.decodeStream(in, null, o);
        }
        if (src == null) {
            throw new IOException("cannot decode " + uri);
        }

        if (rotateDeg % 360 != 0) {
            Matrix m = new Matrix();
            m.postRotate(rotateDeg);
            Bitmap rotated = Bitmap.createBitmap(src, 0, 0, src.getWidth(), src.getHeight(), m, true);
            src.recycle();
            src = rotated;
        }

        Bitmap target = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(target);
        canvas.drawColor(Color.WHITE);

        float sx = (float) WIDTH / src.getWidth();
        float sy = (float) HEIGHT / src.getHeight();
        float scale = cover ? Math.max(sx, sy) : Math.min(sx, sy);
        float dw = src.getWidth() * scale;
        float dh = src.getHeight() * scale;
        float left = (WIDTH - dw) / 2f;
        float top = (HEIGHT - dh) / 2f;

        Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.DITHER_FLAG);
        canvas.drawBitmap(src, null, new RectF(left, top, left + dw, top + dh), paint);
        src.recycle();

        int[] px = new int[WIDTH * HEIGHT];
        target.getPixels(px, 0, WIDTH, 0, 0, WIDTH, HEIGHT);
        target.recycle();

        byte[] gray = new byte[px.length];
        for (int n = 0; n < px.length; n++) {
            int v = px[n];
            int r = (v >> 16) & 0xFF;
            int g = (v >> 8) & 0xFF;
            int b = v & 0xFF;
            gray[n] = (byte) ((r * 299 + g * 587 + b * 114) / 1000);
        }

        return PngEncoder.encodeGray(Dither.floydSteinberg(gray, WIDTH, HEIGHT, levels), WIDTH, HEIGHT);
    }
}
