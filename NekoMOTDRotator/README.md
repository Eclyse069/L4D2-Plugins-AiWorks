# NekoMOTDRotator — host/motd 按时段轮换插件

> v1.0 ｜ SourceMod 1.12 ｜ L4D2 ｜ 与 NekoServerNameRotator 同构机制

## 功能

按现实时间时段（凌晨/早上/下午/夜晚/深夜）轮换服务器横幅（hostfile）与 MOTD（motdfile）内容；也可切换为顺序循环或随机轮换。轮换对之后进服的玩家立即生效（引擎在玩家连接时读取这两个文件）。

## 池文件（`addons/sourcemod/data/motdrotator/`）

| 文件 | 时段（默认起始小时） |
|---|---|
| `host_1.txt` / `motd_1.txt` | 凌晨（0 点） |
| `host_2.txt` / `motd_2.txt` | 早上（6 点） |
| `host_3.txt` / `motd_3.txt` | 下午（12 点） |
| `host_4.txt` / `motd_4.txt` | 夜晚（18 点） |
| `host_5.txt` / `motd_5.txt` | 深夜（22 点） |

- 首次加载自动从**当前生效文件**播种快照（轮换初始零影响），之后直接编辑池文件即可
- 同编号的 host 与 motd **同时应用**；缺哪个跳哪个
- 编辑完想立即看效果：`sm_rotatemotd_next`

## 目标文件解析

生效文件按引擎 convar **运行时值**解析（每次应用时实时读取）：
- `hostfile`（当前为 `host2.txt`）
- `motdfile`（当前为 `motd.txt`）

以后换 hostfile 指向无需动插件。

## 指令（ROOT 权限）

| 指令 | 说明 |
|---|---|
| `sm_rotatemotd` | 查看状态（模式/间隔/当前编号/目标文件/时段表） |
| `sm_rotatemotd_next` | 立即轮换一次（time 模式=重新应用当前时段） |
| `sm_rotatemotd_set <1-5>` | 立即应用指定编号 |
| `sm_rotatemotd_mode <time\|order\|random>` | 切换模式（持久写入配置） |
| `sm_rotatemotd_reload` | 重读配置并补播种缺失池文件 |

## 模式

- `time` — 按现实时段轮换（默认），巡检粒度 10 秒，编号变化才动作
- `order` — 按编号顺序循环，每 `interval` 秒（默认 300）切换
- `random` — 随机（不与上一次重复），每 `interval` 秒切换

## 配置（`addons/sourcemod/configs/NekoMOTDRotator.cfg`）

```
"NekoMOTDRotator"
{
	"Settings"   { mode / interval / timezone }
	"TimePeriods"{ 时段名 → start 起始小时 + index 编号 }
}
```

时段起始小时、编号映射、间隔均可改；配置损坏会自动重新生成默认。

## 已知行为

- time 模式下 `sm_rotatemotd_set` 是**预览性质**：最多 10 秒后被巡检拉回当前时段（时钟说了算）；想钉住某版本请用 order/random 模式
- 换图/重读由引擎决定读取时机：一般对**新进服玩家**立即生效

---

## English

# NekoMOTDRotator — Time-of-Day host/motd Rotator Plugin

> v1.0 | SourceMod 1.12 | L4D2 | same mechanism as NekoServerNameRotator

## Features

Rotates the server banner (hostfile) and MOTD (motdfile) content by real-world time period (dawn / morning / afternoon / evening / late night); can also switch to sequential cycling or random rotation. Rotation takes effect immediately for players joining afterwards (the engine reads both files when a player connects).

## Pool Files (`addons/sourcemod/data/motdrotator/`)

| File | Time period (default start hour) |
|---|---|
| `host_1.txt` / `motd_1.txt` | Late night/dawn (00:00) |
| `host_2.txt` / `motd_2.txt` | Morning (06:00) |
| `host_3.txt` / `motd_3.txt` | Afternoon (12:00) |
| `host_4.txt` / `motd_4.txt` | Evening (18:00) |
| `host_5.txt` / `motd_5.txt` | Late night (22:00) |

- On first load it automatically seeds snapshots from the **currently active files** (zero impact at startup); afterwards just edit the pool files directly
- host and motd with the same index are **applied together**; a missing one is skipped
- To see your edits immediately: `sm_rotatemotd_next`

## Target File Resolution

The active files are resolved from the engine convars' **runtime values** (read live on each apply):
- `hostfile` (currently `host2.txt`)
- `motdfile` (currently `motd.txt`)

If you later point hostfile elsewhere, the plugin needs no changes.

## Commands (ROOT)

| Command | Description |
|---|---|
| `sm_rotatemotd` | Show status (mode/interval/current index/target files/period table) |
| `sm_rotatemotd_next` | Rotate immediately (time mode = re-apply current period) |
| `sm_rotatemotd_set <1-5>` | Apply the given index immediately |
| `sm_rotatemotd_mode <time\|order\|random>` | Switch mode (persisted to config) |
| `sm_rotatemotd_reload` | Reload config and seed any missing pool files |

## Modes

- `time` — rotate by real-world time period (default), 10-second polling, acts only when the index changes
- `order` — cycle by index order, switching every `interval` seconds (default 300)
- `random` — random (never repeats the last one), switching every `interval` seconds

## Config (`addons/sourcemod/configs/NekoMOTDRotator.cfg`)

```
"NekoMOTDRotator"
{
	"Settings"   { mode / interval / timezone }
	"TimePeriods"{ period name → start hour + index }
}
```

Period start hours, index mapping and interval are all editable; a corrupted config is automatically regenerated with defaults.

## Known Behavior

- In time mode `sm_rotatemotd_set` is a **preview only**: within 10 seconds the poller pulls it back to the current period (the clock wins); to pin a version use order/random mode
- When map changes/re-reads happen is up to the engine: generally effective immediately for **newly joining players**
