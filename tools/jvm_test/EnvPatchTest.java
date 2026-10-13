package com.kpw3.frame;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Checks EnvPatcher against the real env.sh the Kindle uses.
 *
 * Usage: EnvPatchTest <path-to-env.sh>
 */
public class EnvPatchTest {

    private static int failures = 0;

    public static void main(String[] args) throws Exception {
        Path real = Paths.get(args[0]);
        String env = new String(Files.readAllBytes(real), StandardCharsets.UTF_8);

        System.out.println("== real env.sh ==");
        String patched = EnvPatcher.patchInterval(env, 123);
        System.out.println("  WALL_INTERVAL line before: " + line(env, "export WALL_INTERVAL="));
        System.out.println("  WALL_INTERVAL line after : " + line(patched, "export WALL_INTERVAL="));
        check("interval replaced", line(patched, "export WALL_INTERVAL=").contains("123"));
        check("no CR anywhere", !patched.contains("\r"));
        check("ends with newline", patched.endsWith("\n"));
        check("no double trailing newline", !patched.endsWith("\n\n\n"));
        check("kept another line", patched.contains("export FETCH_SCHEDULE="));
        check("line count unchanged", count(patched) == count(env));

        // CRLF input must come out as LF with the same value
        String crlf = env.replace("\n", "\r\n");
        String patchedCrlf = EnvPatcher.patchInterval(crlf, 600);
        check("CRLF -> LF", !patchedCrlf.contains("\r"));
        check("CRLF value", line(patchedCrlf, "export WALL_INTERVAL=").contains("600"));

        // a file without the line must get one appended
        String simple = "A=1\nB=2\n";
        String appended = EnvPatcher.patchInterval(simple, 42);
        check("appended", appended.contains("export WALL_INTERVAL=${WALL_INTERVAL:-42}"));
        check("appended keeps A=1", appended.startsWith("A=1\nB=2\n"));

        // apply twice -> idempotent
        String twice = EnvPatcher.patchInterval(patched, 123);
        check("idempotent", twice.equals(patched));

        System.out.println(failures == 0 ? "\nALL CHECKS PASSED" : "\n" + failures + " CHECK(S) FAILED");
        if (failures > 0) {
            System.exit(1);
        }
    }

    private static int count(String s) {
        int n = 0;
        for (int i = 0; i < s.length(); i++) {
            if (s.charAt(i) == '\n') {
                n++;
            }
        }
        return n;
    }

    private static String line(String text, String prefix) {
        for (String l : text.split("\n")) {
            if (l.startsWith(prefix)) {
                return l;
            }
        }
        return "(not found)";
    }

    private static void check(String name, boolean ok) {
        System.out.println((ok ? "  [ok]   " : "  [FAIL] ") + name);
        if (!ok) {
            failures++;
        }
    }
}
