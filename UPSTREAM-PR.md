# 可直接粘贴给上游的英文报告 / Ready-to-post upstream report

> 建议以 **issue** 形式提给 [Supermedo/bloodborne_pc](https://github.com/Supermedo/bloodborne_pc)
> （该仓库未开启 issue，可提到 [deadinside28/bloodborne_pc](https://github.com/deadinside28/bloodborne_pc)）。
> 也可以直接作为 PR —— 改动见本仓库 `patches/0001-windows-chinese-locale-utf8.patch`。

---

**Title:** Windows build cannot start on non-UTF-8 (e.g. Chinese/Japanese/Korean) locales — `'gbk' codec can't encode character '\u2122'`

**Environment**
- Windows 11 24H2, system locale **zh-CN** (ANSI code page **936 / GBK**)
- `Bloodborne-Windows.zip` from release **windows-v1.4** (SHA256 `6bcc5215…2cf59c`)
- Game: `CUSA03023`, `param.sfo APP_VER = 01.09`

**Symptom**

The port never reaches the game. The preparation pipeline aborts with:

```
prepare failed: 'gbk' codec can't encode character '\u2122' in position 919: illegal multibyte sequence
```

**Root cause (three layers)**

1. The frozen `Bloodborne.exe` **ignores `PYTHONUTF8` and `PYTHONIOENCODING`**.
   Verified by running a probe through `Bloodborne.exe --script`:

   ```
   utf8_mode       = 0        (even with PYTHONUTF8=1 set)
   preferred       = cp936
   stdout.encoding = gbk
   PYTHONUTF8      = 1        (visible in os.environ, but not honoured)
   ```

   So on a zh-CN system every default-encoded text stream is GBK.

2. `scripts/prepare.py` writes the analysis JSON without an explicit encoding:

   ```python
   (out / 'analysis.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
   ```

   `Path.write_text()` without `encoding=` uses the locale encoding (GBK here).
   The payload contains the game title from `param.sfo`: `Bloodborne™ The Old Hunters Edition`
   — the **™ (U+2122)** is not representable in GBK, so the write raises and the pipeline dies.
   (`analysis.json` is left at 0 bytes, which is the tell-tale sign.)

3. The same string is also `print()`ed to stdout, which has the same problem — so fixing only
   the file write is not enough.

On Linux the default encoding is UTF-8, which is why this never showed up.

**Fix**

12 hunks across 6 scripts:

- Re-configure stdio to UTF-8 in the 5 scripts that print non-ASCII
  (`prepare.py`, `link_libc.py`, `link_modules.py`, `content_profile.py`, `patches.py`):

  ```python
  import sys as _bb_sys
  try:
      _bb_sys.stdout.reconfigure(encoding='utf-8', errors='replace')
      _bb_sys.stderr.reconfigure(encoding='utf-8', errors='replace')
  except Exception:
      pass
  ```

- Add `encoding='utf-8'` to the 4 JSON `write_text()` calls
  (`prepare.py`, `content_profile.py`, `link_libc.py`, `link_modules.py`)
  and to the 3 text `read_text()` calls (`mods.py` ×1, `patches.py` ×2).

**⚠️ One caveat for whoever applies this**

`mods.py`'s **stdout must stay locale-encoded**. `run.py` consumes it with
`subprocess.run(..., text=True, stdout=PIPE)` — i.e. it decodes the child's output with the
locale codec and uses the result **as a path**. Switching that stream to UTF-8 makes non-ASCII
game paths round-trip incorrectly. Hence the patch deliberately leaves `mods.py`'s stdout alone
and only fixes its `read_text()`.

(A cleaner long-term fix would be to pass `encoding='utf-8'` to the `subprocess.run(...)` calls in
`run.py` and make all stdio UTF-8 consistently — but that touches `run.py`, which is inside the
frozen executable, so a source-level fix is needed there.)

**Verification after the patch**

```
Bloodborne™ The Old Hunters Edition | entry=0xa0 | image=91,042,036 bytes
686 imported symbols; 235,000 relocations; 42 required modules
Output: <port>\out
...
Runtime: PlayGo initialized; 3 chunks, all installed locally
Runtime: SystemService: splash screen hidden
```

i.e. the pipeline completes and the game boots.

**Suggested commit message**

```
scripts: force UTF-8 for stdio and text files (fixes startup on cp936/cp949/cp932 systems)

The frozen launcher ignores PYTHONUTF8/PYTHONIOENCODING, so every default-encoded
stream is the system ANSI code page. prepare.py wrote the analysis JSON with the
locale encoding and died on the game title's U+2122 on Chinese Windows.

- re-configure stdout/stderr to UTF-8 in the 5 scripts that print non-ASCII
- add encoding='utf-8' to JSON writes and text reads
- leave mods.py stdout alone: run.py decodes it with the locale codec and uses it as a path
```
