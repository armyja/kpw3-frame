package com.kpw3.frame;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.zip.CRC32;
import java.util.zip.Deflater;

/** Minimal 8-bit greyscale PNG encoder (no alpha, no interlace, filter 0). */
public final class PngEncoder {

    private PngEncoder() {
    }

    public static byte[] encodeGray(byte[] gray, int width, int height) throws IOException {
        ByteArrayOutputStream raw = new ByteArrayOutputStream((width + 1) * height);
        for (int y = 0; y < height; y++) {
            raw.write(0); // filter type: none
            raw.write(gray, y * width, width);
        }

        byte[] compressed = deflate(raw.toByteArray());

        ByteArrayOutputStream out = new ByteArrayOutputStream(compressed.length + 64);
        out.write(new byte[]{(byte) 0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n'});

        ByteArrayOutputStream ihdr = new ByteArrayOutputStream(13);
        writeInt(ihdr, width);
        writeInt(ihdr, height);
        ihdr.write(8); // bit depth
        ihdr.write(0); // colour type: greyscale
        ihdr.write(0); // compression
        ihdr.write(0); // filter
        ihdr.write(0); // interlace
        chunk(out, "IHDR", ihdr.toByteArray());
        chunk(out, "IDAT", compressed);
        chunk(out, "IEND", new byte[0]);
        return out.toByteArray();
    }

    private static void chunk(ByteArrayOutputStream out, String type, byte[] data) throws IOException {
        writeInt(out, data.length);
        byte[] t = type.getBytes("US-ASCII");
        out.write(t);
        out.write(data);
        CRC32 crc = new CRC32();
        crc.update(t);
        crc.update(data);
        writeInt(out, (int) crc.getValue());
    }

    private static void writeInt(ByteArrayOutputStream out, int v) {
        out.write((v >>> 24) & 0xFF);
        out.write((v >>> 16) & 0xFF);
        out.write((v >>> 8) & 0xFF);
        out.write(v & 0xFF);
    }

    private static byte[] deflate(byte[] data) {
        Deflater deflater = new Deflater(Deflater.BEST_COMPRESSION);
        try {
            deflater.setInput(data);
            deflater.finish();
            ByteArrayOutputStream out = new ByteArrayOutputStream(data.length / 2 + 64);
            byte[] buf = new byte[65536];
            while (!deflater.finished()) {
                int n = deflater.deflate(buf);
                out.write(buf, 0, n);
            }
            return out.toByteArray();
        } finally {
            deflater.end();
        }
    }
}
