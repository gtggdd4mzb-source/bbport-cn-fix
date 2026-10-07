# 卡顿与崩溃：实测记录与缓解手段

## 一、先量化，别凭感觉调

开启 `BB_FRAME_STATS=1` 后，日志会周期性输出真实帧时数据：

```
Frame stats: 59.8 FPS, worst frame 46.0 ms (vblank 60 Hz); 0 shader/pipeline compiles, 0.0 ms;
  600 recorder syncs; 125 write faults/s, 0 hot pages; GPU thread 0.00 us/draw, 14 draws/frame,
  idle 94.2%; blocked: recorder 0.4%, host copies 0.5% (1/frame), copy threads 0.0%, GPU ticks 0.1%
Frame pacing: median 16.66 ms, stddev 1.93 ms, p99 17.90 ms, 1 frames over 1.5x median
```

**安静场景基线**：59.8 FPS、中位数 16.66 ms、标准差 1.93 ms、p99 17.90 ms
（60 帧理论帧时 16.67 ms）——帧节奏实际上是**很干净**的。

**关键读数：`GPU thread … idle 94.2%`** ——GPU 线程 94% 时间在空转，同时
GPU 占用率只有 30~58%、CPU 未饱和。**说明瓶颈在 CPU 端模拟与同步，不在显卡。**
所以"继续降画质/分辨率"对这类卡顿无效。

## 二、帧率腰斩的真正来源（上游 issue #30）

`ObjectMotion::EnsureImage()` 在 motion 向量图像尺寸与请求尺寸不一致时，
会调用 `Scheduler::Finish()` —— **整设备排空**：

```cpp
void ObjectMotion::EnsureImage(u32 width, u32 height) {
    if (image && width == image_width && height == image_height) return;
    if (image) scheduler.Finish();   // ← 每次尺寸翻转就排空整个设备
    ...
}
```

亚楠下水道的水面，其 motion 向量绘制散布在**不同尺寸的 pass** 里，尺寸每帧来回翻转，
于是排空落在关键路径上。上游报告者的对照实测（同机同场景，只改一个开关）：

| 指标 | `BB_OBJECT_MOTION=1` | `BB_OBJECT_MOTION=0` |
|---|---|---|
| FPS 中位数 | 39.8 | **66.5** |
| 帧时中位数 | 25.46 ms，标准差 1.13 ms | **14.72 ms，标准差 0.84 ms** |
| 每帧 GPU 耗时 | 26.07 ms | 15.11 ms |
| 两次提交之间 GPU 空闲 | 10.6 ~ 11.3 ms/帧 | **0.36 ~ 0.43 ms/帧** |
| GPU ticks（命令线程阻塞） | 52.0% | **14.8%** |

### 怎么关掉
**`upscaler=off` 就自动关掉了**——`ObjectMotion` 在 `upscaler != off` 时自动启用。
日志里确认：
```
Object motion: off (enable in menu or BB_OBJECT_MOTION=1)
Upscaler: FSR 3.1 available (off)
```
因为 720p 输出下 FSR 缩放比例本就是 1.0（空转），关掉**没有画质损失**。
也可显式加 `BB_OBJECT_MOTION=0` 双保险。

## 三、`Out of order flip IRQ` 断言（上游 PR #5039）

这是 shadPS4 的著名竞态，全 GitHub 有 40+ 个 issue 提到它。根因原文：

> 断言触发是因为 **GfxFlip 回调（经 IrqC 注册）和触发它的命令缓冲（经 Liverpool 入队）
> 位于两个独立的 FIFO、没有共享锁，所以当 flip 从多个线程提交时，两者的相对顺序会漂移。**

**推论**：bbport 默认 **"在独立线程上呈现"**（present on its own thread）
—— 这正是"从多个线程提交 flip"。设 `BB_PRESENT_THREAD=0` 回到**单线程呈现**路径。

```
[Debug] <Critical> video_out.cpp:354 operator(): Assertion Failed!
Out of order flip IRQ
STOP: GPU library assertion failed
```

上游已在 **PR #5043** 修复该断言（PR #5140 的说明中确认），但 bbport 是独立 HLE 实现，
是否同步了该修复未知。

## 四、崩溃后必须清缓存（上游 issue #3）

一次致命错误（哪怕是有 `STOP:` 标记的受控断言）**会污染序列化管线缓存**
（`user\cache\<TITLE_ID>\`）。之后**每一次**启动都会以一个完全无关的错误失败：

```
GPU [Debug] <Critical> vk_graphics_pipeline.cpp:426 GraphicsPipeline: Assertion Failed!
Failed to create graphics pipeline: ErrorUnknown
```

上游报告者用三套完全不同的配置跑出**逐字节相同**的日志才定位到这一点。
**极易误诊为"新 bug"**。修法：删掉 `user\cache\<TITLE_ID>\` 即可恢复正常。

上游这位报告者的启动器现在会在**退出码 ≥128** 时自动清缓存，
本仓库的 `launchers\智能启动-崩溃自动恢复.cmd` 采用了同样做法。

## 五、一次完整会话的实测分布

315 次采样（约十几分钟游玩，`BB_FPS=60`）：

| 指标 | 值 |
|---|---|
| 平均 / 中位 FPS | 57.8 / 59.4 |
| 最高 / 最低 | 59.8 / 35.7 |
| 低于 55 帧的采样占比 | **13.3%** |

即：**大部分时间稳定 60 帧，但约 1/7 的时间仍在掉帧**，最低到 35.7。

## 六、为什么这些缓解不能根治

- GPU 线程空闲 92~95%，说明瓶颈在 CPU 侧模拟/同步，靠画质设置动不了。
- 上游仍有大量未合并的修复（含前述 `ObjectMotion` 的正确修法、纹理缓存驱逐等）。
- 上游报告：NVIDIA 机器每 6~45 分钟可能因真实 GPU 引擎超时（bugcheck 0x141）崩溃。
- 部分区域（水域、下水道）即使关掉对象运动仍偏低。

**结论：这是一套"降低发生率"的配置，不是修复。**
