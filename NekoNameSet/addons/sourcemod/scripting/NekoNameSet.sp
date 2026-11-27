/**
 * NekoNameSet - 玩家名字持久化插件 v1.0
 *
 * 玩家指令:
 *   sm_nameset <名字>    保存自己的名字(可含空格), 每次进服自动应用
 *   sm_nameset           清空保存, 恢复 Steam 默认名字
 *
 * 管理员指令 (b 权限):
 *   sm_nameset @<目标> <名字>    强制为某玩家保存并设置名字 (也可用 #userid)
 *   sm_nameset @<目标>           清空该玩家的保存名字
 *   对 BOT 使用 = 临时改名(不保存, 便于测试)
 *
 * 机制:
 *   - 存档: addons/sourcemod/data/nekonameset.cfg (SteamID2 -> 名字, 可手工编辑)
 *   - 自动应用: OnClientAuthorized(早于PutInServer, 播报类插件读到的是新名) /
 *     OnClientPutInServer / OnMapStart+1s / round_start+0.5s
 *   - 防回退: player_changename 事件内强制回写, 修复换图/换局后名字回退 Steam 默认名的问题
 *   - player_connect 事件 pre-hook 改写 name 字段, 兼容事件型加入播报插件
 *   - 自动应用全程静默(无聊天框提示)
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0"

public Plugin myinfo =
{
	name        = "Neko NameSet",
	description = "Save player names and auto-apply silently on join/map-change",
	author      = "lead",
	version     = PLUGIN_VERSION,
	url         = ""
};

KeyValues g_kvNames;
char g_sDataPath[PLATFORM_MAX_PATH];
char g_sSteamName[MAXPLAYERS + 1][MAX_NAME_LENGTH];

// ================= 生命周期 =================

public void OnPluginStart()
{
	BuildPath(Path_SM, g_sDataPath, sizeof(g_sDataPath), "data/nekonameset.cfg");

	g_kvNames = new KeyValues("NekoNameSet");
	if (FileExists(g_sDataPath))
		g_kvNames.ImportFromFile(g_sDataPath);

	RegConsoleCmd("sm_nameset", Cmd_NameSet, "sm_nameset <名字> 保存; 留空清除; 管理员: sm_nameset @目标 <名字>");

	HookEvent("player_connect",    Event_PlayerConnect, EventHookMode_Pre);
	HookEvent("player_changename", Event_ChangeName,    EventHookMode_Pre);
	HookEvent("round_start",       Event_RoundStart,     EventHookMode_PostNoCopy);

	// 插件热加载时, 给已在服内的玩家补一次应用
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			char auth[64];
			if (GetClientAuthId(i, AuthId_Steam2, auth, sizeof(auth)))
				GetClientName(i, g_sSteamName[i], MAX_NAME_LENGTH);
			ApplySavedName(i, false);
		}
	}
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (IsFakeClient(client))
		return;

	// 记录 Steam 原始名, 供清空时恢复
	if (IsClientConnected(client))
		GetClientName(client, g_sSteamName[client], MAX_NAME_LENGTH);

	// 关键时机: 早于 OnClientPutInServer, 让播报类插件读到新名字
	ApplySavedName(client, false);
}

public void OnClientPutInServer(int client)
{
	ApplySavedName(client, false);
}

public void OnClientDisconnect(int client)
{
	g_sSteamName[client][0] = 0;
}

public void OnMapStart()
{
	// 换图后 1 秒全量重应用(修复引擎换图回退默认名)
	CreateTimer(1.0, Timer_ReapplyAll);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.5, Timer_ReapplyAll);
}

public Action Timer_ReapplyAll(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
		ApplySavedName(i, false);
	return Plugin_Stop;
}

// ================= 事件拦截 =================

public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
	// 把加入播报事件里的 name 字段替换为保存名 (兼容事件型播报插件)
	char networkid[64];
	event.GetString("networkid", networkid, sizeof(networkid));
	if (networkid[0] == 0 || StrEqual(networkid, "BOT"))
		return Plugin_Continue;

	char saved[MAX_NAME_LENGTH];
	if (!LookupSaved(networkid, saved, sizeof(saved)))
		return Plugin_Continue;

	event.SetString("name", saved);
	return Plugin_Changed;
}

public Action Event_ChangeName(Event event, const char[] name, bool dontBroadcast)
{
	// 引擎/客户端重新上报 Steam 默认名时, 强制回写保存名 (防回退核心)
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || IsFakeClient(client))
		return Plugin_Continue;

	char saved[MAX_NAME_LENGTH];
	if (!GetClientSaved(client, saved, sizeof(saved)))
		return Plugin_Continue;

	char newname[MAX_NAME_LENGTH];
	event.GetString("newname", newname, sizeof(newname));
	if (StrEqual(newname, saved))
		return Plugin_Continue;

	event.SetString("newname", saved);
	SetClientName(client, saved);
	return Plugin_Changed;
}

// ================= 核心 =================

void ApplySavedName(int client, bool force)
{
	if (client <= 0 || client > MaxClients)
		return;
	if (!IsClientConnected(client))
		return;
	if (IsFakeClient(client))
		return;

	char saved[MAX_NAME_LENGTH];
	if (!GetClientSaved(client, saved, sizeof(saved)))
		return;

	char cur[MAX_NAME_LENGTH];
	GetClientName(client, cur, sizeof(cur));
	if (!force && StrEqual(cur, saved))
		return;

	SetClientName(client, saved);
}

bool GetClientSaved(int client, char[] out, int maxlen)
{
	char auth[64];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)) || auth[0] == 0)
		return false;
	return LookupSaved(auth, out, maxlen);
}

bool LookupSaved(const char[] auth, char[] out, int maxlen)
{
	if (auth[0] == 0)
		return false;

	g_kvNames.Rewind();
	if (g_kvNames.JumpToKey(auth, false))
	{
		g_kvNames.GetString("name", out, maxlen, "");
		g_kvNames.Rewind();
		return out[0] != 0;
	}

	// 兼容 [U:1:xxx] (Steam3) 格式的 networkid
	if (strncmp(auth, "[U:1:", 5) == 0)
	{
		char tail[24];
		CopyTail(tail, sizeof(tail), auth, 5);
		int acc = StringToInt(tail);
		if (acc > 0)
		{
			char steam2[64];
			Format(steam2, sizeof(steam2), "STEAM_1:%d:%d", acc & 1, acc >> 1);
			g_kvNames.Rewind();
			if (g_kvNames.JumpToKey(steam2, false))
			{
				g_kvNames.GetString("name", out, maxlen, "");
				g_kvNames.Rewind();
				return out[0] != 0;
			}
		}
	}

	g_kvNames.Rewind();
	return false;
}

bool SaveNameForClient(int client, const char[] name)
{
	char auth[64];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)) || auth[0] == 0)
		return false;

	g_kvNames.Rewind();
	g_kvNames.JumpToKey(auth, true);
	g_kvNames.SetString("name", name);
	g_kvNames.Rewind();
	g_kvNames.ExportToFile(g_sDataPath);

	LogMessage("saved name for client %d (auth %s)", client, auth);
	return true;
}

bool ClearForClient(int client, bool restore)
{
	char auth[64];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)) || auth[0] == 0)
		return false;

	g_kvNames.Rewind();
	bool existed = g_kvNames.JumpToKey(auth, false);
	if (existed)
	{
		g_kvNames.DeleteThis();
		g_kvNames.Rewind();
		g_kvNames.ExportToFile(g_sDataPath);
		LogMessage("cleared name for client %d", client);
	}
	g_kvNames.Rewind();

	if (restore && IsClientInGame(client) && g_sSteamName[client][0] != 0)
		SetClientName(client, g_sSteamName[client]);

	return existed;
}

// ================= 指令 =================

public Action Cmd_NameSet(int client, int args)
{
	char raw[192];
	GetCmdArgString(raw, sizeof(raw));

	// 管理员目标模式
	if (raw[0] == '@' || raw[0] == '#')
		return Cmd_ForceTarget(client, raw);

	// 自身模式
	if (client == 0)
	{
		ReplyToCommand(client, "[NameSet] 控制台请使用: sm_nameset @<目标> <名字>");
		return Plugin_Handled;
	}

	char newname[MAX_NAME_LENGTH];
	if (args == 0 || !CleanName(raw, newname, sizeof(newname)))
	{
		if (ClearForClient(client, true))
			ReplyToCommand(client, "[NameSet] 已清空保存, 恢复 Steam 默认名字");
		else
			ReplyToCommand(client, "[NameSet] 你没有保存过名字");
		return Plugin_Handled;
	}

	if (!SaveNameForClient(client, newname))
	{
		ReplyToCommand(client, "[NameSet] 保存失败(无法获取你的SteamID)");
		return Plugin_Handled;
	}

	SetClientName(client, newname);
	ReplyToCommand(client, "[NameSet] 已保存你的名字: %s", newname);
	return Plugin_Handled;
}

Action Cmd_ForceTarget(int client, const char[] raw)
{
	if (client != 0 && !CheckCommandAccess(client, "sm_nameset_force", ADMFLAG_GENERIC))
	{
		ReplyToCommand(client, "[NameSet] 你没有权限对其他玩家设定名字");
		return Plugin_Handled;
	}

	char target[96], nameraw[MAX_NAME_LENGTH];
	int sp = FindCharInString(raw, ' ');
	if (sp == -1)
	{
		strcopy(target, sizeof(target), raw);
		nameraw[0] = 0;
	}
	else
	{
		strcopy(target, sp + 1, raw);
		CopyTail(nameraw, sizeof(nameraw), raw, sp + 1);
	}

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS];
	int target_count;
	bool tn_is_ml;

	int r = ProcessTargetString(target, client, target_list, sizeof(target_list),
		COMMAND_FILTER_NO_IMMUNITY | COMMAND_FILTER_NO_MULTI,
		target_name, sizeof(target_name), tn_is_ml);

	if (r <= 0)
	{
		ReplyToCommand(client, "[NameSet] 找不到目标: %s (可用 玩家名/@名字/#userid)", target);
		return Plugin_Handled;
	}

	int t = target_list[0];

	char newname[MAX_NAME_LENGTH];
	bool hasName = (nameraw[0] != 0) && CleanName(nameraw, newname, sizeof(newname));

	if (!hasName)
	{
		// 清空目标
		if (IsFakeClient(t))
		{
			ReplyToCommand(client, "[NameSet] BOT 没有保存名字");
			return Plugin_Handled;
		}
		if (ClearForClient(t, true))
			ReplyToCommand(client, "[NameSet] 已清空 %N 的保存名字", t);
		else
			ReplyToCommand(client, "[NameSet] %N 没有保存过名字", t);
		return Plugin_Handled;
	}

	if (IsFakeClient(t))
	{
		SetClientName(t, newname);
		ReplyToCommand(client, "[NameSet] 已临时修改 BOT %N 的名字: %s (不保存)", t, newname);
		return Plugin_Handled;
	}

	if (!SaveNameForClient(t, newname))
	{
		ReplyToCommand(client, "[NameSet] 保存失败(无法获取目标SteamID)");
		return Plugin_Handled;
	}

	SetClientName(t, newname);
	ReplyToCommand(client, "[NameSet] 已为 %N 保存并设置名字: %s", t, newname);
	return Plugin_Handled;
}

// ================= 工具 =================

void CopyTail(char[] dest, int destLen, const char[] src, int start)
{
	int j = 0;
	int n = strlen(src);
	for (int i = start; i < n && j < destLen - 1; i++)
		dest[j++] = src[i];
	dest[j] = 0;
}

bool CleanName(const char[] input, char[] output, int maxlen)
{
	strcopy(output, maxlen, input);

	// 去整体首尾引号
	int len = strlen(output);
	if (len >= 2 && output[0] == '"' && output[len - 1] == '"')
	{
		output[len - 1] = 0;
		CopyTail(output, maxlen, output, 1);
	}

	// 就地清除引号/换行/制表 (引擎与 KV 安全)
	int j = 0;
	int n = strlen(output);
	for (int i = 0; i < n; i++)
	{
		char c = output[i];
		if (c == '"' || c == '\n' || c == '\r' || c == '\t')
			continue;
		output[j++] = c;
	}
	output[j] = 0;

	TrimString(output);
	if (output[0] == 0)
		return false;

	SafeTruncateUTF8(output, maxlen);
	return output[0] != 0;
}

void SafeTruncateUTF8(char[] buf, int maxlen)
{
	// 按字节截断但不切断 UTF-8 多字节字符
	int limit = maxlen - 1;
	int n = 0;
	while (buf[n] != 0 && n < limit)
	{
		int next = n + 1;
		char c = buf[n];
		if ((c & 0xE0) == 0xC0)
			next = n + 2;
		else if ((c & 0xF0) == 0xE0)
			next = n + 3;
		else if ((c & 0xF8) == 0xF0)
			next = n + 4;
		if (next > limit)
			break;
		n = next;
	}
	buf[n] = 0;
}
