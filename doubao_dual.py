#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
豆包 PC 端双开脚本
=====================
原理：
    豆包桌面版基于 Electron / Chromium 内核构建。Chromium 支持
    `--user-data-dir=<目录>` 启动参数，用于指定用户数据目录。
    给每个实例传入不同的 user-data-dir，它们就会使用完全独立的
    登录态、Cookie、缓存、设置，互不干扰，从而实现真正的双开/多开。

    与微信等"抢互斥体"方案的区别：
      - 不需要关闭已在运行的豆包；
      - 不需要抢启动时间差，100% 稳定；
      - 每个实例是独立 profile，第二次启动自动记住登录状态。

用法：
    python doubao_dual.py                 # 再开 1 个窗口（总共双开）
    python doubao_dual.py -n 2            # 再开 2 个窗口（总共三开）
    python doubao_dual.py -p "D:\\Program Files\\Doubao\\app\\Doubao.exe"
"""

import argparse
import glob
import os
import subprocess
import sys


def _check(path):
    return path and os.path.exists(path)


def find_doubao():
    """按多级策略自动探测豆包可执行文件：
       1) 遍历所有盘符 Program Files
       2) Squirrel 安装模式（app-<version> 动态目录）
       3) 注册表卸载项反查
       4) 正在运行的进程
    """
    import string
    local = os.environ.get("LOCALAPPDATA", "")

    # 1) Scan all fixed drives for Program Files\Doubao\app\Doubao.exe
    if sys.platform == "win32":
        for letter in string.ascii_uppercase:
            drive = f"{letter}:\\"
            if not os.path.exists(drive):
                continue
            for sub in (r"Program Files\Doubao\app\Doubao.exe",
                        r"Program Files (x86)\Doubao\app\Doubao.exe"):
                candidate = os.path.join(drive, sub)
                if _check(candidate):
                    return candidate
    # Also check user-local installs
    for c in [
        os.path.join(local, "Programs", "Doubao", "app", "Doubao.exe"),
        os.path.join(local, "Doubao", "app", "Doubao.exe"),
    ]:
        if _check(c):
            return c

    # 2) Squirrel 安装模式：app-<version> 动态目录
    for root in (os.path.join(local, "Doubao"),
                 os.path.join(local, "Programs", "Doubao")):
        for d in glob.glob(os.path.join(root, "app-*")):
            exe = os.path.join(d, "Doubao.exe")
            if _check(exe):
                return exe

    # 3) 注册表卸载项反查
    if sys.platform == "win32":
        try:
            import winreg
            roots = [
                (winreg.HKEY_CURRENT_USER, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
                (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
                (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
            ]
            for hive, sub in roots:
                try:
                    with winreg.OpenKey(hive, sub) as parent:
                        i = 0
                        while True:
                            try:
                                child_name = winreg.EnumKey(parent, i)
                            except OSError:
                                break
                            i += 1
                            try:
                                with winreg.OpenKey(parent, child_name) as k:
                                    try:
                                        display_name = winreg.QueryValueEx(k, "DisplayName")[0]
                                    except OSError:
                                        continue
                                    if "豆包" not in display_name and "doubao" not in display_name.lower():
                                        continue
                                    # 先试 InstallLocation
                                    try:
                                        loc = winreg.QueryValueEx(k, "InstallLocation")[0]
                                        for sub_exe in (os.path.join("app", "Doubao.exe"), "Doubao.exe"):
                                            cand = os.path.join(loc, sub_exe)
                                            if _check(cand):
                                                return cand
                                    except OSError:
                                        pass
                                    # 再试 DisplayIcon
                                    try:
                                        icon = winreg.QueryValueEx(k, "DisplayIcon")[0].split(",")[0].strip('"')
                                        root_dir = os.path.dirname(icon)
                                        for sub_exe in (os.path.join("app", "Doubao.exe"), "Doubao.exe"):
                                            cand = os.path.join(root_dir, sub_exe)
                                            if _check(cand):
                                                return cand
                                    except OSError:
                                        pass
                            except OSError:
                                continue
                except OSError:
                    continue
        except ImportError:
            pass

    # 4) 兜底：正在运行的进程
    if sys.platform == "win32":
        try:
            out = subprocess.run(
                ["wmic", "process", "where", "name='Doubao.exe'", "get", "ExecutablePath"],
                capture_output=True, text=True, timeout=5
            ).stdout
            for line in out.splitlines():
                line = line.strip()
                if line.endswith("Doubao.exe") and _check(line):
                    return line
        except (OSError, subprocess.SubprocessError):
            pass

    return None


def launch(exe, extra_count, profile_root):
    import time
    print(f"[信息] 豆包路径: {exe}")
    print(f"[信息] 数据目录根: {profile_root}")
    os.makedirs(profile_root, exist_ok=True)

    # 智能判断：主实例没在跑就先启动主实例，已在跑就不打扰
    main_running = False
    if sys.platform == "win32":
        try:
            out = subprocess.run(
                ["tasklist", "/fi", "imagename eq Doubao.exe", "/nh"],
                capture_output=True, text=True, timeout=5
            ).stdout
            main_running = "doubao.exe" in out.lower()
        except (OSError, subprocess.SubprocessError):
            pass
    if not main_running:
        print("[信息] 主实例未运行，先启动主账号窗口...")
        try:
            subprocess.Popen([exe])
            time.sleep(3)
        except OSError as e:
            print(f"[警告] 主实例启动失败: {e}")

    # 实例编号从 2 开始：instance-2 = 第二个账号窗口
    for i in range(2, 2 + extra_count):
        prof_dir = os.path.join(profile_root, f"instance-{i}")
        os.makedirs(prof_dir, exist_ok=True)
        try:
            subprocess.Popen([exe, f"--user-data-dir={prof_dir}"])
            print(f"  - 实例 {i} -> {prof_dir}")
        except OSError as e:
            print(f"[错误] 实例 {i} 启动失败: {e}")
    print("[完成] 新窗口是全新登录状态，登录第二个账号即可。")


def main():
    ap = argparse.ArgumentParser(description="豆包 PC 端双开/多开脚本")
    ap.add_argument("-n", "--num", type=int, default=1,
                    help="额外启动的窗口数量，默认 1（即总共双开）")
    ap.add_argument("-p", "--path", default=None,
                    help="Doubao.exe 的完整路径")
    ap.add_argument("-d", "--profile-dir", default=None,
                    help="独立数据目录根路径，默认脚本目录下 profiles/")
    args = ap.parse_args()

    path = args.path or find_doubao()
    if not path or not os.path.exists(path):
        print("[错误] 未自动找到豆包，请用 -p 指定路径，例如：")
        print(r'       -p "D:\Program Files\Doubao\app\Doubao.exe"')
        print()
        print("怎么找：右键桌面豆包快捷方式 -> 属性 -> 目标，复制里面的路径。")
        sys.exit(1)

    if args.num < 1:
        print("[错误] 额外窗口数至少为 1")
        sys.exit(1)

    profile_root = args.profile_dir or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "profiles"
    )
    launch(path, args.num, profile_root)


if __name__ == "__main__":
    main()
