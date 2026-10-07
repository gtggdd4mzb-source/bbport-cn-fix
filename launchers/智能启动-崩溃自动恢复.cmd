@echo off
chcp 65001 >nul
rem ================= 改这一行 =================
rem 游戏目录：含 eboot.bin 的那一层（旁边有 sce_sys \ dvdroot_ps4）
set BB_GAME_DIR=D:\Games\CUSA03173
rem ===========================================
set BB_DATA_DIR=%~dp0
set BB_FRAME_STATS=1
rem 单线程呈现：规避 "Out of order flip IRQ" 多线程 flip 竞态（shadPS4 PR #5039）
set BB_PRESENT_THREAD=0
rem 关闭对象运动向量（upscaler=off 已隐含，这里是双保险）
set BB_OBJECT_MOTION=0set TRIES=0
:loop
echo.
echo === 启动血源诅咒（第 %TRIES% 次重试）===
"%BB_DATA_DIR%Bloodborne.exe" --run
set RC=%ERRORLEVEL%
echo 退出码 = %RC%
if %RC% LSS 128 goto done
echo 检测到异常退出（^>= 128）：可能是显卡 TDR 或显存耗尽，且会污染管线缓存。
if exist "%BB_DATA_DIR%user\cache" rmdir /s /q "%BB_DATA_DIR%user\cache"
echo 已清理缓存（存档 user\savedata 未受影响）。
set /a TRIES+=1
if %TRIES% GEQ 3 goto giveup
echo 5 秒后自动重启...
timeout /t 5 >nul
goto loop
:giveup
echo 连续 3 次异常退出，停止自动重试。请查看 user\last_run.log，或改用 30 帧档位。
:done
pause
