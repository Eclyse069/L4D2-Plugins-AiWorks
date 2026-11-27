#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <l4d2_nativevote>			// https://github.com/fdxx/l4d2_nativevote 0.4
#include <l4d2_source_keyvalues>	// https://github.com/fdxx/l4d2_source_keyvalues 0.3
#include <colors>

/**
 * ============================================================================
 * [PATCH v1.1 by lead] 投票修改保持到服务器重启
 * ----------------------------------------------------------------------------
 * 问题: 投票通过 ServerCommand 改的 cvar 只是内存值, 换图时 server.cfg 重新
 *       执行, 全部打回 cfg 默认。
 * 修复: 投票通过的 ServerCommand 若为 "cvar 赋值 / exec 功能配置" 形式,
 *       存入会话保持列表(插件内存: 换图不丢, 服务器重启/插件重载清零),
 *       每次 OnConfigsExecuted(cfg 执行完毕后)按投票时间顺序重放一遍,
 *       后投的覆盖先投的。
 *       一次性动作(sm_restartmap / sm_reserve / sm_unreserve 等)不会被重放。
 * 新增: sm_votecfg_clear (ROOT) 手动清除保持列表, 下一张图恢复 cfg 默认。
 * 其它: 剥离了本服务器不存在的 savelog.sp 依赖(LogTo -> LogMessage 等价替换)。
 * ============================================================================
 */

#define VERSION "1.1"
#define COMMAND_MAX_LENGTH 511

#define TEAMFLAGS_SPEC	2
#define TEAMFLAGS_SUR	4
#define TEAMFLAGS_INF	8
#define TEAMFLAGS_DEFAULT	(TEAMFLAGS_SPEC|TEAMFLAGS_SUR|TEAMFLAGS_INF)

enum ConfigType
{
	Type_NotFound = 0,
	Type_ServerCommand,
	Type_ClientCommand,
	Type_ExternalVote,
	Type_CheatCommand,
}

enum struct ConfigData
{
	ConfigType type;
	int menuTeamFlags;
	int voteTeamFlags;
	bool bAdminOneVotePassed;
	bool bAdminOneVoteAgainst;
	char description[128];
	char cmd[COMMAND_MAX_LENGTH];
}

SourceKeyValues
	g_kvSelect[MAXPLAYERS+1],
	g_kvRoot;

ConVar g_cvVoteFilePath, g_cvAdminTeamFlags;
ConfigData g_cfgData[MAXPLAYERS+1];

// [PATCH] 投票会话保持列表
ArrayList g_SessionCmds;

public Plugin myinfo =
{
	name = "L4D2 Config Vote",
	author = "fdxx, kita (session-keep patch by lead)",
	version = VERSION,
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("l4d2_config_vote");
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("l4d2_config_vote_version", VERSION, "version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvVoteFilePath = CreateConVar("l4d2_config_vote_path", "data/vote.kv", "Vote config file path");
	g_cvAdminTeamFlags = CreateConVar("l4d2_config_vote_adminteamflags", "1", "Admin bypass TeamFlags.");
	g_cvVoteFilePath.AddChangeHook(OnCvarChanged);

	// [PATCH]
	g_SessionCmds = new ArrayList(ByteCountToCells(COMMAND_MAX_LENGTH));
}

void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	Init();
}

public void OnConfigsExecuted()
{
	// [PATCH] 每次 cfg 执行完毕(server.cfg 等)后重放投票保持项, 覆盖回 cfg 默认值
	ReplaySessionCmds();

	static bool shit;
	if (shit) return;
	shit = true;

	Init();
	RegAdminCmdEx("sm_votecfg_reload", Cmd_Reload, ADMFLAG_ROOT, "Reload config file.");
	RegAdminCmdEx("sm_votecfg_clear", Cmd_ClearSession, ADMFLAG_ROOT, "清除投票保持项, 下一张图恢复cfg默认值。");
	RegConsoleCmdEx("sm_v", Cmd_Vote);
	RegConsoleCmdEx("sm_vt", Cmd_Vote);
	RegConsoleCmdEx("sm_votes", Cmd_Vote);
	RegConsoleCmdEx("sm_si", Cmd_Vote);
}

Action Cmd_Reload(int client, int args)
{
	Init();
	return Plugin_Handled;
}

// [PATCH] 手动清除保持列表
Action Cmd_ClearSession(int client, int args)
{
	int n = g_SessionCmds.Length;
	g_SessionCmds.Clear();
	ReplyToCommand(client, "[ConfigVote] 已清除 %d 条投票保持项, 下一张图将恢复cfg默认值", n);
	LogMessage("[ConfigVote] session keep list cleared by admin (%d items)", n);
	return Plugin_Handled;
}

Action Cmd_Vote(int client, int args)
{
	ShowMenu(client, g_kvRoot, false);
	return Plugin_Handled;
}

void ShowMenu(int client, SourceKeyValues kv, bool bBackButton = true)
{
	if (client < 1 || !IsClientInGame(client) || IsFakeClient(client))
		return;

	if (!kv)
		ThrowError("Invalid SourceKeyValues pointer!");

	g_kvSelect[client] = kv;

	char title[128], display[128], sKv[16];
	kv.GetName(title, sizeof(title));

	Menu menu = new Menu(MenuHandlerCB);
	menu.SetTitle("%s:", title);

	for (SourceKeyValues sub = kv.GetFirstTrueSubKey(); sub; sub = sub.GetNextTrueSubKey())
	{
		if (!IsValidTeamFlags(client, sub.GetInt("MenuTeamFlags", TEAMFLAGS_DEFAULT)))
			continue;

		sub.GetName(display, sizeof(display));
		IntToString(view_as<int>(sub), sKv, sizeof(sKv));
		menu.AddItem(sKv, display);
	}

	menu.ExitBackButton = bBackButton;
	menu.Display(client, 20);
}

int MenuHandlerCB(Menu menu, MenuAction action, int client, int itemNum)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sKv[16];
			menu.GetItem(itemNum, sKv, sizeof(sKv));

			SourceKeyValues kv = view_as<SourceKeyValues>(StringToInt(sKv));
			ConfigType type = GetConfigType(kv);

			switch (type)
			{
				case Type_NotFound:
				{
					ShowMenu(client, kv);
				}
				case Type_ExternalVote:
				{
					char cmd[COMMAND_MAX_LENGTH];
					kv.GetString("Command", cmd, sizeof(cmd));
					ClientCommand(client, "%s", cmd);
				}
				default:
				{
					StartVote(client, kv, type);
				}
			}
		}
		case MenuAction_Cancel:
		{
			if (itemNum == MenuCancel_ExitBack)
			{
				SourceKeyValues kv = GetPreviousNode(g_kvRoot, g_kvSelect[client]);
				ShowMenu(client, kv, kv != g_kvRoot);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void StartVote(int client, SourceKeyValues kv, ConfigType type)
{
	if (!L4D2NativeVote_IsAllowNewVote())
	{
		CPrintToChat(client, "<{green}提示{default}>{blue}投票正在进行中, 暂不能发起新的投票.");
		return;
	}

	g_cfgData[client].type = type;
	g_cfgData[client].voteTeamFlags = kv.GetInt("VoteTeamFlags", TEAMFLAGS_DEFAULT);
	g_cfgData[client].bAdminOneVotePassed = kv.GetInt("AdminOneVotePassed", 1) > 0;
	g_cfgData[client].bAdminOneVoteAgainst = kv.GetInt("AdminOneVoteAgainst", 1) > 0;
	kv.GetString("Description", g_cfgData[client].description, sizeof(g_cfgData[].description));
	kv.GetString("Command", g_cfgData[client].cmd, sizeof(g_cfgData[].cmd));

	L4D2NativeVote vote = L4D2NativeVote(Vote_Handler);
	vote.SetDisplayText("%s", g_cfgData[client].description);
	vote.Initiator = client;

	int iPlayerCount = 0;
	int[] iClients = new int[MaxClients];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			if (!IsValidTeamFlags(i, g_cfgData[client].voteTeamFlags))
				continue;

			iClients[iPlayerCount++] = i;
		}
	}

	if (!vote.DisplayVote(iClients, iPlayerCount, 20))
		LogMessage("发起投票失败");
}

void Vote_Handler(L4D2NativeVote vote, VoteAction action, int param1, int param2)
{
	switch (action)
	{
		case VoteAction_Start:
		{
			CPrintToChatAll("<{green}提示{default}> {blue}%N{default}发起了一个投票 {green}%s", param1, g_cfgData[vote.Initiator].description);
			LogMessage("%N 投票执行 %s ", param1, g_cfgData[vote.Initiator].description);
		}
		case VoteAction_PlayerVoted:
		{
			if (!CheckCommandAccess(param1, "sm_admin", ADMFLAG_ROOT))
				return;

			if (param2 == VOTE_YES && g_cfgData[vote.Initiator].bAdminOneVotePassed)
			{
				vote.YesCount = vote.PlayerCount;
				vote.NoCount = 0;
			}
			else if (param2 == VOTE_NO && g_cfgData[vote.Initiator].bAdminOneVoteAgainst)
			{
				vote.YesCount = 0;
				vote.NoCount = vote.PlayerCount;
			}
		}
		case VoteAction_End:
		{
			if (vote.YesCount > vote.PlayerCount/2)
			{
				vote.SetPass("加载中...");

				switch (g_cfgData[vote.Initiator].type)
				{
					case Type_ServerCommand:
					{
						ServerCommand("%s", g_cfgData[vote.Initiator].cmd);
						StoreSessionCmd(g_cfgData[vote.Initiator].cmd);   // [PATCH]
					}
					case Type_ClientCommand:
					{
						if (IsClientInGame(vote.Initiator))
							ClientCommand(vote.Initiator, "%s", g_cfgData[vote.Initiator].cmd);
					}
					case Type_CheatCommand:
					{
						if (!IsClientInGame(vote.Initiator))
							return;

						char cmd[COMMAND_MAX_LENGTH], cmdArgs[COMMAND_MAX_LENGTH];

						int index = SplitString(g_cfgData[vote.Initiator].cmd, " ", cmd, sizeof(cmd));
						if (index != -1)
							strcopy(cmdArgs, sizeof(cmdArgs), g_cfgData[vote.Initiator].cmd[index]);
						else
							strcopy(cmd, sizeof(cmd), g_cfgData[vote.Initiator].cmd);

						int iFlags = GetCommandFlags(cmd);
						SetCommandFlags(cmd, iFlags & ~FCVAR_CHEAT);
						FakeClientCommand(vote.Initiator, "%s %s", cmd, cmdArgs);
						SetCommandFlags(cmd, iFlags);
					}
				}
			}
			else
				vote.SetFail();
		}
	}
}

// ============================ [PATCH] 会话保持 ============================

void StoreSessionCmd(const char[] cmd)
{
	if (!IsSessionPersistableCmd(cmd))
		return;

	if (g_SessionCmds.FindString(cmd) == -1)
	{
		g_SessionCmds.PushString(cmd);
		LogMessage("[ConfigVote] 会话保持: %s (直到重启或 sm_votecfg_clear)", cmd);
	}
}

bool IsSessionPersistableCmd(const char[] cmd)
{
	// 判定规则(逐分号段): 每段必须是
	//   1) exec 功能配置
	//   2) sm_cvar / sm_cvar2 形式
	//   3) 首token为真实存在 ConVar 的直接赋值
	// 否则视为一次性动作(sm_restartmap 等), 不保持
	char work[COMMAND_MAX_LENGTH];
	strcopy(work, sizeof(work), cmd);
	ReplaceString(work, sizeof(work), "\"", "");
	TrimString(work);

	int len = strlen(work);
	if (len == 0)
		return false;

	char seg[COMMAND_MAX_LENGTH], token[64];
	int pos = 0, segCount = 0;

	while (pos < len)
	{
		int segStart = pos;
		while (pos < len && work[pos] != ';')
			pos++;
		int segEnd = pos;
		if (pos < len)
			pos++;

		int j = 0;
		for (int i = segStart; i < segEnd && j < sizeof(seg) - 1; i++)
			seg[j++] = work[i];
		seg[j] = 0;
		TrimString(seg);

		if (seg[0] == 0)
			continue;

		segCount++;

		int sp = FindCharInString(seg, ' ');
		if (sp == -1)
			strcopy(token, sizeof(token), seg);
		else
			strcopy(token, sp + 1, seg);

		if (StrEqual(token, "exec", false))
			continue;

		if (StrEqual(token, "sm_cvar", false) || StrEqual(token, "sm_cvar2", false))
			continue;

		if (FindConVar(token) != null)
			continue;

		return false;
	}

	return segCount > 0;
}

void ReplaySessionCmds()
{
	int n = g_SessionCmds.Length;
	if (n == 0)
		return;

	char cmd[COMMAND_MAX_LENGTH];
	for (int i = 0; i < n; i++)
	{
		g_SessionCmds.GetString(i, cmd, sizeof(cmd));
		ServerCommand("%s", cmd);
	}

	LogMessage("[ConfigVote] 重放 %d 条投票保持项", n);
}

// ============================ 原有辅助函数 ============================

bool IsValidTeamFlags(int client, int flags)
{
	if (g_cvAdminTeamFlags.BoolValue && CheckCommandAccess(client, "sm_admin", ADMFLAG_ROOT))
		return true;

	int team = GetClientTeam(client);
	return (flags & (1 << team)) != 0;
}

SourceKeyValues GetPreviousNode(SourceKeyValues kvRoot, SourceKeyValues kvTarget)
{
	for (SourceKeyValues sub = kvRoot.GetFirstTrueSubKey(); sub; sub = sub.GetNextTrueSubKey())
	{
		if (sub == kvTarget)
			return kvRoot;

		if (sub.GetFirstTrueSubKey())
		{
			SourceKeyValues result = GetPreviousNode(sub, kvTarget);
			if (result)
				return result;
		}
	}
	return view_as<SourceKeyValues>(0);
}

ConfigType GetConfigType(SourceKeyValues kv)
{
	char type[32];
	kv.GetString("Type", type, sizeof(type));

	if (!strcmp(type, "ServerCommand", false))
		return Type_ServerCommand;

	if (!strcmp(type, "ClientCommand", false))
		return Type_ClientCommand;

	if (!strcmp(type, "ExternalVote", false))
		return Type_ExternalVote;

	if (!strcmp(type, "CheatCommand", false))
		return Type_CheatCommand;

	return Type_NotFound;
}

void RegAdminCmdEx(const char[] cmd, ConCmd callback, int adminflags, const char[] description="", const char[] group="", int flags=0)
{
	if (!CommandExists(cmd))
		RegAdminCmd(cmd, callback, adminflags, description, group, flags);
	else
	{
		char pluginName[PLATFORM_MAX_PATH];
		FindPluginNameByCmd(pluginName, sizeof(pluginName), cmd);
		LogError("The command \"%s\" already exists, plugin: \"%s\"", cmd, pluginName);
	}
}

void RegConsoleCmdEx(const char[] cmd, ConCmd callback, const char[] description="", int flags=0)
{
	if (!CommandExists(cmd))
		RegConsoleCmd(cmd, callback, description, flags);
	else
	{
		char pluginName[PLATFORM_MAX_PATH];
		FindPluginNameByCmd(pluginName, sizeof(pluginName), cmd);
		LogError("The command \"%s\" already exists, plugin: \"%s\"", cmd, pluginName);
	}
}

bool FindPluginNameByCmd(char[] buffer, int maxlength, const char[] cmd)
{
	char cmdBuffer[128];
	bool result = false;
	CommandIterator iter = new CommandIterator();

	while (iter.Next())
	{
		iter.GetName(cmdBuffer, sizeof(cmdBuffer));
		if (strcmp(cmdBuffer, cmd, false))
			continue;

		GetPluginFilename(iter.Plugin, buffer, maxlength);
		result = true;
		break;
	}

	if (!result)
	{
		ConVar cvar = FindConVar(cmd);
		if (cvar)
		{
			GetPluginFilename(cvar.Plugin, buffer, maxlength);
			result = true;
		}
	}

	delete iter;
	return result;
}

void Init()
{
	if (g_kvRoot)
		g_kvRoot.deleteThis();

	char file[PLATFORM_MAX_PATH];
	char g_sVoteFile[128];
	GetConVarString(g_cvVoteFilePath, g_sVoteFile, sizeof(g_sVoteFile));
	BuildPath(Path_SM, file, sizeof(file), g_sVoteFile);

	g_kvRoot = SourceKeyValues("");
	g_kvRoot.UsesEscapeSequences(true);
	if (!g_kvRoot.LoadFromFile(file))
		SetFailState("Failed to load %s", file);
}

public void OnPluginEnd()
{
	if (g_kvRoot)
		g_kvRoot.deleteThis();
}
