/**
 * NekoVanillaNameRotator v1.0 - 原版服名轮换
 *
 * NekoServerNameRotator 的姊妹版本, 面向不使用 NekoServerName.smx 的服务器:
 * 直接轮换引擎原生 hostname(即 server.cfg 里的服务器名), 零外部依赖。
 *
 * 与 Neko 版的差异:
 *   - 不依赖 NekoServerName.smx, 不覆写 nekocustom.cfg, 不触发 reload
 *   - 名字是纯静态文本(无 {gamedifficulty} 等占位符 —— 那是 NekoServerName 的功能)
 *   - 巡检时如果 hostname 被其它插件/server.cfg 改掉, 10秒内自动纠正回来
 *   - server.cfg 每次换图重设 hostname 的问题天然免疫(下一巡检即恢复)
 *
 * 三种模式(与 Neko 系列一致):
 *   time   - 按现实时间时段轮换(凌晨0/早上6/下午12/夜晚18/深夜22, 配置可改)
 *   order  - 按配置顺序循环, 每 interval 秒一切换
 *   random - 随机(不与上一次重复), 每 interval 秒一切换
 *
 * 管理命令 (ROOT):
 *   sm_hostnamerotate               查看状态
 *   sm_hostnamerotate_next          立即轮换一次(time=重新应用当前时段)
 *   sm_hostnamerotate_set <1-N>     立即应用指定编号
 *   sm_hostnamerotate_mode <mode>   切换模式(持久写入配置)
 *   sm_hostnamerotate_reload        重读配置
 *
 * 配置: addons/sourcemod/configs/NekoVanillaNameRotator.cfg
 *      TimePeriods 每项: start=起始小时, name=该时段服务器名
 *      新增名字就加一项, 然后 sm_hostnamerotate_reload
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.0"
#define MAX_POOL       32
#define NAME_LEN       160
#define TICK_SECONDS   10.0

public Plugin myinfo =
{
	name        = "Neko Vanilla ServerName Rotator",
	description = "Rotate the vanilla hostname by time period / order / random",
	author      = "lead",
	version     = PLUGIN_VERSION,
	url         = ""
};

char g_sNames[MAX_POOL][NAME_LEN];
char g_sPeriodLabels[MAX_POOL][64];
int  g_iPeriodStart[MAX_POOL];
int  g_iPeriodCount = 0;

int  g_iCurrentIndex = -1;
int  g_iLastSwitch   = 0;

char g_sMode[16] = "time";
int  g_iInterval = 300;
int  g_iTimezone = 8;

ConVar g_cvHostname;
char g_sConfigPath[PLATFORM_MAX_PATH];

public void OnPluginStart()
{
	BuildPath(Path_SM, g_sConfigPath, sizeof(g_sConfigPath), "configs/NekoVanillaNameRotator.cfg");

	g_cvHostname = FindConVar("hostname");

	RegAdminCmd("sm_hostnamerotate",        Cmd_Status,    ADMFLAG_ROOT, "查看原版服名轮换状态");
	RegAdminCmd("sm_hostnamerotate_next",   Cmd_Next,       ADMFLAG_ROOT, "立即轮换一次");
	RegAdminCmd("sm_hostnamerotate_set",    Cmd_Set,        ADMFLAG_ROOT, "立即应用指定编号");
	RegAdminCmd("sm_hostnamerotate_mode",   Cmd_Mode,       ADMFLAG_ROOT, "切换轮换模式 time/order/random");
	RegAdminCmd("sm_hostnamerotate_reload", Cmd_CfgReload,  ADMFLAG_ROOT, "重读配置");

	LoadConfig();

	CreateTimer(TICK_SECONDS, Timer_Tick, _, TIMER_REPEAT);
}

public void OnConfigsExecuted()
{
	// 插件加载后立即应用一次
	if (g_iCurrentIndex == -1)
		Tick(true);
}

public Action Timer_Tick(Handle timer)
{
	Tick(false);
	return Plugin_Continue;
}

// ================= 轮换逻辑 =================

void Tick(bool immediate)
{
	if (g_iPeriodCount == 0 || g_cvHostname == null)
		return;

	if (StrEqual(g_sMode, "time", false))
	{
		// time 模式: 始终把当前时段的名字钉在 hostname 上
		ApplyIndex(GetPeriodIndexForNow(), immediate);
		return;
	}

	int now = GetTime();
	if (!immediate && now - g_iLastSwitch < g_iInterval)
		return;
	g_iLastSwitch = now;

	if (StrEqual(g_sMode, "random", false))
		ApplyIndex(RandomExcept(g_iCurrentIndex), true);
	else
		ApplyIndex(NextOrderIndex(), true);
}

int NextOrderIndex()
{
	if (g_iCurrentIndex < 0 || g_iCurrentIndex >= g_iPeriodCount)
		return 0;
	return (g_iCurrentIndex + 1) % g_iPeriodCount;
}

void ApplyIndex(int idx, bool force)
{
	if (idx < 0 || idx >= g_iPeriodCount)
		return;
	if (!force && idx == g_iCurrentIndex)
		return;

	char cur[NAME_LEN];
	g_cvHostname.GetString(cur, sizeof(cur));
	if (StrEqual(cur, g_sNames[idx], false))
	{
		// 名字已一致(比如被 server.cfg 重设后又改回, 或本来就没变), 只更新状态
		g_iCurrentIndex = idx;
		return;
	}

	g_cvHostname.SetString(g_sNames[idx]);
	g_iCurrentIndex = idx;

	PrintToServer("[VanillaNameRotator] applied index %d (%s, mode:%s): %s", idx + 1, g_sPeriodLabels[idx], g_sMode, g_sNames[idx]);
	LogMessage("applied index %d (%s, mode:%s): %s", idx + 1, g_sPeriodLabels[idx], g_sMode, g_sNames[idx]);
}

int GetPeriodIndexForNow()
{
	int hour = GetLocalHour();
	int best = -1;
	for (int i = 0; i < g_iPeriodCount; i++)
	{
		if (g_iPeriodStart[i] <= hour)
			best = i;
		else
			break;
	}
	if (best == -1)
		best = g_iPeriodCount - 1; // 跨午夜回绕到最晚时段

	return (best >= 0) ? best : 0;
}

int GetLocalHour()
{
	int secs = (GetTime() + g_iTimezone * 3600) % 86400;
	if (secs < 0)
		secs += 86400;
	return secs / 3600;
}

int RandomExcept(int avoid)
{
	if (g_iPeriodCount <= 1)
		return 0;

	int idx = GetRandomInt(0, g_iPeriodCount - 1);
	if (idx == avoid)
		idx = (idx + GetRandomInt(1, g_iPeriodCount - 1)) % g_iPeriodCount;

	return idx;
}

// ================= 配置 =================

void LoadConfig()
{
	g_iPeriodCount   = 0;
	g_iCurrentIndex  = -1;
	g_iLastSwitch    = GetTime();

	if (!FileExists(g_sConfigPath))
		WriteDefaultConfig(g_sConfigPath);

	if (!ParseConfigFromFile())
	{
		PrintToServer("[VanillaNameRotator] config invalid or no periods, regenerating default");
		LogMessage("config invalid, regenerating default config");
		WriteDefaultConfig(g_sConfigPath);
		ParseConfigFromFile();
	}
}

bool ParseConfigFromFile()
{
	KeyValues kv = new KeyValues("NekoVanillaNameRotator");
	if (!kv.ImportFromFile(g_sConfigPath))
	{
		delete kv;
		return false;
	}

	if (kv.JumpToKey("Settings", false))
	{
		kv.GetString("mode", g_sMode, sizeof(g_sMode), "time");
		g_iInterval = kv.GetNum("interval", 300);
		g_iTimezone = kv.GetNum("timezone", 8);

		if (g_iInterval < 10)
			g_iInterval = 10;
		if (g_iTimezone < -12 || g_iTimezone > 14)
			g_iTimezone = 8;

		kv.Rewind();
	}

	if (kv.JumpToKey("TimePeriods", false) && kv.GotoFirstSubKey(false))
	{
		do
		{
			char label[64], name[NAME_LEN];
			kv.GetSectionName(label, sizeof(label));
			kv.GetString("name", name, sizeof(name), "");
			int start = kv.GetNum("start", -1);

			if (name[0] == 0 || start < 0 || start > 23 || g_iPeriodCount >= MAX_POOL)
				continue;

			strcopy(g_sNames[g_iPeriodCount], NAME_LEN, name);
			strcopy(g_sPeriodLabels[g_iPeriodCount], 64, label);
			g_iPeriodStart[g_iPeriodCount] = start;
			g_iPeriodCount++;
		} while (kv.GotoNextKey(false));
	}
	delete kv;

	return g_iPeriodCount > 0;
}

// 按起始小时升序排序(保证跨午夜回绕逻辑正确)
void SortPeriods()
{
	for (int i = 1; i < g_iPeriodCount; i++)
	{
		int keyStart = g_iPeriodStart[i];
		char keyName[NAME_LEN], keyLabel[64];
		strcopy(keyName, NAME_LEN, g_sNames[i]);
		strcopy(keyLabel, 64, g_sPeriodLabels[i]);

		int j = i - 1;
		while (j >= 0 && g_iPeriodStart[j] > keyStart)
		{
			g_iPeriodStart[j + 1] = g_iPeriodStart[j];
			strcopy(g_sNames[j + 1], NAME_LEN, g_sNames[j]);
			strcopy(g_sPeriodLabels[j + 1], 64, g_sPeriodLabels[j]);
			j--;
		}
		g_iPeriodStart[j + 1] = keyStart;
		strcopy(g_sNames[j + 1], NAME_LEN, keyName);
		strcopy(g_sPeriodLabels[j + 1], 64, keyLabel);
	}
}

void WriteDefaultConfig(const char[] path)
{
	File f = OpenFile(path, "w");
	if (f == null)
	{
		LogError("[VanillaNameRotator] cannot write default config: %s", path);
		return;
	}

	f.WriteLine("\"NekoVanillaNameRotator\"");
	f.WriteLine("{");
	f.WriteLine("\t\"Settings\"");
	f.WriteLine("\t{");
	f.WriteLine("\t\t\"mode\"\t\t\"time\"");
	f.WriteLine("\t\t\"interval\"\t\"300\"");
	f.WriteLine("\t\t\"timezone\"\t\"8\"");
	f.WriteLine("\t}");
	f.WriteLine("\t\"TimePeriods\"");
	f.WriteLine("\t{");
	f.WriteLine("\t\t\"凌晨\"\t{ \"start\" \"0\"\t\"name\" \"你的服务器名·凌晨好梦\" }");
	f.WriteLine("\t\t\"早上\"\t{ \"start\" \"6\"\t\"name\" \"你的服务器名·早上好呀\" }");
	f.WriteLine("\t\t\"下午\"\t{ \"start\" \"12\"\t\"name\" \"你的服务器名·下午好\" }");
	f.WriteLine("\t\t\"夜晚\"\t{ \"start\" \"18\"\t\"name\" \"你的服务器名·晚上好\" }");
	f.WriteLine("\t\t\"深夜\"\t{ \"start\" \"22\"\t\"name\" \"你的服务器名·夜深了\" }");
	f.WriteLine("\t}");
	f.WriteLine("}");
	delete f;
}

void PersistMode(const char[] newMode)
{
	// 整文件重写, 避免任何 KV 导出损坏其它配置节
	File f = OpenFile(g_sConfigPath, "w");
	if (f == null)
	{
		LogError("[VanillaNameRotator] cannot write config: %s", g_sConfigPath);
		return;
	}

	f.WriteLine("\"NekoVanillaNameRotator\"");
	f.WriteLine("{");
	f.WriteLine("\t\"Settings\"");
	f.WriteLine("\t{");
	f.WriteLine("\t\t\"mode\"\t\t\"%s\"", newMode);
	f.WriteLine("\t\t\"interval\"\t\"%d\"", g_iInterval);
	f.WriteLine("\t\t\"timezone\"\t\"%d\"", g_iTimezone);
	f.WriteLine("\t}");
	f.WriteLine("\t\"TimePeriods\"");
	f.WriteLine("\t{");
	for (int i = 0; i < g_iPeriodCount; i++)
	{
		f.WriteLine("\t\t\"%s\"\t{ \"start\" \"%d\"\t\"name\" \"%s\" }", g_sPeriodLabels[i], g_iPeriodStart[i], g_sNames[i]);
	}
	f.WriteLine("\t}");
	f.WriteLine("}");
	delete f;
}

// ================= 命令 =================

public Action Cmd_Status(int client, int args)
{
	ReplyToCommand(client, "[VanillaNameRotator] mode:%s interval:%ds timezone:UTC+%d periods:%d current:%d", g_sMode, g_iInterval, g_iTimezone, g_iPeriodCount, g_iCurrentIndex + 1);

	for (int i = 0; i < g_iPeriodCount; i++)
	{
		char mark[16];
		if (i == g_iCurrentIndex)
			strcopy(mark, sizeof(mark), "  <- now");
		else
			mark[0] = 0;

		ReplyToCommand(client, "[VanillaNameRotator]   #%d %s (start %d:00) \"%s\"%s", i + 1, g_sPeriodLabels[i], g_iPeriodStart[i], g_sNames[i], mark);
	}

	return Plugin_Handled;
}

public Action Cmd_Next(int client, int args)
{
	if (g_iPeriodCount == 0)
	{
		ReplyToCommand(client, "[VanillaNameRotator] no periods configured");
		return Plugin_Handled;
	}

	if (StrEqual(g_sMode, "time", false))
	{
		ApplyIndex(GetPeriodIndexForNow(), true);
	}
	else
	{
		g_iLastSwitch = GetTime();
		if (StrEqual(g_sMode, "random", false))
			ApplyIndex(RandomExcept(g_iCurrentIndex), true);
		else
			ApplyIndex(NextOrderIndex(), true);
	}

	ReplyToCommand(client, "[VanillaNameRotator] done, see server console");
	return Plugin_Handled;
}

public Action Cmd_Set(int client, int args)
{
	if (g_iPeriodCount == 0)
	{
		ReplyToCommand(client, "[VanillaNameRotator] no periods configured");
		return Plugin_Handled;
	}
	if (args < 1)
	{
		ReplyToCommand(client, "[VanillaNameRotator] usage: sm_hostnamerotate_set <1-%d>", g_iPeriodCount);
		return Plugin_Handled;
	}

	char arg[16];
	GetCmdArg(1, arg, sizeof(arg));
	int n = StringToInt(arg);

	if (n < 1 || n > g_iPeriodCount)
	{
		ReplyToCommand(client, "[VanillaNameRotator] invalid index: %s (range 1-%d)", arg, g_iPeriodCount);
		return Plugin_Handled;
	}

	ApplyIndex(n - 1, true);
	ReplyToCommand(client, "[VanillaNameRotator] applied #%d", n);
	return Plugin_Handled;
}

public Action Cmd_Mode(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[VanillaNameRotator] usage: sm_hostnamerotate_mode <time|order|random>  current:%s", g_sMode);
		return Plugin_Handled;
	}

	char arg[16];
	GetCmdArg(1, arg, sizeof(arg));
	if (!StrEqual(arg, "time", false) && !StrEqual(arg, "order", false) && !StrEqual(arg, "random", false))
	{
		ReplyToCommand(client, "[VanillaNameRotator] unknown mode: %s (use time|order|random)", arg);
		return Plugin_Handled;
	}

	strcopy(g_sMode, sizeof(g_sMode), arg);
	PersistMode(g_sMode);

	ReplyToCommand(client, "[VanillaNameRotator] mode set to %s (saved to config)", g_sMode);
	LogMessage("mode changed to %s", g_sMode);

	g_iLastSwitch = GetTime();
	Tick(true);
	return Plugin_Handled;
}

public Action Cmd_CfgReload(int client, int args)
{
	LoadConfig();
	SortPeriods();
	Tick(true);
	ReplyToCommand(client, "[VanillaNameRotator] config reloaded (mode:%s, periods:%d)", g_sMode, g_iPeriodCount);
	return Plugin_Handled;
}
