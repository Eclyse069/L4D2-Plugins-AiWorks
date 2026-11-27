/*
 * L4D2 Item Give - R键递物
 *
 * 手持以下物品、准星对着存活队友、单击 R 即递给对方：
 *   医疗包 / 电击器 / 燃烧弹药箱 / 高爆弹药箱 / 燃烧瓶 / 土制炸弹 / 胆汁罐
 *
 * 实现：
 *  - IN_RELOAD 上升沿 + 活动武器白名单，不影响主/副武器换弹；
 *  - 射线取准星队友（150 单位内），接收方倒地/同类槽位占用会给出单人提示；
 *  - RemovePlayerItem + Kill + GivePlayerItem 完成转移，失败自动退还；
 *  - 聊天提示：PrintToChatAll 风格 "\x04[提示]\x03%s\x05递给了\x03%s\x05一个\x04%s"，
 *    名字用 GetTrueName（含 ★闲置:名★ 判定，取自幸存者死亡提示插件）；
 *  - 原版游戏提示：env_instructor_hint 教练提示框（实现取自 LMC_Black_and_White_Notifier
 *    的 DirectorHint 系列函数：hint_target/icon_info/ShowHint/OnUser1 自清理）。
 *
 * v1.0.1：
 *  - 聊天颜色改走 multicolors 库（CPrintToChat）：{green}/{olive}/{lightgreen} 标签由库在
 *    发送前替换成真实颜色字节，原生 PrintToChat 不处理标签会显示纯文本。
 *
 * v1.0.2：
 *  - 系统音效复刻：递物成功时给予者播放 ui/bigreward.wav、被给予者播放
 *    ui/littlereward.wav（原版右键给药同款反馈）；
 *  - 台词不再强制播 wav，改为触发游戏自带 talker：vocalize PlayerAlertGiveItem
 *    （与 radial 菜单同路径），由游戏按角色挑台词、带字幕与口型同步。
 *
 * 仅支持 L4D2；依赖 sourcemod / sdktools / sdkhooks / multicolors（纯 stock include，
 * 编译时打入 smx，服务器无需额外插件）；无 gamedata。
 * 注意：不要与 l4d_gear_transfer（投掷医疗包按R给队友）同时启用，两者都拦 R 键递物。
 *
 * Tested compiler: SourceMod 1.12.0.7220
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>

#define PLUGIN_VERSION "1.0.2"
#define ITEM_COUNT 7

static const char g_sItemClass[][] =
{
	"weapon_first_aid_kit",
	"weapon_defibrillator",
	"weapon_upgradepack_incendiary",
	"weapon_upgradepack_explosive",
	"weapon_molotov",
	"weapon_pipe_bomb",
	"weapon_vomitjar"
};

static const char g_sItemPhrase[][] =
{
	"Item_Medkit",
	"Item_Defib",
	"Item_Incendiary",
	"Item_Explosive",
	"Item_Molotov",
	"Item_Pipebomb",
	"Item_Bile"
};

static const char g_sItemAllowCvar[][] =
{
	"l4d2_giveitem_allow_medkit",
	"l4d2_giveitem_allow_defib",
	"l4d2_giveitem_allow_incendiary",
	"l4d2_giveitem_allow_explosive",
	"l4d2_giveitem_allow_molotov",
	"l4d2_giveitem_allow_pipebomb",
	"l4d2_giveitem_allow_bile"
};

// throwables live in slot 2, medkit class items in slot 3.
static const int g_iItemSlot[ITEM_COUNT] = { 3, 3, 3, 3, 2, 2, 2 };

public Plugin myinfo =
{
	name = "L4D2 Item Give (R key)",
	author = "built for the JS-MODS server owner",
	description = "Hand medkit/defib/ammo packs/throwables to teammates by aiming and pressing R",
	version = PLUGIN_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

ConVar g_cvEnable;
ConVar g_cvRange;
ConVar g_cvCooldown;
ConVar g_cvChat;
ConVar g_cvHint;
ConVar g_cvHintTime;
ConVar g_cvHintColour;
ConVar g_cvVoice;
ConVar g_cvSound;
ConVar g_cvAllow[ITEM_COUNT];

bool  g_bEnabled;
bool  g_bChat;
bool  g_bHint;
bool  g_bVoice;
bool  g_bSound;
bool  g_bAllow[ITEM_COUNT];
float g_flRange;
float g_flCooldown;
float g_flHintTime;
char  g_sHintColour[17];

int   g_iPrevButtons[MAXPLAYERS + 1];
float g_flNextGive[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("l4d2_giveitem.phrases");

	g_cvEnable = CreateConVar("l4d2_giveitem_enable", "1",
		"Master switch: 0 disables handing items with R, 1 enables the plugin",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvRange = CreateConVar("l4d2_giveitem_range", "150.0",
		"Maximum distance (units) to hand an item to a teammate",
		FCVAR_NONE, true, 50.0, true, 500.0);

	g_cvCooldown = CreateConVar("l4d2_giveitem_cooldown", "0.5",
		"Per player give cooldown in seconds",
		FCVAR_NONE, true, 0.1, true, 5.0);

	g_cvChat = CreateConVar("l4d2_giveitem_chat", "1",
		"Broadcast the hand-off in chat (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvHint = CreateConVar("l4d2_giveitem_hint", "1",
		"Show the game instructor hint to the giver and the receiver (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvHintTime = CreateConVar("l4d2_giveitem_hinttime", "5.0",
		"Instructor hint timeout in seconds",
		FCVAR_NONE, true, 1.0, true, 20.0);

	g_cvHintColour = CreateConVar("l4d2_giveitem_hintcolour", "255 255 255",
		"Instructor hint colour (R G B)",
		FCVAR_NONE);

	g_cvVoice = CreateConVar("l4d2_giveitem_voice", "1",
		"Trigger the game talker (vocalize PlayerAlertGiveItem) on the giver, with subtitles and lip sync (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_cvSound = CreateConVar("l4d2_giveitem_sound", "1",
		"Play the vanilla reward sounds: bigreward.wav to the giver and littlereward.wav to the receiver (0/1)",
		FCVAR_NONE, true, 0.0, true, 1.0);

	for (int i = 0; i < ITEM_COUNT; i++)
	{
		g_cvAllow[i] = CreateConVar(g_sItemAllowCvar[i], "1",
			"Allow handing this item to teammates (0/1)",
			FCVAR_NONE, true, 0.0, true, 1.0);
		HookConVarChange(g_cvAllow[i], OnCvarChanged);
	}

	HookConVarChange(g_cvEnable, OnCvarChanged);
	HookConVarChange(g_cvRange, OnCvarChanged);
	HookConVarChange(g_cvCooldown, OnCvarChanged);
	HookConVarChange(g_cvChat, OnCvarChanged);
	HookConVarChange(g_cvHint, OnCvarChanged);
	HookConVarChange(g_cvHintTime, OnCvarChanged);
	HookConVarChange(g_cvHintColour, OnCvarChanged);
	HookConVarChange(g_cvVoice, OnCvarChanged);
	HookConVarChange(g_cvSound, OnCvarChanged);

	AutoExecConfig(true, "l4d2_giveitem");
	RefreshSettings();

	PrintToServer("[Item Give] v%s loaded", PLUGIN_VERSION);
	LogMessage("[Item Give] v%s loaded", PLUGIN_VERSION);
}

public void OnConfigsExecuted()
{
	RefreshSettings();
}

public void OnMapStart()
{
	// Vanilla system feedback sounds, precached so the first hand-off is instant.
	PrecacheSound("ui/bigreward.wav");
	PrecacheSound("ui/littlereward.wav");
}

public void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RefreshSettings();
}

public void OnClientPutInServer(int client)
{
	if (client >= 1 && client <= MaxClients)
	{
		g_iPrevButtons[client] = 0;
		g_flNextGive[client] = 0.0;
	}
}

public void OnClientDisconnect(int client)
{
	if (client >= 1 && client <= MaxClients)
	{
		g_iPrevButtons[client] = 0;
		g_flNextGive[client] = 0.0;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (client < 1 || client > MaxClients)
	{
		return Plugin_Continue;
	}

	// Rising edge of the reload key only; holding R never repeats.
	int pressed = buttons & ~g_iPrevButtons[client];
	g_iPrevButtons[client] = buttons;

	if (!g_bEnabled || (pressed & IN_RELOAD) == 0)
	{
		return Plugin_Continue;
	}

	if (IsFakeClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2)
	{
		return Plugin_Continue;
	}

	float now = GetGameTime();
	if (now < g_flNextGive[client])
	{
		return Plugin_Continue;
	}

	// Only intercept R while one of the supported items is actively held; the
	// primary/secondary reload is never touched.
	int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (wep <= MaxClients || !IsValidEntity(wep))
	{
		return Plugin_Continue;
	}

	char cls[64];
	GetEntityClassname(wep, cls, sizeof(cls));

	int item = FindItemIndex(cls);
	if (item < 0 || !g_bAllow[item])
	{
		return Plugin_Continue;
	}

	// Crosshair target: same feel as the vanilla pills give.
	float eye[3];
	float ang[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, ang);

	Handle trace = TR_TraceRayFilterEx(eye, ang, MASK_SOLID, RayType_Infinite, TraceFilterIgnoreSelf, client);
	if (!TR_DidHit(trace))
	{
		delete trace;
		return Plugin_Continue;
	}

	float hitpos[3];
	TR_GetEndPosition(hitpos, trace);
	int hit = TR_GetEntityIndex(trace);
	delete trace;

	if (hit < 1 || hit > MaxClients || hit == client
		|| !IsClientInGame(hit) || !IsPlayerAlive(hit) || GetClientTeam(hit) != 2)
	{
		return Plugin_Continue;
	}

	if (GetVectorDistance(eye, hitpos) > g_flRange)
	{
		return Plugin_Continue;
	}

	// The press is consumed from here on: failures enter the cooldown too so
	// the fail messages cannot be spammed.
	g_flNextGive[client] = now + g_flCooldown;

	char nameGiver[40];
	char nameReceiver[40];
	GetTrueName(client, nameGiver, sizeof(nameGiver));
	GetTrueName(hit, nameReceiver, sizeof(nameReceiver));

	if (IsClientIncapacitated(hit))
	{
		CPrintToChat(client, "%t", "FailIncap");
		return Plugin_Continue;
	}

	if (GetPlayerWeaponSlot(hit, g_iItemSlot[item]) != -1)
	{
		CPrintToChat(client, "%t", "FailSlotFull", nameReceiver);
		return Plugin_Continue;
	}

	// Transfer: remove from the giver, respawn the same classname on the
	// receiver. All supported items are single use so no state is lost.
	RemovePlayerItem(client, wep);
	AcceptEntityInput(wep, "Kill");

	int given = GivePlayerItem(hit, cls);
	if (given == -1)
	{
		// Roll back so the item is never lost.
		GivePlayerItem(client, cls);
		CPrintToChat(client, "%t", "FailGive");
		return Plugin_Continue;
	}

	// Vanilla system feedback: the giver hears bigreward, the receiver littlereward.
	if (g_bSound)
	{
		EmitSoundToClient(client, "ui/bigreward.wav");
		EmitSoundToClient(hit, "ui/littlereward.wav");
	}

	// Vanilla talker: the same vocalize path the radial menu uses, so the game
	// picks the character line with lip sync and subtitles instead of us
	// force-playing a wav.
	if (g_bVoice)
	{
		FakeClientCommand(client, "vocalize PlayerAlertGiveItem");
	}

	// Chat broadcast, item name localized per recipient.
	if (g_bChat)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			char iname[48];
			Format(iname, sizeof(iname), "%T", g_sItemPhrase[item], i);
			CPrintToChat(i, "%t", "GaveItem", nameGiver, nameReceiver, iname);
		}
	}

	// Original style game instructor hint (env_instructor_hint), one per viewer.
	if (g_bHint)
	{
		char cap[96];
		char iname[48];

		Format(iname, sizeof(iname), "%T", g_sItemPhrase[item], client);
		Format(cap, sizeof(cap), "%T", "HintGave", client, nameReceiver, iname);
		ShowGameHint(client, hit, cap);

		Format(iname, sizeof(iname), "%T", g_sItemPhrase[item], hit);
		Format(cap, sizeof(cap), "%T", "HintGot", hit, nameGiver, iname);
		ShowGameHint(hit, hit, cap);
	}

	return Plugin_Continue;
}

int FindItemIndex(const char[] classname)
{
	for (int i = 0; i < ITEM_COUNT; i++)
	{
		if (StrEqual(classname, g_sItemClass[i]))
		{
			return i;
		}
	}
	return -1;
}

public bool TraceFilterIgnoreSelf(int entity, int mask, any data)
{
	return entity != data;
}

bool IsClientIncapacitated(int client)
{
	if (!HasEntProp(client, Prop_Send, "m_isIncapacitated"))
	{
		return false;
	}
	return GetEntProp(client, Prop_Send, "m_isIncapacitated") != 0;
}

// Same semantics as the death notice plugin: mark idle bots with the human
// spectator's name so chat shows who really owns the survivor.
void GetTrueName(int client, char[] buffer, int maxlen)
{
	int human = 0;
	if (HasEntProp(client, Prop_Send, "m_humanSpectatorUserID"))
	{
		human = GetClientOfUserId(GetEntProp(client, Prop_Send, "m_humanSpectatorUserID"));
	}

	if (human != 0)
	{
		Format(buffer, maxlen, "★闲置:%N★", human);
	}
	else
	{
		GetClientName(client, buffer, maxlen);
	}
}

// env_instructor_hint is the vanilla game hint box; implementation follows the
// DirectorHint functions of LMC_Black_and_White_Notifier.
void ShowGameHint(int viewer, int anchor, const char[] caption)
{
	if (viewer < 1 || viewer > MaxClients || !IsClientInGame(viewer) || anchor < 1)
	{
		return;
	}

	char tname[24];
	FormatEx(tname, sizeof(tname), "gih%d", anchor);
	DispatchKeyValue(anchor, "targetname", tname);

	int hint = CreateEntityByName("env_instructor_hint");
	if (hint == -1)
	{
		return;
	}

	DispatchKeyValue(hint, "hint_target", tname);
	DispatchKeyValue(hint, "hint_range", "0.1");
	DispatchKeyValue(hint, "hint_icon_onscreen", "icon_info");

	char val[24];
	FormatEx(val, sizeof(val), "%f", g_flHintTime);
	DispatchKeyValue(hint, "hint_timeout", val);

	DispatchKeyValue(hint, "hint_caption", caption);
	DispatchKeyValue(hint, "hint_color", g_sHintColour);

	DispatchSpawn(hint);
	AcceptEntityInput(hint, "ShowHint", viewer);

	// Self cleanup, same trick as the reference plugin.
	FormatEx(val, sizeof(val), "OnUser1 !self:Kill::%f:1", g_flHintTime);
	SetVariantString(val);
	AcceptEntityInput(hint, "AddOutput");
	AcceptEntityInput(hint, "FireUser1");
}

void RefreshSettings()
{
	g_bEnabled = g_cvEnable.BoolValue;
	g_bChat = g_cvChat.BoolValue;
	g_bHint = g_cvHint.BoolValue;
	g_bVoice = g_cvVoice.BoolValue;
	g_bSound = g_cvSound.BoolValue;
	g_flRange = g_cvRange.FloatValue;
	g_flCooldown = g_cvCooldown.FloatValue;
	g_flHintTime = g_cvHintTime.FloatValue;
	g_cvHintColour.GetString(g_sHintColour, sizeof(g_sHintColour));

	for (int i = 0; i < ITEM_COUNT; i++)
	{
		g_bAllow[i] = g_cvAllow[i].BoolValue;
	}
}
