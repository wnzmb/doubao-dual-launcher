# 豆包 PC 端双开登录脚本

> **原理一句话**
>
> ：豆包桌面版是 
>
> **Electron / Chromium 架构**
>
> ，通过 Chromium 标准启动参数 
>
> `--user-data-dir=<目录>`
>
>  指定不同的用户数据目录，就能让每个实例使用完全独立的登录态和配置，从而实现稳定双开。
> 与微信双开脚本的本质区别：微信是 "抢互斥体竞态条件"（不稳定，要抢时间差），豆包是 "独立 profile 目录"（100% 稳定，不抢时间、不关已有实例）。



## 平台支持情况

豆包官方桌面客户端目前只提供 **Windows** 和 **macOS** 两个版本（见[官方下载页](https://www.doubao.com/download/desktop)和[豆包工作配置要求](https://www.doubao.com/work/docs/zh-cn/articles/069516812827-app-requirement)），**没有 Linux 原生桌面版**。

| 操作系统 | 是否有官方桌面客户端 | 本仓库方案 |
|---|---|---|
| Windows | ✅ 有 | `豆包双开.bat` / `启动豆包双开.ps1` / `doubao_dual.py` |
| macOS | ✅ 有 | 原理相同，见下方说明 |
| Linux | ❌ 无（只能用网页版） | `dual-doubao.sh`（Chrome 独立配置目录访问网页版） |

| 文件               | 环境                         | 运行方式                                                  |
| ---------------- | -------------------------- | ----------------------------------------------------- |
| `豆包双开.bat`       | Windows（推荐）                | 双击即可，零依赖                                              |
| `启动豆包双开.ps1`     | Windows PowerShell 5.1+    | 右键 "使用 PowerShell 运行"，或 `powershell -File 启动豆包双开.ps1` |
| `doubao_dual.py` | Windows + Python 3         | `python doubao_dual.py`                               |
| `dual-doubao.sh` | Linux（网页版方案，非桌面客户端） | `./dual-doubao.sh`                                    |

> **macOS 用户**：原理完全一样。豆包 Mac 版也是 Electron 应用，在终端执行：
> ```bash
> /Applications/Doubao.app/Contents/MacOS/Doubao --user-data-dir=/path/to/second-profile
> ```
> 即可开第二个独立实例。本仓库暂未提供 macOS 脚本，有需要的同学可以参照 Windows 版自行封装。



***

## 快速开始（GitHub clone 下来直接用）



```
git clone <本仓库地址>
cd doubao-dual-launcher
# Windows 下双击 豆包双开.bat 即可
```

脚本会**自动探测豆包安装路径**，按以下顺序逐级兜底：

1. **遍历所有盘符**（C: 到 Z:）检查 `\Program Files\Doubao\app\Doubao.exe` 和 `\Program Files (x86)\Doubao\app\Doubao.exe`——不管豆包装在哪个盘都能找到
2. **用户目录安装**：`%LOCALAPPDATA%\Programs\Doubao\` 和 `%LOCALAPPDATA%\Doubao\`
3. **Squirrel 安装模式**：`%LOCALAPPDATA%\Doubao\app-<版本号>\Doubao.exe`（版本号自动通配）
4. **运行中进程反查**：如果豆包已经在跑，直接从进程列表拿路径
5. **注册表反查**：从卸载项里找 DisplayName 含"豆包"的，读 DisplayIcon 反推安装目录——**即使豆包装在随意目录（不在 Program Files 里）也能找到**

即使每个人豆包装在不同盘、不同目录、甚至是自定义安装路径，都能自动找到，无需改脚本。

**智能启动逻辑**：脚本运行时会先检测豆包是否在运行——如果没在运行，会先用默认 profile 启动主账号窗口，等 3 秒后再启动额外实例；如果已经在运行，则直接追加新窗口，不打扰你当前的使用。刚开机一键双开和用着用着加账号两种场景都覆盖。

> 实在找不到的极端情况，脚本会提示你：右键桌面豆包快捷方式 → 属性 → 目标，把路径复制到配置区的 
>
> `DOUBAO_PATH=`
>
>  即可。



***

## 一、实现原理（答辩要点）

### 1. 豆包桌面版的技术架构

豆包 Windows 桌面版不是原生 Win32 程序，而是基于 **Electron** 框架开发的 —— 也就是说，它本质上是一个被定制过的 **Chromium 浏览器**，只是把页面换成了豆包的界面。

这一点从安装目录就能看出来（以本机为例）：



```
D:\Program Files\Doubao\app\
├── Doubao.exe            ← 主程序（Chromium 浏览器主进程）
├── Doubao.dll / Doubao_elf.dll
├── libEGL.dll / libGLESv2.dll   ← Chromium GPU 组件
├── ffmpeg.dll            ← Chromium 内置 FFmpeg
├── icudtl.dat            ← Chromium ICU 数据
├── *.pak                 ← Chromium 资源包
└── ...
```

这些都是 Chromium/Electron 应用的标志性文件。

### 2. Chromium 的 `--user-data-dir` 参数

Chrome/Chromium 浏览器有一个标准启动参数：



```
chrome.exe --user-data-dir=<目录路径>
```

它的作用是：**指定用户数据目录**（存放登录 Cookie、缓存、LocalStorage、设置等）。默认情况下，Chrome 用的是 `%LOCALAPPDATA%\Google\Chrome\User Data`。

关键特性：**只要两个进程传入的&#x20;**`--user-data-dir`**&#x20;不同，它们就是两个完全独立的 "浏览器"**—— 互不相通的 Cookie、互不相通的登录态、互不相通的缓存，而且**不会触发单实例锁**（单实例锁是按 user-data-dir 区分的）。

### 3. 豆包如何利用这个参数双开

豆包作为 Electron 应用，完整继承了 Chromium 的这个参数。我们做的事情非常简单：



| 实例          | 数据目录                            | 登录态  |
| ----------- | ------------------------------- | ---- |
| 主实例（你正在用的）  | `%LOCALAPPDATA%\Doubao`（默认）     | 账号 A |
| 第二实例（脚本启动的） | `脚本目录\profiles\instance-2`（自定义） | 账号 B |
| 第三实例（可选）    | `脚本目录\profiles\instance-3`      | 账号 C |

启动命令等价于：



```
"D:\Program Files\Doubao\app\Doubao.exe" --user-data-dir="D:\...\profiles\instance-2"
```

第二个进程拿到独立的数据目录后，Chromium 会把它当作一个全新的、从未启动过的浏览器 —— 没有任何登录态，直接进入登录页面。登录账号 B 之后，这个状态保存在 `instance-2` 目录里，下次再启动还是账号 B。

### 4. 为什么这个方案比 "抢互斥体" 可靠？



| 对比项        | 微信（抢互斥体方案）                 | 豆包（--user-data-dir 方案）  |
| ---------- | -------------------------- | ----------------------- |
| 稳定性        | 靠时间差，偶尔抢不到                 | 100% 成功，不依赖时序           |
| 是否需要关闭已有实例 | 必须先关掉，否则被置顶                | 不需要，已有实例继续跑             |
| 登录态隔离      | 共用，切换账号会顶掉                 | 完全隔离，各登各的               |
| 第二次使用      | 还要重新扫码                     | 自动记住上次登录                |
| 原理可解释性     | 需要理解 Mutex + FindWindow 竞态 | 等价于 "开第二个 Chrome 用户"，直观 |



***

## 二、运行方法

### 方案一：BAT（最省事，推荐）



1. 把整个文件夹放到任意位置；

2. **双击&#x20;**`豆包双开.bat`；

3. 脚本会自动探测豆包安装路径，并在 `profiles\instance-2\` 下创建独立数据目录；

4. 弹出一个全新的豆包窗口，登录第二个账号即可。

想三开：用记事本打开 `.bat`，把 `set "EXTRA_COUNT=1"` 改成 `2`（再开 2 个，加上主实例总共 3 个）。

### 方案二：PowerShell



```
.\启动豆包双开.ps1                 # 再开 1 个（双开）
.\启动豆包双开.ps1 -ExtraCount 2   # 再开 2 个（三开）
.\启动豆包双开.ps1 -DoubaoPath "D:\Program Files\Doubao\app\Doubao.exe"
```

### 方案三：Python



```
python doubao_dual.py             # 再开 1 个（双开）
python doubao_dual.py -n 2        # 再开 2 个（三开）
python doubao_dual.py -p "D:\Program Files\Doubao\app\Doubao.exe"
```

### 方案四：Linux（网页版方案）

豆包没有 Linux 原生桌面客户端，本脚本用 Chrome/Chromium 开独立配置窗口访问 doubao.com 网页版：

```
chmod +x dual-doubao.sh
./dual-doubao.sh          # 双开（两个独立浏览器窗口，各登各的账号）
./dual-doubao.sh 3        # 三开
```

> 注意：这是网页版，没有桌面客户端的悬浮窗、全局快捷键、本地文件操作等功能，但多账号并行对话是一样的。



***

## 三、目录结构

运行一次之后，文件夹长这样：



```
doubao-dual-launcher/
├── 豆包双开.bat
├── 启动豆包双开.ps1
├── doubao_dual.py
├── dual-doubao.sh
├── README.md
└── profiles/                  ← 自动生成，存放各实例的登录数据
    ├── instance-2/            ← 第二个账号的全部数据
    │   ├── Default/
    │   ├── Local State
    │   └── ...
    └── instance-3/            ← 第三个账号（如果开了三开）
```

**想完全重置第二个账号**：直接删掉 `profiles\instance-2\` 整个文件夹，下次启动就是全新登录页。



***

## 四、常见问题（FAQ）

**Q1：为什么不直接在豆包设置里加账号？**

豆包工作客户端确实支持 "添加多个账号"，但那是**切换式**的 —— 同一时刻只能活跃一个账号，不能两个窗口同时各自对话。本脚本实现的是**并行双开**，两个窗口同时在线、各自独立对话。

**Q2：两个窗口会互相顶号吗？**

不会。它们的数据目录完全独立，相当于两个不同的豆包安装版。同一账号在手机、平板、另一个电脑上同时登录也不会互相影响（官方本身就支持多设备同时在线）。

**Q3：会触发封号风险吗？**

不会。这个方案没有注入 DLL、没有 Hook、没有修改程序文件，只是传了一个 Chromium 原生支持的命令行参数，等价于 "开第二个 Chrome 用户"。属于正常使用方式。

**Q4：脚本找不到豆包路径怎么办？**

脚本已经按以下顺序自动探测：

1. 遍历所有盘符（C:~Z:）的 `Program Files\Doubao\`
2. 用户目录安装（`%LOCALAPPDATA%`）
3. Squirrel 安装模式（`app-<版本号>` 动态目录自动通配）
4. 正在运行的 Doubao.exe 进程
5. 注册表卸载项反查（自定义安装目录也能找到）

如果全都没中，手动指定：



* bat：在配置区取消 `set "DOUBAO_PATH=..."` 的注释，改成你的路径

* ps1：用 `-DoubaoPath` 参数

* python：用 `-p` 参数

怎么找路径：右键桌面豆包快捷方式 → 属性 → 目标，复制里面的路径。

**Q5：profiles 文件夹能不能挪到别的盘？**

可以。直接移动整个 `profiles` 文件夹到别的位置，然后在脚本里改 `PROFILE_ROOT`（bat）/ `-ProfileRoot`（ps1）/ `-d`（python）指向新位置即可。

**Q6：豆包更新后会失效吗？**

`--user-data-dir` 是 Chromium 内核的基础参数，只要豆包还是 Electron 架构就不会失效。即使豆包大版本更新，这个参数也几乎不可能被移除（Chrome 自己都在用）。

**Q7：和用网页版 + 客户端组合相比，这个方案好在哪？**

网页版 + 客户端组合的缺点是：网页版没有桌面悬浮窗、全局快捷键、开机自启、本地文件操作（工作模式）等客户端功能。本脚本启动的是**完整的客户端**，第二个窗口和第一个一样功能齐全。

**Q8：Linux 下能用吗？**

豆包官方没有 Linux 桌面客户端。`dual-doubao.sh` 走的是 Chrome 独立配置目录访问网页版方案，能实现多账号并行对话，但缺少桌面客户端的本地能力（悬浮窗、全局快捷键、工作模式操作本地文件等）。

**Q9：bat、ps1、python 三个脚本混着用会冲突吗？**

不会。三个脚本默认共用同一个 `profiles\` 目录，实例编号规则一致（instance-2、instance-3...）。如果某个 instance-N 已经在运行，再用任何脚本去启动它，Chromium 会把已有窗口拉到前台而不是报错或重复开。想新开一个账号窗口，就调大数量参数（bat 改 `EXTRA_COUNT`，ps1 改 `-ExtraCount`，python 改 `-n`），脚本自动找下一个空的 instance-N。

***

## 五、调试日志与修复记录

开发过程中实际踩到的坑，记录在此方便后续维护：

### bat 脚本

| 问题 | 原因 | 修复 |
|---|---|---|
| 双击 bat 闪退，中文全是乱码 | bat 保存为 UTF-8 无 BOM，cmd 用 GBK 解析中文，乱码后的内容被当成命令执行，破坏语法结构 | 改为 **ASCII/纯英文输出**，`chcp 437`，彻底规避编码问题 |
| `do was unexpected at this time` | 注册表探测段嵌套了两层 `for /f`，内部还有管道和引号，bat 嵌套 for 语法非常脆弱 | 去掉注册表探测，保留固定路径 + Squirrel + wmic 进程反查三级兜底 |
| 固定路径探测找不到豆包 | 只列了 `%ProgramFiles%`（C盘），但豆包装在 D 盘，`%ProgramFiles%` 不包含 D 盘路径 | 固定路径里**显式列出 C/D 盘**的 `Program Files` 和 `Program Files (x86)` |
| wmic 结果读不出来 | wmic 输出到临时文件是 **UTF-8 BOM** 编码，bat 的 `for /f` 按 ANSI 读不了 BOM 头 | 改为 `for /f` 直接执行 wmic 命令并管道到 findstr，不落临时文件 |
| for 循环没执行 | 去掉了 `EnableDelayedExpansion` 但循环里用了 `!VAR!`；`%EXTRA_COUNT%+1` 不会做数学运算 | 加回 `EnableDelayedExpansion`，用 `set /a "LAST=2+EXTRA_COUNT-1"` 先算好结束值 |
| 只覆盖 C/D 盘，别人装 E/F 盘找不到 | 固定路径硬编码了 C/D 盘 | 改成**遍历所有盘符 C:~Z:** 检查 `Program Files\Doubao\` |
| 装在随意目录（不在 Program Files）找不到 | 前几步只查标准路径 | 加**注册表卸载项反查**（bat 用 Base64 编码的 PowerShell 命令避免引号嵌套），从 DisplayIcon 反推安装目录 |
| 刚开机豆包没开时，脚本只开了第二窗口，主账号窗口缺失 | 脚本假设用户已开着豆包 | 加**智能检测**：脚本先查 Doubao.exe 进程，没在跑就先启动主实例等 3 秒，再启动额外实例 |

### ps1 脚本

| 问题 | 原因 | 修复 |
|---|---|---|
| 路径打印了两次 | Squirrel 探测段用了 `Get-ChildItem \| ForEach-Object { return $exe }`，PowerShell 里 `ForEach-Object` 脚本块里的 `return` 只是从管道块返回，不会退出函数，导致函数继续走到进程反查又输出了一次 | 改成普通 `foreach ($d in $dirs) { ... return $exe }`，`return` 真正退出函数 |

### python 脚本

一次通过，无 bug。

***

## 六、参考来源

这个思路最早发现于无忧启动论坛的一个帖子，网友 `窄口牛` 在回帖里点破了关键：

> " 用谷歌的启动参数，就能把它设置到任意位置。
>
> `--user-data-dir=W:\Data`
>
> "



* 原始帖子：[自制 绿色版豆包 方法分享 - 无忧启动论坛](http://bbs.wuyou.net/archiver/?tid-452633.html)

* 帖子里楼主 `sunlenghua` 原本是做 "绿色版豆包"（把数据目录从 `%LOCALAPPDATA%` 搬到安装目录），回帖点出 `--user-data-dir` 参数后，思路就从 "绿色版" 升级成了 "双开"。

豆包平台支持情况参考：

* 豆包官方下载页：https://www.doubao.com/download/desktop （仅提供 Windows / macOS）

* 豆包工作配置要求：https://www.doubao.com/work/docs/zh-cn/articles/069516812827-app-requirement （系统要求只列 Windows 10+ 和 macOS 26+）

本项目在此基础上做了：



* 自动路径探测（常见路径 + Squirrel 动态目录 + 注册表 + 进程），不用手动改路径

* 多实例支持（不只双开，可以三开、四开）

* Windows 三端实现（bat /ps1 /python）+ Linux 网页版方案

* 完整原理说明和 FAQ



***

## 七、提交检查清单



* [x] 脚本可直接运行，无需安装任何第三方工具（bat 方案零依赖）

* [x] 自动探测豆包安装路径，兼容 NSIS / Squirrel 两种安装方式，兼容自定义安装目录

* [x] 不需要关闭已有豆包实例，直接追加新窗口

* [x] 实例数量可配置（`EXTRA_COUNT` / `-ExtraCount` / `-n`）

* [x] 每个实例数据完全隔离，第二次启动自动记住登录态

* [x] 含原理说明（Electron 架构 + Chromium user-data-dir）与 FAQ

* [x] Windows（bat/ps1/python）+ macOS（原理说明）+ Linux（网页版方案）

* [x] bat 已修复编码、路径探测、循环逻辑等问题，双击不闪退

* [x] ps1 已修复路径重复输出 bug

* [x] 附参考来源，可直接上传 GitHub



***

> 提示：本脚本仅用于个人多账号登录管理等自用场景。
> 原理上只是利用 Chromium 原生启动参数，不修改、不破解豆包程序本身。