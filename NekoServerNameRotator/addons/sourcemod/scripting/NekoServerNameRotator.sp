/**
 * NekoServerNameRotator - 服务器名字轮换插件 (配合 NekoServerName.smx 使用)
 *
 * 原理: NekoServerName.smx 只在插件加载/换图时读取 data/nekocustom.cfg 并缓存 ServerNameFormat。
 * 本插件把选中的 data/nekocustom_XX.cfg (同内部格式) 整文件覆写到 data/nekocustom.cfg,
 * 然后执行 reloadcmd (默认 sm plugins reload NekoServerName) 让其立即重读并刷新服务器名字。
 * 全程不抢 hostname, 与 NekoServerName 零冲突。
 *
 * 模式:
 *   time   - 按现实时间时段轮换 (凌晨/早上/下午/夜晚/深夜, 起始小时可在配置里改)
 *   order  - 按编号顺序轮换 (interval 秒切换一次)
 *   random - 随机轮换 (interval 秒切换一次, 不与上一次重复)
 *
 * 命令 (需要 ROOT 权限):
 *   sm_rotatename                 查看状态
 *   sm_rotatename_next            立即轮换一次 (time 模式 = 立即重新应用当前时段)
 *   sm_rotatename_set <1-N>       立即应用指定编号的 XX 文件
 *   sm_rotatename_mode <mode>     切换模式 time/order/random (会写入配置文件)
 *   sm_rotatename_reload          重读本插件配置
 *
 * 配置: addons/sourcemod/configs/NekoServerNameRotator.cfg
 * 注意: 每次轮换会重载 NekoServerName, 其内部 {restartcount} 失败重启计数会被清零。
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.1"
#define MAX_POOL       32
#define MAX_CFG_BYTES  16384
#define TICK_SECONDS   10.0

public Plugin myinfo =
{
	name        = "Neko ServerName Rotator",
	description = "Rotate server name via data/nekocustom_XX.cfg (time/order/random)",
	author      = "lead",
	version     = PLUGIN_VERSION,
	url         = ""
};

char g_sPoolFiles[MAX_POOL][PLATFORM_MAX_PATH];
char g_sPoolBase[MAX_POOL][64];
char g_sPeriodLabels[MAX_POOL][64];
int  g_iPeriodStart[MAX_POOL];
int  g_iPoolCount = 0;

int  g_iCurrentIndex = -1;
int  g_iLastSwitch   = 0;

char g_sMode[16]       = "time";
int  g_iInterval       = 300;
int  g_iTimezone       = 8;
char g_sReloadCmd[160] = "sm plugins reload NekoServerName";

char g_sTargetPath[PLATFORM_MAX_PATH];
char g_sConfigPath[PLATFORM_MAX_PATH];

public void OnPluginStart()
{
	BuildPath(Path_SM, g_sTargetPath, sizeof(g_sTargetPath), "data/nekocustom.cfg");
	BuildPath(Path_SM, g_sConfigPath, sizeof(g_sConfigPath), "configs/NekoServerNameRotator.cfg");

	RegAdminCmd("sm_rotatename",        Cmd_Status,    ADMFLAG_ROOT, "查看服务器名字轮换状态");
	RegAdminCmd("sm_rotatename_next",   Cmd_Next,      ADMFLAG_ROOT, "立即轮换一次");
	RegAdminCmd("sm_rotatename_set",    Cmd_Set,       ADMFLAG_ROOT, "立即应用指定编号配置");
	RegAdminCmd("sm_rotatename_mode",   Cmd_Mode,      ADMFLAG_ROOT, "切换轮换模式 time/order/random");
	RegAdminCmd("sm_rotatename_reload", Cmd_CfgReload, ADMFLAG_ROOT, "重读轮换插件配置");

	LoadConfig();

	CreateTimer(TICK_SECONDS, Timer_Tick, _, TIMER_REPEAT);
}

public void OnConfigsExecuted()
{
	// 插件加载后首次激活; 之后的换图不再重复动作 (nekocustom.cfg 已是目标内容)
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
	if (g_iPoolCount == 0)
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
		ApplyIndex((g_iCurrentIndex + 1) % g_iPoolCount, true);
}

void ApplyIndex(int idx, bool force)
{
	if (idx < 0 || idx >= g_iPoolCount)
		return;
	if (!force && idx == g_iCurrentIndex)
		return;

	if (!FileExists(g_sPoolFiles[idx]))
	{
		LogError("[NameRotator] pool file missing: %s", g_sPoolBase[idx]);
		return;
	}
	if (FileSize(g_sPoolFiles[idx]) > MAX_CFG_BYTES)
	{
		LogError("[NameRotator] pool file too large (>%d bytes): %s", MAX_CFG_BYTES, g_sPoolBase[idx]);
		return;
	}
	if (!CopyFileText(g_sPoolFiles[idx], g_sTargetPath))
	{
		LogError("[NameRotator] copy failed: %s -> nekocustom.cfg", g_sPoolBase[idx]);
		return;
	}

	g_iCurrentIndex = idx;
	ServerCommand("%s", g_sReloadCmd);

	PrintToServer("[NameRotator] applied %s (%s, mode:%s)", g_sPoolBase[idx], g_sPeriodLabels[idx], g_sMode);
	LogMessage("applied %s (%s, mode:%s)", g_sPoolBase[idx], g_sPeriodLabels[idx], g_sMode);
}

int GetPeriodIndexForNow()
{
	int hour = GetLocalHour();
	int best = -1;
	for (int i = 0; i < g_iPoolCount; i++)
	{
		if (g_iPeriodStart[i] <= hour)
			best = i;
		else
			break;
	}
	if (best == -1)
		best = g_iPoolCount - 1; // 跨午夜回绕到最晚时段

	return best;
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
	if (g_iPoolCount <= 1)
		return 0;

	int idx = GetRandomInt(0, g_iPoolCount - 1);
	if (idx == avoid)
		idx = (idx + GetRandomInt(1, g_iPoolCount - 1)) % g_iPoolCount;

	return idx;
}

// ================= 配置 =================

void LoadConfig()
{
	g_iPoolCount     = 0;
	g_iCurrentIndex  = -1;
	g_iLastSwitch    = GetTime();

	if (!FileExists(g_sConfigPath))
		WriteDefaultConfig(g_sConfigPath);

	if (!ParseConfigFromFile())
	{
		// 配置损坏或没有有效池条目: 重新生成默认配置并再读一次
		PrintToServer("[NameRotator] config invalid or no pool entries, regenerating default: configs/NekoServerNameRotator.cfg");
		LogMessage("config invalid, regenerating default config");
		WriteDefaultConfig(g_sConfigPath);
		ParseConfigFromFile();
	}

	// 按起始小时升序排序 (保证 GetPeriodIndexForNow 的回绕逻辑正确)
	for (int i = 1; i < g_iPoolCount; i++)
	{
		int key = g_iPeriodStart[i];
		char kpath[PLATFORM_MAX_PATH], kbase[64], klabel[64];
		strcopy(kpath, PLATFORM_MAX_PATH, g_sPoolFiles[i]);
		strcopy(kbase, 64, g_sPoolBase[i]);
		strcopy(klabel, 64, g_sPeriodLabels[i]);

		int j = i - 1;
		while (j >= 0 && g_iPeriodStart[j] > key)
		{
			g_iPeriodStart[j + 1] = g_iPeriodStart[j];
			strcopy(g_sPoolFiles[j + 1], PLATFORM_MAX_PATH, g_sPoolFiles[j]);
			strcopy(g_sPoolBase[j + 1], 64, g_sPoolBase[j]);
			strcopy(g_sPeriodLabels[j + 1], 64, g_sPeriodLabels[j]);
			j--;
		}
		g_iPeriodStart[j + 1] = key;
		strcopy(g_sPoolFiles[j + 1], PLATFORM_MAX_PATH, kpath);
		strcopy(g_sPoolBase[j + 1], 64, kbase);
		strcopy(g_sPeriodLabels[j + 1], 64, klabel);
	}

	// 缺失的池文件: 用当前 nekocustom.cfg 复制兜底生成, 避免空转 (内容请自行编辑)
	for (int i = 0; i < g_iPoolCount; i++)
	{
		if (!FileExists(g_sPoolFiles[i]))
		{
			if (FileExists(g_sTargetPath) && CopyFileText(g_sTargetPath, g_sPoolFiles[i]))
			{
				PrintToServer("[NameRotator] pool file missing, created from nekocustom.cfg: %s (please edit it)", g_sPoolBase[i]);
				LogMessage("created missing pool file %s from nekocustom.cfg", g_sPoolBase[i]);
			}
			else
			{
				LogError("[NameRotator] pool file missing: %s", g_sPoolBase[i]);
			}
		}
	}
}

void WriteDefaultConfig(const char[] path)
{
	File f = OpenFile(path, "w");
	if (f == null)
	{
		LogError("[NameRotator] cannot write default config: %s", path);
		return;
	}

	f.WriteLine("\"NekoServerNameRotator\"");
	f.WriteLine("{");
	f.WriteLine("\t\"Settings\"");
	f.WriteLine("\t{");
	f.WriteLine("\t\t\"mode\"\t\t\"time\"");
	f.WriteLine("\t\t\"interval\"\t\"300\"");
	f.WriteLine("\t\t\"timezone\"\t\"8\"");
	f.WriteLine("\t\t\"reloadcmd\"\t\"sm plugins reload NekoServerName\"");
	f.WriteLine("\t}");
	f.WriteLine("\t\"TimePeriods\"");
	f.WriteLine("\t{");
	f.WriteLine("\t\t\"凌晨\"\t{ \"start\" \"0\"\t\"file\" \"nekocustom_01.cfg\" }");
	f.WriteLine("\t\t\"早上\"\t{ \"start\" \"6\"\t\"file\" \"nekocustom_02.cfg\" }");
	f.WriteLine("\t\t\"下午\"\t{ \"start\" \"12\"\t\"file\" \"nekocustom_03.cfg\" }");
	f.WriteLine("\t\t\"夜晚\"\t{ \"start\" \"18\"\t\"file\" \"nekocustom_04.cfg\" }");
	f.WriteLine("\t\t\"深夜\"\t{ \"start\" \"22\"\t\"file\" \"nekocustom_05.cfg\" }");
	f.WriteLine("\t}");
	f.WriteLine("}");
	delete f;
}

void PersistMode(const char[] newMode)
{
	// 用内存中的完整状态整文件重写配置, 不用 KV ExportToFile (它只从当前位置导出, 会丢掉其它配置节)
	File f = OpenFile(g_sConfigPath, "w");
	if (f == null)
	{
		LogError("[NameRotator] cannot write config: %s", g_sConfigPath);
		return;
	}

	f.WriteLine("\"NekoServerNameRotator\"");
	f.WriteLine("{");
	f.WriteLine("\t\"Settings\"");
	f.WriteLine("\t{");
	f.WriteLine("\t\t\"mode\"\t\t\"%s\"", newMode);
	f.WriteLine("\t\t\"interval\"\t\"%d\"", g_iInterval);
	f.WriteLine("\t\t\"timezone\"\t\"%d\"", g_iTimezone);
	f.WriteLine("\t\t\"reloadcmd\"\t\"%s\"", g_sReloadCmd);
	f.WriteLine("\t}");
	f.WriteLine("\t\"TimePeriods\"");
	f.WriteLine("\t{");
	for (int i = 0; i < g_iPoolCount; i++)
	{
		f.WriteLine("\t\t\"%s\"\t{ \"start\" \"%d\"\t\"file\" \"%s\" }", g_sPeriodLabels[i], g_iPeriodStart[i], g_sPoolBase[i]);
	}
	f.WriteLine("\t}");
	f.WriteLine("}");
	delete f;
}

bool ParseConfigFromFile()
{
	KeyValues kv = new KeyValues("NekoServerNameRotator");
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
		kv.GetString("reloadcmd", g_sReloadCmd, sizeof(g_sReloadCmd), "sm plugins reload NekoServerName");

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
			char label[64], file[PLATFORM_MAX_PATH], full[PLATFORM_MAX_PATH];
			kv.GetSectionName(label, sizeof(label));
			kv.GetString("file", file, sizeof(file), "");
			int start = kv.GetNum("start", -1);

			if (file[0] == 0 || start < 0 || start > 23 || g_iPoolCount >= MAX_POOL)
				continue;

			BuildPath(Path_SM, full, sizeof(full), "data/%s", file);
			strcopy(g_sPoolFiles[g_iPoolCount], PLATFORM_MAX_PATH, full);
			strcopy(g_sPoolBase[g_iPoolCount], 64, file);
			strcopy(g_sPeriodLabels[g_iPoolCount], 64, label);
			g_iPeriodStart[g_iPoolCount] = start;
			g_iPoolCount++;
		} while (kv.GotoNextKey(false));
	}
	delete kv;

	return g_iPoolCount > 0;
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

	char line[2048];
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

// ================= 命令 =================

public Action Cmd_Status(int client, int args)
{
	char cur[64];
	if (g_iCurrentIndex >= 0)
		strcopy(cur, sizeof(cur), g_sPoolBase[g_iCurrentIndex]);
	else
		strcopy(cur, sizeof(cur), "(none)");

	ReplyToCommand(client, "[NameRotator] mode:%s interval:%ds timezone:UTC+%d current:%s", g_sMode, g_iInterval, g_iTimezone, cur);

	for (int i = 0; i < g_iPoolCount; i++)
	{
		char mark[16];
		if (i == g_iCurrentIndex)
			strcopy(mark, sizeof(mark), "  <- now");
		else
			mark[0] = 0;

		ReplyToCommand(client, "[NameRotator]   #%d %s (start %d:00, %s)%s", i + 1, g_sPoolBase[i], g_iPeriodStart[i], g_sPeriodLabels[i], mark);
	}

	return Plugin_Handled;
}

public Action Cmd_Next(int client, int args)
{
	if (g_iPoolCount == 0)
	{
		ReplyToCommand(client, "[NameRotator] no pool files configured");
		return Plugin_Handled;
	}

	if (StrEqual(g_sMode, "time", false))
	{
		// time 模式: 立即重新应用当前时段 (编辑过 XX 文件后用它立即生效)
		ApplyIndex(GetPeriodIndexForNow(), true);
	}
	else
	{
		g_iLastSwitch = GetTime();
		if (StrEqual(g_sMode, "random", false))
			ApplyIndex(RandomExcept(g_iCurrentIndex), true);
		else
			ApplyIndex((g_iCurrentIndex + 1) % g_iPoolCount, true);
	}

	ReplyToCommand(client, "[NameRotator] done, see server console");
	return Plugin_Handled;
}

public Action Cmd_Set(int client, int args)
{
	if (g_iPoolCount == 0)
	{
		ReplyToCommand(client, "[NameRotator] no pool files configured");
		return Plugin_Handled;
	}
	if (args < 1)
	{
		ReplyToCommand(client, "[NameRotator] usage: sm_rotatename_set <1-%d>", g_iPoolCount);
		return Plugin_Handled;
	}

	char arg[16];
	GetCmdArg(1, arg, sizeof(arg));
	int n = StringToInt(arg);

	if (n < 1 || n > g_iPoolCount)
	{
		ReplyToCommand(client, "[NameRotator] invalid index: %s (range 1-%d)", arg, g_iPoolCount);
		return Plugin_Handled;
	}

	ApplyIndex(n - 1, true);
	ReplyToCommand(client, "[NameRotator] applied #%d (%s)", n, g_sPoolBase[n - 1]);
	return Plugin_Handled;
}

public Action Cmd_Mode(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[NameRotator] usage: sm_rotatename_mode <time|order|random>  current:%s", g_sMode);
		return Plugin_Handled;
	}
	if (g_iPoolCount == 0)
	{
		ReplyToCommand(client, "[NameRotator] no pool files configured");
		return Plugin_Handled;
	}

	char arg[16];
	GetCmdArg(1, arg, sizeof(arg));
	if (!StrEqual(arg, "time", false) && !StrEqual(arg, "order", false) && !StrEqual(arg, "random", false))
	{
		ReplyToCommand(client, "[NameRotator] unknown mode: %s (use time|order|random)", arg);
		return Plugin_Handled;
	}

	strcopy(g_sMode, sizeof(g_sMode), arg);
	PersistMode(g_sMode);

	ReplyToCommand(client, "[NameRotator] mode set to %s (saved to config)", g_sMode);
	LogMessage("mode changed to %s", g_sMode);

	g_iLastSwitch = GetTime();
	Tick(true);
	return Plugin_Handled;
}

public Action Cmd_CfgReload(int client, int args)
{
	LoadConfig();
	Tick(true);
	ReplyToCommand(client, "[NameRotator] config reloaded (mode:%s, pool:%d files)", g_sMode, g_iPoolCount);
	return Plugin_Handled;
}
