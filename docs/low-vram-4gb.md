# 4GB 显存问题：完整实测记录

## 症状（默认配置）
游玩 1~2 分钟后**进程消失**。Windows 事件日志里**没有** Application Error / WER 崩溃记录，
只有一个 `RADAR_PRE_LEAK_64`（内存泄漏启发式，非崩溃）——所以是**内存耗尽被终止**，不是崩溃。

日志停滞在：
```
Texture cache: memory pressure, 3469 of 1536 MiB (critical 3072): 0 images evicted, 0 written back since the last report
== Stall during rendering at flush 1876
HLE thread: join failed (thread::join failed: No such device or address); waiting for it to finish
```

纹理缓存目标 1536 MiB，实际冲到 **3469 MiB（超 2.2 倍）**，且**一张都没能驱逐**。

## 根因（一个容易被忽略的组合）
`bbport.ini` 的 `output_res` 默认 `1920x1080`，而 `scripts/patches.py` 的：

```python
def scaled_sizes(settings):
    out = output_size(settings)
    if out == OUTPUT_SIZE or settings.get('upscaler') == 'taa':
        return None          # ← 1080p 时直接返回 None
```

`OUTPUT_SIZE = (1920, 1080)`。也就是说 **1080p 输出时降分辨率渲染完全不启用**，
游戏按 **原生 1080p** 渲染。4GB 显存必爆。

## 修复与效果

`bbport.ini`：
```ini
output_res=1280x720
upscaler=off
preset=0
live_resolution=0
skip_intro=1
effect_chromatic_aberration=0
effect_dof=0
effect_motion_blur=0
effect_ssao=0
effect_dynamic_shadows=0
model_lod=1
```

生效确认（日志）：
```
Output 1280x720: scene 1280x720, direct memory 9152 MiB (live_resolution=1: live changes)
Patches: scene 1280x720; UI 1920x1080
Patches: 267 writes from ['60 FPS++', 'Disable Chromatic Aberration', 'Disable DoF',
  'Disable Motion Blur (perf increase)', 'Disable SSAO',
  'Disable Dynamic Light Shadows (perf increase)', 'Skip Intro', 'Model LOD 1 (Lower)']
Object motion: off (enable in menu or BB_OBJECT_MOTION=1)
Upscaler: FSR 3.1 available (off)
VideoOut: vblank 60 Hz, frame limit 0 FPS
```

| 指标 | 改前 | 改后 |
|---|---|---|
| 纹理缓存压力报告次数 | 28（持续刷） | **0** |
| 显存占用 | 冲向 3469 MiB → 进程死亡 | **1614~1657 / 4096 MiB** |
| GPU 负载 | — | 30~58% |
| 能否进游戏 | 1~2 分钟后死 | 正常运行 |

## 仍未解决（上游 issue #39 记录的真实缺陷）
长时间游玩后，压力报告仍会出现（一次 315 采样的实测：首次 1729 MiB → **峰值 3195 MiB**，
255 次报告，其中 **68 次超过 critical 阈值 3072**，驱逐数仍为 **0**）。

原因是纹理缓存对 **tiled 的 GPU 写入图像**无法回收：
```cpp
if (tiled && download) return false;   // texture_cache.cpp, GarbageCollectImages()
```
而 PS4 纹理绝大多数是 tiled。上游报告者的结论：
- 降低阈值没用，因为"收集器没有允许它释放的东西"
- `BB_GC_BUDGET_MB` 在低显存卡上**保护不了**
- **死亡（YOU DIED）是最可靠的触发点**：角色/布料子系统重初始化 + 地图纹理重载的分配爆发
- 在 5GB 卡上"接近抛硬币"；只能靠降低输出分辨率减少频率

**结论：720p 是降低频率，不是根治。4GB 显存下这颗炸弹始终存在。**
