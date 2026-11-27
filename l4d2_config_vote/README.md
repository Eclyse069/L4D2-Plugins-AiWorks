# l4d2_config_vote — 投票修改保持补丁（v1.1）

> 原作者 fdxx, kita ｜ 会话保持补丁 by lead ｜ 本目录含**旧版原始**与**新版修复**两套完整文件

## 问题
投票通过 `ServerCommand` 改的 cvar 只是内存值，换图时 server.cfg 重新执行，全部打回 cfg 默认。

## 修复机制（v1.1）
1. 投票通过的 ServerCommand，若为以下形式则存入**会话保持列表**（插件内存）：
   - ✅ 直接 cvar 赋值（`fps_max 128`、`sv_maxplayers X;sv_visiblemaxplayers X`、`l4d_pushdrag_enable 1` 等，逐分号段校验首 token 必须是真实存在的 ConVar）
   - ✅ `exec "match_votes/..."` 功能配置（HUD/躲猫猫/胆汁/友伤等整套 cvar 状态）
   - ❌ 一次性动作（`sm_restartmap`、`sm_reserve`、`sm_unreserve` 等绝不每图重放）
2. 每次 `OnConfigsExecuted`（cfg 执行完毕后）按投票时间顺序重放全部保持项，后投的覆盖先投的
3. 清零时机：**服务器重启**（需求语义）或插件热重载或手动清除

## 新增命令
`sm_votecfg_clear`（ROOT）：清除保持列表，下一张图恢复 cfg 默认值（不用重启服务器）

## 其它变更
- 剥离了服务器上不存在的 `savelog.sp` 依赖（`LogTo` → `LogMessage`，一处等价替换）
- 服务器上原版已就地备份为 `l4d2_config_vote.sp.orig` / `.smx.orig`

## 验证步骤
1. 游戏内投票改 `fps_max`（如 30）→ `sm_cvar fps_max` 确认已变
2. 换一张图 → `sm_cvar fps_max` 应仍是 30（不再回默认）
3. `sm_votecfg_clear` → 换图 → 恢复 cfg 默认
4. 重启服务器 → 保持列表清零，全部恢复默认

## 基础使用教程

**玩家侧**：聊天框输入 `!v`（或 `!vt` / `!votes` / `!si`）打开投票菜单 → 树状分类逐层选 → 弹出 L4D2 原生投票框（F1 赞成 / F3 反对），持续 20 秒，**赞成数 > 参与人数的一半**即通过执行。

**管理员特权**：
- 投票中管理员默认**一票通过**（投 F1）或**一票否决**（投 F3），由各投票项的 `AdminOneVotePassed` / `AdminOneVoteAgainst` 控制（默认开）
- 管理员默认无视 MenuTeamFlags / VoteTeamFlags 队伍限制（cvar `l4d2_config_vote_adminteamflags` 默认 1）

**命令速查**：

| 命令 | 说明 |
|---|---|
| `sm_v` / `sm_vt` / `sm_votes` / `sm_si` | 打开投票菜单 |
| `sm_votecfg_reload` | 修改 vote.kv 后重载配置 |
| `sm_votecfg_clear` | 清除投票保持列表，下一张图恢复 cfg 默认 |

## vote.kv 自定义投票格式

文件位置：`addons/sourcemod/data/vote.kv`，修改后执行 `sm_votecfg_reload` 生效。

**结构规则**：
- **节名 = 菜单上显示的文字**
- 节内嵌套子节 = 子菜单（可任意层级嵌套）
- 节内出现 `Type` 字段 = 叶子节点 = 一个投票项

**字段说明**：

| 字段 | 值 | 说明 |
|---|---|---|
| `Type` | `ServerCommand` | 投票通过后在**服务器**上执行 Command（改 cvar / exec cfg 等）|
| | `ClientCommand` | 投票通过后对**发起玩家**执行 Command |
| | `CheatCommand` | 对发起玩家以临时去 cheat 标记方式执行（如 `z_spawn tank`）|
| | `ExternalVote` | 不进入投票，选中时直接对发起玩家执行 Command（挂接其它插件的命令）|
| `MenuTeamFlags` | 位值 | 谁能在菜单里**看到**此项：旁观 2 / 生还者 4 / 感染者 8，相加组合（12 = 生还+感染）|
| `VoteTeamFlags` | 位值 | 谁有资格**参与投票**（同上位值规则）|
| `AdminOneVotePassed` | 0/1 | 管理员投赞成是否一票通过（默认 1）|
| `AdminOneVoteAgainst` | 0/1 | 管理员投反对是否一票否决（默认 1）|
| `Description` | 文本 | 原生投票框里显示的标题 |
| `Command` | 命令 | 对应 Type 的命令内容；**含引号需转义**，如 `exec \"match_votes/hud/off.cfg\"` |

**最小示例**（加进根节内即可用）：
```
"选择投票类型"
{
	// ...原有内容...

	"我的直投项"
	{
		"Type"			"ServerCommand"
		"MenuTeamFlags"	"12"
		"VoteTeamFlags"	"12"
		"Description"	"开启无限弹药"
		"Command"		"sv_infinite_ammo 1"
	}
	"我的分组"
	{
		"MenuTeamFlags" "12"

		"选项A"
		{
			"Type"			"ServerCommand"
			"MenuTeamFlags"	"12"
			"VoteTeamFlags"	"12"
			"Description"	"功能: 开启"
			"Command"		"功能cvar 1"
		}
		"选项B"
		{
			"Type"			"ServerCommand"
			"MenuTeamFlags"	"12"
			"VoteTeamFlags"	"12"
			"Description"	"功能: 关闭"
			"Command"		"功能cvar 0"
		}
	}
}
```

**v1.1 保持规则（做新投票项前须知）**：
- Command 写成 **cvar 赋值**（`xxx_cvar 1`、`a 1;b 2` 分号链）或 **exec cfg** 形式 → 投票效果**跨图保持**（直到服务器重启或 `sm_votecfg_clear`）
- 写成 `sm_xxx` 等一次性动作 → 换图后失效（不保持，防止危险重放）
- 想让某功能可投票且跨图保持：把它的 cvar 收进一个 cfg 文件，投票项用 `exec "cfg路径"` 执行

## 目录说明
- `旧版原始\`：修复前的原版（含 vote.kv 快照）
- `新版修复\`：当前服务器在跑的 v1.1（含同一份 vote.kv）

---

## English

# l4d2_config_vote — Vote-based Cvar Persistence Patch (v1.1)

> Original authors fdxx, kita | session-persistence patch by lead | this folder contains both the **original old version** and the **fixed new version**, each complete

## Problem
Cvars changed through votes via `ServerCommand` are only in-memory values; on map change server.cfg is re-executed and everything reverts to cfg defaults.

## Fix Mechanism (v1.1)
1. ServerCommands passed by votes are stored in a **session-persistence list** (in plugin memory) if they take the following forms:
   - ✅ Direct cvar assignments (`fps_max 128`, `sv_maxplayers X;sv_visiblemaxplayers X`, `l4d_pushdrag_enable 1`, etc. — each semicolon-separated segment is validated so the first token must be a real existing ConVar)
   - ✅ `exec "match_votes/..."` feature configs (full sets of cvar states for HUD / hide-and-seek / bile / friendly fire, etc.)
   - ❌ One-shot actions (`sm_restartmap`, `sm_reserve`, `sm_unreserve`, etc. are never replayed each map)
2. On every `OnConfigsExecuted` (after cfg files finish executing) all persisted entries are replayed in vote order; later votes override earlier ones
3. Clear timing: **server restart** (by design), plugin hot-reload, or manual clear

## New Command
`sm_votecfg_clear` (ROOT): clears the persistence list; the next map reverts to cfg defaults (no server restart needed)

## Other Changes
- Stripped the dependency on `savelog.sp` which doesn't exist on the server (`LogTo` → `LogMessage`, an equivalent one-line replacement)
- The server's original version is backed up in place as `l4d2_config_vote.sp.orig` / `.smx.orig`

## Verification Steps
1. In game, vote to change `fps_max` (e.g. 30) → `sm_cvar fps_max` confirms the change
2. Change map → `sm_cvar fps_max` should still be 30 (no longer reverts to default)
3. `sm_votecfg_clear` → change map → back to cfg default
4. Restart the server → persistence list cleared, everything back to default

## Basic Usage Tutorial

**Player side**: type `!v` (or `!vt` / `!votes` / `!si`) in chat to open the vote menu → navigate the tree categories → L4D2 native vote box appears (F1 yes / F3 no), lasts 20 seconds, passes when **yes votes > half of participants**.

**Admin privileges**:
- Admins get one-vote-pass (F1) and one-vote-veto (F3) by default, controlled per-entry by `AdminOneVotePassed` / `AdminOneVoteAgainst` (default on)
- Admins ignore MenuTeamFlags / VoteTeamFlags team restrictions by default (cvar `l4d2_config_vote_adminteamflags`, default 1)

**Command reference**:

| Command | Description |
|---|---|
| `sm_v` / `sm_vt` / `sm_votes` / `sm_si` | Open the vote menu |
| `sm_votecfg_reload` | Reload vote.kv after editing |
| `sm_votecfg_clear` | Clear the persistence list; next map reverts to cfg defaults |

## vote.kv Custom Vote Format

File: `addons/sourcemod/data/vote.kv`; run `sm_votecfg_reload` after editing.

**Structure rules**:
- Section name = the text shown in the menu
- Nested sub-sections = sub-menus (any depth)
- A section containing a `Type` key = a leaf = one vote entry

**Fields**:

| Field | Value | Description |
|---|---|---|
| `Type` | `ServerCommand` | Command runs on the **server** when the vote passes (set cvar / exec cfg, etc.) |
| | `ClientCommand` | Command runs on the **initiating player** when the vote passes |
| | `CheatCommand` | Runs on the initiating player with the cheat flag temporarily stripped (e.g. `z_spawn tank`) |
| | `ExternalVote` | No vote; the command executes on the initiating player immediately on selection (hook other plugins' commands) |
| `MenuTeamFlags` | bitmask | Who can **see** this entry in the menu: spectator 2 / survivor 4 / infected 8, added together (12 = survivors+infected) |
| `VoteTeamFlags` | bitmask | Who is **allowed to vote** (same bit rules) |
| `AdminOneVotePassed` | 0/1 | Admin yes-vote instantly passes (default 1) |
| `AdminOneVoteAgainst` | 0/1 | Admin no-vote instantly vetoes (default 1) |
| `Description` | text | Title shown in the native vote box |
| `Command` | string | The command for the chosen Type; inner quotes must be escaped, e.g. `exec \"match_votes/hud/off.cfg\"` |

**Minimal example**:
```
"选择投票类型"
{
	// ...existing content...

	"My direct vote"
	{
		"Type"			"ServerCommand"
		"MenuTeamFlags"	"12"
		"VoteTeamFlags"	"12"
		"Description"	"Enable infinite ammo"
		"Command"		"sv_infinite_ammo 1"
	}
	"My group"
	{
		"MenuTeamFlags" "12"

		"Option A"
		{
			"Type"			"ServerCommand"
			"MenuTeamFlags"	"12"
			"VoteTeamFlags"	"12"
			"Description"	"Feature: ON"
			"Command"		"feature_cvar 1"
		}
	}
}
```

**v1.1 persistence rules (read before adding new vote entries)**:
- Commands written as **cvar assignments** (`xxx_cvar 1`, `a 1;b 2` chains) or **exec cfg** forms are **kept across map changes** (until server restart or `sm_votecfg_clear`)
- One-shot actions (`sm_xxx` etc.) do not persist (reverted each map; never replayed for safety)
- To make a feature votable AND persistent: put its cvars in a cfg file and vote with `exec "path/to.cfg"`

## Folder Layout
- `旧版原始\` (original old version): pre-fix original (with vote.kv snapshot)
- `新版修复\` (fixed new version): the v1.1 currently running on the server (with the same vote.kv)
