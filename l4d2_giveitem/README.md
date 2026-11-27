# L4D2 Item Give（R 键递物插件）

Left 4 Dead 2 插件：手持指定物品、准星对准存活队友、**单击 R** 即把物品递给对方，并复刻原版的聊天提示、教练提示框、角色语音和系统音效。当前版本 **v1.0.2**。

---

## 支持的物品

| 物品 | classname | 接收方占用槽位 |
|---|---|---|
| 医疗包 | `weapon_first_aid_kit` | 3 |
| 电击器 | `weapon_defibrillator` | 3 |
| 燃烧弹药箱 | `weapon_upgradepack_incendiary` | 3 |
| 高爆弹药箱 | `weapon_upgradepack_explosive` | 3 |
| 燃烧瓶 | `weapon_molotov` | 2 |
| 土制炸弹 | `weapon_pipe_bomb` | 2 |
| 胆汁罐 | `weapon_vomitjar` | 2 |

原版止痛药 / 肾上腺素的右键递给不受影响；主副武器 R 换弹不受影响。

## 反馈（全部复刻原版）

- **聊天提示**（彩色，走 multicolors 库）：`[提示] XX 递给了 XX 一个 XX`；接收方是闲置机器人时显示 `★闲置:XX★`
- **原版教练提示框**（`env_instructor_hint`）：递/接双方各弹一条（"已把 医疗包 递给 XX" / "XX 递给你 医疗包"）
- **角色语音**：触发游戏自带 talker（`vocalize PlayerAlertGiveItem`，与语音轮盘同路径）——按角色挑台词、带字幕和口型同步
- **系统音效**：给予者播放 `ui/bigreward.wav`、被给予者播放 `ui/littlereward.wav`（原版同款）

## 失败提示

只给递出者单人提示：队友已携带同类物品 / 队友倒地无法接收 / 递物失败（物品自动退还，不会消失）。准星没对准队友时无反应无刷屏。

## 依赖

| 项目 | 说明 |
|---|---|
| SourceMod | 1.10 – 1.12（编译环境 1.12.0.7220） |
| 扩展 | 仅需 **SDKHooks** |
| 库 | multicolors（**纯 include，编译时打入 smx，服务器零依赖**） |
| gamedata | 无 |

## 安装

```
addons/sourcemod/plugins/l4d2_giveitem.smx
addons/sourcemod/scripting/l4d2_giveitem.sp          （源码，可不装）
addons/sourcemod/translations/l4d2_giveitem.phrases.txt
cfg/sourcemod/l4d2_giveitem.cfg
cfg/sourcemod/l4d2_giveitem_english.cfg              （ASCII 备用版，中文注释刷屏时用它覆盖上一行同名文件）
```

> **不要与 `l4d_gear_transfer`（投掷医疗包按R给队友）同时启用**——两者都拦截 R 键递物，会重复触发/判断混乱，二选一。
> 升级时手动覆盖 `cfg/sourcemod/l4d2_giveitem.cfg`（`AutoExecConfig` 不重写已存在的文件）。

## cvar 一览（16 项）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d2_giveitem_enable` | 1 | 总开关 |
| `l4d2_giveitem_range` | 150.0 | 递物最大距离（单位） |
| `l4d2_giveitem_cooldown` | 0.5 | 同一玩家递物冷却（秒） |
| `l4d2_giveitem_chat` | 1 | 全场聊天提示 |
| `l4d2_giveitem_hint` | 1 | 原版教练提示框 |
| `l4d2_giveitem_hinttime` | 5.0 | 提示框停留秒数 |
| `l4d2_giveitem_hintcolour` | 255 255 255 | 提示框颜色（R G B） |
| `l4d2_giveitem_voice` | 1 | 触发原版 talker 台词（带字幕） |
| `l4d2_giveitem_sound` | 1 | 原版系统音效（bigreward / littlereward） |
| `l4d2_giveitem_allow_medkit` | 1 | 允许递医疗包 |
| `l4d2_giveitem_allow_defib` | 1 | 允许递电击器 |
| `l4d2_giveitem_allow_incendiary` | 1 | 允许递燃烧弹药箱 |
| `l4d2_giveitem_allow_explosive` | 1 | 允许递高爆弹药箱 |
| `l4d2_giveitem_allow_molotov` | 1 | 允许递燃烧瓶 |
| `l4d2_giveitem_allow_pipebomb` | 1 | 允许递土制炸弹 |
| `l4d2_giveitem_allow_bile` | 1 | 允许递胆汁罐 |

## 实现说明（给想改的人）

- 转移方式：`RemovePlayerItem` + `Kill` → `GivePlayerItem`（同名重给；7 类物品均为一次性无状态）。`GivePlayerItem` 失败会自动退还，物品不会消失。
- 递物成功后 `FakeClientCommand(client, "vocalize PlayerAlertGiveItem")` —— 与服务端语音轮盘同路径，由游戏 talker 完成台词挑选 / 字幕 / 口型。
- 聊天颜色走 multicolors 的 `{green}` / `{lightgreen}` / `{olive}` 标签（库在发送前替换成真实颜色字节；原生 `PrintToChat` 不处理标签）。
- 弹药箱（upgradepack）在个别环境 `GivePlayerItem` 可能失败——已内置退还逻辑，若实测失败反馈作者换实体落地方案。

## 已知限制

- 教练提示框受客户端「教学提示」设置影响：客户端关闭则看不到（聊天提示不受影响）。
- `vocalize` 台词受游戏语音冷却约束，连续快速递物时可能间隔一两句才出声（原版机制如此）。

---

## English

# L4D2 Item Give (R-Key Item Handoff Plugin)

Left 4 Dead 2 plugin: hold a supported item, aim your crosshair at a living teammate, and **single-click R** to hand the item over — reproducing the vanilla chat message, instructor hint, survivor voice line and system sounds. Current version **v1.0.2**.

---

## Supported Items

| Item | classname | Slot taken by receiver |
|---|---|---|
| First aid kit | `weapon_first_aid_kit` | 3 |
| Defibrillator | `weapon_defibrillator` | 3 |
| Incendiary ammo pack | `weapon_upgradepack_incendiary` | 3 |
| Explosive ammo pack | `weapon_upgradepack_explosive` | 3 |
| Molotov | `weapon_molotov` | 2 |
| Pipe bomb | `weapon_pipe_bomb` | 2 |
| Bile bomb | `weapon_vomitjar` | 2 |

The vanilla right-click handoff for pain pills / adrenaline is unaffected; R-key reload for primary/secondary weapons is unaffected.

## Feedback (all faithfully reproduced from vanilla)

- **Chat message** (colored, via the multicolors library): `[提示] XX handed XX a XX`-style line; if the receiver is an idle bot, it shows `★Idle:XX★`
- **Vanilla instructor hint** (`env_instructor_hint`): shown to both giver and receiver ("Gave first aid kit to XX" / "XX gave you a first aid kit")
- **Voice lines**: triggers the game's own talker (`vocalize PlayerAlertGiveItem`, same path as the vocalize wheel) — character-appropriate lines with lip sync and subtitles
- **System sounds**: giver hears `ui/bigreward.wav`, receiver hears `ui/littlereward.wav` (same as vanilla)

## Failure Prompts

Only the giver gets a private message: teammate already carries the same item type / teammate is incapped and cannot receive / handoff failed (the item is automatically returned, never lost). Aiming at nothing or at a non-teammate produces no output and no spam.

## Requirements

| Component | Notes |
|---|---|
| SourceMod | 1.10 – 1.12 (compiled on 1.12.0.7220) |
| Extensions | **SDKHooks** only |
| Libraries | multicolors (**include only, compiled into the smx — zero server dependencies**) |
| gamedata | none |

## Installation

```
addons/sourcemod/plugins/l4d2_giveitem.smx
addons/sourcemod/scripting/l4d2_giveitem.sp          (source, optional)
addons/sourcemod/translations/l4d2_giveitem.phrases.txt
cfg/sourcemod/l4d2_giveitem.cfg
cfg/sourcemod/l4d2_giveitem_english.cfg              (ASCII fallback; overwrite the above file if Chinese comments cause spam)
```

> **Do not run together with `l4d_gear_transfer` (throw medkit with R to give it to teammates)** — both intercept R for handoff and will double-trigger/conflict; pick one.
> When upgrading, manually overwrite `cfg/sourcemod/l4d2_giveitem.cfg` (`AutoExecConfig` never rewrites an existing file).

## Cvars (16 total)

| cvar | Default | Description |
|---|---|---|
| `l4d2_giveitem_enable` | 1 | Master switch |
| `l4d2_giveitem_range` | 150.0 | Max handoff distance (units) |
| `l4d2_giveitem_cooldown` | 0.5 | Per-player handoff cooldown (seconds) |
| `l4d2_giveitem_chat` | 1 | Global chat message |
| `l4d2_giveitem_hint` | 1 | Vanilla instructor hint |
| `l4d2_giveitem_hinttime` | 5.0 | Hint display seconds |
| `l4d2_giveitem_hintcolour` | 255 255 255 | Hint color (R G B) |
| `l4d2_giveitem_voice` | 1 | Vanilla talker voice lines (with subtitles) |
| `l4d2_giveitem_sound` | 1 | Vanilla system sounds (bigreward / littlereward) |
| `l4d2_giveitem_allow_medkit` | 1 | Allow handing first aid kits |
| `l4d2_giveitem_allow_defib` | 1 | Allow handing defibrillators |
| `l4d2_giveitem_allow_incendiary` | 1 | Allow handing incendiary ammo packs |
| `l4d2_giveitem_allow_explosive` | 1 | Allow handing explosive ammo packs |
| `l4d2_giveitem_allow_molotov` | 1 | Allow handing molotovs |
| `l4d2_giveitem_allow_pipebomb` | 1 | Allow handing pipe bombs |
| `l4d2_giveitem_allow_bile` | 1 | Allow handing bile bombs |

## Implementation Notes (for those who want to modify)

- Transfer method: `RemovePlayerItem` + `Kill` → `GivePlayerItem` (re-gives the same classname; all 7 item types are stateless one-shot items). If `GivePlayerItem` fails, the item is automatically returned — it never disappears.
- On a successful handoff, `FakeClientCommand(client, "vocalize PlayerAlertGiveItem")` — the same path as the server-side vocalize wheel; the game's talker picks the line, subtitles and lip sync.
- Chat colors use multicolors' `{green}` / `{lightgreen}` / `{olive}` tags (the library replaces them with real color bytes before sending; native `PrintToChat` doesn't process tags).
- Ammo packs (upgradepack) may fail `GivePlayerItem` in some environments — refund logic is built in; if it fails in practice, report to the author to switch to a drop-and-pickup approach.

## Known Limitations

- The instructor hint depends on the client's "instructions/hints" setting: if disabled on the client, the hint won't show (chat message unaffected).
- `vocalize` lines obey the game's voice cooldown; rapid consecutive handoffs may skip a line or two (vanilla behavior).
