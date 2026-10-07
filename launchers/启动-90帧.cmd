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
set BB_OBJECT_MOTION=0set BB_FPS=90
echo 启动血源诅咒  BB_FPS=90
"%~dp0Bloodborne.exe" --run
pause

