# NekoNameSet — 玩家名字持久化插件

> v1.0 ｜ SourceMod 1.12 ｜ L4D2 ｜ 部署于 `test` 服（`/root/steamcmd/test/left4dead2`）

## 功能

玩家在服务器保存一个自定义名字，之后**每次进服自动应用**；管理员可强制为任意玩家设定/清空名字。自动应用全程静默（无聊天框提示），并修复了"换图/下一局后名字被引擎换回 Steam 默认名"的问题。

## 指令

| 指令 | 权限 | 说明 |
|---|---|---|
| `sm_nameset <名字>` | 所有人 | 保存自己的名字（可含空格），立即生效并持久化 |
| `sm_nameset`（留空） | 所有人 | 清空保存，恢复 Steam 默认名字 |
| `sm_nameset @<目标> <名字>` | 管理员(b) | 强制为某玩家保存并设置名字（也可用 `#userid`） |
| `sm_nameset @<目标>` | 管理员(b) | 清空该玩家的保存名字 |
| 对 BOT 使用目标语法 | 管理员 | 临时改名（不保存，便于测试/整活） |

## 机制

- **存档**：`addons/sourcemod/data/nekonameset.cfg`（KeyValues，SteamID2 → 名字），可手工编辑
- **自动应用时机**：
  - `OnClientAuthorized`（关键：早于 `OnClientPutInServer`，加入提示 / lerpmonitor 等播报插件读到的就是新名字）
  - `OnClientPutInServer`、换图后 1 秒全量、`round_start` 0.5 秒
- **防回退**（换局换回默认名的修复）：`player_changename` 事件内强制回写保存名
- **加入播报拦截**：`player_connect` 事件 pre-hook 改写事件的 name 字段（覆盖事件型播报）
- **静默**：自动应用零输出；指令操作只回执操作者本人

## 规则与限制

- 名字上限 31 字节，UTF-8 安全截断（不会切出半截乱码汉字）
- 自动清除引号、换行、制表符（引擎与 KV 安全）
- 清空时会立即恢复进服时记录的 Steam 原名（同图内就恢复，不用等换图）
- 有保存名的玩家在游戏中途改 Steam 名也会被强制拉回保存名（"保存名说了算"）

## 相关文件

- 插件：`addons/sourcemod/plugins/NekoNameSet.smx`
- 源码：`addons/sourcemod/scripting/NekoNameSet.sp`
- 存档：`addons/sourcemod/data/nekonameset.cfg`
- 配套补丁：`NekoNameSetPatch`（修正"连接中"提示显示默认名的问题，见其 README）

---

## English

# NekoNameSet — Player Name Persistence Plugin

> v1.0 | SourceMod 1.12 | L4D2 | deployed on the `test` server (`/root/steamcmd/test/left4dead2`)

## Features

Players can save a custom name on your server which is then **automatically applied every time they join**; admins can force-set or clear names for any player. Automatic application is fully silent (no chat output), and it fixes the issue of "the engine reverting names back to the Steam default after a map change / next round".

## Commands

| Command | Permission | Description |
|---|---|---|
| `sm_nameset <name>` | everyone | Save your own name (spaces allowed), applied immediately and persisted |
| `sm_nameset` (empty) | everyone | Clear the saved name, restore the Steam default name |
| `sm_nameset @<target> <name>` | admin(b) | Force-save and set a name for a player (`#userid` also works) |
| `sm_nameset @<target>` | admin(b) | Clear that player's saved name |
| Target syntax on a BOT | admin | Temporary rename (not saved, handy for testing/fun) |

## Mechanism

- **Storage**: `addons/sourcemod/data/nekonameset.cfg` (KeyValues, SteamID2 → name), manually editable
- **Apply timing**:
  - `OnClientAuthorized` (key point: earlier than `OnClientPutInServer`, so join announcements / lerpmonitor and other broadcast plugins already see the new name)
  - `OnClientPutInServer`, a full pass 1 second after map change, and 0.5 seconds after `round_start`
- **Anti-revert** (fix for names reverting to default on round change): force rewrites the saved name inside the `player_changename` event
- **Join announcement interception**: pre-hooks the `player_connect` event and rewrites its name field (covers event-based announcements)
- **Silence**: automatic application produces zero output; command feedback goes only to the operator

## Rules & Limits

- Name limit 31 bytes, UTF-8-safe truncation (never cuts a Chinese character in half into mojibake)
- Quotes, newlines and tabs are stripped automatically (engine & KV safe)
- Clearing restores the Steam original name recorded at join time immediately (same map, no need to wait for a map change)
- Players with a saved name who change their Steam name mid-game are forced back to the saved name ("the saved name wins")

## Related Files

- Plugin: `addons/sourcemod/plugins/NekoNameSet.smx`
- Source: `addons/sourcemod/scripting/NekoNameSet.sp`
- Storage: `addons/sourcemod/data/nekonameset.cfg`
- Companion patch: `NekoNameSetPatch` (fixes the "connecting" announcement showing the default name; see its README)
