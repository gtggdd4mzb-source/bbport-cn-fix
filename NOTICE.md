# NOTICE — 归属、改动与许可 / Attribution, modifications, license

## 上游项目 / Upstream projects

| 项目 | 作者 | 许可 |
|---|---|---|
| [deadinside28/bloodborne_pc](https://github.com/deadinside28/bloodborne_pc)（bbport 原作，Linux/AppImage） | deadinside28 | **GPL-2.0** |
| [Supermedo/bloodborne_pc](https://github.com/Supermedo/bloodborne_pc)（Windows 分支，本仓库针对它） | Supermedo | **GPL-2.0** |

## 本仓库改了什么 / What this repository modifies

只有上游发行包中 `bbport-windows\scripts\` 下的 **6 个 Python 脚本**，共 **12 处**：

| 文件 | 改动 |
|---|---|
| `prepare.py` | stdout/stderr 重设为 UTF-8；`analysis.json` 写入补 `encoding='utf-8'` |
| `content_profile.py` | 同上（stdout 重设 + JSON 写入补编码） |
| `link_libc.py` | 同上 |
| `link_modules.py` | 同上 |
| `patches.py` | stdout 重设 + 2 处文本读取补 `encoding='utf-8'` |
| `mods.py` | **仅**补 1 处文本读取编码；**故意不改 stdout**（原因见 README） |

其余内容（配置、启动器、文档）为本仓库新增，不修改上游代码。

完整改动见 [`patches/0001-windows-chinese-locale-utf8.patch`](patches/0001-windows-chinese-locale-utf8.patch)
（标准 `git diff` 格式，`git apply -p1` 可直接应用）。

## 许可 / License

上游为 GPL-2.0，本仓库的补丁是其**衍生修改**，因此同样以 **GPL-2.0** 发布，全文见 [LICENSE](LICENSE)。

## 免责 / Disclaimers

- 本仓库与上游作者**无任何隶属关系**，也**不是官方发布**。
- **不包含任何游戏文件、不包含上游二进制发行包。** 请自行准备你合法拥有的游戏本体 dump。
- *Bloodborne* 是 Sony Interactive Entertainment / FromSoftware 的商标与版权作品；
  本仓库与索尼、FromSoftware **无任何关系**，也不分发其任何内容。
- 本仓库提供的配置只能**降低**已知崩溃的发生频率，**不保证稳定**；
  使用风险自负。See README for the honest list of remaining known failures.
