#pragma semicolon 1
#pragma tabsize 0

#include <sourcemod>
#include <sdktools>
#include <estore/estore-commons>

#if !defined REQUIRE_PLUGIN
	#define REQUIRE_PLUGIN
#endif
#include <estore/estore-core>
#include <estore/estore-backend>
#include <estore/estore-logging>

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("estore-admin");
	return APLRes_Success;
}

public Plugin:myinfo =
{
	name = "[ES] Admin",
	author = ESTORE_AUTHOR,
	description = "Admin component for [ES]",
	version = ESTORE_VERSION,
	url = ESTORE_URL
};

new String:g_sCurrencyName[64];
new bool:g_bActionLogging = true;


public OnPluginStart()
{
	PrintToServer("[ES] ADMIN COMPONENT LOADED.");

	LoadConfig();

	LoadTranslations("common.phrases");
	LoadTranslations("estore.admin.phrases");

	RegAdminCmd("es_givecredits", Command_GiveCredits, ADMFLAG_ROOT, "Gives credits to a player.", "sm_estore", 0);
	RegAdminCmd("es_setgroup", Command_SetGroup, ADMFLAG_ROOT, "Set the group of a player.", "sm_estore", 0);
}

public OnAllPluginsLoaded()
{
    EStore_GetCurrencyName(g_sCurrencyName, sizeof(g_sCurrencyName));
}

LoadConfig()
{
	new Handle:kv = CreateKeyValues("root");

	decl String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/estore/estore_admin.cfg");

	if (!FileToKeyValues(kv, path))
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	g_bActionLogging = bool:KvGetNum(kv, "action_logging", 1);

	CloseHandle(kv);
}

public Action:Command_GiveCredits(client, args)
{
	if (args != 2)
	{
		ReplyToCommand(client, "%s%t", ESTORE_PREFIX, "give_credits_command");
		return Plugin_Handled;
	}

	decl String:name[32];
	GetClientName(client, name, sizeof(name));

	decl String:target[65];
	GetCmdArg(1, target, sizeof(target));

	new String:credits[32];
	GetCmdArg(2, credits, sizeof(credits));
	new icredits = StringToInt(credits);
	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS];
	decl target_count;
	decl bool:tn_is_ml;

	if ((target_count = ProcessTargetString(
			target,
			0,
			target_list,
			MAXPLAYERS,
			0,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for (new i = 0; i < target_count; i++)
	{
		if (IsValidClient(target_list[i]))
		{
			if(g_bActionLogging)
			{
				EStore_LogInfo("'%s' gives %d %s to user '%s'", name, icredits, g_sCurrencyName, target_name[i]);
			}
			EStore_GiveCreditsToUser(GetSteamAccountID(target_list[i]), icredits);
			CPrintToChat(target_list[i], "%s%t", ESTORE_PREFIX, "credits_receive_from", icredits, g_sCurrencyName, name);
		}
	}

	return Plugin_Handled;
}

public Action:Command_SetGroup(client, args)
{
	if (args != 2)
	{
		ReplyToCommand(client, "%s%t", ESTORE_PREFIX, "set_group_command");
		return Plugin_Handled;
	}

	decl String:name[32];
	GetClientName(client, name, sizeof(name));

	decl String:target[65];
	GetCmdArg(1, target, sizeof(target));

	decl String:group_name[34];
	GetCmdArg(2, group_name, sizeof(group_name));
	StripQuotes(group_name);

	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS];
	decl target_count;
	decl bool:tn_is_ml;

	if ((target_count = ProcessTargetString(
			target,
			0,
			target_list,
			MAXPLAYERS,
			0,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for (new i = 0; i < target_count; i++)
	{
		if (IsValidClient(target_list[i]))
		{
            EStore_SetUserGroup(client, target_list[i], group_name, SetUserGroupCallback);
		}
	}
	return Plugin_Handled;
}

public SetUserGroupCallback(error, admin, client, const String:group_name[34])
{
	switch(error)
	{
		case 0:
		{
			decl String:name[32];
			GetClientName(admin, name, sizeof(name));
			if (g_bActionLogging)
		    {
		        EStore_LogInfo("'%s' changed the user group from %d to '%s'", name, GetSteamAccountID(client), group_name);
		    }
			CPrintToChat(client, "%s%t", ESTORE_PREFIX, "set_group", name, group_name);
		}
		case 1:
		{
			ReplyToCommand(admin, "%s%t", ESTORE_PREFIX, "set_group_error", group_name);
		}
		case 2:
		{
			ReplyToCommand(admin, "%s%t", ESTORE_PREFIX, "set_group_error_no_change", group_name);
		}
	}
}
