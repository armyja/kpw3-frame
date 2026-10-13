# KPW3 Frame

[English](README.md) · **中文**

把越狱的 **Kindle Paperwhite 3** 变成一块电子墨水相框：图片由你自己的服务器提供。

Kindle 用**硬件 RTC 闹钟**把自己唤醒，下载一张图、画上去，然后立刻睡回深度休眠。
墨水屏不耗电就能保持画面，所以一次充电能用好几周；而且取图发生在**屏幕"关着"的时候**，
所以你每次看到的都是最新的那张。

不用云、不用账号、不用一直插着 USB。服务器可以是你电脑上的一个 Python 文件，
也可以是手机上那个 ~45 KB 的 APK（同一个迷你 HTTP 服务，图片转换在手机上做）。

```
   服务器（电脑 或 安卓）                          Kindle Paperwhite 3
   ─────────────────────                          ────────────────────
   GET /health  ->  ok <间隔秒数>   ◀── wall.sh 每次唤醒读一次
   GET /frame   ->  1072×1448 灰度 PNG  ◀── 下载 → 画屏 → 深睡
   GET /list    ->  ["a.jpg", ...]
```

## 目录

- [你会得到什么](#你会得到什么)
- [环境要求](#环境要求)
- [安装：服务器](#安装服务器)
- [安装：Kindle](#安装kindle)
- [配置](#配置)
- [工作原理](#工作原理)
- [实测数据](#实测数据)
- [排障](#排障)
- [设计笔记（最有意思的部分）](#设计笔记最有意思的部分)
- [鸣谢](#鸣谢)
- [许可](#许可)

## 你会得到什么

KUAL 里就两项，别的都没有：

```
Custom Screensaver (KPW3)
 ├ Refresh image now      → 立刻抓一张并按当前设置显示
 └ Start wall display     → 启动自动刷新循环（按一下电源键即停止）
```

其余功能都在 `/mnt/us/screensaver/` 里以脚本形式存在，需要时手动调用
（见[配置](#配置)）。

## 环境要求

| | |
|---|---|
| Kindle | Paperwhite 3（2015，平台 `kindlepw2`），已越狱并装好 **KUAL** 与 **MRPI** |
| 固件 | 在 **5.16.2.1.1** 上开发与实测 |
| 服务器 | 同一 Wi-Fi 下的电脑 / 树莓派（**Python 3.9+ 和 Pillow**），或安卓 APK |
| 可选 | **FBInk**（显示状态提示用，`libkh` 或 KOReader 里自带的那份即可）；以及静态 **`xh`** 二进制——仅当设备没有可用的 `wget` 时才需要 |

屏幕是 1072 × 1448、16 级灰度。两个服务器端都会精确渲染到这个尺寸。

## 安装：服务器

### 方案 A — 电脑 / 树莓派

```bash
pip install -r server/requirements.txt
python server/frame_server.py --pin my-photo.jpg --fit cover --rotate 90
```

把图片放进 `server/images/`，然后双击 `start-server.bat`（Windows）或执行上面的命令。
启动时会打印该用的地址：

```
Kindle should use:  http://192.168.1.50:8000/frame
```

每次访问 `/frame` 返回下一张图，并已转成 1072 × 1448 灰度 + Floyd–Steinberg 抖动。常用参数：

| 参数 | 含义 |
|---|---|
| `--pin 文件名` / `--single` | 永远只返回固定的一张 |
| `--rotate 0\|90\|180\|270` | 裁切前先旋转（设备横放时用 `90`） |
| `--fit cover\|contain` | 铺满屏幕（裁边）或完整显示（留白） |
| `--interval N` | 下发给 Kindle 的刷新间隔（默认 900 秒） |

### 方案 B — 安卓

`android/` 能编出一个 45 KB、**零第三方依赖**的 APK：

```bat
android\build.bat          :: aapt2 → javac → d8 → zipalign → apksigner
adb install -r android\build\kpw3-frame-debug.apk
```

它在前台服务里跑同一套 HTTP 协议，用系统选择器挑图、在手机上完成转换，
还能**通过 USB**（OTG + 存储访问框架）把 Kindle 的 `server.txt` 直接写掉 ——
当你知道手机地址、但 Kindle 还指不到它时特别方便。

## 安装：Kindle

用 USB 拷两个目录过去（Kindle 会作为普通 U 盘出现）：

```
kindle/screensaver/                  →  /mnt/us/screensaver/
kindle/extensions/kpw3-screensaver/  →  /mnt/us/extensions/kpw3-screensaver/
```

安全弹出后，做一次性初始化。等价于（默认没把它放进菜单，因为只需一次）：

```sh
sh /mnt/us/screensaver/enable.sh      # 建立屏保目录软链 + 写入 cron 兜底任务
```

然后让 Kindle 指向你的服务器，三种方式任选：

- 直接编辑 `/mnt/us/screensaver/server.txt`（就一行 URL，插 USB 就能改）；
- 用安卓 App 里的 **Write to Kindle (USB)**；
- 或者在 shell 里 `sh /mnt/us/screensaver/set_server.sh detect`（扫局域网自动找服务器；
  为了把菜单压到两项，它没有放进 KUAL）。

最后 **KUAL → Start wall display** 启动。按一下电源键即停止，Kindle 就恢复成普通阅读器。

## 配置

全部配置都在 `/mnt/us/screensaver/env.sh`，就是个普通 shell 文件，插 USB 就能改。
常改的几项：

| 配置 | 默认 | 含义 |
|---|---|---|
| `FRAME_URL` | `http://192.168.1.50:8000/frame` | 取图地址（APK 或 `set_server.sh` 也会写这里） |
| `WALL_INTERVAL` | `900` | 刷新间隔秒数 —— **会被服务器覆盖** |
| `WALL_WIFI_WAIT` | `240` | 每次唤醒后等 Wi-Fi 和服务器的最长时间 |
| `SLOT_COUNT` | `1` | 保留几个屏保槽位（1 = 更新最快） |
| `SINGLE_IMAGE` | `yes` | 每次同一张，或按槽位轮播 |

**改间隔通常根本不用碰 Kindle。** 服务器通过 `/health` 下发（`ok 900`），循环每次唤醒读一次，
把新值直接写回 `env.sh`，下一轮生效 —— 不用 USB、不用重启。

不在 KUAL 菜单里、但需要时用得上的脚本：

| 脚本 | 作用 |
|---|---|
| `enable.sh` / `disable.sh` | 建立 / 撤销屏保软链（完全可逆） |
| `set_server.sh show\|test\|detect` | 显示 / 测试 / 自动探测服务器地址 |
| `wall.sh stop` | 从 shell 停止循环 |
| `suspend_test.sh` | 设 60 秒 RTC 闹钟 → 挂起 → 屏上报告 PASS/FAIL |
| `diag.sh` | 只读诊断 → `/mnt/us/diag.txt` |

## 工作原理

```
wall.sh（循环）
   ├─ 设一个 WALL_INTERVAL 秒后的 RTC 闹钟      ── 回读校验，设不上就不睡
   ├─ echo mem > /sys/power/state               （深度休眠；墨水屏保持画面）
   ├─ ……闹钟到点，设备恢复……
   ├─ 等服务器可达（/health），顺便把间隔同步进 env.sh
   ├─ fetch.sh：下载 → 写入 1 个槽位（转换是服务器做的）
   ├─ 用 eips -f 画屏（它会等面板刷完）
   └─ 重复，直到你按电源键（提前唤醒 = 退出）
```

系统自带屏保也没被放弃：`enable.sh` 会把 `/usr/share/blanket/screensaver`
指向 `/mnt/us/screensaver/images`，所以设备自己睡下时（或你在循环停止时按电源键）
显示的还是同一张图。另外还有一条 cron（`FETCH_SCHEDULE`）每 10 分钟刷新该目录作为兜底。

## 实测数据

Paperwhite 3 上，**一次"唤醒 → 看到新图"约 7 秒**：

| 阶段 | 耗时 | 说明 |
|---|---|---|
| Wi-Fi 重连 | 2~3 秒 | 休眠时射频是关的，平台决定 |
| 下载 | ~1 秒 | 335 KB，走 Wi-Fi |
| 写屏保槽位 | <0.1 秒 | 之前 20 个槽位要好几秒 —— 所以有了 `SLOT_COUNT=1` |
| `eips -f` 全刷 | 1~2 秒 | 墨水屏物理刷新，省不掉 |

每轮都会把分段耗时写进日志，方便自己对症下药：

```
server reachable after 2s
server asks for 60s (was 900s) -> saving to env.sh
fetched in 3s
painted in 2s
wake-to-sleep prep took 5s
```

续航：刷新之间设备都在深睡，每个间隔只醒一次射频。15 分钟一档的话，一次充电能撑很久。

## 排障

| 现象 | 先看哪里 |
|---|---|
| 点 Start 后没反应 | `logs/wall.log` —— 每一步都有记录 |
| 图一直不变 | 点一次 `Refresh image now`；再到 `logs/fetch.log` 找 `applied the same image to 1 slot(s)` |
| 屏幕又变回 Kindle 界面 | 循环大概率退出了（电源键 = 停止），重新 Start |
| 锁屏上有状态栏残留 | 框架在我们画完之后又重绘了；这是"不接管屏幕"的代价（见下） |
| 画面撕裂/花屏 | 面板在刷新中途被挂起；`draw_final` 用的是会等待的 `eips`，理论上不该再出现 |
| Wi-Fi 一直不回来 | 休眠时射频关闭是正常的；`WALL_WIFI_WAIT`（240 秒）足以应付慢路由 |
| 固件升级后失效 | 重新跑一次 `enable.sh` —— 软链可能被重置 |

## 设计笔记（最有意思的部分）

这些都是踩出来的坑，也是代码为什么长这样：

1. **不要接管屏幕。** 最常见的做法（停掉 Kindle UI → 画图 → 挂起 → 重启 UI）在很多看板项目里都用，
   但在这台设备上最终会**自发重启**：停掉 `lab126_gui` 会让系统电源管理跟挂起对着干，看门狗把设备干掉；
   而且杀掉 UI 会让 `poll_daemons` 开始报警。我们的做法是**完全不碰 UI**，循环只负责"画"，
   靠"挂起"本身让画面停住。代价是唤醒后框架可能把状态栏重绘到我们图上。

2. **图必须自己画。** 系统屏保是框架在 **powerd** 决定休眠时（`goingToScreenSaver`）画的。
   裸 `echo mem > /sys/power/state` 绕过了 powerd，那个事件永远不触发 —— 面板会保持原来的内容。
   所以 `wall.sh` 自己画。

3. **最后一次绘制用 `eips`，不用 `fbink`。** `fbink` 提交完刷新就返回，紧接着挂起会撞在刷新中间，
   屏幕就是花的。`eips` 会等刷新完成。（FBInk 的 `-w` 参数官方文档里并未声明对图片生效。）

4. **设不上闹钟就绝不挂起。** `arm_alarm` 写完 RTC 闹钟会**回读**；值不对就改成普通 sleep。
   没有唤醒源就挂起，就是"必须长按电源键 20 秒"的来源。

5. **醒着的时候也要有保险。** 循环干活期间会挂一个 **300 秒的安全闹钟**，
   这样即使被电源管理中途挂起，设备也能自己醒来接着跑。

6. **只留一个屏保槽位。** 系统渲染器只会从 `/usr/share/blanket/screensaver` 里挑一个文件，
   所以单图模式下 20 个槽位内容完全一样 —— 每次刷新写 20 份纯粹是浪费闪存和几秒时间。
   现在 `SLOT_COUNT=1`，多余的删掉；儿童模式的 `bg_kids_ss*` 保持不动。

7. **间隔由服务器"推"，而不是靠 USB"拉"。** 让服务器成为唯一真源
   （`/health` → `ok <秒数>`，Kindle 写回 `env.sh`）之后，改刷新频率在服务器上点一下就完事；
   以后想下发别的设置，同一个机制直接复用。

8. **"升级"要克制。** 循环默认对 Wi-Fi 完全被动：唤醒后立刻 `wpa_cli reconnect`
   会**把本来好好的链路拆了重连** —— 实测要 21 秒，而被动等待只要 9 秒。
   所以只有在连续 60 秒连不上时才尝试一次。

## 鸣谢

这个项目是站在别人肩膀上的，特别感谢：

- **[pascalw/kindle-dash](https://github.com/pascalw/kindle-dash)**（MIT）——
  "定时从一个 URL 取图、刷新之间深度休眠"这个思路以及循环的雏形都来自它。
  它自带的 `xh`/`next-wakeup` 二进制和 `eips` 绘制在这台设备上没能继续用，
  但架构是它的。
- **[brunomarinho/labs-kindle-artframe](https://github.com/brunomarinho/labs-kindle-artframe)**（MIT）——
  把"为什么必须停掉 GUI 框架才能让挂起生效"讲得最清楚；"提前唤醒 = 按了电源键 → 退出"
  这条规则、以及 FBInk 的用法都参考了它。
- **[jstriblet/kindle-wall-display](https://github.com/jstriblet/kindle-wall-display)** ——
  我们**刻意照搬**了它的几条保险规则：没有回读校验就不挂起、抓图失败保留上一张、
  在把电池交给循环之前先跑一次短"挂起测试"。
- **[jjss520/custom_screensaver](https://github.com/jjss520/custom_screensaver)** ——
  自定义锁屏能成立全靠它那个小技巧：把 `/usr/share/blanket/screensaver` 软链到用户分区。
- **[chengandre/kindle-custom-screensaver](https://github.com/chengandre/kindle-custom-screensaver)** ——
  它的价值恰恰相反：证明了新一代（`kindlehf`）设备需要完全不同的机制，
  从而确认我们走的是 legacy 这条路。
- **[NiLuJe/FBInk](https://github.com/NiLuJe/FBInk)**（GPL-3.0，**未随本项目分发**）——
  Kindle 上最靠谱的绘制工具，上面第 3 条笔记里的 `wait_for_complete` 细节就来自它的文档。
- **[ducaale/xh](https://github.com/ducaale/xh)**（MIT，**未随本项目分发**）——
  当设备没有可用的 `wget` 时，我们用它作为静态 ARM HTTP 客户端兜底。
- **[KindleModding](https://kindlemodding.org/)** —— KUAL/MRPI 安装指南，
  以及 `com.lab126.powerd`、`com.lab126.keyboard`、`com.lab126.pillow` 这些 LIPC 参考页，
  让我们知道该去问什么问题。
- **MobileRead** 论坛与 wiki —— 关于 Kindle 的每个问题那里都有答案，通常来自 2013 年，而且往往依然正确。
- **[mitanshu7/tailscale_kual](https://github.com/mitanshu7/tailscale_kual)**、
  **[bookfere/BookFere-Tools](https://github.com/bookfere/BookFere-Tools)** 以及前面那个
  `kindle-wall-display` —— 让我们看清 KUAL 的 `menu.json`（含子菜单）到底该怎么写。

## 参与开发

这里没有构建系统。Kindle 脚本和 Python 服务器都是"改完就拷"；测试不需要设备：

```bat
tools\syntax_check.bat         :: 用 busybox sh 语法检查所有 Kindle 脚本
tools\sh_test\run_test.bat     :: server_interval / save_interval / ensure_slots
```

```bash
javac -d tools/jvm_test/out android/java/com/kpw3/frame/PngEncoder.java \
      android/java/com/kpw3/frame/Dither.java android/java/com/kpw3/frame/EnvPatcher.java \
      tools/jvm_test/*.java
java -cp tools/jvm_test/out com.kpw3.frame.EnvPatchTest kindle/screensaver/env.sh
java -cp tools/jvm_test/out com.kpw3.frame.PngDitherTest out.png 16
```

安卓端用 `android\build.bat` 编译 —— `aapt2` + `javac` + `d8` + `apksigner`，
不需要 Gradle，也不需要 Android Studio。

## 许可

MIT，见 [LICENSE](LICENSE)。上面提到的第三方工具均未随本仓库分发。
