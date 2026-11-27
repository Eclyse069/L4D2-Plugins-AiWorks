/**
 * DiageticChat v1.0 - 聊天消息"头顶气泡"
 *
 * 来源: MOD "Diagetic Chat Messages" (scripts/vscripts/diagetic_chat.nut, 893行)
 *       的 SourceMod 插件化移植。
 *
 * 功能:
 *   玩家打字 -> 聊天框正常显示(共存, 不抑制) + 同时在说话者头顶
 *   显示世界空间气泡(env_instructor_hint)。
 *   - 长句分块(>maxchunk 按空格/标点切)顺序播放, 每块时长=字数x0.065s+注视奖励
 *   - 观看者没看向说话者(44度视线锥+回滞) -> 气泡变屏边提醒图标指向说话者
 *   - 回头看 -> 显示正文, 漏看中间段加"-"前缀
 *   - 每观看者独立锚点实体, 每0.03s跟随说话者头部, 侧向偏移避免挡名牌
 *   - 首块无人看时最多再挂1.25s宽限
 *   - sm_dchat(!dchat): 切换本人是否看到气泡(持久化), 关闭者只看聊天框
 *
 * 按要求未移植: 原MOD的音效子系统(幸存者bark语音)与图标子系统(materials)
 *              -> 所有气泡统一使用引擎自带 icon_alert 图标
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0"

// ================= 常数 (照抄原 MOD Config, 手感一致) =================
#define CHAR_READ_TIME      0.065
#define FIRST_CHUNK_GAZE    0.45
#define MIDDLE_CHUNK_GAZE   0.15
#define MIN_CHUNK_DURATION  2.2
#define MAX_CHUNK_DURATION  4.0
#define FINAL_CHUNK_MIN     4.5
#define FINAL_CHUNK_MAX     5.0
#define FIRST_CHUNK_GRACE   1.25
#define HEAD_OFFSET_Z       4.0
#define SELF_HEAD_OFFSET_Z  16.0
#define SIDEWAYS_OFFSET    10.0
#define CHUNK_GAP_DELAY     0.1
#define THINK_INTERVAL      0.03
#define SHOW_DELAY          0.1
#define LOOK_CONE_DOT       0.72
#define LOOK_CONE_HYST      0.04
#define CHUNK_SPLIT_MARGIN  10

#define MAX_CHUNKS   12
#define CHUNK_LEN    64
#define HINT_COLOR   "255 255 255"
#define HINT_ICON    "icon_alert"

#define INVALID_REF  INVALID_ENT_REFERENCE

// viewer hint state
enum
{
	STATE_NONE = 0,
	STATE_MESSAGE = 1,
	STATE_REMINDER = 2
};

public Plugin myinfo =
{
	name        = "Diagetic Chat",
	description = "World-space chat bubbles above speakers (chat feed untouched)",
	author      = "lead (ported from VScript mod Diagetic Chat Messages)",
	version     = PLUGIN_VERSION,
	url         = ""
};

// ================= cvars =================
ConVar g_cvEnabled;
ConVar g_cvShowOwn;
ConVar g_cvMaxChunk;
ConVar g_cvDebug;

// ================= 说话者条目 =================
bool  g_Active[MAXPLAYERS + 1];
char  g_Chunks[MAXPLAYERS + 1][MAX_CHUNKS][CHUNK_LEN];
int   g_ChunkCount[MAXPLAYERS + 1];
int   g_ChunkIndex[MAXPLAYERS + 1];
float g_ChunkDuration[MAXPLAYERS + 1];
float g_ReadyAt[MAXPLAYERS + 1];
float g_ExpiresAt[MAXPLAYERS + 1];
float g_GraceDeadline[MAXPLAYERS + 1];
bool  g_FirstSeen[MAXPLAYERS + 1];

// ================= 观看者(说话者x观看者)状态 =================
int   g_Anchor[MAXPLAYERS + 1][MAXPLAYERS + 1];
char  g_AnchorName[MAXPLAYERS + 1][MAXPLAYERS + 1][48];
float g_AnchorReadyAt[MAXPLAYERS + 1][MAXPLAYERS + 1];
int   g_Hint[MAXPLAYERS + 1][MAXPLAYERS + 1];
int   g_HintState[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool  g_RecInit[MAXPLAYERS + 1][MAXPLAYERS + 1];
int   g_LastSeenChunk[MAXPLAYERS + 1][MAXPLAYERS + 1];
int   g_HyphenChunk[MAXPLAYERS + 1][MAXPLAYERS + 1];

int g_Serial = 0;

// ================= 退订(!dchat)持久化 =================
StringMap g_OptMap;
ArrayList g_OptList;
char g_sOptPath[PLATFORM_MAX_PATH];

// ================= 生命周期 =================

public void OnPluginStart()
{
	BuildPath(Path_SM, g_sOptPath, sizeof(g_sOptPath), "data/diagetchat_optout.cfg");

	g_cvEnabled  = CreateConVar("dchat_enabled",  "1", "[0/1] 插件总开关");
	g_cvShowOwn  = CreateConVar("dchat_showown",  "1", "[0/1] 说话者自己是否看到自己的气泡");
	g_cvMaxChunk = CreateConVar("dchat_maxchunk", "42", "单块气泡最大字符数(字节)", _, true, 10.0, true, 58.0);
	g_cvDebug    = CreateConVar("dchat_debug",    "0", "[0/1] 调试输出到服务器控制台");
	AutoExecConfig(true, "L4D2_DiageticChat");

	RegConsoleCmd("sm_dchat", Cmd_DChat, "切换自己是否看到聊天气泡");

	HookEvent("player_say",        Event_PlayerSay);
	HookEvent("player_disconnect",  Event_PlayerDisconnect);
	HookEvent("round_start",        Event_RoundStart);
	HookEvent("round_end",          Event_RoundEnd);

	g_OptMap  = new StringMap();
	g_OptList = new ArrayList(ByteCountToCells(64));
	LoadOptOut();

	CreateTimer(THINK_INTERVAL, Timer_Think, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	ClearAllHints();
}

// ================= 指令 =================

public Action Cmd_DChat(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[DiageticChat] 此命令请在游戏内使用");
		return Plugin_Handled;
	}

	char auth[64];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)) || auth[0] == 0)
	{
		PrintToChat(client, "\x04[DiageticChat]\x01 无法获取你的SteamID, 稍后再试");
		return Plugin_Handled;
	}

	bool optedOut = true;
	if (g_OptMap.GetValue(auth, optedOut) && optedOut)
	{
		optedOut = false;  // 当前是关闭 -> 切换为开启
	}
	else
	{
		optedOut = true;   // 当前是开启 -> 切换为关闭
	}

	if (optedOut)
	{
		g_OptMap.SetValue(auth, true);
		if (g_OptList.FindString(auth) == -1)
			g_OptList.PushString(auth);
		PurgeViewerFromAllHints(client);
		PrintToChat(client, "\x04[DiageticChat]\x01 气泡已\x03关闭\x01, 你将只看到普通聊天框");
	}
	else
	{
		g_OptMap.SetValue(auth, false);
		PrintToChat(client, "\x04[DiageticChat]\x01 气泡已\x05开启\x01");
	}
	SaveOptOut();

	return Plugin_Handled;
}

// ================= 事件 =================

public void Event_PlayerSay(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnabled.BoolValue)
		return;

	int uid = event.GetInt("userid");
	if (uid == 0)
		return;

	int client = GetClientOfUserId(uid);
	if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
		return;

	char text[256];
	event.GetString("text", text, sizeof(text));

	// 命令类消息(! / @开头)不做气泡, 交给SM触发器
	if (text[0] == '!' || text[0] == '/' || text[0] == '@')
		return;

	ShowChatHint(client, text);
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients)
	{
		ClearPlayerHint(client);
		PurgeViewerFromAllHints(client);
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	ClearAllHints();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	ClearAllHints();
}

// ================= 核心: 显示 =================

void ShowChatHint(int client, const char[] rawText)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return;

	char norm[256];
	NormalizeChatText(rawText, norm, sizeof(norm));

	char chunks[MAX_CHUNKS][CHUNK_LEN];
	int count = SplitMessageChunks(norm, chunks);
	if (count == 0)
		return;

	ClearPlayerHint(client);

	float now = GetGameTime();
	float firstDur = ComputeChunkDuration(chunks[0], 0, count);
	float readyAt = now + SHOW_DELAY;
	float grace = (count > 1 && FIRST_CHUNK_GRACE > 0.0) ? (readyAt + FIRST_CHUNK_GRACE) : 0.0;

	for (int i = 0; i < count; i++)
		strcopy(g_Chunks[client][i], CHUNK_LEN, chunks[i]);
	g_ChunkCount[client]    = count;
	g_ChunkIndex[client]    = 0;
	g_ChunkDuration[client] = firstDur;
	g_ReadyAt[client]       = readyAt;
	g_ExpiresAt[client]     = readyAt + firstDur;
	g_GraceDeadline[client] = grace;
	g_FirstSeen[client]     = false;
	g_Active[client]        = true;

	for (int viewer = 1; viewer <= MaxClients; viewer++)
	{
		if (!IsEligibleViewer(client, viewer))
			continue;
		CreateViewerAnchor(client, viewer, readyAt);
	}

	if (g_cvDebug.BoolValue)
		PrintToServer("[DiageticChat] %N -> %d chunk(s), first %.2fs: \"%s\"", client, count, firstDur, chunks[0]);
}

// ================= 核心: Think (0.03s) =================

public Action Timer_Think(Handle timer)
{
	if (!g_cvEnabled.BoolValue)
		return Plugin_Continue;

	float now = GetGameTime();

	for (int speaker = 1; speaker <= MaxClients; speaker++)
	{
		if (!g_Active[speaker])
			continue;

		if (!IsClientInGame(speaker) || !IsPlayerAlive(speaker))
		{
			ClearPlayerHint(speaker);
			continue;
		}

		float headBase[3];
		GetHeadBasePosition(speaker, headBase);

		float lookTarget[3];
		lookTarget = headBase;
		lookTarget[2] += HEAD_OFFSET_Z;

		// 锚点跟随说话者
		for (int viewer = 1; viewer <= MaxClients; viewer++)
		{
			int ref = g_Anchor[speaker][viewer];
			if (ref == INVALID_REF)
				continue;
			if (!IsClientInGame(viewer))
			{
				DestroyAnchorEnt(ref);
				g_Anchor[speaker][viewer] = INVALID_REF;
				continue;
			}
			float apos[3];
			GetViewerAnchorPosition(speaker, viewer, apos);
			int ent = EntRefToEntIndex(ref);
			if (ent > 0 && IsValidEntity(ent))
				TeleportEntity(ent, apos, NULL_VECTOR, NULL_VECTOR);
		}

		if (now < g_ReadyAt[speaker])
			continue;

		float hintTimeoutSec = g_ExpiresAt[speaker] - now;
		if (g_ChunkIndex[speaker] == 0 && !g_FirstSeen[speaker] && g_GraceDeadline[speaker] > now)
			hintTimeoutSec += (g_GraceDeadline[speaker] - now);

		for (int viewer = 1; viewer <= MaxClients; viewer++)
		{
			if (!IsEligibleViewer(speaker, viewer))
				continue;

			if (g_Anchor[speaker][viewer] == INVALID_REF)
			{
				int ref = CreateViewerAnchor(speaker, viewer, now + SHOW_DELAY);
				if (ref == INVALID_REF)
					continue;
			}

			if (now < g_AnchorReadyAt[speaker][viewer])
				continue;

			float anchorPos[3];
			GetViewerAnchorPosition(speaker, viewer, anchorPos);

			if (viewer == speaker)
			{
				// 自己: 永远显示正文态
				if (g_HintState[speaker][viewer] == STATE_NONE)
					SpawnViewerHint(speaker, viewer, STATE_MESSAGE, g_AnchorName[speaker][viewer], anchorPos, hintTimeoutSec, false);
				continue;
			}

			if (!g_RecInit[speaker][viewer])
			{
				g_RecInit[speaker][viewer]       = true;
				g_LastSeenChunk[speaker][viewer]  = -1;
				g_HyphenChunk[speaker][viewer]    = -1;
			}

			bool wasMessage = (g_HintState[speaker][viewer] == STATE_MESSAGE);
			bool looking = IsLookingAt(viewer, lookTarget, wasMessage);

			if (looking)
			{
				if (g_ChunkIndex[speaker] == 0)
					g_FirstSeen[speaker] = true;

				if (g_LastSeenChunk[speaker][viewer] < g_ChunkIndex[speaker])
				{
					if (g_ChunkIndex[speaker] > 0 && g_LastSeenChunk[speaker][viewer] < g_ChunkIndex[speaker] - 1)
						g_HyphenChunk[speaker][viewer] = g_ChunkIndex[speaker];
					g_LastSeenChunk[speaker][viewer] = g_ChunkIndex[speaker];
				}
			}

			int desired = looking ? STATE_MESSAGE : STATE_REMINDER;
			if (desired != g_HintState[speaker][viewer])
			{
				if (g_Hint[speaker][viewer] != INVALID_REF)
				{
					DestroyHintEnt(g_Hint[speaker][viewer]);
					g_Hint[speaker][viewer] = INVALID_REF;
				}
				bool prependHyphen = (looking && g_HyphenChunk[speaker][viewer] == g_ChunkIndex[speaker]);
				SpawnViewerHint(speaker, viewer, desired, g_AnchorName[speaker][viewer], anchorPos, hintTimeoutSec, prependHyphen);
			}
		}

		// 首块宽限
		if (g_ChunkIndex[speaker] == 0 && g_GraceDeadline[speaker] > 0.0)
		{
			if (!g_FirstSeen[speaker] && now < g_GraceDeadline[speaker])
				g_ExpiresAt[speaker] = now + g_ChunkDuration[speaker];
			else
				g_GraceDeadline[speaker] = 0.0;
		}

		if (now >= g_ExpiresAt[speaker])
		{
			if (g_ChunkIndex[speaker] + 1 < g_ChunkCount[speaker])
			{
				ClearViewerHints(speaker);
				g_ChunkIndex[speaker]++;
				g_ChunkDuration[speaker] = ComputeChunkDuration(g_Chunks[speaker][g_ChunkIndex[speaker]], g_ChunkIndex[speaker], g_ChunkCount[speaker]);
				g_GraceDeadline[speaker] = 0.0;
				g_ReadyAt[speaker]   = now + CHUNK_GAP_DELAY;
				g_ExpiresAt[speaker] = g_ReadyAt[speaker] + g_ChunkDuration[speaker];
			}
			else
			{
				ClearPlayerHint(speaker);
			}
		}
	}

	return Plugin_Continue;
}

// ================= 气泡/锚点实体 =================

int CreateViewerAnchor(int speaker, int viewer, float readyAt)
{
	float pos[3];
	GetViewerAnchorPosition(speaker, viewer, pos);

	char anchorName[48];
	Format(anchorName, sizeof(anchorName), "dchat_a_%d_%d_%d", speaker, viewer, ++g_Serial);

	int ref = SpawnAnchorEntity(anchorName, pos);
	if (ref == INVALID_REF)
		return INVALID_REF;

	strcopy(g_AnchorName[speaker][viewer], 48, anchorName);
	g_Anchor[speaker][viewer]       = ref;
	g_AnchorReadyAt[speaker][viewer] = readyAt;
	return ref;
}

void SpawnViewerHint(int speaker, int viewer, int state, const char[] anchorName, const float pos[3], float remainingSec, bool prependHyphen)
{
	if (remainingSec <= 0.15)
		return;

	int timeoutInt = RoundToCeil(remainingSec);
	if (timeoutInt < 1)
		timeoutInt = 1;

	bool isMessage = (state == STATE_MESSAGE);

	char caption[CHUNK_LEN + 4];
	if (isMessage)
	{
		if (prependHyphen)
			Format(caption, sizeof(caption), "-%s", g_Chunks[speaker][g_ChunkIndex[speaker]]);
		else
			strcopy(caption, sizeof(caption), g_Chunks[speaker][g_ChunkIndex[speaker]]);
	}
	else
	{
		caption[0] = 0;
	}

	char hintName[56], replaceKey[40], sTimeout[8];
	Format(hintName, sizeof(hintName), "dchat_%d_%d_%d", speaker, viewer, ++g_Serial);
	Format(replaceKey, sizeof(replaceKey), "dchat_p%d_v%d", speaker, viewer);
	IntToString(timeoutInt, sTimeout, sizeof(sTimeout));

	int ref = SpawnHintEntity(hintName, replaceKey, anchorName, pos, caption, isMessage, sTimeout);
	if (ref == INVALID_REF)
		return;

	int ent = EntRefToEntIndex(ref);
	AcceptEntityInput(ent, "ShowHint", viewer);

	g_Hint[speaker][viewer]      = ref;
	g_HintState[speaker][viewer] = state;
}

int SpawnHintEntity(const char[] hintName, const char[] replaceKey, const char[] anchorName, const float pos[3], const char[] caption, bool noOffscreen, const char[] sTimeout)
{
	int ent = CreateEntityByName("env_instructor_hint");
	if (ent == -1)
		return INVALID_REF;

	DispatchKeyValue(ent, "targetname",             hintName);
	DispatchKeyValue(ent, "hint_name",              hintName);
	DispatchKeyValue(ent, "hint_replace_key",       replaceKey);
	DispatchKeyValue(ent, "hint_target",            anchorName);
	DispatchKeyValue(ent, "hint_caption",           caption);
	DispatchKeyValue(ent, "hint_timeout",           sTimeout);
	DispatchKeyValue(ent, "hint_range",             "0");
	DispatchKeyValue(ent, "hint_auto_start",        "0");
	DispatchKeyValue(ent, "hint_local_player_only", "0");
	DispatchKeyValue(ent, "hint_static",           "0");
	DispatchKeyValue(ent, "hint_nooffscreen",      noOffscreen ? "1" : "0");
	DispatchKeyValue(ent, "hint_forcecaption",     "0");
	DispatchKeyValue(ent, "hint_icon_onscreen",    HINT_ICON);
	DispatchKeyValue(ent, "hint_icon_offscreen",    HINT_ICON);
	DispatchKeyValue(ent, "hint_allow_nodraw_target", "1");
	DispatchKeyValue(ent, "hint_color",            HINT_COLOR);
	DispatchKeyValue(ent, "hint_instance_type",     "2");
	DispatchKeyValue(ent, "hint_suppress_rest",    "1");

	if (!DispatchSpawn(ent))
	{
		AcceptEntityInput(ent, "Kill");
		return INVALID_REF;
	}

	TeleportEntity(ent, pos, NULL_VECTOR, NULL_VECTOR);
	return EntIndexToEntRef(ent);
}

int SpawnAnchorEntity(const char[] anchorName, const float pos[3])
{
	int ent = CreateEntityByName("info_target_instructor_hint");
	if (ent == -1)
		ent = CreateEntityByName("info_target");
	if (ent == -1)
		return INVALID_REF;

	DispatchKeyValue(ent, "targetname", anchorName);

	if (!DispatchSpawn(ent))
	{
		AcceptEntityInput(ent, "Kill");
		return INVALID_REF;
	}

	TeleportEntity(ent, pos, NULL_VECTOR, NULL_VECTOR);
	return EntIndexToEntRef(ent);
}

void DestroyHintEnt(int ref)
{
	int ent = EntRefToEntIndex(ref);
	if (ent > 0 && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "EndHint");
		AcceptEntityInput(ent, "Kill");
	}
}

void DestroyAnchorEnt(int ref)
{
	int ent = EntRefToEntIndex(ref);
	if (ent > 0 && IsValidEntity(ent))
		AcceptEntityInput(ent, "Kill");
}

// ================= 清理 =================

void ClearViewerHints(int speaker)
{
	for (int viewer = 1; viewer <= MaxClients; viewer++)
	{
		if (g_Hint[speaker][viewer] != INVALID_REF)
		{
			DestroyHintEnt(g_Hint[speaker][viewer]);
			g_Hint[speaker][viewer]      = INVALID_REF;
			g_HintState[speaker][viewer] = STATE_NONE;
		}
	}
}

void ClearPlayerHint(int speaker)
{
	ClearViewerHints(speaker);

	for (int viewer = 1; viewer <= MaxClients; viewer++)
	{
		if (g_Anchor[speaker][viewer] != INVALID_REF)
		{
			DestroyAnchorEnt(g_Anchor[speaker][viewer]);
			g_Anchor[speaker][viewer] = INVALID_REF;
		}
		g_RecInit[speaker][viewer]      = false;
		g_LastSeenChunk[speaker][viewer] = -1;
		g_HyphenChunk[speaker][viewer]   = -1;
	}

	g_Active[speaker] = false;
}

void ClearAllHints()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_Active[i])
			ClearPlayerHint(i);
	}
}

void PurgeViewerFromAllHints(int viewer)
{
	for (int speaker = 1; speaker <= MaxClients; speaker++)
	{
		if (!g_Active[speaker])
			continue;

		if (g_Hint[speaker][viewer] != INVALID_REF)
		{
			DestroyHintEnt(g_Hint[speaker][viewer]);
			g_Hint[speaker][viewer]       = INVALID_REF;
			g_HintState[speaker][viewer]  = STATE_NONE;
		}
		if (g_Anchor[speaker][viewer] != INVALID_REF)
		{
			DestroyAnchorEnt(g_Anchor[speaker][viewer]);
			g_Anchor[speaker][viewer] = INVALID_REF;
		}
		g_RecInit[speaker][viewer]      = false;
		g_LastSeenChunk[speaker][viewer] = -1;
		g_HyphenChunk[speaker][viewer]   = -1;
	}
}

// ================= 资格与几何 =================

bool IsEligibleViewer(int speaker, int viewer)
{
	if (!IsClientInGame(viewer) || IsFakeClient(viewer))
		return false;
	if (IsOptedOut(viewer))
		return false;
	if (viewer == speaker)
		return g_cvShowOwn.BoolValue;
	return true;
}

void GetHeadBasePosition(int client, float pos[3])
{
	GetClientAbsOrigin(client, pos);

	float eye[3];
	if (GetClientEyePosition(client, eye))
		pos[2] = eye[2];
}

void GetViewerAnchorPosition(int speaker, int viewer, float pos[3])
{
	float base[3];
	GetHeadBasePosition(speaker, base);

	if (viewer == speaker)
	{
		pos = base;
		pos[2] += SELF_HEAD_OFFSET_Z;
		return;
	}

	float vOrigin[3];
	GetClientAbsOrigin(viewer, vOrigin);

	float dx = base[0] - vOrigin[0];
	float dy = base[1] - vOrigin[1];
	float horiz = SquareRoot(dx * dx + dy * dy);

	pos = base;
	pos[2] += HEAD_OFFSET_Z;

	if (horiz > 0.001)
	{
		pos[0] += (dy / horiz) * SIDEWAYS_OFFSET;
		pos[1] += (-dx / horiz) * SIDEWAYS_OFFSET;
	}
}

bool IsLookingAt(int viewer, const float targetPos[3], bool wasLooking)
{
	float eye[3];
	if (!GetClientEyePosition(viewer, eye))
		return false;

	float dx = targetPos[0] - eye[0];
	float dy = targetPos[1] - eye[1];
	float dz = targetPos[2] - eye[2];
	float dist = SquareRoot(dx * dx + dy * dy + dz * dz);
	if (dist < 1.0)
		return true;

	dx /= dist;
	dy /= dist;
	dz /= dist;

	float ang[3], fwd[3];
	GetClientEyeAngles(viewer, ang);
	GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);

	float dot = fwd[0] * dx + fwd[1] * dy + fwd[2] * dz;
	float threshold = wasLooking ? (LOOK_CONE_DOT - LOOK_CONE_HYST) : LOOK_CONE_DOT;
	return dot >= threshold;
}

// ================= 文本处理 (逐行移植) =================

void NormalizeChatText(const char[] raw, char[] out, int outLen)
{
	int len = strlen(raw);
	int n = 0;
	bool lastWasSpace = true;

	for (int i = 0; i < len; i++)
	{
		char ch = raw[i];
		bool isSpace = false;

		if ((ch == '\\' || ch == '/') && (i + 1 < len) && raw[i + 1] == 't')
		{
			isSpace = true;
			i++;
		}
		else if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n')
		{
			isSpace = true;
		}

		if (isSpace)
		{
			if (!lastWasSpace && n < outLen - 1)
			{
				out[n++] = ' ';
				lastWasSpace = true;
			}
		}
		else
		{
			if (n < outLen - 1)
				out[n++] = ch;
			lastWasSpace = false;
		}
	}
	out[n] = 0;
	TrimString(out);
}

void FormatNonFinalChunk(char[] chunk, int maxlen)
{
	int len = strlen(chunk);
	if (len == 0)
		return;

	int endIdx = len;
	while (endIdx > 0)
	{
		char ch = chunk[endIdx - 1];
		if (ch == ',' || ch == ';' || ch == ':' || ch == '-' || ch == '.' || ch == ' ' || ch == '\t')
			endIdx--;
		else
			break;
	}

	if (endIdx <= 0)
		return;

	chunk[endIdx] = 0;
	StrCat(chunk, maxlen, "...");
}

int SplitMessageChunks(const char[] norm, char chunks[MAX_CHUNKS][CHUNK_LEN])
{
	char remaining[256];
	strcopy(remaining, sizeof(remaining), norm);

	int maxLen = g_cvMaxChunk.IntValue;
	int splitMax = (maxLen > 6) ? (maxLen - 3) : maxLen;
	int minSplit = splitMax - CHUNK_SPLIT_MARGIN;
	if (minSplit < 1)
		minSplit = 1;

	int count = 0;

	while (true)
	{
		int rlen = strlen(remaining);
		if (rlen <= maxLen)
		{
			if (rlen > 0 && count < MAX_CHUNKS)
				strcopy(chunks[count++], CHUNK_LEN, remaining);
			break;
		}

		int splitIdx = -1, punctIdx = -1;
		for (int i = splitMax; i >= minSplit; i--)
		{
			if (remaining[i] == ' ')
			{
				if (splitIdx == -1)
					splitIdx = i;
				if (i > 0)
				{
					int prev = remaining[i - 1];
					if (prev == ',' || prev == ';' || prev == ':' || prev == '.' || prev == '!' || prev == '?')
					{
						punctIdx = i;
						break;
					}
				}
			}
		}

		int finalIdx = (punctIdx != -1) ? punctIdx : splitIdx;

		char chunk[CHUNK_LEN], tail[256];
		if (finalIdx != -1)
		{
			strcopy(chunk, finalIdx + 1, remaining);
			TrimString(chunk);
			CopyTailSP(tail, sizeof(tail), remaining, finalIdx + 1);
		}
		else
		{
			strcopy(chunk, splitMax + 1, remaining);
			TrimString(chunk);
			CopyTailSP(tail, sizeof(tail), remaining, splitMax);
		}
		TrimString(tail);
		strcopy(remaining, sizeof(remaining), tail);

		if (strlen(chunk) > 0 && count < MAX_CHUNKS)
		{
			FormatNonFinalChunk(chunk, sizeof(chunk));
			strcopy(chunks[count++], CHUNK_LEN, chunk);
		}

		if (count >= MAX_CHUNKS)
			break;
	}

	return count;
}

float ComputeChunkDuration(const char[] text, int chunkIndex, int totalChunks)
{
	if (chunkIndex == totalChunks - 1)
	{
		int maxLen = g_cvMaxChunk.IntValue;
		float ratio = (maxLen > 0) ? (float(strlen(text)) / float(maxLen)) : 1.0;
		if (ratio < 0.0) ratio = 0.0;
		if (ratio > 1.0) ratio = 1.0;
		return FINAL_CHUNK_MIN + (FINAL_CHUNK_MAX - FINAL_CHUNK_MIN) * ratio;
	}

	float gaze = (chunkIndex == 0) ? FIRST_CHUNK_GAZE : MIDDLE_CHUNK_GAZE;
	float dur = float(strlen(text)) * CHAR_READ_TIME + gaze;
	if (dur < MIN_CHUNK_DURATION) dur = MIN_CHUNK_DURATION;
	if (dur > MAX_CHUNK_DURATION) dur = MAX_CHUNK_DURATION;
	return dur;
}

void CopyTailSP(char[] dest, int destLen, const char[] src, int start)
{
	int j = 0;
	int n = strlen(src);
	for (int i = start; i < n && j < destLen - 1; i++)
		dest[j++] = src[i];
	dest[j] = 0;
}

// ================= 退订持久化 =================

bool IsOptedOut(int client)
{
	if (IsFakeClient(client))
		return true;

	char auth[64];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)) || auth[0] == 0)
		return false;

	bool v = false;
	return g_OptMap.GetValue(auth, v) && v;
}

void LoadOptOut()
{
	if (!FileExists(g_sOptPath))
		return;

	File f = OpenFile(g_sOptPath, "r");
	if (f == null)
		return;

	char line[96];
	while (f.ReadLine(line, sizeof(line)))
	{
		TrimString(line);
		if (line[0] == 0)
			continue;
		int eq = FindCharInString(line, '=');
		if (eq <= 0)
			continue;

		char auth[64], val[4];
		strcopy(auth, eq + 1, line);
		CopyTailSP(val, sizeof(val), line, eq + 1);

		if (StrEqual(val, "1", false))
		{
			g_OptMap.SetValue(auth, true);
			if (g_OptList.FindString(auth) == -1)
				g_OptList.PushString(auth);
		}
		else
		{
			g_OptMap.SetValue(auth, false);
		}
	}
	delete f;
}

void SaveOptOut()
{
	File f = OpenFile(g_sOptPath, "w");
	if (f == null)
		return;

	char auth[64];
	for (int i = 0; i < g_OptList.Length; i++)
	{
		g_OptList.GetString(i, auth, sizeof(auth));
		bool v = false;
		if (g_OptMap.GetValue(auth, v))
			f.WriteLine("%s=%d", auth, v ? 1 : 0);
	}
	delete f;
}
