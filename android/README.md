# KPW3 Frame — Android 服务器 App

把手机变成 Kindle 的图片服务器：App 里选好图片，Kindle 从手机取图当屏保。
和 PC 版**协议完全一致**，所以 Kindle 端**不需要改任何东西**。

```
Android 手机                                    Kindle Paperwhite 3
--------------                                  -------------------
 KPW3 Frame (前台服务)                            /mnt/us/screensaver/*
   ├ /health   -> "ok <秒数>"   <── wall.sh 每次唤醒读一次，把间隔同步进 env.sh
   ├ /frame    -> 1072×1448 灰度 PNG  <── Kindle 的 wall.sh 定时下载
   ├ /list     -> 图片名列表
   └ /interval -> 刷新间隔（秒）
```

## 已构建的成品

```
android/build/kpw3-frame-debug.apk      (~45 KB，debug 签名)
```

安装方式任选：

```bat
adb install -r android\build\kpw3-frame-debug.apk
```

或者把 APK 拷到手机、用文件管理器点开安装（需允许"未知来源"）。

## 使用步骤

1. **打开 App** → 点 **选择图片**（可多选；选完会给持久读取权限）。
2. 设置：**转向**（默认顺时针 90°）、**缩放**（满屏裁边 / 完整留白）、**灰度级数**（默认 16）、
   **端口**（默认 8000）、**Kindle 刷新间隔**、是否多图轮播。
3. 点 **启动服务器**。界面会显示 `http://<手机IP>:8000/frame`，可点 **复制地址**。
   - 界面里的 **Kindle 刷新间隔** 会通过 `/health`（返回 `ok <秒数>`）下发给 Kindle，Kindle 会自己写进 `env.sh` ——
     **改间隔不需要 USB**。
   - 想马上自检：用同一 Wi-Fi 的手机/电脑浏览器打开这个地址，应该看到转好的竖版灰度图。
4. **让 Kindle 指向手机**，两种方式：
   - **USB 写入（推荐）**：用 OTG 线连 Kindle（Kindle 会作为 U 盘出现）→ 点 **写入 Kindle（USB）** →
     选中 **Kindle 盘的根目录**（**也可以直接选 `screensaver` 文件夹本身**）→ App 会写
     `screensaver/server.txt`，并把 `screensaver/env.sh` 的 `WALL_INTERVAL` 改成你设置的间隔
     （写入结果对话框里会显示实际目录，方便核对）；
   - 或者在 Kindle 上手动改 `/mnt/us/screensaver/server.txt`（就一行 URL）。
5. Kindle 上 **KUAL → Start wall display** 即可。

> 手机 IP 变了不用管：重新 USB 写入一次 `server.txt`（或在 Kindle 上改那一行）就行。

## 长时间运行建议

- 把本 App 加入系统的 **电池优化白名单**（否则息屏后可能被系统杀掉）。
- App 内部已经持有 **CPU 唤醒锁 + Wi-Fi 高性能锁**，并以前台服务运行（有常驻通知）。
- 建议插着充电器当"服务器"。
- 若路由器开了 **AP 隔离 / 客户端隔离**，手机和 Kindle 会互相访问不到，需要关掉。

## 源码 / 重新编译

```
android/
  AndroidManifest.xml
  res/                        图标 + 字符串
  java/com/kpw3/frame/
    MainActivity.java         界面、选图、USB 写入
    FrameService.java         前台服务、唤醒锁、图片缓存
    HttpServerThread.java     迷你 HTTP 服务器
    EinkConverter.java        取图→旋转/缩放→灰度
    Dither.java               Floyd-Steinberg 抖动（纯 Java，可单测）
    PngEncoder.java           8 位灰度 PNG 编码器（纯 Java，可单测）
    KindleWriter.java         通过 SAF 写 Kindle 的 server.txt / env.sh
    Prefs.java                设置存储
  build.bat                   一键编译（不需要 Gradle）
```

**不需要 Android Studio / Gradle**：`build.bat` 用本机 SDK 直接走
`aapt2 → javac → d8 → 注入 classes.dex → zipalign → apksigner`。
依赖项只有本机已装的 `C:\Android\build-tools\35.0.0` 与 `platforms\android-34`。

```bat
android\build.bat
```

### 离机验证

图像流水线里**纯 Java 的部分**（抖动 + PNG 编码）可以在电脑上直接跑，已用于自检：

```bat
javac -d tools\jvm_test\out ^
  android\java\com\kpw3\frame\PngEncoder.java ^
  android\java\com\kpw3\frame\Dither.java ^
  tools\jvm_test\PngDitherTest.java
java -cp tools\jvm_test\out com.kpw3.frame.PngDitherTest tools\jvm_test\out.png 16
```

（输出的 PNG 已确认：`mode=L`、`1072×1448`、灰度级数 ≤16。）

`env.sh` 的改写逻辑（`EnvPatcher`）同样可以在电脑上用**真实的 env.sh** 验证：

```bat
javac -d tools\jvm_test\out ^
  android\java\com\kpw3\frame\EnvPatcher.java ^
  tools\jvm_test\EnvPatchTest.java
java -cp tools\jvm_test\out com.kpw3.frame.EnvPatchTest kindle\screensaver\env.sh
```

覆盖：替换 `WALL_INTERVAL`、CRLF→LF 规范化、缺行时追加、幂等性、行数不变。

服务器地址与间隔的解析/回写逻辑（`server_interval` / `save_interval`）也能在电脑上直接验证：

```bat
tools\sh_test\run_test.bat
```

（用真实的可执行 stub 冒充 `wget`，调用 `common.sh` 里的真函数，检查解析与 `env.sh` 回写。）
