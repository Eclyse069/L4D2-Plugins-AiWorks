# NekoVanillaNameRotator — 原版服名轮换插件

> v1.0 ｜ SourceMod 1.12 ｜ 仅本地归档，**未部署到服务器**（按你的要求）
> NekoServerNameRotator 的姊妹版本，面向**不使用 NekoServerName.smx** 的服务器

## 与 Neko 版的差异

| 项目 | NekoServerNameRotator | 本插件 NekoVanillaNameRotator |
|---|---|---|
| 依赖 | NekoServerName.smx + nekocustom.cfg | **零依赖**，直接改引擎原生 hostname |
| 服名内容 | 支持 {gamedifficulty}/{flow}/{realplayernum} 等占位符 | **纯静态文本**（占位符是 NekoServerName 的功能）|
| 生效方式 | 覆写 nekocustom.cfg + reload NekoServerName | hostname convar 直写，即时生效 |
| server.cfg 换图重设服名 | 靠 reload 机制覆盖 | **10 秒巡检自动纠正回来**（自愈式）|
| 其它插件抢改 hostname | — | 同样 10 秒内纠正 |

## 三种模式
- `time` — 按现实时段轮换（凌晨0/早上6/下午12/夜晚18/深夜22，配置可改）
- `order` — 按配置顺序循环，每 `interval` 秒一切换（默认 300）
- `random` — 随机（不与上一次重复），每 `interval` 秒一切换

## 部署（目标服务器上）
```
addons/sourcemod/plugins/NekoVanillaNameRotator.smx   ← 编译产物
addons/sourcemod/scripting/NekoVanillaNameRotator.sp   ← 源码留档
addons/sourcemod/configs/NekoVanillaNameRotator.cfg    ← 配置(缺失时插件会自动生成默认)
```
首次加载自动生成默认配置（时段照抄、名字为"你的服务器名·XX"占位），编辑配置后 `sm_hostnamerotate_reload` 生效。

## 配置（configs/NekoVanillaNameRotator.cfg）
```
"NekoVanillaNameRotator"
{
	"Settings"   { mode / interval / timezone }
	"TimePeriods"
	{
		"凌晨"	{ "start" "0"	"name" "你的服务器名·凌晨好梦" }
		"早上"	{ "start" "6"	"name" "..." }
		...每项: start=起始小时, name=该时段服务器名, 加名字就加一项
	}
}
```

## 管理命令（ROOT）
- `sm_hostnamerotate` — 状态（模式/时段表/当前应用项）
- `sm_hostnamerotate_next` — 立即轮换（time 模式=重新应用当前时段）
- `sm_hostnamerotate_set <1-N>` — 立即应用指定编号
- `sm_hostnamerotate_mode <time|order|random>` — 切换并持久化
- `sm_hostnamerotate_reload` — 重读配置

## 继承自 Neko 系列的成熟机制
10 秒巡检、跨午夜回绕、配置损坏自动重生、模式切换整文件重写（不丢配置）、order 首轮防卡死、只在变化时输出日志。

---

## English

# NekoVanillaNameRotator — Vanilla Hostname Rotator Plugin

> v1.0 | SourceMod 1.12 | local archive only, **not deployed to any server** (per your request)
> Sister version of NekoServerNameRotator, for servers that **don't use NekoServerName.smx**

## Differences vs. the Neko Version

| Item | NekoServerNameRotator | This Plugin: NekoVanillaNameRotator |
|---|---|---|
| Dependency | NekoServerName.smx + nekocustom.cfg | **Zero dependencies**, directly sets the engine's native hostname |
| Name content | Supports placeholders like {gamedifficulty}/{flow}/{realplayernum} | **Pure static text** (placeholders are a NekoServerName feature) |
| How it applies | Overwrite nekocustom.cfg + reload NekoServerName | Writes the hostname convar directly, instant effect |
| server.cfg resetting the name on map change | Covered by the reload mechanism | **Auto-corrected back within 10 seconds by polling** (self-healing) |
| Other plugins hijacking hostname | — | Corrected back within 10 seconds too |

## Three Modes
- `time` — rotate by real-world time period (late night 0 / morning 6 / afternoon 12 / evening 18 / late night 22, configurable)
- `order` — cycle in config order, switching every `interval` seconds (default 300)
- `random` — random (never repeats the last one), switching every `interval` seconds

## Deployment (on the target server)
```
addons/sourcemod/plugins/NekoVanillaNameRotator.smx   ← compiled binary
addons/sourcemod/scripting/NekoVanillaNameRotator.sp   ← source archive
addons/sourcemod/configs/NekoVanillaNameRotator.cfg    ← config (auto-generated with defaults if missing)
```
On first load a default config is generated automatically (same time periods; names are "Your Server Name·XX" placeholders); after editing the config run `sm_hostnamerotate_reload` to apply.

## Config (configs/NekoVanillaNameRotator.cfg)
```
"NekoVanillaNameRotator"
{
	"Settings"   { mode / interval / timezone }
	"TimePeriods"
	{
		"凌晨"	{ "start" "0"	"name" "Your Server Name·Late night" }
		"早上"	{ "start" "6"	"name" "..." }
		...each item: start=start hour, name=server name for that period; add an item to add a name
	}
}
```

## Admin Commands (ROOT)
- `sm_hostnamerotate` — status (mode/period table/currently applied item)
- `sm_hostnamerotate_next` — rotate immediately (time mode = re-apply current period)
- `sm_hostnamerotate_set <1-N>` — apply the given index immediately
- `sm_hostnamerotate_mode <time|order|random>` — switch and persist
- `sm_hostnamerotate_reload` — reload the config

## Proven Mechanisms Inherited from the Neko Series
10-second polling, midnight wrap-around, auto-regeneration of corrupted configs, whole-file rewrite on mode switch (config never lost), order-mode first-cycle deadlock guard, logging only on actual changes.
