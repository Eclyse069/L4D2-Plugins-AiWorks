# DiageticChat — 聊天消息"头顶气泡"插件

> v1.0 ｜ SourceMod 1.12 ｜ L4D2
> 由客户端 MOD "Diagetic Chat Messages"（`scripts/vscripts/diagetic_chat.nut`，893 行）移植

## 功能

玩家打字 → **聊天框照常显示（共存，零抑制）**，同时在说话者头顶显示世界空间气泡（env_instructor_hint）：

- **长句分块**：超过 42 字节按空格/标点智能切块，顺序播放；每块时长 = 字数 × 0.065s + 注视奖励，钳制 2.2~4.0s，末块 4.5~5.0s
- **视线感知**：观看者没看向说话者（44° 视线锥 + 0.04 回滞）→ 气泡变成**屏幕边缘提醒图标**，指向说话者方向；回头看 → 显示正文，漏看了中间段落则加 `-` 前缀
- **每观看者独立锚点**：气泡挂在独立锚点实体上，每 0.03s 跟随说话者头部移动；侧向偏移 10 单位避免遮挡名牌
- **首块宽限**：所有人都没在看时，首块最多多挂 1.25 秒
- **关闭开关**：`sm_dchat`（聊天框输入 `!dchat`）切换本人是否看到气泡；关闭者只看普通聊天框。按 SteamID 持久化

## 与原 MOD 的差异（按部署要求）

| 项目 | 原 MOD | 本插件 |
|---|---|---|
| 聊天框 | 被抑制（只在气泡里看）| **保留，与气泡共存** |
| 幸存者 bark 语音 | 说话时角色喊话（8 角色 ×4 条，1/40 稀有音）| **未移植**（忽略 sound） |
| 自定义气泡图标 | 需客户端装 materials，!chaticons 开关 | **未移植**（忽略 materials），统一 `icon_alert` |
| 触发方式 | VScript InterceptChat（客户端 MOD）| SM 插件（服务端，玩家免装） |

## 指令与配置

- `sm_dchat` / `!dchat` — 切换本人气泡显示（持久化到 `data/diagetchat_optout.cfg`）
- cvars（`cfg/sourcemod/L4D2_DiageticChat.cfg`）：
  - `dchat_enabled`（默认 1）总开关
  - `dchat_showown`（默认 1）说话者自己是否看到自己的气泡
  - `dchat_maxchunk`（默认 42）单块最大字符数（字节，10~58）
  - `dchat_debug`（默认 0）调试输出
- 时长/偏移/视线锥等手感常数照抄原 MOD 数值（源码 `#define` 区）

## 文件位置

- 插件：`addons/sourcemod/plugins/DiageticChat.smx`
- 源码：`addons/sourcemod/scripting/DiageticChat.sp`
- 退订存档：`addons/sourcemod/data/diagetchat_optout.cfg`（格式：`STEAM_1:x:y=1`，可手工编辑）
- cvar 配置：`cfg/sourcemod/L4D2_DiageticChat.cfg`

## 行为细节

- `!` `/` `@` 开头的消息（SM 触发器/命令）不做气泡
- `say_team` 与普通聊天同样处理（与原 MOD 一致）
- 说话者死亡/离开时气泡立即清除；换图/换局时全量清除
- 玩家中途 `!dchat` 关闭，屏幕上已有的气泡立即消失

---

## English

# DiageticChat — Chat Message "Overhead Bubble" Plugin

> v1.0 | SourceMod 1.12 | L4D2
> Ported from the client-side MOD "Diagetic Chat Messages" (`scripts/vscripts/diagetic_chat.nut`, 893 lines)

## Features

When a player types a message → **the chat box still shows it as usual (coexists, zero suppression)**, while a world-space bubble (env_instructor_hint) is displayed above the speaker's head:

- **Long message chunking**: messages longer than 42 bytes are intelligently split at spaces/punctuation and played in order; each chunk lasts chars × 0.065s + gaze bonus, clamped to 2.2–4.0s (last chunk 4.5–5.0s)
- **Gaze awareness**: if the viewer isn't looking at the speaker (44° view cone + 0.04 hysteresis) → the bubble turns into an **edge-of-screen reminder icon** pointing toward the speaker; looking back shows the text again, with a `-` prefix if middle chunks were missed
- **Per-viewer independent anchors**: each bubble hangs on its own anchor entity, following the speaker's head every 0.03s; 10-unit lateral offset avoids covering the name tag
- **First-chunk grace**: when nobody is looking, the first chunk can stay up to 1.25 seconds longer
- **Opt-out switch**: `sm_dchat` (type `!dchat` in chat) toggles whether *you* see bubbles; players who opt out only see the normal chat box. Persisted per SteamID

## Differences from the Original MOD (per deployment requirements)

| Item | Original MOD | This Plugin |
|---|---|---|
| Chat box | Suppressed (only visible in bubbles) | **Kept, coexists with bubbles** |
| Survivor bark voices | Characters speak when talking (8 characters × 4 lines, 1/40 rare sounds) | **Not ported** (sound ignored) |
| Custom bubble icons | Requires client-side materials, !chaticons toggle | **Not ported** (materials ignored), unified `icon_alert` |
| Trigger method | VScript InterceptChat (client MOD) | SM plugin (server-side, no client install needed) |

## Commands & Configuration

- `sm_dchat` / `!dchat` — toggle your own bubble display (persisted to `data/diagetchat_optout.cfg`)
- cvars (`cfg/sourcemod/L4D2_DiageticChat.cfg`):
  - `dchat_enabled` (default 1) master switch
  - `dchat_showown` (default 1) whether the speaker sees their own bubble
  - `dchat_maxchunk` (default 42) max characters per chunk (bytes, 10~58)
  - `dchat_debug` (default 0) debug output
- Timing/offset/view-cone feel constants are copied verbatim from the original MOD (see `#define` section in source)

## File Locations

- Plugin: `addons/sourcemod/plugins/DiageticChat.smx`
- Source: `addons/sourcemod/scripting/DiageticChat.sp`
- Opt-out storage: `addons/sourcemod/data/diagetchat_optout.cfg` (format: `STEAM_1:x:y=1`, manually editable)
- cvar config: `cfg/sourcemod/L4D2_DiageticChat.cfg`

## Behavior Details

- Messages starting with `!` `/` `@` (SM triggers/commands) get no bubble
- `say_team` is handled the same as normal chat (same as the original MOD)
- Bubbles are cleared immediately when the speaker dies/leaves; full cleanup on map change/round change
- If a player turns off `!dchat` mid-round, bubbles already on their screen disappear immediately
