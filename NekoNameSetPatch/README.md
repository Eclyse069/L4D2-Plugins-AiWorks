# NekoNameSetPatch — "连接中"提示改名补丁

> v1.0 ｜ NekoNameSet 的配套补丁 ｜ 需与 NekoNameSet + [L4D2]加入退出提示 共存

## 解决的问题

`加入退出提示.smx` 在玩家连接时输出：

```
[服务器] 玩家[Steam默认名]连接中...
```

该消息在 `OnClientConnected` 转发里用 `%N`（当时引擎名）打印，早于 NekoNameSet 在 `OnClientAuthorized` 的改名时机，所以显示的是默认名（"加入"消息时机更晚，NekoNameSet 已覆盖，显示正确）。

## 解决方式

读 `加入退出提示.sp` 源码后发现它自带开关 cvar `l4d2_connecting_notify`（只管"连接中"消息和音效）。补丁因此：

1. **加载/每张图开始**：置 `l4d2_connecting_notify = 0`，关闭原"连接中"输出
2. **自己挂 `OnClientConnected`**：
   - 每次连接时**重新导入** `data/nekonameset.cfg`（与 NekoNameSet 保存的最新名字实时同步）
   - 有保存名 → 输出同格式消息（颜色代码 \x04\x05\x03 与原版逐字节一致）：`[服务器] 玩家<保存名>连接中...`
   - 无保存名/取不到 ID → 输出与原版**一模一样**的默认名消息，行为不变
3. **音效**照搬原版：`klaxon1.wav` + EmitSoundToAll 参数逐个一致，听感相同
4. **卸载补丁自动还原** cvar 为 1，恢复原插件行为，零残留

方案不依赖插件加载顺序；"加入"、"退出"、退出理由翻译等功能全部不动。

## 相关文件

- 插件：`addons/sourcemod/plugins/NekoNameSetPatch.smx`
- 源码：`addons/sourcemod/scripting/NekoNameSetPatch.sp`
- 依赖：NekoNameSet 的存档 `data/nekonameset.cfg`（只读）、加入退出提示.smx 在服（其 cvar 被接管）

## 维护提醒

- 如果以后更新了 `加入退出提示.smx`，确认它仍保留 `l4d2_connecting_notify` 这个 cvar（在就无影响；不在则补丁只影响"连接中"这一条，卸载即恢复）
- 想彻底停用补丁：`sm plugins unload NekoNameSetPatch`（自动还原原行为）

---

## English

# NekoNameSetPatch — "Connecting" Announcement Rename Patch

> v1.0 | companion patch for NekoNameSet | requires NekoNameSet + [L4D2] join/leave announcements to coexist

## The Problem

`加入退出提示.smx` (join/leave announcements) prints this when a player connects:

```
[服务器] 玩家[Steam default name]连接中...   ([Server] Player [Steam default name] connecting...)
```

That message is printed with `%N` (the engine name at that moment) inside the `OnClientConnected` forward, which fires before NekoNameSet's rename at `OnClientAuthorized`, so it shows the default name (the "joined" message fires later, after NekoNameSet has already overridden it, and displays correctly).

## The Solution

Reading the `加入退出提示.sp` source revealed it ships a switch cvar `l4d2_connecting_notify` (governs only the "connecting" message and sound). The patch therefore:

1. **On load / at each map start**: sets `l4d2_connecting_notify = 0`, turning off the original "connecting" output
2. **Hooks `OnClientConnected` itself**:
   - On every connect it **re-imports** `data/nekonameset.cfg` (always in sync with NekoNameSet's latest saved names)
   - If a saved name exists → prints a same-format message (color codes \x04\x05\x03 byte-identical to the original): `[Server] Player <saved name> connecting...`
   - No saved name / ID unavailable → prints a default-name message **identical** to the original, no behavior change
3. **Sound** copied from the original: `klaxon1.wav` + EmitSoundToAll parameters matched one by one, sounds the same
4. **Unloading the patch automatically restores** the cvar to 1, restoring original plugin behavior, zero residue

The approach doesn't depend on plugin load order; "joined", "left", leave-reason translation and all other features are untouched.

## Related Files

- Plugin: `addons/sourcemod/plugins/NekoNameSetPatch.smx`
- Source: `addons/sourcemod/scripting/NekoNameSetPatch.sp`
- Depends on: NekoNameSet's storage `data/nekonameset.cfg` (read-only), `加入退出提示.smx` on the server (its cvar is taken over)

## Maintenance Notes

- If you later update `加入退出提示.smx`, verify it still has the `l4d2_connecting_notify` cvar (if present, nothing changes; if removed, the patch only affects the single "connecting" line, and unloading restores everything)
- To fully disable the patch: `sm plugins unload NekoNameSetPatch` (original behavior is restored automatically)
