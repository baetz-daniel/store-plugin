#pragma semicolon 1
#pragma dynamic 131072
#pragma tabsize 0

#include <sourcemod>
#include <sdktools>
#include <estore/estore-commons>

#include <estore/estore-core>
#if !defined REQUIRE_PLUGIN
	#define REQUIRE_PLUGIN
#endif
#include <estore/estore-backend>
#include <estore/estore-logging>


public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("EStore_GetClientGroup", Native_GetClientGroup);
	CreateNative("EStore_GetCurrencyName", Native_GetCurrencyName);

	CreateNative("EStore_AddMainMenuItem", Native_AddMainMenuItem);

	RegPluginLibrary("estore-core");
	return APLRes_Success;
}

public Plugin:myinfo =
{
	name = "[ES] Core",
	author = ESTORE_AUTHOR,
	description = "Core component for [ES]",
	version = ESTORE_VERSION,
	url = ESTORE_URL
};

enum ClientGroupInfo
{
	GroupIndex,
    String:GroupName[ESTORE_MAX_NAME_LENGTH],
	GroupFlag
};

new g_aClientGroupInfo[MAXPLAYERS + 1][ClientGroupInfo];

enum MenuItem
{
	String:MenuItemDisplayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT],
	String:MenuItemValue[ESTORE_MAX_MENUITEM_VALUE_LENGHT],
	Handle:MenuItemPlugin,
	EStore_MenuItemPressedCallback:MenuItemCallback,
	MenuItemOrder
};

new g_aMenuItems[ESTORE_MAX_MENU_ITEMS + 1][MenuItem];
new g_iMenuItemCount = 0;

new bool:g_bEnableMessagePerDistribute;
new String:g_sCurrencyName[64];

new g_iMenuCommandCount;
new String:g_aMenuCommands[6][32];

new g_iCreditsCommandCount;
new String:g_aCreditsCommands[6][32];

new g_iVipBuyCommandCount;
new String:g_aVipBuyCommands[6][32];

new String:g_sVipBuyLink[255];

new g_iCreditsOnFirstConnection = 0;
new Float:g_fCreditsTimer = 120.0;

new g_aCreditsGroupIndices[ESTORE_MAX_GROUPS] = {-1, ...};
new g_aCreditsPerTime[ESTORE_MAX_GROUPS];
new g_aCreditsDailyBonus[ESTORE_MAX_GROUPS];

new bool:g_bAllPluginsLoaded = false;

new Handle:g_hCreditsTimer;

public OnPluginStart()
{
	PrintToServer("[ES] CORE COMPONENT LOADED.");

	CreateConVar("es_version", ESTORE_VERSION, "Encoded Store Version", FCVAR_REPLICATED|FCVAR_NOTIFY);
	LoadConfig();

	LoadTranslations("common.phrases");
	LoadTranslations("estore.core.phrases");
	LoadTranslations("estore.mainmenu.phrases");

	AddCommandListener(CmdSayCallback, "say");
	AddCommandListener(CmdSayCallback, "say_team");

	g_bAllPluginsLoaded = false;
}

public OnPluginEnd()
{
	CleanUp();
}

public OnAllPluginsLoaded()
{
	SortMainMenuItems();
	g_bAllPluginsLoaded = true;
}

public OnMapStart()
{
	g_hCreditsTimer = CreateTimer(g_fCreditsTimer, Credits_TimerCallback, _, TIMER_REPEAT);
}

public OnMapEnd()
{
	CleanUp();
}

public OnClientPostAdminCheck(client)
{
	if(IsFakeClient(client))
	{
		return;
	}
	EStore_RegisterUser(client, g_iCreditsOnFirstConnection);
	EStore_CheckDailyLogin(client, CheckDailyLoginCallback);
}

public OnClientDisconnect(client)
{
	if(IsFakeClient(client))
	{
		return;
	}
	g_aClientGroupInfo[client][GroupIndex] = 0;
	strcopy(g_aClientGroupInfo[client][GroupName], ESTORE_MAX_NAME_LENGTH, "");
	g_aClientGroupInfo[client][GroupFlag] = 0;
}

CleanUp()
{
	if(g_hCreditsTimer != INVALID_HANDLE)
	{
		KillTimer(g_hCreditsTimer);
		g_hCreditsTimer = INVALID_HANDLE;
	}
}

LoadConfig()
{
	new Handle:kv = CreateKeyValues("root");

	decl String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/estore/estore_core.cfg");

	if (!FileToKeyValues(kv, path))
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	decl String:menuCommands[6 * 33];
	KvGetString(kv, "mainmenu_commands", menuCommands, sizeof(menuCommands), "!estore /estore");
	g_iMenuCommandCount = ExplodeString(menuCommands, " ", g_aMenuCommands, sizeof(g_aMenuCommands), sizeof(g_aMenuCommands[]));

	decl String:creditsCommands[6 * 33];
	KvGetString(kv, "credits_commands", creditsCommands, sizeof(creditsCommands), "!credits /credits");
	g_iCreditsCommandCount = ExplodeString(creditsCommands, " ", g_aCreditsCommands, sizeof(g_aCreditsCommands), sizeof(g_aCreditsCommands[]));

	decl String:vipBuyCommands[6 * 33];
	KvGetString(kv, "vip_buy_commands", vipBuyCommands, sizeof(vipBuyCommands), "!vip /vip");
	g_iVipBuyCommandCount = ExplodeString(vipBuyCommands, " ", g_aVipBuyCommands, sizeof(g_aVipBuyCommands), sizeof(g_aVipBuyCommands[]));

	KvGetString(kv, "vip_buy_link", g_sVipBuyLink, sizeof(g_sVipBuyLink));
	KvGetString(kv, "currency_name", g_sCurrencyName, sizeof(g_sCurrencyName), "Credits");

	g_iCreditsOnFirstConnection = KvGetNum(kv, "credits_on_first_connection", 10);
	g_fCreditsTimer = KvGetFloat(kv, "credits_timer", 120.0);

	decl String:creditsGroupIndices[ESTORE_MAX_GROUPS * 3];
	KvGetString(kv, "credits_group_indices", creditsGroupIndices, sizeof(creditsGroupIndices), "0 1 2");
	decl String:creditsGroupIndicesE[ESTORE_MAX_GROUPS][2];
	new creditsGroupIndicesCount = ExplodeString(creditsGroupIndices, " ", creditsGroupIndicesE, sizeof(creditsGroupIndicesE), sizeof(creditsGroupIndicesE[]));

	for(new i = 0; i < creditsGroupIndicesCount; i++)
	{
		new index = StringToInt(creditsGroupIndicesE[i]);
		g_aCreditsGroupIndices[index] = i;
	}

	decl String:creditsPerTime[ESTORE_MAX_GROUPS * ESTORE_MAX_CREDIT_INT_LENGTH];
	KvGetString(kv, "credits_per_time", creditsPerTime, sizeof(creditsPerTime), "2 4 2");
	decl String:creditsPerTimeE[ESTORE_MAX_GROUPS][ESTORE_MAX_CREDIT_INT_LENGTH];
	new creditsPerTimeCount = ExplodeString(creditsPerTime, " ", creditsPerTimeE, sizeof(creditsPerTimeE), sizeof(creditsPerTimeE[]));

	if(creditsPerTimeCount != creditsGroupIndicesCount)
	{
		SetFailState("config file error credits_per_time does not match credits_per_time_group_indices");
	}

	for(new i = 0; i < creditsPerTimeCount; i++)
	{
		g_aCreditsPerTime[i] = StringToInt(creditsPerTimeE[i]);
	}

	decl String:creditsDailyBonus[ESTORE_MAX_GROUPS * ESTORE_MAX_CREDIT_INT_LENGTH];
	KvGetString(kv, "credits_daily_bonus", creditsDailyBonus, sizeof(creditsDailyBonus),"5 10 5");

	decl String:creditsDailyBonusE[ESTORE_MAX_GROUPS][ESTORE_MAX_CREDIT_INT_LENGTH];
	new creditsDailyBonusCount = ExplodeString(creditsDailyBonus, " ", creditsDailyBonusE, sizeof(creditsDailyBonusE), sizeof(creditsDailyBonusE[]));

	if(creditsDailyBonusCount != creditsGroupIndicesCount)
	{
		SetFailState("config file error credits_daily_bonus does not match credits_per_time_group_indices");
	}

	for(new i = 0; i < creditsDailyBonusCount; i++)
	{
		g_aCreditsDailyBonus[i] = StringToInt(creditsDailyBonusE[i]);
	}

	g_bEnableMessagePerDistribute = bool:KvGetNum(kv, "enable_message_per_distribute", 1);

	CloseHandle(kv);
}

public Action:Credits_TimerCallback(Handle:timer)
{
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client) && !IsClientObserver(client))
		{
			EStore_GetUserInfo(client, ReceiveCreditsCallback);
		}
	}
	return Plugin_Handled;
}

public ReceiveCreditsCallback(client, credits, erg_index, const String:erg_name[ESTORE_MAX_NAME_LENGTH], erg_flag, any:data)
{
	new groupOffset = g_aCreditsGroupIndices[erg_index];
	if(groupOffset == -1)
	{
		return;
	}
	new receiveCredits = g_aCreditsPerTime[groupOffset];

	if (g_bEnableMessagePerDistribute)
	{
		CPrintToChat(client, "%s%t", ESTORE_PREFIX, "credits_receive", receiveCredits, g_sCurrencyName);
	}

	EStore_GiveCreditsToUser(GetSteamAccountID(client), receiveCredits);
}

CheckDailyLoginCallback(client, bool:dailyBonus, credits, erg_index, const String:erg_name[ESTORE_MAX_NAME_LENGTH], erg_flag)
{
	g_aClientGroupInfo[client][GroupIndex] = erg_index;
	strcopy(g_aClientGroupInfo[client][GroupName], ESTORE_MAX_NAME_LENGTH, erg_name);
	g_aClientGroupInfo[client][GroupFlag] = erg_flag;

	decl String:name[32];
	GetClientName(client, name, sizeof(name));
	CPrintToChat(client, "%s%t", ESTORE_PREFIX, "welcome", name);
	if(dailyBonus)
	{
		new groupOffset = g_aCreditsGroupIndices[erg_index];
		new receiveDailyCredits = g_aCreditsDailyBonus[groupOffset];
		credits = credits + receiveDailyCredits;
		CPrintToChat(client, "%s%t", ESTORE_PREFIX, "credits_receive_daily", receiveDailyCredits, g_sCurrencyName);

		EStore_GiveCreditsToUser(GetSteamAccountID(client), receiveDailyCredits);
	}
	CPrintToChat(client, "%s%t", ESTORE_PREFIX, "credits", credits, g_sCurrencyName);
}

public EStore_OnSetUserGroup_Post(client)
{
	EStore_GetUserInfo(client, OnSetUserGroup_PostCallback);
}

public OnSetUserGroup_PostCallback(client, credits, erg_index, const String:erg_name[ESTORE_MAX_NAME_LENGTH], erg_flag, any:data)
{
	g_aClientGroupInfo[client][GroupIndex] = erg_index;
	strcopy(g_aClientGroupInfo[client][GroupName], ESTORE_MAX_NAME_LENGTH, erg_name);
	g_aClientGroupInfo[client][GroupFlag] = erg_flag;
}

public Action:CmdSayCallback(client, const String:command[], argc)
{
	if (0 < client <= MaxClients && !IsClientInGame(client))
	{
		return Plugin_Handled;
	}

	decl String:text[34];
	GetCmdArgString(text, sizeof(text));
	StripQuotes(text);

	for (new i = 0; i < g_iMenuCommandCount; i++)
	{
		if (StrEqual(g_aMenuCommands[i], text))
		{
			OpenMainMenu(client);
			return Plugin_Handled;
		}
	}
	for (new i = 0; i < g_iCreditsCommandCount; i++)
	{
		if (StrEqual(g_aCreditsCommands[i], text))
		{
			EStore_GetUserInfo(client, GetUserInfoCallback);
			return Plugin_Handled;
		}
	}

	for (new i = 0; i < g_iVipBuyCommandCount; i++)
	{
		if (StrEqual(g_aVipBuyCommands[i], text))
		{
			//VIP BUY LINK CHAT!?
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public GetUserInfoCallback(client, credits, erg_index, const String:erg_name[ESTORE_MAX_NAME_LENGTH], erg_flag, any:data)
{
	CPrintToChat(client, "%s%t", ESTORE_PREFIX, "credits", credits, g_sCurrencyName);
}

public Native_GetClientGroup(Handle:plugin, num_params)
{
	new client = GetNativeCell(1);
	SetNativeCellRef(2, g_aClientGroupInfo[client][GroupIndex]);
	SetNativeString(3, g_aClientGroupInfo[client][GroupName], GetNativeCell(4));
}

public Native_GetCurrencyName(Handle:plugin, num_params)
{
	SetNativeString(1, g_sCurrencyName, GetNativeCell(2));
}

OpenMainMenu(client)
{
	EStore_GetUserInfo(client, OpenMainMenuCallback);
}

public OpenMainMenuCallback(client, credits, erg_index, const String:erg_name[ESTORE_MAX_NAME_LENGTH], erg_flag, any:data)
{
	new Handle:menu = CreateMenu(MainMenuSelectHandleCallback);
	SetMenuTitle(menu, "%t", "menu_title", credits, g_sCurrencyName);
	SetMenuPagination(menu, 3);
	for (new i = 0; i < g_iMenuItemCount; i++)
	{
		// mmi_DISPLAYNAME
		decl String:tDisplayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
		Format(tDisplayName, sizeof(tDisplayName), "mmi_%s", g_aMenuItems[i][MenuItemDisplayName]);

		// mmi_DISPLAYNAME_desc
		decl String:tDescription[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
		Format(tDescription, sizeof(tDescription), "mmi_%s_desc", g_aMenuItems[i][MenuItemDisplayName]);

		decl String:text[255];
		Format(text, sizeof(text), "%t\n  - %t", tDisplayName, tDescription);

		AddMenuItem(menu, g_aMenuItems[i][MenuItemValue], text, ITEMDRAW_DEFAULT);
	}

	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 0);
}

MainMenuSelectHandleCallback(Handle:menu, MenuAction:action, client, item)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			Call_StartFunction(g_aMenuItems[item][MenuItemPlugin], g_aMenuItems[item][MenuItemCallback]);
			Call_PushCell(client);
			Call_PushString(g_aMenuItems[item][MenuItemValue]);
			Call_Finish();
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Native_AddMainMenuItem(Handle:plugin, params)
{
	decl String:displayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
	GetNativeString(1, displayName, sizeof(displayName));

	decl String:value[ESTORE_MAX_MENUITEM_VALUE_LENGHT];
	GetNativeString(2, value, sizeof(value));

	AddMainMenuItem(displayName, value, plugin, EStore_MenuItemPressedCallback:GetNativeFunction(3), GetNativeCell(4));
}

AddMainMenuItem(const String:displayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT], const String:value[ESTORE_MAX_MENUITEM_VALUE_LENGHT] = "", Handle:plugin = INVALID_HANDLE, EStore_MenuItemPressedCallback:callback, order = 32)
{
	new item = 0;
	for (; item <= g_iMenuItemCount; item++)
	{
		if (item == g_iMenuItemCount || StrEqual(g_aMenuItems[item][MenuItemDisplayName], displayName))
		{
			break;
		}
	}

	strcopy(g_aMenuItems[item][MenuItemDisplayName], ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT, displayName);
	strcopy(g_aMenuItems[item][MenuItemValue], ESTORE_MAX_MENUITEM_VALUE_LENGHT, value);
	g_aMenuItems[item][MenuItemPlugin] = plugin;
	g_aMenuItems[item][MenuItemCallback] = callback;
	g_aMenuItems[item][MenuItemOrder] = order;

	if (item == g_iMenuItemCount)
	{
		g_iMenuItemCount++;
	}

	if (g_bAllPluginsLoaded)
	{
		SortMainMenuItems();
	}
}

SortMainMenuItems()
{
	new sortIndex = sizeof(g_aMenuItems) - 1;

	for (new x = 0; x < g_iMenuItemCount; x++)
	{
		for (new y = 0; y < g_iMenuItemCount; y++)
		{
			if (g_aMenuItems[x][MenuItemOrder] < g_aMenuItems[y][MenuItemOrder])
			{
				g_aMenuItems[sortIndex] = g_aMenuItems[x];
				g_aMenuItems[x] = g_aMenuItems[y];
				g_aMenuItems[y] = g_aMenuItems[sortIndex];
			}
		}
	}
}
