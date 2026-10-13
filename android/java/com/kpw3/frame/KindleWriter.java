package com.kpw3.frame;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

/**
 * Writes the frame-server address (and the refresh interval) straight into the
 * Kindle's USB storage using the Storage Access Framework.
 *
 * The user may pick either the Kindle drive root (we then use its
 * "screensaver" child) or the "screensaver" folder itself.
 */
public final class KindleWriter {

    private KindleWriter() {
    }

    public static String apply(Context ctx, Uri treeUri, String serverUrl, int intervalSeconds)
            throws IOException {
        ContentResolver cr = ctx.getContentResolver();
        String pickedId = DocumentsContract.getTreeDocumentId(treeUri);
        String pickedName = displayName(cr, treeUri, pickedId);

        String dirId;
        String where;
        if ("screensaver".equalsIgnoreCase(pickedName)) {
            // The user picked the folder itself.
            dirId = pickedId;
            where = "<选中的 screensaver 目录>";
        } else {
            dirId = findChild(cr, treeUri, pickedId, "screensaver", true);
            if (dirId == null) {
                dirId = findChild(cr, treeUri, pickedId, "screensaver", false);
            }
            if (dirId == null) {
                throw new IOException("在 “" + pickedName + "” 里没有找到 screensaver 目录。\n"
                        + "请选择 Kindle 盘的根目录（或直接选 screensaver 文件夹）。");
            }
            where = pickedName + "/screensaver";
        }

        // --- server.txt -------------------------------------------------
        String serverId = findChild(cr, treeUri, dirId, "server.txt", false);
        Uri serverUri;
        if (serverId == null) {
            Uri parent = DocumentsContract.buildDocumentUriUsingTree(treeUri, dirId);
            serverUri = DocumentsContract.createDocument(cr, parent, "text/plain", "server.txt");
        } else {
            serverUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, serverId);
        }
        if (serverUri == null) {
            throw new IOException("无法创建 " + where + "/server.txt");
        }
        write(cr, serverUri, serverUrl + "\n");

        // --- env.sh : refresh interval ----------------------------------
        String envId = findChild(cr, treeUri, dirId, "env.sh", false);
        String envNote;
        if (envId == null) {
            envNote = "没找到 env.sh（只写了 server.txt）";
        } else {
            Uri envUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, envId);
            String text = read(cr, envUri);
            String patched = patchInterval(text, intervalSeconds);
            if (patched.equals(text)) {
                envNote = "env.sh: WALL_INTERVAL 已经是 " + intervalSeconds;
            } else {
                write(cr, envUri, patched);
                envNote = String.format(Locale.US, "env.sh: WALL_INTERVAL=%d", intervalSeconds);
            }
        }

        return "目录：" + where + "\n\n"
                + "server.txt -> " + serverUrl + "\n"
                + envNote + "\n\n"
                + "（Kindle 上重新 Start 一次 Wall display，或在下次唤醒时生效）";
    }

    /**
     * Replace the WALL_INTERVAL line, appending one when it is missing.
     * Also normalises CRLF to LF, because the Kindle needs LF-only shell files.
     */
    static String patchInterval(String env, int seconds) {
        return EnvPatcher.patchInterval(env, seconds);
    }

    private static String displayName(ContentResolver cr, Uri tree, String docId) {
        Uri doc = DocumentsContract.buildDocumentUriUsingTree(tree, docId);
        String[] cols = {DocumentsContract.Document.COLUMN_DISPLAY_NAME};
        try (Cursor c = cr.query(doc, cols, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                String name = c.getString(0);
                return name == null ? docId : name;
            }
        } catch (Exception ignored) {
        }
        return docId;
    }

    private static String findChild(ContentResolver cr, Uri tree, String parentId, String name,
                                    boolean dirOnly) {
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId);
        String[] cols = {
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
        };
        try (Cursor c = cr.query(children, cols, null, null, null)) {
            if (c == null) {
                return null;
            }
            while (c.moveToNext()) {
                String displayName = c.getString(1);
                String mime = c.getString(2);
                boolean isDir = DocumentsContract.Document.MIME_TYPE_DIR.equals(mime);
                if (!name.equals(displayName)) {
                    continue;
                }
                if (dirOnly && !isDir) {
                    continue;
                }
                if (!dirOnly && isDir) {
                    continue;
                }
                return c.getString(0);
            }
        }
        return null;
    }

    private static String read(ContentResolver cr, Uri doc) throws IOException {
        try (InputStream in = cr.openInputStream(doc)) {
            if (in == null) {
                throw new IOException("cannot read " + doc);
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    private static void write(ContentResolver cr, Uri doc, String text) throws IOException {
        try (OutputStream out = cr.openOutputStream(doc, "wt")) {
            if (out == null) {
                throw new IOException("cannot write " + doc);
            }
            out.write(text.getBytes(StandardCharsets.UTF_8));
            out.flush();
        }
    }
}
