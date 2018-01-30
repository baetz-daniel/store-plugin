#pragma semicolon 1
#pragma tabsize 0

#include <estore/estore-core>
#include <estore/estore-logging>

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("EStore_LogInfo", Native_LogInfo);
	CreateNative("EStore_LogWarning", Native_LogWarning);
	CreateNative("EStore_LogError", Native_LogError);
	CreateNative("EStore_LogDebug", Native_LogDebug);
	CreateNative("EStore_LogTrace", Native_LogTrace);

	RegPluginLibrary("estore-logging");

	return APLRes_Success;
}

public Plugin:myinfo =
{
	name = "[ES] Logging",
	author = ESTORE_AUTHOR,
	description = "Logging component for [ES]",
	version = ESTORE_VERSION,
	url = ESTORE_URL
};

static Handle:g_hLogFile = INVALID_HANDLE;

static Float:g_fLogDateCheckTime = 20.0;
static g_iLogLevel = _:EStore_LogLevelNone;
static g_iLogFlushLevel = _:EStore_LogLevelNone;
static Float:g_fLogFlushTime = 10.0;
static String:g_sCurrentDate[20];

public OnPluginStart()
{
	PrintToServer("[ES] LOGGING COMPONENT LOADED.");

	LoadConfig();

	if (g_iLogLevel > _:EStore_LogLevelNone)
	{
		FormatTime(g_sCurrentDate, sizeof(g_sCurrentDate), "%Y-%m-%d", GetTime());
		CreateTimer(g_fLogDateCheckTime, OnCheckDate, INVALID_HANDLE, TIMER_REPEAT);
		CreateTimer(g_fLogFlushTime, OnFlushLogFile, INVALID_HANDLE, TIMER_REPEAT);
		CreateLogFile();
	}
}

public OnPluginEnd()
{
	if (g_hLogFile != INVALID_HANDLE)
	{
		CloseLogFile();
	}
}

LoadConfig()
{
	new Handle:kv = CreateKeyValues("root");

	decl String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/estore/estore_logging.cfg");

	if (!FileToKeyValues(kv, path))
    {
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	g_fLogDateCheckTime = KvGetFloat(kv, "log_date_check_time", 10.0);
	g_iLogLevel = KvGetNum(kv, "log_level", _:(EStore_LogLevelInfo | EStore_LogLevelWarning | EStore_LogLevelError));
	g_iLogFlushLevel = KvGetNum(kv, "log_flush_level", _:EStore_LogLevelError);
	g_fLogFlushTime = KvGetFloat(kv, "log_flush_time", 10.0);

	CloseHandle(kv);
}

public Action:OnCheckDate(Handle:timer)
{
	decl String:date[20];
	FormatTime(date, sizeof(date), "%Y-%m-%d", GetTime());

	if (g_iLogLevel > _:EStore_LogLevelNone && !StrEqual(date, g_sCurrentDate))
    {
		strcopy(g_sCurrentDate, sizeof(g_sCurrentDate), date);

		if (g_hLogFile != INVALID_HANDLE)
        {
			WriteMessage(INVALID_HANDLE, EStore_LogLevelInfo, "INFO", "Date changed; switching log file", true);
			CloseLogFile();
		}

		CreateLogFile();
	}
	return Plugin_Handled;
}

public Action:OnFlushLogFile(Handle:timer)
{
	if (g_hLogFile != INVALID_HANDLE)
	{
		FlushFile(g_hLogFile);
	}
	return Plugin_Handled;
}

CloseLogFile()
{
	WriteMessage(INVALID_HANDLE, EStore_LogLevelInfo,"INFO", "logging stopped...", true);
	CloseHandle(g_hLogFile);
	g_hLogFile = INVALID_HANDLE;
}

bool:CreateLogFile()
{
	decl String:filename[128];
	new pos = BuildPath(Path_SM, filename, sizeof(filename), "logs/");
	FormatTime(filename[pos], sizeof(filename)-pos, "estore_%Y-%m-%d.log", GetTime());

	if ((g_hLogFile = OpenFile(filename, "a")) == INVALID_HANDLE)
    {
		g_iLogLevel = _:EStore_LogLevelNone;
		LogError("Can't create estore log file");
		return false;
	}
	else
    {
		WriteMessage(INVALID_HANDLE, EStore_LogLevelInfo, "INFO", "logging started...", true);
		return true;
	}
}

bool:CheckFlag(flag, EStore_LogLevel:level){
    return flag & _:level == _:level;
}

public Native_LogInfo(Handle:plugin, num_params)
{
	if(g_hLogFile == INVALID_HANDLE)
	{
		return;
	}
	if (CheckFlag(g_iLogLevel, EStore_LogLevelInfo))
	{
		decl String:message[4096], written;
		FormatNativeString(0, 1, 2, sizeof(message), written, message);
		WriteMessage(plugin, EStore_LogLevelInfo, "INFO", message);
    }
}

public Native_LogWarning(Handle:plugin, num_params)
{
	if(g_hLogFile == INVALID_HANDLE)
	{
		return;
	}
	if (CheckFlag(g_iLogLevel, EStore_LogLevelWarning))
    {
		decl String:message[4096], written;
		FormatNativeString(0, 1, 2, sizeof(message), written, message);
		WriteMessage(plugin, EStore_LogLevelWarning, "WARN", message);
	}
}

public Native_LogError(Handle:plugin, num_params)
{
	if(g_hLogFile == INVALID_HANDLE)
	{
		return;
	}
	if (CheckFlag(g_iLogLevel, EStore_LogLevelError))
    {
		decl String:message[4096], written;
		FormatNativeString(0, 1, 2, sizeof(message), written, message);
		WriteMessage(plugin, EStore_LogLevelError, "ERROR", message);
	}
}

public Native_LogDebug(Handle:plugin, num_params)
{
	if(g_hLogFile == INVALID_HANDLE)
	{
		return;
	}
	if (CheckFlag(g_iLogLevel, EStore_LogLevelDebug))
    {
		decl String:message[4096], written;
		FormatNativeString(0, 1, 2, sizeof(message), written, message);
		WriteMessage(plugin, EStore_LogLevelDebug, "DEBUG", message);
	}
}

public Native_LogTrace(Handle:plugin, num_params)
{
	if(g_hLogFile == INVALID_HANDLE)
	{
		return;
	}
	if (CheckFlag(g_iLogLevel, EStore_LogLevelTrace))
    {
		decl String:message[4096], written;
		FormatNativeString(0, 1, 2, sizeof(message), written, message);
		WriteMessage(plugin, EStore_LogLevelTrace, "TRACE", message);
	}
}

WriteMessage(Handle:plugin, EStore_LogLevel:logLevel, const String:logLevelName[], const String:message[], bool:force_flush = false)
{
	decl String:line[4220];
	PrepareLine(plugin, logLevelName, message, line);
	WriteFileString(g_hLogFile, line, false);

	if (CheckFlag(g_iLogFlushLevel, logLevel) || force_flush)
    {
		FlushFile(g_hLogFile);
    }
}

PrepareLine(Handle:plugin, const String:logLevelName[], const String:message[], String:line[4220])
{
	decl String:pName[64];
	GetPluginFilename(plugin, pName, sizeof(pName));
	decl String:date[40];
	FormatTime(date, sizeof(date), "%Y-%m-%d %H:%M:%S", GetTime());
	Format(line, sizeof(line), "[%s] (%s) | %s - %s\r\n", date, pName, logLevelName, message);
}
