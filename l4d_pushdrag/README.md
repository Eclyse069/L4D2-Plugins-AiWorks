# Push And Drag（推人拖物插件）优化版

Left 4 Dead 1 / Left 4 Dead 2 的抓取、拖动、投掷插件。
原版作者 **Pan Xiaohai**（v1.2）https://forums.alliedmods.net/showthread.php?p=1325370；本仓库为大幅优化/修复版，当前版本 **v2.5.0**。

---

## 功能一览

- **抓取**：物件 / 玩家 / 队友 / 敌方特感 / Witch / 地图布娃娃，双击 R 抓起，任意拖动
- **投掷**：普通投掷、大力投掷；投掷物可击伤特感与普通感染者，物理击杀归属记到投掷者
- **安全性**（原版弹飞等老 bug 全部修复）：
  - 释放 / 投掷 / 放下后踩上物件不会再被弹飞（投掷力落地清理）
  - 机关实体（电梯、门、机关等）禁止抓取，不会出现"磁铁排斥"现象
  - 释放玩家有秒级摔伤保护；特感被扔出会吃摔伤
- **Witch 抓取**：原点拖拽 + 模拟弹道投掷（她无视速度写入）
- **布娃娃**：地图摆放的 `prop_ragdoll` 抓起瞬间减重、速度 ×3，弹簧拉不动自动切原点拖拽；投掷用模拟弹道，落地恢复原重
- **硬直特感**：调用引擎 `CTerrorPlayer::CancelStagger` 真取消硬直后即可抓起（需 gamedata，失效自动降级）
- **被特感控制时禁止抓取**（Hunter 扑 / Smoker 拉 / Jockey 骑 / Charger 撞）
- **旁观者支持**：旁观状态可抓物件 / 玩家 / 特感，E 投掷、F（手电筒）回正
- **多语言提示**：简中 / 繁中 / 英 / 俄；聊天彩色（multicolors）、原版教练提示框
- **诊断命令**：`!pdlevel` / `!pddebug` / `!pdver`

## 依赖

| 项目 | 说明 |
|---|---|
| SourceMod | 1.10 – 1.12（编译环境 1.12.0.7220） |
| 扩展 | 仅需 **SDKHooks**；不需要 DHooks |
| gamedata | `addons/sourcemod/gamedata/l4_pushdrag.txt`（用于取消硬直；缺失只降级不报错） |

## 安装

```
addons/sourcemod/plugins/l4d_pushdrag_v25.smx
addons/sourcemod/scripting/l4d_pushdrag_v25.sp        （源码，可不装）
addons/sourcemod/gamedata/l4_pushdrag.txt
addons/sourcemod/translations/l4d_pushdrag.phrases.txt
cfg/sourcemod/l4d_pushdrag.cfg                        （见下方升级注意）
```

> **只保留一个 pushdrag 的 .smx**。旧版本请移入 `plugins/disabled/` 或删除。
> **升级时必须手动覆盖 `cfg/sourcemod/l4d_pushdrag.cfg`**：`AutoExecConfig` 只在文件不存在时生成，之后永不重写；不覆盖的话新 cvar 会以插件内置默认值运行、旧 cvar 残留刷 unknown command。
> cfg 中文注释在个别环境会刷 unknown command：用 `cfg/sourcemod/l4d_pushdrag_english.cfg` 覆盖同名文件即可（ASCII 备用版）。

## 按键

| 按键 | 动作 |
|---|---|
| 双击 R | 普通抓取（240 单位） |
| 按住 Shift + 双击 R | 超远距离抓取（默认 1000，可设仅管理员） |
| 持握中右键 | 投掷 |
| 按住 Shift + 右键 | 大力投掷（可设仅管理员） |
| 持握中单击 R | 放下 |
| 被抓的玩家按空格 | 挣脱 |
| 狙击瞄准键（玩家）/ **F 或 Ctrl**（旁观者）/ `!pdlevel` | 回正模式开关 |
| 旁观者持握中按 **E** | 投掷（旁观时右键是切换观战）；Shift+E 大力投掷 |
| 倒地时按左键 | 投掷兜底（`incap_attack_throw`） |
| `!pddebug` / `!pdver` | 开关诊断输出 / 查看版本与硬直取消是否就绪 |

管理员判定权限：`sm_pushdrag_admin`（默认 `ADMFLAG_GENERIC`）。

## cvar 一览（52 项）

### 总开关与模式（13）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d_pushdrag_enable` | 1 | 总开关；0 关闭并立刻释放所有持握 |
| `l4d_pushdrag_versus_survivor` | 3 | 对抗模式生还者：0 禁用 / 1 物件 / 2 队友 / 3 全部 |
| `l4d_pushdrag_versus_infected` | 2 | 对抗模式感染者：0/1/2/3 |
| `l4d_pushdrag_player_grab` | 1 | 是否允许抓玩家（总闸） |
| `l4d_pushdrag_spectator_grab` | 1 | 旁观者可抓物件 |
| `l4d_pushdrag_spectator_grab_players` | 1 | 旁观者也可抓玩家/特感 |
| `l4d_pushdrag_survivor_grab_special` | 1 | 生还者可抓敌方特感（含 Tank） |
| `l4d_pushdrag_admin_only` | 0 | 抓取总功能仅管理员 |
| `l4d_pushdrag_admin_only_special` | 0 | 抓特感仅管理员 |
| `l4d_pushdrag_admin_only_spectator` | 0 | 旁观者抓取仅管理员 |
| `l4d_pushdrag_admin_only_far_grab` | 0 | 超远抓取仅管理员（非管理员降级普通距离） |
| `l4d_pushdrag_admin_only_strong_throw` | 0 | 大力投掷仅管理员（非管理员降级普通投掷） |
| `l4d_pushdrag_block_when_controlled` | 1 | 被特感控制时禁止抓取 |

### 抓取距离（8）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d_pushdrag_grab_range` | 240.0 | 普通抓取最大距离 |
| `l4d_pushdrag_far_grab_range` | 1000.0 | Shift+双击 R 超远抓取距离 |
| `l4d_pushdrag_hold_dist_object` | 120.0 | `prop_*` 悬停距离 |
| `l4d_pushdrag_hold_dist_car` | 200.0 | 车辆类悬停距离 |
| `l4d_pushdrag_hold_dist_weapon` | 50.0 | `weapon_*` 悬停距离 |
| `l4d_pushdrag_hold_dist_player` | 70.0 | 玩家悬停距离 |
| `l4d_pushdrag_hold_dist_default` | 100.0 | 其他实体默认悬停距离（Witch / 布娃娃同用） |
| `l4d_pushdrag_hold_dist_special` | 180.0 | 生还者抓敌方特感的悬停距离 |

### 持握时长（5）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d_pushdrag_hold_time_object` | 15.0 | `prop_*` 最长持握秒数 |
| `l4d_pushdrag_hold_time_car` | 10.0 | 车辆类 |
| `l4d_pushdrag_hold_time_weapon` | 30.0 | `weapon_*` |
| `l4d_pushdrag_hold_time_player` | 15.0 | 玩家 |
| `l4d_pushdrag_hold_time_default` | 10.0 | 其他实体 |

### 持握物理与修复（12）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d_pushdrag_hold_force` | 0.2 | 拉力系数：速度 = 系数 × 距离² |
| `l4d_pushdrag_hold_force_dist` | 100.0 | 拉力距离截断 |
| `l4d_pushdrag_hold_max_speed` | 2000.0 | 物件最大速度 |
| `l4d_pushdrag_break_dist` | 350.0 | 超过距离自动松手 |
| `l4d_pushdrag_release_stop` | 1 | 松手清人工速度（修复重力异常的关键项） |
| `l4d_pushdrag_latency_comp` | 4.0 | 延迟补偿系数 |
| `l4d_pushdrag_release_settle` | 1 | 放下时清角速度/同步原点 |
| `l4d_pushdrag_no_held_damage` | 1 | 持握中的物件不造成碰撞伤害 |
| `l4d_pushdrag_player_fall_protect` | 0.3 | 释放玩家后免摔伤秒数（0=关闭） |
| `l4d_pushdrag_throw_settle` | 1 | 投掷物停下后清残留投掷力（防弹飞核心项） |
| `l4d_pushdrag_physics_attacker` | 1 | 写引擎归属字段；另有 OnTakeDamage 兜底，击杀始终归属投掷者 |
| `l4d_pushdrag_attacker_time` | 5.0 | 归属保留秒数（引擎窗口 5 秒） |

### 投掷与布娃娃（7）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d_pushdrag_throw_force` | 2000.0 | Shift+右键大力投掷 |
| `l4d_pushdrag_throw_force_base` | 200.0 | 最远距离附加力 |
| `l4d_pushdrag_throw_falloff_dist` | 1000.0 | 投掷力衰减距离 |
| `l4d_pushdrag_thrown_prop_damage_scale` | 0.05 | 生还者/旁观者投出物件对特感与普通感染者伤害 = 速度 × 系数（0=关闭） |
| `l4d_pushdrag_thrown_si_fall_damage_scale` | 0.02 | 生还者投出特感落地摔伤 = 投掷力 × 系数（0=关闭） |
| `l4d_pushdrag_ragdoll_gravity` | 1 | 布娃娃抓起失重/投掷落地恢复原重（见下方说明） |
| `l4d_pushdrag_ragdoll_speed_mult` | 3.0 | 持握布娃娃的速度倍率；弹簧拉不动自动切原点拖拽 |

### 输入与杂项（7）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d_pushdrag_double_tap_time` | 0.3 | 双击 R 判定窗口（秒） |
| `l4d_pushdrag_player_jump_escape` | 1 | 被抓玩家按空格挣脱 |
| `l4d_pushdrag_incap_attack_throw` | 0 | 倒地时左键也可投掷（兜底） |
| `l4d_pushdrag_level_key` | 1 | 回正开关（玩家狙击瞄准键；旁观者 F / Ctrl / `!pdlevel`） |
| `l4d_pushdrag_sound` | 1 | 抓取音效 |
| `l4d_pushdrag_debug` | 0 | 诊断输出（`!pddebug` 可即时切换） |
| `l4d_pushdrag_cancel_stagger` | 1 | 调用引擎 CancelStagger 真取消被抓者硬直（需 gamedata） |

## 布娃娃说明（v2.5）

- 只作用于**地图摆放**的 `prop_ragdoll` / `physics_prop_ragdoll`（装饰尸体）。
- 特感/玩家尸体是 `cs_ragdoll`（客户端物理）、幸存者尸体是 `survivor_death_model`——**不同实体类型，本来就不可能被服务端抓取，也不受本插件影响**。
- 抓起瞬间失重（`DisableGravity`）+ 速度 ×3；弹簧 0.2 秒内拉不动自动切原点拖拽；投掷走模拟弹道（肢体甩动），落地后恢复原重。

## 常见问题

| 现象 | 原因与处理 |
|---|---|
| 服务器自动生成 `l4d_pushdrag_v12.cfg` | 有**原版 1.2 的旧插件**仍被加载（`AutoExecConfig` 名是代码里写死的）。`sm plugins list` 找出版本号为 **1.2** 的 "Push And Drag"，删除对应 .smx（可能藏在 plugins 子文件夹，文件名任意） |
| 新 cvar 不生效 | `AutoExecConfig` 不会重写已存在的 cfg——升级后必须手动覆盖 `cfg/sourcemod/l4d_pushdrag.cfg` |
| cfg 刷 unknown command | 中文注释问题，用 `l4d_pushdrag_english.cfg` 覆盖 |
| 硬直特感又抓不起来 | 游戏更新可能使 CancelStagger 签名失效：`!pdver` 查看；失效时先 `sm_cvar l4d_pushdrag_cancel_stagger 0`（降级为压制方案），并更新 gamedata |
| 抓 Witch / 特感手感异常 | Witch 用原点拖拽属正常设计；特感尸体（cs_ragdoll）抓不到属正常 |

## 版本历史

见 [`l4d_pushdrag_更新日志.md`](l4d_pushdrag_更新日志.md)。

---

## English

# Push And Drag (Push & Drag Plugin) — Optimized Edition

A grab, drag and throw plugin for Left 4 Dead 1 / Left 4 Dead 2.
Original author **Pan Xiaohai** (v1.2); this repository is a heavily optimized/fixed edition, current version **v2.5.0**.

---

## Feature Overview

- **Grab**: props / players / teammates / enemy special infected / Witches / map ragdolls — double-tap R to grab, drag freely
- **Throw**: normal throw, strong throw; thrown props can hurt special infected and common infected, physics kills are credited to the thrower
- **Safety** (all old bugs like launch-flinging fixed):
  - No more getting flung when stepping on a prop after release / throw / drop (throw force cleaned on landing)
  - Mechanism entities (elevators, doors, machinery) cannot be grabbed — no more "magnet repulsion" weirdness
  - Players released get seconds of fall-damage protection; thrown special infected take fall damage
- **Witch grabbing**: origin-drag + simulated ballistic throw (she ignores velocity writes)
- **Ragdolls**: map-placed `prop_ragdoll` becomes weightless on grab, speed ×3; auto-switches to origin-drag when the spring can't keep up; throws use simulated ballistics, original weight restored on landing
- **Staggered special infected**: calls the engine's `CTerrorPlayer::CancelStagger` to truly cancel stagger, then they can be grabbed (needs gamedata; degrades gracefully if unavailable)
- **Grabbing disabled while being controlled by special infected** (Hunter pounce / Smoker pull / Jockey ride / Charger charge)
- **Spectator support**: spectators can grab props / players / special infected, throw with E, level-out with F (flashlight)
- **Multilingual prompts**: Simplified Chinese / Traditional Chinese / English / Russian; colored chat (multicolors), vanilla instructor hints
- **Diagnostic commands**: `!pdlevel` / `!pddebug` / `!pdver`

## Requirements

| Component | Notes |
|---|---|
| SourceMod | 1.10 – 1.12 (compiled on 1.12.0.7220) |
| Extensions | **SDKHooks** only; DHooks not required |
| gamedata | `addons/sourcemod/gamedata/l4_pushdrag.txt` (for stagger cancel; missing = graceful downgrade, no errors) |

## Installation

```
addons/sourcemod/plugins/l4d_pushdrag_v25.smx
addons/sourcemod/scripting/l4d_pushdrag_v25.sp        (source, optional)
addons/sourcemod/gamedata/l4_pushdrag.txt
addons/sourcemod/translations/l4d_pushdrag.phrases.txt
cfg/sourcemod/l4d_pushdrag.cfg                        (see upgrade notes below)
```

> **Keep only one pushdrag .smx.** Move old versions to `plugins/disabled/` or delete them.
> **When upgrading you must manually overwrite `cfg/sourcemod/l4d_pushdrag.cfg`**: `AutoExecConfig` only generates the file if it doesn't exist and never rewrites it afterwards; without overwriting, new cvars run on built-in defaults and leftover old cvars spam "unknown command".
> If Chinese comments in the cfg spam "unknown command" in some environments: overwrite the file with `cfg/sourcemod/l4d_pushdrag_english.cfg` (ASCII fallback).

## Controls

| Key | Action |
|---|---|
| Double-tap R | Normal grab (240 units) |
| Hold Shift + double-tap R | Long-range grab (default 1000, can be admin-only) |
| Right-click while holding | Throw |
| Hold Shift + right-click | Strong throw (can be admin-only) |
| Single-click R while holding | Drop |
| Space (as a grabbed player) | Struggle free |
| Zoom key (players) / **F or Ctrl** (spectators) / `!pdlevel` | Toggle level-out mode |
| **E** while holding (spectator) | Throw (right-click switches view as spectator); Shift+E for strong throw |
| Left-click while incapped | Throw fallback (`incap_attack_throw`) |
| `!pddebug` / `!pdver` | Toggle diagnostic output / check version & stagger-cancel readiness |

Admin permission flag: `sm_pushdrag_admin` (default `ADMFLAG_GENERIC`).

## Cvars (52 total)

### Master Switches & Modes (13)

| cvar | Default | Description |
|---|---|---|
| `l4d_pushdrag_enable` | 1 | Master switch; 0 disables and immediately releases everything held |
| `l4d_pushdrag_versus_survivor` | 3 | Versus survivors: 0 off / 1 props / 2 teammates / 3 all |
| `l4d_pushdrag_versus_infected` | 2 | Versus infected: 0/1/2/3 |
| `l4d_pushdrag_player_grab` | 1 | Whether players can be grabbed (master gate) |
| `l4d_pushdrag_spectator_grab` | 1 | Spectators can grab props |
| `l4d_pushdrag_spectator_grab_players` | 1 | Spectators can also grab players/special infected |
| `l4d_pushdrag_survivor_grab_special` | 1 | Survivors can grab enemy special infected (incl. Tank) |
| `l4d_pushdrag_admin_only` | 0 | All grabbing admin-only |
| `l4d_pushdrag_admin_only_special` | 0 | Grabbing special infected admin-only |
| `l4d_pushdrag_admin_only_spectator` | 0 | Spectator grabbing admin-only |
| `l4d_pushdrag_admin_only_far_grab` | 0 | Long-range grab admin-only (non-admins fall back to normal range) |
| `l4d_pushdrag_admin_only_strong_throw` | 0 | Strong throw admin-only (non-admins fall back to normal throw) |
| `l4d_pushdrag_block_when_controlled` | 1 | No grabbing while being controlled by special infected |

### Grab Distances (8)

| cvar | Default | Description |
|---|---|---|
| `l4d_pushdrag_grab_range` | 240.0 | Max normal grab distance |
| `l4d_pushdrag_far_grab_range` | 1000.0 | Shift+double-tap R long-range grab distance |
| `l4d_pushdrag_hold_dist_object` | 120.0 | Hover distance for `prop_*` |
| `l4d_pushdrag_hold_dist_car` | 200.0 | Hover distance for vehicles |
| `l4d_pushdrag_hold_dist_weapon` | 50.0 | Hover distance for `weapon_*` |
| `l4d_pushdrag_hold_dist_player` | 70.0 | Hover distance for players |
| `l4d_pushdrag_hold_dist_default` | 100.0 | Default hover distance (Witch / ragdolls) |
| `l4d_pushdrag_hold_dist_special` | 180.0 | Hover distance for survivors grabbing enemy special infected |

### Hold Durations (5)

| cvar | Default | Description |
|---|---|---|
| `l4d_pushdrag_hold_time_object` | 15.0 | Max hold seconds for `prop_*` |
| `l4d_pushdrag_hold_time_car` | 10.0 | Vehicles |
| `l4d_pushdrag_hold_time_weapon` | 30.0 | `weapon_*` |
| `l4d_pushdrag_hold_time_player` | 15.0 | Players |
| `l4d_pushdrag_hold_time_default` | 10.0 | Other entities |

### Hold Physics & Fixes (12)

| cvar | Default | Description |
|---|---|---|
| `l4d_pushdrag_hold_force` | 0.2 | Pull coefficient: speed = coefficient × distance² |
| `l4d_pushdrag_hold_force_dist` | 100.0 | Pull force distance cutoff |
| `l4d_pushdrag_hold_max_speed` | 2000.0 | Max prop speed |
| `l4d_pushdrag_break_dist` | 350.0 | Auto-release beyond this distance |
| `l4d_pushdrag_release_stop` | 1 | Clear artificial velocity on release (key fix for gravity glitches) |
| `l4d_pushdrag_latency_comp` | 4.0 | Latency compensation coefficient |
| `l4d_pushdrag_release_settle` | 1 | Clear angular velocity / sync origin on drop |
| `l4d_pushdrag_no_held_damage` | 1 | Held props deal no collision damage |
| `l4d_pushdrag_player_fall_protect` | 0.3 | Fall-damage-immune seconds after releasing a player (0=off) |
| `l4d_pushdrag_throw_settle` | 1 | Clear residual throw force after the prop stops (core anti-fling fix) |
| `l4d_pushdrag_physics_attacker` | 1 | Write engine attacker field; plus OnTakeDamage fallback, kills always credit the thrower |
| `l4d_pushdrag_attacker_time` | 5.0 | Attacker attribution seconds (engine window is 5s) |

### Throw & Ragdolls (7)

| cvar | Default | Description |
|---|---|---|
| `l4d_pushdrag_throw_force` | 2000.0 | Shift+right-click strong throw |
| `l4d_pushdrag_throw_force_base` | 200.0 | Extra force at max distance |
| `l4d_pushdrag_throw_falloff_dist` | 1000.0 | Throw force falloff distance |
| `l4d_pushdrag_thrown_prop_damage_scale` | 0.05 | Damage of survivor/spectator-thrown props vs special & common infected = speed × scale (0=off) |
| `l4d_pushdrag_thrown_si_fall_damage_scale` | 0.02 | Fall damage of survivor-thrown special infected = throw force × scale (0=off) |
| `l4d_pushdrag_ragdoll_gravity` | 1 | Ragdolls weightless while grabbed / original weight restored on landing (see notes) |
| `l4d_pushdrag_ragdoll_speed_mult` | 3.0 | Speed multiplier while holding a ragdoll; auto-switch to origin-drag if spring can't keep up |

### Input & Misc (7)

| cvar | Default | Description |
|---|---|---|
| `l4d_pushdrag_double_tap_time` | 0.3 | Double-tap R detection window (seconds) |
| `l4d_pushdrag_player_jump_escape` | 1 | Grabbed players press Space to struggle free |
| `l4d_pushdrag_incap_attack_throw` | 0 | Left-click throw while incapped (fallback) |
| `l4d_pushdrag_level_key` | 1 | Level-out switch (players: zoom key; spectators: F / Ctrl / `!pdlevel`) |
| `l4d_pushdrag_sound` | 1 | Grab sound |
| `l4d_pushdrag_debug` | 0 | Diagnostic output (`!pddebug` toggles live) |
| `l4d_pushdrag_cancel_stagger` | 1 | Truly cancel the grabbed entity's stagger via engine CancelStagger (needs gamedata) |

## Ragdoll Notes (v2.5)

- Only affects **map-placed** `prop_ragdoll` / `physics_prop_ragdoll` (decorative corpses).
- Special infected/player corpses are `cs_ragdoll` (client-side physics) and survivor corpses are `survivor_death_model` — **different entity types, never server-grabbable to begin with, and unaffected by this plugin**.
- On grab: gravity disabled + speed ×3; if the spring can't hold within 0.2s it auto-switches to origin-drag; throws use simulated ballistics (limbs flailing), original weight restored on landing.

## FAQ

| Symptom | Cause & Fix |
|---|---|
| Server auto-generates `l4d_pushdrag_v12.cfg` | An **old original v1.2 plugin** is still loaded (`AutoExecConfig` names are hardcoded). Run `sm plugins list`, find "Push And Drag" with version **1.2**, and delete that .smx (may hide in a plugins subfolder, any filename) |
| New cvars don't take effect | `AutoExecConfig` never rewrites an existing cfg — after upgrading you must manually overwrite `cfg/sourcemod/l4d_pushdrag.cfg` |
| cfg spams "unknown command" | Chinese comment issue; overwrite with `l4d_pushdrag_english.cfg` |
| Staggered special infected can't be grabbed again | A game update may break the CancelStagger signature: check `!pdver`; if broken, first run `sm_cvar l4d_pushdrag_cancel_stagger 0` (downgrade to the suppression method) and update gamedata |
| Weird feel when grabbing Witch / special infected | Witch uses origin-drag by design; special infected corpses (cs_ragdoll) not being grabbable is normal |

## Version History

See [`l4d_pushdrag_更新日志.md`](l4d_pushdrag_更新日志.md) (Chinese changelog).
