# NekoServerNameRotator 使用说明

服务器名字轮换插件 v1.1（配合 NekoServerName.smx 使用，零冲突）。
部署于 `test` 服（端口 30666，`/root/steamcmd/test/left4dead2`，SourceMod 1.12）。

## 工作原理

NekoServerName.smx 只在插件加载/换图时读取一次 `data/nekocustom.cfg` 并缓存 `ServerNameFormat`。
本插件把选中的 `data/nekocustom_XX.cfg`（与 nekocustom.cfg 完全相同的内部格式）整文件覆写到
`data/nekocustom.cfg`，再执行 `sm plugins reload NekoServerName` 让它立即重读并刷新服务器名字。
不抢 hostname、不重复实现名字格式化，NekoServerName 的 `{gamedifficulty}`、`{flow}`、`{maptime}`
等占位符功能全部保留。

## 三种轮换模式

| 模式 | 行为 |
|---|---|
| `time` | 按现实时间时段轮换：凌晨(0-6)→01、早上(6-12)→02、下午(12-18)→03、夜晚(18-22)→04、深夜(22-24)→05 |
| `order` | 按编号顺序循环切换，每 `interval` 秒一次 |
| `random` | 随机切换（不与上一次重复），每 `interval` 秒一次 |

巡检粒度 10 秒；只有目标文件变化时才会真正覆写+重载，不会刷屏。

## 文件位置（服务器上）

- 插件：`addons/sourcemod/plugins/NekoServerNameRotator.smx`
- 源码：`addons/sourcemod/scripting/NekoServerNameRotator.sp`
- 配置：`addons/sourcemod/configs/NekoServerNameRotator.cfg`
- 名字池：`addons/sourcemod/data/nekocustom_01.cfg` ~ `nekocustom_05.cfg`

## 管理命令（需要 ROOT 权限，服务器控制台或游戏内管理可用）

- `sm_rotatename` — 查看当前模式/间隔/当前应用的是哪个文件
- `sm_rotatename_next` — 立即轮换一次（time 模式下=立即重新应用当前时段，改完 XX 文件后用它立即生效）
- `sm_rotatename_set <1-5>` — 立即应用指定编号的名字文件
- `sm_rotatename_mode <time|order|random>` — 切换模式（会持久写入配置文件）
- `sm_rotatename_reload` — 重新读取配置

## 怎么改名字内容

直接编辑 `data/nekocustom_XX.cfg` 里的 `ServerNameFormat` 一行（其余键和注释别删），
然后在控制台执行 `sm_rotatename_next` 立即生效（或等下一次轮换点自动生效）。
NekoServerName 的所有占位符（`{gamedifficulty}`、`{flow}`、`{realplayernum}` 等）照常可用。

## 配置项说明（configs/NekoServerNameRotator.cfg）

- `mode` — 轮换模式 time/order/random
- `interval` — order/random 模式的切换间隔（秒，最小 10）
- `timezone` — 时区（UTC 偏移小时，服务器为 CST 所以填 8）
- `reloadcmd` — 覆写后执行的刷新命令（默认 `sm plugins reload NekoServerName`）
- `TimePeriods` — 时段名/起始小时/对应文件；新增名字文件就往这里加一行，然后 `sm_rotatename_reload`

注意：配置损坏或缺失时插件会自动重新生成默认配置。

## 已知限制

- 每次轮换会重载 NekoServerName，其内部 `{restartcount}`（失败重启次数）计数会被清零——对服名展示影响极小。
- time 模式下 `sm_rotatename_set` 是预览性质：最多 10 秒后会被巡检切回当前时段（时钟说了算）；想钉住某个名字请用 order/random 模式。

---

## English

# NekoServerNameRotator Usage

Server name rotator plugin v1.1 (works alongside NekoServerName.smx, zero conflicts).
Deployed on the `test` server (port 30666, `/root/steamcmd/test/left4dead2`, SourceMod 1.12).

## How It Works

NekoServerName.smx reads `data/nekocustom.cfg` only once on plugin load/map change and caches `ServerNameFormat`.
This plugin overwrites the selected `data/nekocustom_XX.cfg` (internal format identical to nekocustom.cfg) onto
`data/nekocustom.cfg` as a whole file, then runs `sm plugins reload NekoServerName` so it re-reads and refreshes the server name immediately.
It doesn't fight over hostname or re-implement name formatting — all of NekoServerName's placeholders like `{gamedifficulty}`, `{flow}`, `{maptime}` keep working.

## Three Rotation Modes

| Mode | Behavior |
|---|---|
| `time` | Rotates by real-world time period: late night/dawn(0-6)→01, morning(6-12)→02, afternoon(12-18)→03, evening(18-22)→04, late night(22-24)→05 |
| `order` | Cycles through indices in order, switching every `interval` seconds |
| `random` | Random switching (never repeats the last one), every `interval` seconds |

Polling granularity is 10 seconds; overwrite + reload only happens when the target file actually changes, so there's no spam.

## File Locations (on the server)

- Plugin: `addons/sourcemod/plugins/NekoServerNameRotator.smx`
- Source: `addons/sourcemod/scripting/NekoServerNameRotator.sp`
- Config: `addons/sourcemod/configs/NekoServerNameRotator.cfg`
- Name pool: `addons/sourcemod/data/nekocustom_01.cfg` ~ `nekocustom_05.cfg`

## Admin Commands (ROOT required; server console or in-game admins)

- `sm_rotatename` — show current mode/interval/which file is currently applied
- `sm_rotatename_next` — rotate immediately (in time mode = re-apply the current period; use it after editing an XX file for instant effect)
- `sm_rotatename_set <1-5>` — apply the given name file index immediately
- `sm_rotatename_mode <time|order|random>` — switch mode (persisted to the config file)
- `sm_rotatename_reload` — reload the config

## How to Edit Name Contents

Just edit the `ServerNameFormat` line in `data/nekocustom_XX.cfg` (keep the other keys and comments),
then run `sm_rotatename_next` in console for instant effect (or wait for the next rotation point).
All of NekoServerName's placeholders (`{gamedifficulty}`, `{flow}`, `{realplayernum}`, etc.) keep working as usual.

## Config Keys (configs/NekoServerNameRotator.cfg)

- `mode` — rotation mode: time/order/random
- `interval` — switch interval for order/random modes (seconds, min 10)
- `timezone` — timezone (UTC offset hours; the server runs CST so it's 8)
- `reloadcmd` — refresh command run after overwriting (default `sm plugins reload NekoServerName`)
- `TimePeriods` — period names / start hours / mapped files; add a line here for each new name file, then run `sm_rotatename_reload`

Note: if the config is corrupted or missing, the plugin automatically regenerates defaults.

## Known Limitations

- Each rotation reloads NekoServerName, which resets its internal `{restartcount}` (failed-restart counter) — negligible impact on the displayed name.
- In time mode `sm_rotatename_set` is a preview only: within 10 seconds the poller switches back to the current period (the clock wins); to pin a name use order/random mode.
