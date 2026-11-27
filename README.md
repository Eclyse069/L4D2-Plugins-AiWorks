# L4D2-Plugins-AiWorks

> 本仓库收录求生之路 2（L4D2）服务器编写、移植与修复的 SourceMod 插件。每个插件目录内含完整的插件文件（`addons/`、`cfg/` 等）、源码与中英双语 README。均由DeepSeekV4.1 Flash 与 GLM-5.1许愿修改与编写。
>
> This repository collects SourceMod plugins By DeepSeekV4.1 Flash and GLM-5.1, ported or fixed for my Left 4 Dead 2 server. Each plugin folder contains the full plugin files (`addons/`, `cfg/`, etc.), source code and a bilingual (Chinese/English) README.

- **游戏 / Game**: Left 4 Dead 2（部分插件兼容 L4D1 / some plugins also work on L4D1）
- **平台 / Platform**: Windows / Linux 服务端 / dedicated servers
- **依赖 / Requirements**: [SourceMod](https://www.sourcemod.net/) 1.10 – 1.12；大部分插件仅需 SDKHooks 扩展 / most plugins only need the SDKHooks extension

## 插件列表 / Plugins

### 游戏玩法 · Gameplay & Fun

1. [DiageticChat](./DiageticChat/): Shows player chat messages as world-space "speech bubbles" (env_instructor_hint) above the speaker's head, while the chat box keeps working as usual. Long messages are auto-chunked and played in sequence; if you're not looking at the speaker, the bubble turns into an edge-of-screen icon pointing at them. Ported from the client-side VScript MOD "Diagetic Chat Messages", rebuilt as a server plugin so players need no client mod.
   > 聊天消息"头顶气泡"插件：打字时聊天框照常显示，同时在说话者头顶播放世界空间气泡（长句自动分块、视线感知、按 SteamID 持久化开关），由客户端 MOD 移植为服务端插件，玩家免装。

2. [l4d2_giveitem](./l4d2_giveitem/): Hand an item to a living teammate by aiming at them and single-clicking R — supports first aid kit, defibrillator, ammo packs, molotov, pipe bomb and bile bomb. Faithfully reproduces the vanilla chat message, instructor hint, survivor voice line and reward sounds. Failed handoffs auto-return the item.
   > R 键递物插件：手持指定物品、准星对准存活队友单击 R 即可递出（医疗包/电击器/弹药箱/燃烧瓶/土制炸弹/胆汁罐），完整复刻原版聊天提示、教练提示框、角色语音与系统音效；失败自动退还，物品不丢。

3. [l4d_pushdrag](./l4d_pushdrag/): Grab, drag and throw props, players, teammates, enemy special infected, Witches and map ragdolls (double-tap R). Heavily optimized and fixed edition of Pan Xiaohai's "Push And Drag" (v2.5.0): all launch-fling bugs fixed, mechanism entities protected, fall-damage protection, stagger-cancel via engine CancelStagger, spectator support, 4 languages, 52 cvars.
   > 推人拖物插件优化版（v2.5.0）：双击 R 抓取物件/玩家/特感/Witch/布娃娃，任意拖动投掷；修复原版弹飞等老 bug，支持旁观者抓取、硬直真取消、击杀归属投掷者，52 项 cvar 可调。

### 服务器管理 · Server Management & Tools

5. [l4d2_config_vote](./l4d2_config_vote/): Makes cvars changed through in-game votes survive map changes — a session-persistence patch for fdxx/kita's config vote plugin. Direct cvar assignments and `exec match_votes/...` configs passed by vote are replayed after every map's cfg execution; one-shot commands are never replayed. `sm_votecfg_clear` resets everything.
   > 投票修改保持补丁（v1.1）：投票通过的 cvar 赋值与功能配置换图后不再被 server.cfg 打回默认（会话内按投票顺序重放），重启服务器或 `sm_votecfg_clear` 才清零。

6. [l4d2_custom_commands](./l4d2_custom_commands/): Custom admin command pack (sm_grabentity and friends), refactored with full i18n (English / Simplified Chinese / Traditional Chinese, auto-selected by client language), fixed the stuck-grab bug when the grabbed entity dies, and adds `sm_grabentity_inv` — grab an entity that only you can see while its collision, AI and physics keep working.
   > 自定义命令国际化重构版：约 130 处提示接入翻译系统（英/简中/繁中按客户端语言自动生效）；修复抓取对象失效后永久卡死的 bug；新增 sm_grabentity_inv 隐形抓取（仅自己可见，碰撞照常）。

7. [NekoNameSet](./NekoNameSet/): Players save a custom name (`sm_nameset <name>`) that is silently re-applied every time they join — applied early at `OnClientAuthorized` so join announcements already show the new name, with anti-revert protection against the engine switching names back to the Steam default. Admins can force-set/clear names for any player.
   > 玩家名字持久化插件：玩家保存自定义名字后每次进服自动静默应用，修复"换图/下一局名字被换回 Steam 默认名"的问题；管理员可强制为任意玩家设定/清空名字。

8. [NekoNameSetPatch](./NekoNameSetPatch/): Companion patch for NekoNameSet — makes the "[Server] Player connecting..." announcement show the player's saved name instead of their Steam default name, by taking over the join/leave plugin's "connecting" message with byte-identical colors and sound. Unloading the patch restores original behavior automatically.
   > "连接中"提示改名补丁：接管加入退出提示插件的"连接中"消息，使其显示 NekoNameSet 保存名（颜色码与音效与原版逐字节一致），卸载自动还原，零残留。

9. [NekoServerNameRotator](./NekoServerNameRotator/): Rotates the server name through a pool of `nekocustom_XX.cfg` files — by real-world time period (late night/morning/afternoon/evening/late night), in order, or randomly. Overwrites `nekocustom.cfg` and reloads NekoServerName.smx, so all its placeholders (`{gamedifficulty}`, `{flow}`, `{realplayernum}`…) keep working.
   > 服务器名字轮换插件（配合 NekoServerName.smx）：按现实时段/顺序/随机轮换服名池文件，覆写 + 重载即生效，占位符功能全部保留。

10. [NekoVanillaNameRotator](./NekoVanillaNameRotator/): Sister version of NekoServerNameRotator for servers that don't run NekoServerName.smx — rotates the engine's native `hostname` directly with zero dependencies, and self-heals within 10 seconds whenever server.cfg or another plugin resets the name on map change.
    > 原版服名轮换插件：不依赖 NekoServerName，直写引擎 hostname 定时轮换；server.cfg 换图重设服名时 10 秒内自动纠正（自愈式）。

11. [NekoMOTDRotator](./NekoMOTDRotator/): Rotates the server banner (hostfile) and MOTD (motdfile) content by real-world time period, in order, or randomly — the same mechanism as NekoServerNameRotator. Takes effect for every player who joins afterwards; pool files are seeded from the currently active files on first load.
    > host/MOTD 按时段轮换插件：按现实时段（凌晨/早上/下午/夜晚/深夜）或顺序/随机轮换服务器横幅与 MOTD 内容，对之后进服的玩家立即生效。

## 安装 / Installation

- 将插件目录中的 `addons/`、`cfg/` 整体复制到服务器 `left4dead2/` 目录下 / Copy each plugin's `addons/` and `cfg/` folders into your server's `left4dead2/` directory.
- 编译产物为 `.smx`（已在各插件 `addons/sourcemod/plugins/` 内），源码 `.sp` 在 `addons/sourcemod/scripting/` / Each plugin ships its compiled `.smx` in `addons/sourcemod/plugins/`; `.sp` sources are kept in `addons/sourcemod/scripting/`.
- 带 `cfg/sourcemod/xxx_english.cfg` 的插件为 ASCII 备用配置（中文注释在个别环境会刷 unknown command 时用它覆盖同名文件）/ Plugins with an `xxx_english.cfg` provide an ASCII fallback config — use it to overwrite the normal cfg if Chinese comments cause "unknown command" spam on your server.
- 具体依赖与注意事项见各插件目录的 README / See each plugin folder's README for dependencies and caveats.

## 说明 / Notes

- 所有插件在 SourceMod 1.12（SourcePawn）下编译，向后兼容 1.10+ / All plugins are compiled under SourceMod 1.12 (SourcePawn) and compatible with 1.10+.

## License / 许可证

本仓库整体以 [GPL-3.0](./LICENSE) 授权 / This repository is licensed under the [GPL-3.0](./LICENSE).

部分目录为**第三方插件的修改版或移植版**，原作者对其原始代码保留全部版权与署名，本仓库仅对修改/移植部分声明 GPL-3.0 / Some folders contain **modified or ported versions of third-party plugins**; the original authors keep all copyright and attribution for their original code, and GPL-3.0 applies only to the modifications/ports made in this repository:

| 目录 / Folder | 原作者 / Original author | 说明 / Note |
|---|---|---|
| `l4d_pushdrag` | Pan Xiaohai（v1.2）| 本仓库为大幅优化/修复版（v2.5.0），原作版权归原作者 / heavily optimized & fixed edition; original copyright belongs to the original author |
| `l4d2_config_vote` | fdxx, kita | 会话保持补丁版（v1.1），原作版权归原作者 / session-persistence patch (v1.1) |
| `DiageticChat` | 客户端 MOD "Diagetic Chat Messages" 原作者 by andy | 由 VScript MOD 移植为服务端插件 / ported from the client-side VScript MOD |

编译所依赖的第三方库（multicolors、morecolors 等 include）遵循其各自的许可证 / Third-party libraries used for compilation (multicolors, morecolors, etc.) are governed by their own licenses.
