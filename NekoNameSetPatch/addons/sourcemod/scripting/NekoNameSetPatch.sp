/**
 * NekoNameSetPatch v1.0 - NekoNameSet 补丁:
 * 修正 [L4D2]加入退出提示 在玩家连接时显示 Steam 默认名的问题
 *
 * 原理:
 *   加入退出提示.smx 的"连接中"消息在 OnClientConnected 用 %N 打印,
 *   早于 NekoNameSet 在 OnClientAuthorized 的改名时机, 所以显示默认名。
 *   本补丁把它自带的开关 cvar l4d2_connecting_notify 置 0 关闭原输出,
 *   由本插件输出同格式(逐字节一致的颜色代码)与同音效的保存名版本;
 *   玩家无保存名时输出与原版一模一样的默认名消息, 行为不变。
 *
 * 卸载本补丁会自动把 l4d2_connecting_notify 还原为 1, 恢复原插件行为。
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define SOUND_CONNECTING "ambient/alarms/klaxon1.wav"

public Plugin myinfo =
{
	name        = "Neko NameSet Patch (connecting notify)",
	description = "Take over the connecting message with saved names",
	author      = "lead",
	version     = "1.0",
	url         = ""
};

ConVar g_cvConnectingNotify;
char   g_sDataPath[PLATFORM_MAX_PATH];

public void OnPluginStart()
{
	BuildPath(Path_SM, g_sDataPath, sizeof(g_sDataPath), "data/nekonameset.cfg");

	// 接管"连接中"提示
	g_cvConnectingNotify = FindConVar("l4d2_connecting_notify");
	if (g_cvConnectingNotify != null)
		g_cvConnectingNotify.SetInt(0);
}

public void OnPluginEnd()
{
	// 卸载补丁时还原原插件行为
	if (g_cvConnectingNotify != null)
		g_cvConnectingNotify.SetInt(1);
}

public void OnMapStart()
{
	PrecacheSound(SOUND_CONNECTING);

	if (g_cvConnectingNotify != null)
		g_cvConnectingNotify.SetInt(0);
}

public void OnClientConnected(int client)
{
	if (IsFakeClient(client))
		return;

	char saved[MAX_NAME_LENGTH];
	if (GetSavedNameAtConnect(client, saved, sizeof(saved)))
	{
		PrintToChatAll("\x04[服务器] \x05玩家\x03%s\x05连接中...", saved);
	}
	else
	{
		PrintToChatAll("\x04[服务器] \x05玩家\x03%N\x05连接中...", client);
	}

	PlaySound(SOUND_CONNECTING);
}

bool GetSavedNameAtConnect(int client, char[] out, int maxlen)
{
	// 连接早期取 SteamID (validate=false, 与原插件取ID同思路)
	char auth[64];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), false) || auth[0] == 0)
		return false;

	if (!FileExists(g_sDataPath))
		return false;

	// 每次连接重新读档, 与 NekoNameSet 保存的最新名字同步
	KeyValues kv = new KeyValues("NekoNameSet");
	if (!kv.ImportFromFile(g_sDataPath))
	{
		delete kv;
		return false;
	}

	bool found = false;
	if (kv.JumpToKey(auth, false))
	{
		kv.GetString("name", out, maxlen, "");
		found = out[0] != 0;
	}
	delete kv;

	return found;
}

// 与加入退出提示.sp 的 PlaySound 逐参数一致, 保证听感相同
void PlaySound(const char[] sample)
{
	EmitSoundToAll(sample, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
}
