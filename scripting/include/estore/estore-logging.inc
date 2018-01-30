#if defined _estore_logging_included
#endinput
#endif
#define _estore_logging_included

enum EStore_LogLevel
{
	EStore_LogLevelNone = 0,
	EStore_LogLevelInfo = 1,
	EStore_LogLevelWarning = 4,
    EStore_LogLevelError = 8,
	EStore_LogLevelDebug = 16,
	EStore_LogLevelTrace = 32
};

native EStore_LogInfo(const String:format[], any:...);
native EStore_LogWarning(const String:format[], any:...);
native EStore_LogError(const String:format[], any:...);
native EStore_LogDebug(const String:format[], any:...);
native EStore_LogTrace(const String:format[], any:...);

public SharedPlugin:__pl_estore_logging =
{
	name = "estore-logging",
	file = "estore-logging.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_estore_logging_SetNTVOptional()
{
    MarkNativeAsOptional("EStore_LogInfo");
	MarkNativeAsOptional("EStore_LogWarning");
	MarkNativeAsOptional("EStore_LogError");
    MarkNativeAsOptional("EStore_LogDebug");
    MarkNativeAsOptional("EStore_LogTrace");
}
#endif
