package com.kpw3.frame;

/**
 * Rewrites WALL_INTERVAL in env.sh. Pure Java (no Android APIs) so it can be
 * tested on a normal JVM against the real file the Kindle uses.
 */
public final class EnvPatcher {

    private EnvPatcher() {
    }

    public static String patchInterval(String env, int seconds) {
        String normalised = env.replace("\r\n", "\n").replace("\r", "\n");
        String replacement = "export WALL_INTERVAL=${WALL_INTERVAL:-" + seconds + "}";

        StringBuilder out = new StringBuilder();
        boolean replaced = false;
        String[] lines = normalised.split("\n", -1);
        for (int n = 0; n < lines.length; n++) {
            String line = lines[n];
            if (line.startsWith("export WALL_INTERVAL=")) {
                out.append(replacement);
                replaced = true;
            } else {
                out.append(line);
            }
            if (n < lines.length - 1) {
                out.append('\n');
            }
        }

        if (!replaced) {
            if (out.length() > 0 && out.charAt(out.length() - 1) != '\n') {
                out.append('\n');
            }
            out.append(replacement);
        }
        if (out.length() == 0 || out.charAt(out.length() - 1) != '\n') {
            out.append('\n');
        }
        return out.toString();
    }
}
