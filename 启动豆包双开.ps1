#Requires -Version 5.1
<#
.SYNOPSIS
  豆包 PC 端双开启动器（PowerShell 版）
.DESCRIPTION
  原理：豆包桌面版是基于 Electron / Chromium 内核构建的，
  Chromium 支持 --user-data-dir 启动参数，用于指定用户数据目录。
  给每个实例传入不同的 --user-data-dir，它们就会使用完全独立的
  登录态、缓存、设置，互不干扰，从而实现真正的双开/多开。

  与"抢互斥体"类方案的区别：
    - 不需要关闭已在运行的豆包；
    - 不需要抢启动时间差，100% 稳定；
    - 每个实例是完全独立的 profile，第二次启动自动记住登录状态。

  用法示例：
    .\启动豆包双开.ps1                  # 再开 1 个窗口（总共双开）
    .\启动豆包双开.ps1 -ExtraCount 2   # 再开 2 个（总共三开）
    .\启动豆包双开.ps1 -DoubaoPath "D:\Program Files\Doubao\app\Doubao.exe"
#>
[CmdletBinding()]
param(
    [int]$ExtraCount = 1,
    [string]$DoubaoPath,
    [string]$ProfileRoot
)

$ErrorActionPreference = 'Stop'

function Get-DoubaoPath {
    # 0) 用户手动指定
    if ($DoubaoPath -and (Test-Path -LiteralPath $DoubaoPath)) { return $DoubaoPath }

    # 1) 常见固定安装路径（NSIS 模式）
    # 1) Scan all drive letters for Program Files\Doubao\app\Doubao.exe
    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' } | ForEach-Object { $_.Name.TrimEnd('\') }
    foreach ($drv in $drives) {
        foreach ($sub in @('Program Files\Doubao\app\Doubao.exe', 'Program Files (x86)\Doubao\app\Doubao.exe')) {
            $candidate = Join-Path $drv $sub
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    # Also check user-local installs
    foreach ($c in @(
        "$env:LOCALAPPDATA\Programs\Doubao\app\Doubao.exe"
        "$env:LOCALAPPDATA\Doubao\app\Doubao.exe"
    )) { if (Test-Path -LiteralPath $c) { return $c } }

    # 2) Squirrel 安装模式：%LOCALAPPDATA%\Doubao\app-<version>\Doubao.exe
    $sqRoots = @(
        "$env:LOCALAPPDATA\Doubao"
        "$env:LOCALAPPDATA\Programs\Doubao"
    )
    foreach ($r in $sqRoots) {
        if (Test-Path -LiteralPath $r) {
            $dirs = Get-ChildItem -Path $r -Directory -Filter 'app-*' -ErrorAction SilentlyContinue
            foreach ($d in $dirs) {
                $exe = Join-Path $d.FullName 'Doubao.exe'
                if (Test-Path -LiteralPath $exe) { return $exe }
            }
        }
    }

    # 3) 注册表卸载项反查
    $uninstallKeys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($k in $uninstallKeys) {
        if (-not (Test-Path $k)) { continue }
        $subKeys = Get-ChildItem $k -ErrorAction SilentlyContinue
        foreach ($sk in $subKeys) {
            $p = Get-ItemProperty $sk.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -match '豆包|doubao') {
                # DisplayIcon 形如 "D:\...\icon.ico,0"
                $icon = ($p.DisplayIcon -split ',')[0].Trim('"')
                if ($icon -and (Test-Path -LiteralPath $icon)) {
                    $root = Split-Path $icon -Parent
                    foreach ($sub in @('app\Doubao.exe', 'Doubao.exe')) {
                        $candidate = Join-Path $root $sub
                        if (Test-Path -LiteralPath $candidate) { return $candidate }
                    }
                }
                if ($p.InstallLocation) {
                    foreach ($sub in @('app\Doubao.exe', 'Doubao.exe')) {
                        $candidate = Join-Path $p.InstallLocation $sub
                        if (Test-Path -LiteralPath $candidate) { return $candidate }
                    }
                }
            }
        }
    }

    # 4) 兜底：从正在运行的进程里找
    $proc = Get-Process -Name 'Doubao' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path -and (Test-Path -LiteralPath $proc.Path)) { return $proc.Path }

    return $null
}

$exe = Get-DoubaoPath
if (-not $exe) {
    Write-Host '[错误] 未自动找到豆包安装路径。' -ForegroundColor Red
    Write-Host ''
    Write-Host '请用 -DoubaoPath 手动指定，例如：' -ForegroundColor Yellow
    Write-Host '  .\启动豆包双开.ps1 -DoubaoPath "D:\Program Files\Doubao\app\Doubao.exe"' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '怎么找：右键桌面豆包快捷方式 -> 属性 -> 目标，复制里面的路径。' -ForegroundColor Yellow
    exit 1
}
Write-Host "[信息] 豆包路径: $exe" -ForegroundColor Cyan

if (-not $ProfileRoot) {
    $ProfileRoot = Join-Path $PSScriptRoot 'profiles'
}
if (-not (Test-Path -LiteralPath $ProfileRoot)) {
    New-Item -ItemType Directory -Path $ProfileRoot -Force | Out-Null
}
Write-Host "[信息] 独立数据目录根: $ProfileRoot" -ForegroundColor Cyan

# 智能判断：主实例没在跑就先启动主实例，已在跑就不打扰
$running = Get-Process -Name 'Doubao' -ErrorAction SilentlyContinue
if (-not $running) {
    Write-Host "[信息] 主实例未运行，先启动主账号窗口..." -ForegroundColor Yellow
    Start-Process -FilePath $exe
    Start-Sleep -Seconds 3
}

# 核心：为每个额外实例指定独立的 user-data-dir
Write-Host "[信息] 正在启动 $ExtraCount 个独立账号窗口..." -ForegroundColor Cyan
for ($i = 2; $i -lt 2 + $ExtraCount; $i++) {
    $dir = Join-Path $ProfileRoot "instance-$i"
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Write-Host "  - 实例 $i -> $dir"
    Start-Process -FilePath $exe -ArgumentList "--user-data-dir=`"$dir`""
}

Write-Host '[完成] 新窗口是全新登录状态，登录第二个账号即可。' -ForegroundColor Green
Write-Host '      下次再运行本脚本，会自动记住上次登录的账号。' -ForegroundColor Green
