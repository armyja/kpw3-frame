package com.kpw3.frame;

import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * A very small HTTP/1.0 server, protocol compatible with the PC one:
 *
 *   GET /health    -> "ok"            (used by the Kindle's Auto-detect)
 *   GET /frame     -> the e-ink PNG   (what the Kindle downloads)
 *   GET /list      -> JSON list of selected picture names
 *   GET /interval  -> refresh interval in seconds (plain text)
 */
public final class HttpServerThread extends Thread {

    public interface Provider {
        byte[] framePng() throws Exception;

        List<String> imageNames();

        int intervalSeconds();
    }

    private final int port;
    private final Provider provider;

    private volatile boolean running = true;
    private ServerSocket serverSocket;

    public HttpServerThread(int port, Provider provider) {
        this.port = port;
        this.provider = provider;
        setName("kpw3-http");
        setDaemon(true);
    }

    public boolean isRunning() {
        return running;
    }

    public void shutdown() {
        running = false;
        try {
            if (serverSocket != null) {
                serverSocket.close();
            }
        } catch (IOException ignored) {
            // closing is best effort
        }
    }

    @Override
    public void run() {
        try {
            serverSocket = new ServerSocket();
            serverSocket.setReuseAddress(true);
            serverSocket.bind(new InetSocketAddress(port), 32);
        } catch (IOException e) {
            running = false;
            return;
        }

        while (running) {
            try {
                final Socket client = serverSocket.accept();
                Thread worker = new Thread(() -> handle(client));
                worker.setDaemon(true);
                worker.start();
            } catch (IOException e) {
                if (!running) {
                    break;
                }
            }
        }
    }

    private void handle(Socket client) {
        try (Socket s = client) {
            s.setSoTimeout(15000);
            BufferedReader in = new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.US_ASCII));
            String requestLine = in.readLine();
            if (requestLine == null) {
                return;
            }
            // drain headers
            String line;
            while ((line = in.readLine()) != null && !line.isEmpty()) {
                // ignore
            }

            String path = "/";
            String[] parts = requestLine.split(" ");
            if (parts.length > 1) {
                path = parts[1];
            }
            int q = path.indexOf('?');
            if (q >= 0) {
                path = path.substring(0, q);
            }
            if (path.length() > 1 && path.endsWith("/")) {
                path = path.substring(0, path.length() - 1);
            }

            if (path.equals("/health")) {
                // "ok" plus the refresh interval the Kindle should use.
                sendText(s, 200, "ok " + provider.intervalSeconds());
            } else if (path.equals("/interval")) {
                sendText(s, 200, String.valueOf(provider.intervalSeconds()));
            } else if (path.equals("/list")) {
                StringBuilder sb = new StringBuilder("[");
                List<String> names = provider.imageNames();
                for (int n = 0; n < names.size(); n++) {
                    if (n > 0) {
                        sb.append(',');
                    }
                    sb.append('"').append(names.get(n).replace("\"", "\\\"")).append('"');
                }
                sb.append(']');
                sendText(s, 200, sb.toString());
            } else if (path.equals("/") || path.equals("/frame") || path.equals("/frame.png") || path.equals("/next")) {
                byte[] png;
                try {
                    png = provider.framePng();
                } catch (Exception e) {
                    png = null;
                }
                if (png == null || png.length == 0) {
                    sendText(s, 404, "no image selected");
                } else {
                    sendBytes(s, 200, "image/png", png);
                }
            } else {
                sendText(s, 404, "not found");
            }
        } catch (IOException ignored) {
            // client went away
        }
    }

    private static void sendText(Socket s, int code, String body) throws IOException {
        sendBytes(s, code, "text/plain; charset=utf-8", body.getBytes(StandardCharsets.UTF_8));
    }

    private static void sendBytes(Socket s, int code, String contentType, byte[] body) throws IOException {
        OutputStream out = new BufferedOutputStream(s.getOutputStream());
        String head = "HTTP/1.0 " + code + (code == 200 ? " OK" : " Error") + "\r\n"
                + "Content-Type: " + contentType + "\r\n"
                + "Content-Length: " + body.length + "\r\n"
                + "Cache-Control: no-store\r\n"
                + "Connection: close\r\n"
                + "\r\n";
        out.write(head.getBytes(StandardCharsets.US_ASCII));
        out.write(body);
        out.flush();
    }
}
