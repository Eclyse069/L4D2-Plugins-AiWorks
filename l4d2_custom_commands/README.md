# l4d2_custom_commands — 国际化重构 + 抓取修复 + 隐形变体 原版地址：https://forums.alliedmods.net/showthread.php?p=1251446 by Author: honorcode23

> 旧版原始 + 新版修复双归档 ｜ test 服已部署新版（Status: running，无错误）

## 本次改动

### 1. 全部提示国际化（翻译系统）
- 源码所有用户可见提示改为 `%t` 短语调用（约 130 处），颜色码留在代码
- 新增三套翻译文件（`LoadTranslations("l4d2_custom_commands.phrases")`）：
  - `translations/l4d2_custom_commands.phrases.txt`（英文基准，其他语言玩家显示英文）
  - `translations/chi/...`（简体中文，游戏语言=简中的玩家自动生效）
  - `translations/zho/...`（繁体中文，游戏语言=繁中的玩家自动生效）
- 覆盖：用法提示、结果提示、错误提示、sm_cchelp 帮助列表、示例行
- 菜单标签（约75个 AddMenuItem）保持原有中文硬编码（服务你的受众，不引入风险）
- 控制台/日志消息跟随服务器语言（英文为主）
- 顺手修掉：帮助行与控制台行中重复打印的残留（原版复制粘贴 bug）

### 2. sm_grabentity 修复
| 问题 | 修复 |
|---|---|
| **抓取对象被破坏/死亡后，取消抓取报"该entity无效"且永久卡死** | Release 无效分支现在清除全部抓取状态并提示"抓取已取消 (对象已失效)" |
| 空瞄准（什么都没看）触发数组越界错误 | 先判 entity≤0，提示"无效Entity或未瞄准Entity" |
| CmdGrabEntity 控制台拒绝消息重复打印两次 | 去重 |
| OnMapEnd 漏清客户端槽位的 g_iLastGrabbedEntity | 补清 |

### 3. 新增 sm_grabentity_inv
- 抓取后对象**仅抓取者本人可见**（SDKHook SetTransmit 对他人拦截）
- **碰撞、AI、物理全部照常**（纯视觉层屏蔽）
- 再次输入解除抓取并恢复正常可见
- 权限与 sm_grabentity 相同（DESIRED_FLAGS = ADMFLAG_UNBAN）

## 实测清单
1. 抓物品 → 把它打碎 → 再按 sm_grabentity → 提示"抓取已取消"，可正常抓新对象
2. 什么都不瞄准按 sm_grabentity → 正常提示，无错误刷屏
3. sm_grabentity_inv 抓感染者 → 其他人看不见、你看得见、它照样挡路
4. 再按一次 sm_grabentity_inv → 解除抓取，其他人恢复可见
5. 简中/繁中/英文客户端各看一遍提示（sm_cchelp 与任意命令的用法错误）
6. **sm_cchelp 修复（v2）**：帮助列表改为输出到**控制台**（聊天框只留一句提示），逐行翻译、按客户端语言显示；修复了三个转换残留 bug（`%%t` 双百分号、HelpGrabEntityInv 重复、服务器控制台无防护）
6. sm_grabentity_inv 帮助行已加入 sm_cchelp 列表

## 归档说明
- **旧版原始**：取自 gua 服（sourcemod2）的同版本副本（5293 行/中文修改版，与 test 服原版逐项特征吻合）。test 服原文件在本次改造中被直接替换——下次改造前我会先做 .orig 备份
- **新版修复**：当前 test 服在跑的版本（含 smx/sp/三套翻译文件）

## 已知但不改的设计（原版行为）
- 抓取玩家实体是原设计（parenting 玩家有理论风险，慎用）
- 抓取会重命名 entity 的 targetname，个别依赖实体名的地图 I/O 可能受影响
- LogCommand 日志保持原样（非用户可见）

---

## English

# l4d2_custom_commands — i18n Refactor + Grab Fix + Invisible Variant Org form https://forums.alliedmods.net/showthread.php?p=1251446 by Author: honorcode23

> Both the original old version and the fixed new version are archived | the new version is deployed on the test server (Status: running, no errors)

## Changes in This Version

### 1. Full i18n of All Player-Facing Messages (translation system)
- All user-visible prompts in the source changed to `%t` phrase calls (about 130 places); color codes stay in code
- Three new translation files added (`LoadTranslations("l4d2_custom_commands.phrases")`):
  - `translations/l4d2_custom_commands.phrases.txt` (English baseline; players in other languages see English)
  - `translations/chi/...` (Simplified Chinese; auto-applies to players whose game language is Simplified Chinese)
  - `translations/zho/...` (Traditional Chinese; auto-applies to players whose game language is Traditional Chinese)
- Coverage: usage prompts, result prompts, error prompts, sm_cchelp listing, example lines
- Menu labels (about 75 AddMenuItem calls) keep the original hardcoded Chinese (serves the target audience, avoids risk)
- Console/log messages follow the server language (mostly English)
- Also fixed along the way: leftover duplicate prints in help lines and console lines (original copy-paste bugs)

### 2. sm_grabentity Fixes
| Problem | Fix |
|---|---|
| **After the grabbed entity is destroyed/dies, cancelling the grab reports "entity invalid" and gets permanently stuck** | The Release invalid branch now clears all grab state and prints "grab cancelled (target no longer valid)" |
| Empty aim (looking at nothing) triggered an array out-of-bounds error | Check entity≤0 first, print "invalid entity or not aiming at an entity" |
| CmdGrabEntity console denial message printed twice | Deduplicated |
| OnMapEnd missed clearing g_iLastGrabbedEntity for client slots | Now cleared |

### 3. New: sm_grabentity_inv
- After grabbing, the entity is **visible only to the grabber** (SDKHook SetTransmit blocks it for others)
- **Collision, AI and physics all keep working** (pure visual blocking)
- Type it again to release the grab and restore normal visibility
- Same permission as sm_grabentity (DESIRED_FLAGS = ADMFLAG_UNBAN)

## Tested Checklist
1. Grab an item → destroy it → press sm_grabentity again → prints "grab cancelled", can grab a new target normally
2. Aim at nothing and press sm_grabentity → normal prompt, no error spam
3. sm_grabentity_inv grab an infected → others can't see it, you can, it still blocks the way
4. Press sm_grabentity_inv again → grab released, visible to others again
5. Check prompts on Simplified Chinese / Traditional Chinese / English clients (sm_cchelp and any command's usage error)
6. **sm_cchelp fix (v2)**: the help listing now prints to the **console** (only a one-line notice in chat), translated line by line per client language; fixed three leftover conversion bugs (`%%t` double percent, duplicated HelpGrabEntityInv, unguarded server console)
6. sm_grabentity_inv help line added to the sm_cchelp listing

## Archive Notes
- **Old version (旧版原始)**: same-version copy taken from the gua server (sourcemod2) (5293 lines / Chinese modified edition, feature-matched against the test server's original). The test server's original files were directly replaced in this refactor — next time I'll make a .orig backup first
- **New version (新版修复)**: the version currently running on the test server (includes smx/sp/three translation files)

## Known-But-Unchanged Design (original behavior)
- Grabbing player entities is the original design (parenting players carries theoretical risk; use with care)
- Grabbing renames the entity's targetname; map I/O relying on entity names may be affected on some maps
- LogCommand logging left as-is (not user-visible)
