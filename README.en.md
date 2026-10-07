# bbport for Windows — CJK-locale startup fix & low-VRAM (4 GB) profile

> **No game files and no upstream binaries are included in this repository.**
> It is a **patch + config + documentation** repo that makes
> [Supermedo/bloodborne_pc](https://github.com/Supermedo/bloodborne_pc)
> (the Windows build of [deadinside28/bloodborne_pc](https://github.com/deadinside28/bloodborne_pc))
> start on **non-UTF-8 Windows locales** (zh-CN / ja-JP / ko-KR, i.e. ANSI code page 936 / 932 / 949)
> and run on a **4 GB laptop GPU**.

## Three problems, three fixes

| # | Problem | Symptom | Fix |
|---|---|---|---|
| 1 | Startup fails on CJK locales | `'gbk' codec can't encode character '\u2122'` | 12 hunks in 6 scripts — [`patches/`](patches) |
| 2 | Out of VRAM on 4 GB | process vanishes after 1–2 min, `memory pressure … 0 images evicted` | [`config/bbport.ini`](config/bbport.ini) 720p + effects off |
| 3 | Halved framerate / occasional crash | ~40 FPS in water areas, `Out of order flip IRQ` assert | [`launchers/`](launchers) with `BB_PRESENT_THREAD=0` + `BB_OBJECT_MOTION=0` |

## Quick start
1. Download `Bloodborne-Windows.zip` from the upstream release (tested: **windows-v1.4**) and unpack it.
2. Apply the fix: `powershell -ExecutionPolicy Bypass -File .\apply.ps1 -PortDir <...\bbport-windows>`
   — or apply [`patches/0001-windows-chinese-locale-utf8.patch`](patches/0001-windows-chinese-locale-utf8.patch)
   with `git apply -p1` from the port root.
3. Copy `config\bbport.ini` into `bbport-windows\`.
4. Copy `launchers\*.cmd` into `bbport-windows\`, edit `BB_GAME_DIR` to your dump folder
   (the one containing `eboot.bin`), and run it.

Requirements: Windows 10 1903+ / 11 x64, a Vulkan 1.3 driver, and **your own** decrypted dump of
Bloodborne with `param.sfo APP_VER = 01.09` (`CUSA03173` or `CUSA03023` both work — the version is
what actually gets checked, not the title id).

## Problem 1 — the real bug (please fix this upstream)

`Bloodborne.exe` is a PyInstaller bundle and **ignores `PYTHONUTF8` / `PYTHONIOENCODING`**:

```
utf8_mode        = 0      (set PYTHONUTF8=1 and it is still 0)
locale.getpreferredencoding(False) = cp936
sys.stdout.encoding                = gbk
```

`scripts/prepare.py` then does:

```python
(out / 'analysis.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
```

No `encoding=` → locale codec → the game title `Bloodborne™ …` contains **U+2122**, which GBK
cannot encode → the pipeline aborts before the game ever starts.

Full write-up and ready-to-paste issue text: **[UPSTREAM-PR.md](UPSTREAM-PR.md)**.

**Caveat:** do **not** switch `mods.py`'s stdout to UTF-8. `run.py` runs it with
`subprocess.run(..., text=True)` and uses the decoded output **as a path**; changing one side only
breaks non-ASCII game paths. The patch leaves that stream alone.

## Problem 2 — 4 GB VRAM

`bbport.ini`'s `output_res` defaults to `1920x1080`, and at `preset=0` `scaled_sizes()` returns
`None` for that size — so **no reduced-resolution render is patched in and the game renders at its
native 1080p**. On 4 GB:

```
Texture cache: memory pressure, 3469 of 1536 MiB (critical 3072): 0 images evicted
```

With `output_res=1280x720` the pressure reports went from 28 to **0** and VRAM usage from
*3469 MiB and climbing* to **1614–1657 / 4096 MiB**.

## Problem 3 — stutter & crashes (mitigation, not a cure)

- **`upscaler=off` also disables ObjectMotion** (it self-enables whenever the upscaler is not off).
  That path calls `Scheduler::Finish()` — a full device drain — per size change. Upstream issue #30
  measured **39.8 → 66.5 FPS** in the Yharnam sewer with it off, frame time 25.46 → 14.72 ms.
  Since we render at 720p and output 720p, FSR's ratio is 1.0 anyway — turning it off costs nothing.
- **`BB_PRESENT_THREAD=0`** — the default is "present on its own thread", which is exactly the
  multi-threaded flip submission behind the `Out of order flip IRQ` race (root cause in
  shadPS4 **PR #5039**: the GfxFlip callback and its command buffer live in two FIFOs with no shared
  lock; fixed upstream in **#5043**).
- **Clear `user\cache` after a fatal exit** — an assertion poisons the serialized pipeline cache and
  every later start then fails with an unrelated `Failed to create graphics pipeline: ErrorUnknown`
  (upstream issue #3). `launchers\智能启动-崩溃自动恢复.cmd` does this automatically when the exit
  code is ≥128.

## Known limitations (honest list)

This is beta software released **2026-10-01**. The config only *reduces* how often these happen:

1. **Dying (`YOU DIED`) is the most reliable crash trigger** — the character/cloth subsystem
   re-initialises and map textures reload; the texture cache **cannot evict tiled GPU-written
   images** (`if (tiled && download) return false;`) → `ErrorOutOfDeviceMemory`. An upstream
   reporter calls this "close to a coin flip" on a 5 GB card. 4 GB is worse.
2. Occasional `Out of order flip IRQ`.
3. Upstream reports of NVIDIA machines dying every 6–45 minutes from a GPU engine timeout (0x141).
4. Some areas still dip to ~40 FPS. Measured over 315 samples: avg 57.8, median 59.4, min 35.7,
   13.3 % of samples below 55 FPS.

If your goal is to *finish the game*, the much more mature **shadPS4** project (Bloodborne is its
flagship title) is usually the more stable route — that is a different architecture and out of scope here.

## License / attribution

Upstream is **GPL-2.0**; these patches are derivative modifications, released under the same license
— see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). Not affiliated with the upstream authors.
No game files are distributed; *Bloodborne* is © Sony Interactive Entertainment / FromSoftware.
