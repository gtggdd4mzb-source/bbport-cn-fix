# bbport Windows 版 · 中文系统修复 + 低显存稳定配置

> **本仓库不含任何游戏文件，也不含上游的二进制发行包。**
> 它是 **补丁 + 配置 + 文档**，用来让
> [Supermedo/bloodborne_pc](https://github.com/Supermedo/bloodborne_pc)
> （[deadinside28/bloodborne_pc](https://github.com/deadinside28/bloodborne_pc) 的 Windows 分支）
> 在 **中文区域设置的 Windows** 上能正常启动，并在 **4GB 显存** 的笔记本显卡上稳定运行。

> [!IMPORTANT]
> **上游进展：** 问题一的启动崩溃已报告给上游，且是**该 bug 的首次报告** ——
> [deadinside28/bloodborne_pc#55](https://github.com/deadinside28/bloodborne_pc/issues/55)。
> 在该 issue 被修复并合并之前，请使用本仓库的补丁。

## 三个问题与本仓库的做法

| # | 问题 | 症状 | 做法 |
|---|---|---|---|
| 1 | 中文 Windows 下 **100% 启动失败** | `prepare failed: 'gbk' codec can't encode character '\u2122'` | [`patches/`](patches) 6 个脚本共 12 处编码修复 |
| 2 | 4GB 显存 **爆显存** | 玩 1~2 分钟后进程消失，日志刷 `memory pressure … 0 images evicted` | [`config/bbport.ini`](config/bbport.ini)：720p + 关特效 + 降 LOD |
| 3 | 帧率被腰斩 / 偶发崩溃 | 水域等区域掉到 40 帧、`Out of order flip IRQ` 断言 | [`launchers/`](launchers) 内置 `BB_PRESENT_THREAD=0` + `BB_OBJECT_MOTION=0` |

## 快速开始

前置：Windows 10 1903+ / 11 64 位、显卡驱动含 **Vulkan 1.3**、以及你自己的
Bloodborne 本体 dump（`param.sfo` 的 `APP_VER` = **01.09**）。**本仓库不提供游戏本体。**

1. 从上游 release 下载 `Bloodborne-Windows.zip`（windows-v1.4 实测）并解压到任意目录，
   得到 `bbport-windows\`。
2. **应用编码补丁**（二选一）：
   ```powershell
   # 方式 A：一键脚本（推荐）
   powershell -ExecutionPolicy Bypass -File .\apply.ps1 -PortDir "D:\path\to\bbport-windows"

   # 方式 B：标准补丁（便于审查改动）
   cd D:\path\to\bbport-windows
   git init; git add scripts; git commit -m base
   git apply -p1 D:\bbport-cn-fix\patches\0001-windows-chinese-locale-utf8.patch
   ```
3. 把 `config\bbport.ini` 复制到 `bbport-windows\`（覆盖同名文件，若有）。
4. 把 `launchers\*.cmd` 复制到 `bbport-windows\`，**打开任一启动器改掉 `BB_GAME_DIR`**，
   指向你本体里含 `eboot.bin` 的那一层，然后双击启动。

---

## 问题一：中文 Windows 下必崩

### 症状
```
prepare failed: 'gbk' codec can't encode character '\u2122' in position 919: illegal multibyte sequence
```

### 根因（三层，缺一不可）
1. **PyInstaller 冻结的 `Bloodborne.exe` 完全忽略 `PYTHONUTF8` / `PYTHONIOENCODING`。**
   实测 `sys.flags.utf8_mode == 0`、`locale.getpreferredencoding(False) == 'cp936'`、
   `sys.stdout.encoding == 'gbk'` —— 即使显式设了这两个环境变量也一样。
2. **`prepare.py` 写 JSON 时没指定编码**：
   ```python
   (out / 'analysis.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
   ```
   `write_text()` 不传 `encoding` 就用 locale 默认编码 = 中文系统上的 **GBK**，
   而这份 JSON 里含游戏标题 `Bloodborne™ The Old Hunters Edition` 的 **™（U+2122）**，
   GBK 编不出来 → 抛异常 → 整个管线中断。
3. 同一份数据还会被 `print()` 到 stdout（也是 GBK），同样会炸。

上游作者在 Linux 上默认 UTF-8，所以从未遇到。

### 修复（12 处，见 `patches/`）
- **5 个脚本**（`prepare.py` / `link_libc.py` / `link_modules.py` / `content_profile.py` / `patches.py`）
  在 import 区插入 stdout/stderr 重设：
  ```python
  import sys as _bb_sys
  try:
      _bb_sys.stdout.reconfigure(encoding='utf-8', errors='replace')
      _bb_sys.stderr.reconfigure(encoding='utf-8', errors='replace')
  except Exception:
      pass
  ```
- **7 处补 `encoding='utf-8'`**：`prepare.py` / `content_profile.py` / `link_libc.py` /
  `link_modules.py` 的 JSON 写入，以及 `mods.py` / `patches.py` 的文本读取。

### ⚠️ 一个必须注意的坑：`mods.py` 不能改 stdout 编码
`run.py` 用 `subprocess.run(..., text=True)` **以 locale 编码（cp936）解码 `mods.py` 的输出，
并把它当作路径使用**。如果给 `mods.py` 的 stdout 改成 UTF-8，中文路径会在这一轮往返里被解坏。
所以本补丁**故意不修改 `mods.py` 的 stdout**，只给它补了 `read_text(encoding='utf-8')`。

### 上游状态
这是一条真正的 bug，建议直接提给上游（见 [UPSTREAM-PR.md](UPSTREAM-PR.md)，已备好可直接粘贴的英文报告）。

---

## 问题二：4GB 显存爆显存

`bbport.ini` 的 `output_res` 默认 `1920x1080`，而 `preset=0` 时
`scaled_sizes()` 会直接返回 `None`（因为 `out == OUTPUT_SIZE`），**降分辨率渲染根本不启用**
——游戏以**原生 1080p** 渲染。4GB 显存下表现为：

```
Texture cache: memory pressure, 3469 of 1536 MiB (critical 3072): 0 images evicted, 0 written back
== Stall during rendering at flush 1876
```

之后进程消失（不是崩溃，是内存耗尽被终止；Windows 事件日志里只有
`RADAR_PRE_LEAK_64` 内存泄漏启发式，没有 Application Error）。

改 `output_res=1280x720` 后：纹理缓存压力报告从 28 次降到 **0 次**，
显存占用从"冲到 3469 MiB"降到 **1614~1657 / 4096 MiB**。

详见 [docs/low-vram-4gb.md](docs/low-vram-4gb.md)。

---

## 问题三：卡顿与崩溃（缓解，非根治）

### `upscaler=off` 顺带修掉帧率腰斩
`ObjectMotion` **会在 `upscaler != off` 时自动启用**（上游 issue #39 实测）。
而 `ObjectMotion::EnsureImage()` 在尺寸变化时调用 `Scheduler::Finish()`（**整设备排空**），
让 CPU 和 GPU 严格串行。上游 issue #30 的对照实测：

| 指标 | ObjectMotion 开 | 关 |
|---|---|---|
| 水域 FPS 中位数 | 39.8 | **66.5** |
| 帧时中位数 | 25.46 ms | **14.72 ms** |
| GPU 空闲/帧 | 10.6–11.3 ms | **0.36–0.43 ms** |

因为 720p 输出下 FSR 缩放比例本就是 1.0（空转），关掉 `upscaler` **没有任何画质损失**。

### `BB_PRESENT_THREAD=0` 规避 flip IRQ 竞态
`Out of order flip IRQ` 是 shadPS4 的著名竞态断言。上游 PR #5039 的原文解释：

> 断言触发是因为 **GfxFlip 回调（经 IrqC 注册）和触发它的命令缓冲（经 Liverpool 入队）
> 位于两个独立的 FIFO、没有共享锁，所以当 flip 从多个线程提交时，两者的相对顺序会漂移。**

bbport 默认 **"在独立线程上呈现"** = 多线程提交 flip，正是竞态前提；
`BB_PRESENT_THREAD=0` 回到单线程呈现路径。上游已在 PR #5043 修复该断言，但 bbport 是否同步了未知。

### 崩溃后必须清缓存
上游 issue #3 记录：**一次致命错误会污染序列化管线缓存**，之后每次启动都以一个
完全无关的错误失败（`Failed to create graphics pipeline: ErrorUnknown`），
极易误诊为"新 bug"。所以 `launchers/智能启动-崩溃自动恢复.cmd`
在退出码 ≥128 时会自动清掉 `user\cache` 再重启。

详见 [docs/stutter-and-crashes.md](docs/stutter-and-crashes.md)。

---

## 已知限制（诚实声明）

这是 **2026-10-01 才出现的、发布仅数日的 beta 软件**，上游有大量未合并的崩溃修复。
本仓库的配置**只能降低**下面这些问题的发生频率，**不能消除**：

1. **死亡（YOU DIED）是最可靠的崩溃触发点**：游戏会重初始化角色/布料子系统并重载地图纹理，
   而纹理缓存**无法驱逐 tiled 的 GPU 写入图像**（`if (tiled && download) return false;`）
   → 一次性分配失败 → `ErrorOutOfDeviceMemory`。上游报告者在 5GB 卡上称之为"接近抛硬币"。
   **4GB 更低。降分辨率只降低频率。**
2. 偶发 `Out of order flip IRQ`。
3. 上游报告：NVIDIA 机器每 6~45 分钟可能因 GPU 引擎超时（bugcheck 0x141）崩溃。
4. 部分区域仍会掉到 40 帧上下（实测 315 次采样：平均 57.8、中位 59.4、最低 35.7，
   13.3% 的采样低于 55 帧）。

> 若目标是**通关**而不是折腾移植版，成熟得多的 **shadPS4**（血源是其招牌游戏）通常是更稳的选择；
> 但它属于另一条技术路线（CPU 侧模拟），不在本仓库范围内。

## 上游问题索引（本仓库结论的依据）

| 来源 | 内容 |
|---|---|
| deadinside28/bloodborne_pc **issue #30** | Object motion 每帧 `Scheduler::Finish()` 让水域帧率腰斩；含 CPU/GPU 对照实测表 |
| deadinside28/bloodborne_pc **issue #31** | 最小化窗口（Win+D）导致 0x0 swapchain extent → 会话结束 |
| deadinside28/bloodborne_pc **issue #39** | 纹理缓存无法驱逐 tiled 图像（低显存卡必踩）；致命错误污染管线缓存；`BB_VK_RECORD_THREAD=0` 顶点爆炸 |
| deadinside28/bloodborne_pc **issue #44** | 0.3 起天空盒闪烁（未修复） |
| deadinside28/bloodborne_pc **PR #6** | Windows 移植主体；记录纹理缓存 stale 上传导致的黑/白剪影 |
| shadps4-emu/shadPS4 **PR #5039** | `Out of order flip IRQ` 竞态根因（双 FIFO 无共享锁） |
| shadps4-emu/shadPS4 **PR #5140** | 注明该断言已在 **#5043** 修复 |

## 许可与归属

- 上游代码：[deadinside28/bloodborne_pc](https://github.com/deadinside28/bloodborne_pc)（**GPL-2.0**）
  与 [Supermedo/bloodborne_pc](https://github.com/Supermedo/bloodborne_pc)（Windows 分支，**GPL-2.0**）。
- 本仓库的补丁是针对上述代码的**修改**，因此同样以 **GPL-2.0** 发布，见 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md)。
- **本仓库与上游作者无任何隶属关系**，也不是官方发布。
- 不包含任何游戏文件；请自行准备你合法拥有的本体 dump。
