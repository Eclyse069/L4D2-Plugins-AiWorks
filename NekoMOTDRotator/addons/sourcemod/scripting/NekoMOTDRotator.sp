/**
 * NekoMOTDRotator - host/motd 按时段轮换插件 v1.0
 * (NekoServerNameRotator 同款机制, 轮换目标改为 hostfile/motdfile 指向的文件)
 *
 * 机制:
 *   - 生效文件按引擎 convar 运行时值解析: hostfile(当前 host2.txt) / motdfile(motd.txt)
 *     每次应用时实时读取, 改指向后无需重载插件
 *   - 池文件: addons/sourcemod/data/motdrotator/host_1..N.txt + motd_1..N.txt
 *     首次加载自动从当前生效文件播种快照(轮换初始零影响), 之后逐个编辑即可
 *   - 应用 = 池文件整文件字节覆写生效文件, 同一编号同时驱动 host 与 motd, 缺哪个跳哪个
 *   - 引擎在玩家连接时读取 host/motd, 轮换对之后进服的玩家立即生效
 *
 * 模式:
 *   time   - 按现实时间时段轮换(凌晨/早上/下午/夜晚/深夜, 配置可改)
 *   order  - 按编号顺序循环, 每 interval 秒一次
 *   random - 随机(不与上一次重复), 每 interval 秒一次
 *
 * 管理命令 (ROOT 权限):
 *   sm_rotatemotd               查看状态
 *   sm_rotatemotd_next          立即轮换一次(time=重新应用当前时段)
 *   sm_rotatemotd_set <1-N>     立即应用指定编号
 *   sm_rotatemotd_mode <mode>   切换模式(持久写入配置)
 *   sm_rotatemotd_reload        重读配置并补播种缺失池文件
 *
 * 配置: addons/sourcemod/configs/NekoMOTDRotator.cfg
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.0"
#define MAX_POOL       32
#define MAX_FILE_BYTES 65536
#define TICK_SECONDS   10.0

public Plugin myinfo =
{
	name        = "Neko MOTD Rotator",
	description = "Rotate host/motd files by time period / order / random",
	author      = "lead",
	version     = PLUGIN_VERSION,
	url         = ""
};

char g_sPeriodLabels[MAX_POOL][64];
int  g_iPeriodStart[MAX_POOL];
int  g_iPeriodIndex[MAX_POOL];
int  g_iPeriodCount = 0;

int  g_iMaxIndex    = 0;
int  g_iCurrentIndex = -1;
int  g_iLastSwitch  = 0;

char g_sMode[16] = "time";
int  g_iInterval = 300;
int  g_iTimezone = 8;

char g_sConfigPath[PLATFORM_MAX_PATH];

public void OnPluginStart()
{
	BuildPath(Path_SM, g_sConfigPath, sizeof(g_sConfigPath), "configs/NekoMOTDRotator.cfg");

	RegAdminCmd("sm_rotatemotd",        Cmd_Status,    ADMFLAG_ROOT, "查看 host/motd 轮换状态");
	RegAdminCmd("sm_rotatemotd_next",   Cmd_Next,       ADMFLAG_ROOT, "立即轮换一次");
	RegAdminCmd("sm_rotatemotd_set",    Cmd_Set,        ADMFLAG_ROOT, "立即应用指定编号");
	RegAdminCmd("sm_rotatemotd_mode",   Cmd_Mode,       ADMFLAG_ROOT, "切换轮换模式 time/order/random");
	RegAdminCmd("sm_rotatemotd_reload", Cmd_CfgReload,  ADMFLAG_ROOT, "重读配置并补播种");

	LoadConfig();

	CreateTimer(TICK_SECONDS, Timer_Tick, _, TIMER_REPEAT);
}

public void OnConfigsExecuted()
{
	// 插件加载后首次激活; 之后换图不再重复动作
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
	if (g_iMaxIndex <= 0)
		return;

	if (StrEqual(g_sMode, "time", false))
	{
		ApplyIndex(GetPeriodIndexForNow(), false);
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
	if (g_iCurrentIndex < 1)
		return 1;
	return (g_iCurrentIndex % g_iMaxIndex) + 1;
}

void ApplyIndex(int idx, bool force)
{
	if (idx < 1 || idx > g_iMaxIndex)
		return;
	if (!force && idx == g_iCurrentIndex)
		return;

	bool any = false;
	if (CopyPoolToTarget("host", idx, true))
		any = true;
	if (CopyPoolToTarget("motd", idx, false))
		any = true;

	if (any)
	{
		g_iCurrentIndex = idx;
		PrintToServer("[MOTDRotator] applied index %d (mode:%s)", idx, g_sMode);
		LogMessage("applied index %d (mode:%s)", idx, g_sMode);
	}
}

bool CopyPoolToTarget(const char[] prefix, int idx, bool isHost)
{
	char pool[PLATFORM_MAX_PATH];
	GetPoolPath(pool, sizeof(pool), prefix, idx);
	if (!FileExists(pool))
		return false;
	if (FileSize(pool) > MAX_FILE_BYTES)
	{
		LogError("[MOTDRotator] pool file too large (>%d bytes): %s_%d.txt", MAX_FILE_BYTES, prefix, idx);
		return false;
	}

	char target[PLATFORM_MAX_PATH];
	GetTargetPath(target, sizeof(target), isHost);
	if (target[0] == 0)
		return false;

	if (!CopyFileText(pool, target))
	{
		LogError("[MOTDRotator] copy failed: %s_%d.txt -> %s", prefix, idx, target);
		return false;
	}

	return true;
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

	return (best >= 0) ? g_iPeriodIndex[best] : 1;
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
	if (g_iMaxIndex <= 1)
		return 1;

	int idx = GetRandomInt(1, g_iMaxIndex);
	if (idx == avoid)
		idx = (idx % g_iMaxIndex) + 1;

	return idx;
}

// ================= 目标与池路径 =================

void GetTargetPath(char[] out, int maxlen, bool isHost)
{
	char fname[PLATFORM_MAX_PATH];
	if (isHost)
		ResolveConvarFile("hostfile", "host.txt", fname, sizeof(fname));
	else
		ResolveConvarFile("motdfile", "motd.txt", fname, sizeof(fname));

	// 去掉可能的路径前缀, 只留文件名, 固定落到游戏目录
	int slash = FindCharInString(fname, '/', true);
	char base[PLATFORM_MAX_PATH];
	if (slash != -1)
		CopyTail2(base, sizeof(base), fname, slash + 1);
	else
		strcopy(base, sizeof(base), fname);

	// Path_SM 若为绝对路径, 剥掉 /addons/sourcemod 得游戏目录;
	// 若为相对路径(本服即是), srcds 的 CWD 就是游戏目录, 直接用文件名
	char smbase[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, smbase, sizeof(smbase), ".");
	if (smbase[0] == '/')
	{
		ReplaceString(smbase, sizeof(smbase), "/addons/sourcemod", "");
		ReplaceString(smbase, sizeof(smbase), "/.", "");
		if (smbase[0] != 0)
		{
			Format(out, maxlen, "%s/%s", smbase, base);
			return;
		}
	}
	strcopy(out, maxlen, base);
}

void ResolveConvarFile(const char[] cvarname, const char[] def, char[] out, int outLen)
{
	ConVar cv = FindConVar(cvarname);
	if (cv != null)
	{
		cv.GetString(out, outLen);
		TrimString(out);
		if (out[0] != 0)
			return;
	}
	strcopy(out, outLen, def);
}

void GetPoolPath(char[] out, int maxlen, const char[] prefix, int idx)
{
	BuildPath(Path_SM, out, maxlen, "data/motdrotator/%s_%d.txt", prefix, idx);
}

// ================= 配置 =================

void LoadConfig()
{
	g_iPeriodCount   = 0;
	g_iMaxIndex      = 0;
	g_iCurrentIndex  = -1;
	g_iLastSwitch    = GetTime();

	if (!FileExists(g_sConfigPath))
		WriteDefaultConfig(g_sConfigPath);

	if (!ParseConfigFromFile())
	{
		PrintToServer("[MOTDRotator] config invalid or no periods, regenerating default: configs/NekoMOTDRotator.cfg");
		LogMessage("config invalid, regenerating default config");
		WriteDefaultConfig(g_sConfigPath);
		ParseConfigFromFile();
	}

	SeedMissingPools();
}

bool ParseConfigFromFile()
{
	KeyValues kv = new KeyValues("NekoMOTDRotator");
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
			char label[64];
			kv.GetSectionName(label, sizeof(label));
			int start = kv.GetNum("start", -1);
			int index = kv.GetNum("index", -1);

			if (start < 0 || start > 23 || index < 1 || index > MAX_POOL || g_iPeriodCount >= MAX_POOL)
				continue;

			strcopy(g_sPeriodLabels[g_iPeriodCount], 64, label);
			g_iPeriodStart[g_iPeriodCount] = start;
			g_iPeriodIndex[g_iPeriodCount]  = index;
			if (index > g_iMaxIndex)
				g_iMaxIndex = index;
			g_iPeriodCount++;
		} while (kv.GotoNextKey(false));
	}
	delete kv;

	return g_iPeriodCount > 0;
}

void SeedMissingPools()
{
	if (g_iMaxIndex <= 0)
		return;

	// 确保池目录存在
	char pooldir[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, pooldir, sizeof(pooldir), "data/motdrotator");
	if (!DirExists(pooldir))
		CreateDirectory(pooldir, 511);

	char hostTarget[PLATFORM_MAX_PATH], motdTarget[PLATFORM_MAX_PATH];
	GetTargetPath(hostTarget, sizeof(hostTarget), true);
	GetTargetPath(motdTarget, sizeof(motdTarget), false);

	char pool[PLATFORM_MAX_PATH];

	for (int i = 1; i <= g_iMaxIndex; i++)
	{
		GetPoolPath(pool, sizeof(pool), "host", i);
		if (!FileExists(pool) && FileExists(hostTarget) && CopyFileText(hostTarget, pool))
		{
			PrintToServer("[MOTDRotator] seeded host_%d.txt from active host file", i);
			LogMessage("seeded host_%d.txt", i);
		}

		GetPoolPath(pool, sizeof(pool), "motd", i);
		if (!FileExists(pool) && FileExists(motdTarget) && CopyFileText(motdTarget, pool))
		{
			PrintToServer("[MOTDRotator] seeded motd_%d.txt from active motd file", i);
			LogMessage("seeded motd_%d.txt", i);
		}
	}
}

void WriteDefaultConfig(const char[] path)
{
	File f = OpenFile(path, "w");
	if (f == null)
	{
		LogError("[MOTDRotator] cannot write default config: %s", path);
		return;
	}

	f.WriteLine("\"NekoMOTDRotator\"");
	f.WriteLine("{");
	f.WriteLine("\t\"Settings\"");
	f.WriteLine("\t{");
	f.WriteLine("\t\t\"mode\"\t\t\"time\"");
	f.WriteLine("\t\t\"interval\"\t\"300\"");
	f.WriteLine("\t\t\"timezone\"\t\"8\"");
	f.WriteLine("\t}");
	f.WriteLine("\t\"TimePeriods\"");
	f.WriteLine("\t{");
	f.WriteLine("\t\t\"凌晨\"\t{ \"start\" \"0\"\t\"index\" \"1\" }");
	f.WriteLine("\t\t\"早上\"\t{ \"start\" \"6\"\t\"index\" \"2\" }");
	f.WriteLine("\t\t\"下午\"\t{ \"start\" \"12\"\t\"index\" \"3\" }");
	f.WriteLine("\t\t\"夜晚\"\t{ \"start\" \"18\"\t\"index\" \"4\" }");
	f.WriteLine("\t\t\"深夜\"\t{ \"start\" \"22\"\t\"index\" \"5\" }");
	f.WriteLine("\t}");
	f.WriteLine("}");
	delete f;
}

void PersistMode(const char[] newMode)
{
	// 整文件重写(不用 KV ExportToFile, 避免只导出当前节点丢失其它配置)
	File f = OpenFile(g_sConfigPath, "w");
	if (f == null)
	{
		LogError("[MOTDRotator] cannot write config: %s", g_sConfigPath);
		return;
	}

	f.WriteLine("\"NekoMOTDRotator\"");
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
		f.WriteLine("\t\t\"%s\"\t{ \"start\" \"%d\"\t\"index\" \"%d\" }", g_sPeriodLabels[i], g_iPeriodStart[i], g_iPeriodIndex[i]);
	}
	f.WriteLine("\t}");
	f.WriteLine("}");
	delete f;
}

// ================= 工具 =================

bool CopyFileText(const char[] src, const char[] dst)
{
	File fIn = OpenFile(src, "r");
	if (fIn == null)
		return false;

	File fOut = OpenFile(dst, "w");
	if (fOut == null)
	{
		delete fIn;
		return false;
	}

	char line[4096];
	while (fIn.ReadLine(line, sizeof(line)))
	{
		int len = strlen(line);
		while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
			line[--len] = 0;
		fOut.WriteLine("%s", line);
	}

	delete fIn;
	delete fOut;
	return true;
}

void CopyTail2(char[] dest, int destLen, const char[] src, int start)
{
	int j = 0;
	int n = strlen(src);
	for (int i = start; i < n && j < destLen - 1; i++)
		dest[j++] = src[i];
	dest[j] = 0;
}

// ================= 命令 =================

public Action Cmd_Status(int client, int args)
{
	ReplyToCommand(client, "[MOTDRotator] mode:%s interval:%ds timezone:UTC+%d current index:%d / max:%d",
		g_sMode, g_iInterval, g_iTimezone, g_iCurrentIndex, g_iMaxIndex);

	char hostTarget[PLATFORM_MAX_PATH], motdTarget[PLATFORM_MAX_PATH];
	GetTargetPath(hostTarget, sizeof(hostTarget), true);
	GetTargetPath(motdTarget, sizeof(motdTarget), false);
	ReplyToCommand(client, "[MOTDRotator] host target: %s", hostTarget);
	ReplyToCommand(client, "[MOTDRotator] motd target: %s", motdTarget);

	for (int i = 0; i < g_iPeriodCount; i++)
	{
		char mark[16];
		if (g_iPeriodIndex[i] == g_iCurrentIndex)
			strcopy(mark, sizeof(mark), "  <- now");
		else
			mark[0] = 0;

		ReplyToCommand(client, "[MOTDRotator]   %s (start %d:00, index %d)%s", g_sPeriodLabels[i], g_iPeriodStart[i], g_iPeriodIndex[i], mark);
	}

	return Plugin_Handled;
}

public Action Cmd_Next(int client, int args)
{
	if (g_iMaxIndex <= 0)
	{
		ReplyToCommand(client, "[MOTDRotator] no periods configured");
		return Plugin_Handled;
	}

	if (StrEqual(g_sMode, "time", false))
	{
		// time 模式: 立即重新应用当前时段(编辑池文件后用它立即生效)
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

	ReplyToCommand(client, "[MOTDRotator] done, see server console");
	return Plugin_Handled;
}

public Action Cmd_Set(int client, int args)
{
	if (g_iMaxIndex <= 0)
	{
		ReplyToCommand(client, "[MOTDRotator] no periods configured");
		return Plugin_Handled;
	}
	if (args < 1)
	{
		ReplyToCommand(client, "[MOTDRotator] usage: sm_rotatemotd_set <1-%d>", g_iMaxIndex);
		return Plugin_Handled;
	}

	char arg[16];
	GetCmdArg(1, arg, sizeof(arg));
	int n = StringToInt(arg);

	if (n < 1 || n > g_iMaxIndex)
	{
		ReplyToCommand(client, "[MOTDRotator] invalid index: %s (range 1-%d)", arg, g_iMaxIndex);
		return Plugin_Handled;
	}

	ApplyIndex(n, true);
	ReplyToCommand(client, "[MOTDRotator] applied index %d", n);
	return Plugin_Handled;
}

public Action Cmd_Mode(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[MOTDRotator] usage: sm_rotatemotd_mode <time|order|random>  current:%s", g_sMode);
		return Plugin_Handled;
	}

	char arg[16];
	GetCmdArg(1, arg, sizeof(arg));
	if (!StrEqual(arg, "time", false) && !StrEqual(arg, "order", false) && !StrEqual(arg, "random", false))
	{
		ReplyToCommand(client, "[MOTDRotator] unknown mode: %s (use time|order|random)", arg);
		return Plugin_Handled;
	}

	strcopy(g_sMode, sizeof(g_sMode), arg);
	PersistMode(g_sMode);

	ReplyToCommand(client, "[MOTDRotator] mode set to %s (saved to config)", g_sMode);
	LogMessage("mode changed to %s", g_sMode);

	g_iLastSwitch = GetTime();
	Tick(true);
	return Plugin_Handled;
}

public Action Cmd_CfgReload(int client, int args)
{
	LoadConfig();
	Tick(true);
	ReplyToCommand(client, "[MOTDRotator] config reloaded (mode:%s, periods:%d, max index:%d)", g_sMode, g_iPeriodCount, g_iMaxIndex);
	return Plugin_Handled;
}
