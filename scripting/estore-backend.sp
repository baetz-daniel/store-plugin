#pragma semicolon 1
#pragma tabsize 0

#if !defined REQUIRE_PLUGIN
	#define REQUIRE_PLUGIN
#endif
#include <estore/estore-core>
#include <estore/estore-logging>

#include <estore/estore-backend>

#define ESTORE_MAX_SQL_RECONNECTS	5

#define ESTORE_MAX_CATEGORIES	32
#define ESTORE_MAX_ITEMS		1024
#define ESTORE_MAX_LOADOUTS		8

new Handle:g_hdbInitializedForward;
new Handle:g_hOnSetUserGroup_PostForward;
new Handle:g_hPreCacheOrRealoadCategoriesFinishedForward;
new Handle:g_hPreCacheOrRealoadCategoriesStartForward;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("EStore_Register", Native_Register);
	CreateNative("EStore_RegisterUser", Native_RegisterUser);
	CreateNative("EStore_GetTop10Store", Native_GetTop10Store);

	CreateNative("EStore_GetUserInfo", Native_GetUserInfo);
	CreateNative("EStore_GiveCreditsToUser", Native_GiveCreditsToUser);
	CreateNative("EStore_TakeCreditsFromUser", Native_TakeCreditsFromUser);

	CreateNative("EStore_SetUserGroup", Native_SetUserGroup);

	CreateNative("EStore_CheckDailyLogin", Native_CheckDailyLogin);

	CreateNative("EStore_PreCacheCategoriesOrReload", Native_PreCacheCategoriesOrReload);
	CreateNative("EStore_GetCategoryIndices", Native_GetCategoryIndices);
	CreateNative("EStore_GetCategoryCount", Native_GetCategoryCount);
	CreateNative("EStore_GetCategoryInfo", Native_GetCategoryInfo);
	CreateNative("EStore_GetCategoryInfo2", Native_GetCategoryInfo2);

	CreateNative("EStore_GiveUserItem", Native_GiveUserItem);
	CreateNative("EStore_GetItemsInfo", Native_GetItemsInfo);	
	CreateNative("EStore_GetUserItemsOfCategory", Native_GetUserItemsOfCategory);
	CreateNative("EStore_GetItemData", Native_GetItemData);

	CreateNative("EStore_GetUserBankInfo", Native_GetUserBankInfo);
	CreateNative("EStore_DepositUserBankMoney", Native_DepositUserBankMoney);
	CreateNative("EStore_WithdrawUserBankMoney", Native_WithdrawUserBankMoney);
	CreateNative("EStore_GetTop10Bank", Native_GetTop10Bank);

	CreateNative("EStore_PrecacheAllItems", Native_PrecacheAllItems);

	g_hdbInitializedForward = CreateGlobalForward("EStore_OnDatabaseInitialized", ET_Ignore);
	g_hOnSetUserGroup_PostForward = CreateGlobalForward("EStore_OnSetUserGroup_Post", ET_Ignore, Param_Cell);
	g_hPreCacheOrRealoadCategoriesStartForward = CreateGlobalForward("EStore_PreCacheOrRealoadCategoriesStart", ET_Ignore);
	g_hPreCacheOrRealoadCategoriesFinishedForward = CreateGlobalForward("EStore_PreCacheOrRealoadCategoriesFinished", ET_Ignore, Param_Cell);

	RegPluginLibrary("estore-backend");
	return APLRes_Success;
}

public Plugin:myinfo =
{
	name = "[ES] Backend",
	author = ESTORE_AUTHOR,
	description = "Backend component for [ES]",
	version = ESTORE_VERSION,
	url = ESTORE_URL
};

new Handle:g_hSQL;
new g_iReconnects = 0;

enum Category
{
	CategoryIndex,
	String:CategoryName[ESTORE_MAX_NAME_LENGTH],
	String:CategoryRequirePlugin[ESTORE_MAX_REQUIREPLUGIN_LENGTH],
	String:CategoryDescription[ESTORE_MAX_DESCRIPTION_LENGTH],
	CategoryOrder,
	CategoryFlag
};

new g_aCategories[ESTORE_MAX_CATEGORIES][Category];
new g_iCategoriesCount = 0;

public OnPluginStart()
{
	PrintToServer("[ES] BACKEND COMPONENT LOADED.");

	ConnectSQL();
}

//Precache Categories & Items after initialization
public EStore_OnDatabaseInitialized()
{
	PreCacheCategoriesOrReload();
}

ConnectSQL()
{
	if (g_hSQL != INVALID_HANDLE)
    {
		CloseHandle(g_hSQL);
    }

	g_hSQL = INVALID_HANDLE;

	if (SQL_CheckConfig("estore"))
	{
		SQL_TConnect(T_ConnectSQLCallback, "estore");
	}
	else
	{
		SetFailState("No config entry found for 'estore' in databases.cfg.");
	}
}

public T_ConnectSQLCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (g_iReconnects >= ESTORE_MAX_SQL_RECONNECTS)
	{
		SetFailState("PLUGIN STOPPED - Reason: reconnect reached max. ERROR: %s", error);
		return;
	}

	if (hndl == INVALID_HANDLE)
	{
		EStore_LogError("%s", error);
		g_iReconnects++;
		ConnectSQL();
		return;
	}

	decl String:driver[16];
	SQL_GetDriverIdent(owner, driver, sizeof(driver));

	g_hSQL = CloneHandle(hndl);

	if (StrEqual(driver, "mysql", false))
	{
		SQL_FastQuery(g_hSQL, "SET NAMES  'utf8'");
	}

	CloseHandle(hndl);

	Call_StartForward(g_hdbInitializedForward);
	Call_Finish();

	g_iReconnects = 0;
}

public Native_Register(Handle:plugin, num_params)
{
	new String:name[64];
	GetNativeString(2, name, sizeof(name));

	Register(GetNativeCell(1), name, GetNativeCell(3));
}

Register(accountID, const String:name[] = "", credits = 0)
{
	decl String:safeName[2 * 32 + 1];
	SQL_EscapeString(g_hSQL, name, safeName, sizeof(safeName));

	decl String:query[255];
	Format(query, sizeof(query), "INSERT INTO `estore_user` (`steam_id`, `name`, `credits`) VALUES (%d, '%s', %d) ON DUPLICATE KEY UPDATE `name` = '%s';", accountID, safeName, credits, safeName);
	SQL_TQuery(g_hSQL, T_RegisterCallback, query, _, DBPrio_High);
}

public T_RegisterCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		EStore_LogError("RegisterCallback - %s", error);
		return;
	}
}

public Native_RegisterUser(Handle:plugin, num_params)
{
	RegisterUser(GetNativeCell(1), GetNativeCell(2));
}

RegisterUser(client, credits = 0)
{
	if (!IsClientInGame(client)) { return; }
	if (IsFakeClient(client)) { return; }

	decl String:name[32];
	GetClientName(client, name, sizeof(name));

	Register(GetSteamAccountID(client), name, credits);
}

public Native_GetUserInfo(Handle:plugin, num_params)
{
	new any:data = 0;
	if(num_params == 3)
	{
		data = GetNativeCell(3);
	}
	GetUserInfo(GetNativeCell(1), EStore_GetUserInfoCallback:GetNativeFunction(2), plugin, data);
}

GetUserInfo(client, EStore_GetUserInfoCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:pack = CreateDataPack();
	WritePackFunction(pack, callback);
	WritePackCell(pack, plugin);
	WritePackCell(pack, client);
	WritePackCell(pack, data);

	decl String:query[512];
	Format(query, sizeof(query), "SELECT eu.`credits`, erg.`index`, erg.`name`, erg.`flag` FROM `estore_user` eu JOIN `estore_right_group` erg ON (eu.`estore_right_group_index` = erg.`index`) WHERE eu.`steam_id` = %d LIMIT 1;", GetSteamAccountID(client));
	SQL_TQuery(g_hSQL, T_GetUserInfoCallback, query, pack, DBPrio_High);
}

public T_GetUserInfoCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(pack);
		EStore_LogError("GetUserInfoCallback - %s", error);
		return;
	}

	ResetPack(pack);
	new EStore_GetUserInfoCallback:callback = EStore_GetUserInfoCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new client = ReadPackCell(pack);
	new any:data = ReadPackCell(pack);
	CloseHandle(pack);

	if (SQL_FetchRow(hndl))
	{
		decl String:erg_name[32];
		SQL_FetchString(hndl, 2, erg_name, sizeof(erg_name));
		if(callback != INVALID_FUNCTION)
		{
			Call_StartFunction(plugin, callback);
			Call_PushCell(client);
			Call_PushCell(SQL_FetchInt(hndl, 0));
			Call_PushCell(SQL_FetchInt(hndl, 1));
			Call_PushString(erg_name);
			Call_PushCell(SQL_FetchInt(hndl, 3));
			Call_PushCell(data);
			Call_Finish();
		}
	}
}

public Native_GiveCreditsToUser(Handle:plugin, num_params)
{
	GiveCreditsToUser(GetNativeCell(1), GetNativeCell(2));
}

GiveCreditsToUser(accountID, creditsToAdd)
{
	decl String:query[255];
	Format(query, sizeof(query), "UPDATE `estore_user` SET `credits` = `credits` + %d WHERE `steam_id` = %d;", creditsToAdd, accountID);

	new Handle:pack = CreateDataPack();
	WritePackCell(pack, accountID);
	WritePackCell(pack, creditsToAdd);

	SQL_TQuery(g_hSQL, T_GiveCreditsToUserCallback, query, pack, DBPrio_Low);
}

public T_GiveCreditsToUserCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		ResetPack(pack);
		new accountID = ReadPackCell(pack);
		new creditsToAdd = ReadPackCell(pack);
		CloseHandle(pack);

		EStore_LogError("GiveCreditsToUserCallback - %s | accID: %d creditsToAdd: %d", error, accountID, creditsToAdd);
		return;
	}
	CloseHandle(pack);
}

public Native_TakeCreditsFromUser(Handle:plugin, num_params)
{
	TakeCreditsFromUser(GetNativeCell(1), GetNativeCell(2));
}

TakeCreditsFromUser(accountID, creditsToTake)
{
	decl String:query[255];
	Format(query, sizeof(query), "UPDATE `estore_user` SET `credits` = GREATEST(0, `credits` - %d) WHERE `steam_id` = %d;", creditsToTake, accountID);

	new Handle:pack = CreateDataPack();
	WritePackCell(pack, accountID);
	WritePackCell(pack, creditsToTake);

	SQL_TQuery(g_hSQL, T_TakeCreditsFromUserCallback, query, pack, DBPrio_Low);
}

public T_TakeCreditsFromUserCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		ResetPack(pack);
		new accountID = ReadPackCell(pack);
		new creditsToTake = ReadPackCell(pack);
		CloseHandle(pack);

		EStore_LogError("TakeCreditsFromUserCallback - %s | accID: %d creditsToTake: %d", error, accountID, creditsToTake);
		return;
	}
	CloseHandle(pack);
}

public Native_SetUserGroup(Handle:plugin, num_params)
{
	decl String:group_name[ESTORE_MAX_NAME_LENGTH+2];
	GetNativeString(3, group_name, sizeof(group_name));
	SetUserGroup(GetNativeCell(1), GetNativeCell(2), group_name, EStore_SetUserGroupCallback:GetNativeFunction(4), plugin);
}

SetUserGroup(admin, client, const String:group_name[ESTORE_MAX_NAME_LENGTH+2], EStore_SetUserGroupCallback:callback, Handle:plugin = INVALID_HANDLE)
{
	if(GetUserFlagBits(admin) & ADMFLAG_ROOT == ADMFLAG_ROOT)
	{
		new Handle:pack = CreateDataPack();
		WritePackFunction(pack, callback);
		WritePackCell(pack, plugin);
		WritePackCell(pack, admin);
		WritePackCell(pack, client);
		WritePackString(pack, group_name);

		decl String:safeGroupName[2 * (ESTORE_MAX_NAME_LENGTH+2) + 1];
		SQL_EscapeString(g_hSQL, group_name, safeGroupName, sizeof(safeGroupName));

		decl String:query[255];
		Format(query, sizeof(query), "UPDATE `estore_user` SET `estore_right_group_index` = (SELECT IFNULL(SUM(erg.`index`), -1) FROM `estore_right_group` erg  WHERE erg.`name` = '%s' LIMIT 1) WHERE `steam_id` = %d;", safeGroupName, GetSteamAccountID(client));
		SQL_TQuery(g_hSQL, T_SetUserGroupCallback, query, pack, DBPrio_Low);
	}
}

public T_SetUserGroupCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	ResetPack(pack);
	new EStore_SetUserGroupCallback:callback = EStore_SetUserGroupCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new admin = ReadPackCell(pack);
	new client = ReadPackCell(pack);
	decl String:group_name[ESTORE_MAX_NAME_LENGTH+2];
	ReadPackString(pack, group_name, sizeof(group_name));
	CloseHandle(pack);

	new e = 0;
	if(hndl == INVALID_HANDLE)
	{
		e = 1;
	}
	else if(SQL_GetAffectedRows(hndl) <= 0)
	{
		e = 2;
	}
	else
	{
		Call_StartForward(g_hOnSetUserGroup_PostForward);
		Call_PushCell(client);
		Call_Finish();
	}
	if(callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(e);
		Call_PushCell(admin);
		Call_PushCell(client);
		Call_PushString(group_name);
		Call_Finish();
	}
}

public Native_CheckDailyLogin(Handle:plugin, num_params)
{
	CheckDailyLogin(GetNativeCell(1), EStore_CheckDailyLoginCallback:GetNativeFunction(2), plugin);
}

CheckDailyLogin(client, EStore_CheckDailyLoginCallback:callback, Handle:plugin = INVALID_HANDLE)
{
	new Handle:pack = CreateDataPack();
	WritePackFunction(pack, callback);
	WritePackCell(pack, plugin);
	WritePackCell(pack, client);

	decl String:query[255];
	Format(query, sizeof(query), "INSERT INTO `estore_user_history` (`estore_user_index`, `date`, `time`, `count`) VALUES ((SELECT eu.`index` FROM `estore_user` eu WHERE eu.`steam_id` = %d LIMIT 1), now(), now(), 1) ON DUPLICATE KEY UPDATE `count` = `count` + 1, `time` = now();", GetSteamAccountID(client));
	SQL_TQuery(g_hSQL, T_UserHistoryCallback, query, pack, DBPrio_Low);
}

public T_UserHistoryCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(pack);

		EStore_LogError("UserHistoryCallback - %s", error);
		return;
	}

	ResetPack(pack);
	ReadPackFunction(pack);
	ReadPackCell(pack);
	new client = ReadPackCell(pack);

	decl String:query[512];
	Format(query, sizeof(query), "SELECT euh.`count`, eu.`credits`, erg.`index`, erg.`name`, erg.`flag` FROM `estore_user` eu JOIN `estore_user_history` euh ON (eu.`index` = euh.`estore_user_index`) JOIN `estore_right_group` erg ON (eu.`estore_right_group_index` = erg.`index`) WHERE eu.`steam_id` = %d AND euh.`date` = date(now());", GetSteamAccountID(client));
	SQL_TQuery(g_hSQL, T_CheckDailyLoginCallback, query, pack, DBPrio_Low);
}

public T_CheckDailyLoginCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(pack);

		EStore_LogError("CheckDailyLoginCallback - %s", error);
		return;
	}
	ResetPack(pack);
	new EStore_CheckDailyLoginCallback:callback = EStore_CheckDailyLoginCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new client = ReadPackCell(pack);
	CloseHandle(pack);

	if (SQL_FetchRow(hndl))
	{
		decl String:erg_name[ESTORE_MAX_NAME_LENGTH];
		SQL_FetchString(hndl, 3, erg_name, sizeof(erg_name));
		if(callback != INVALID_FUNCTION)
		{
			Call_StartFunction(plugin, callback);
			Call_PushCell(client);
			Call_PushCell(SQL_FetchInt(hndl, 0) <= 1 ? true: false);
			Call_PushCell(SQL_FetchInt(hndl, 1));
			Call_PushCell(SQL_FetchInt(hndl, 2));
			Call_PushString(erg_name);
			Call_PushCell(SQL_FetchInt(hndl, 4));
			Call_Finish();
		}
	}
}

public Native_PreCacheCategoriesOrReload(Handle:plugin, num_params)
{
	PreCacheCategoriesOrReload();
}

PreCacheCategoriesOrReload()
{
	Call_StartForward(g_hPreCacheOrRealoadCategoriesStartForward);
	Call_Finish();

	decl String:query[255];
	Format(query, sizeof(query), "SELECT `index`, `name`, `require_plugin`, `description`, `order`, `flag` FROM `estore_category` ORDER BY `order` LIMIT %d", ESTORE_MAX_CATEGORIES);
	SQL_TQuery(g_hSQL, T_PreCacheCategoriesOrReloadCallback, query, _, DBPrio_Normal);
}

public T_PreCacheCategoriesOrReloadCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		EStore_LogError("PreCacheCategoriesOrReloadCallback - %s", error);
		return;
	}

	g_iCategoriesCount = 0;
	while (SQL_FetchRow(hndl))
	{
		g_aCategories[g_iCategoriesCount][CategoryIndex] = SQL_FetchInt(hndl, 0);
		SQL_FetchString(hndl, 1, g_aCategories[g_iCategoriesCount][CategoryName], ESTORE_MAX_NAME_LENGTH);
		SQL_FetchString(hndl, 2, g_aCategories[g_iCategoriesCount][CategoryRequirePlugin], ESTORE_MAX_REQUIREPLUGIN_LENGTH);
		SQL_FetchString(hndl, 3, g_aCategories[g_iCategoriesCount][CategoryDescription], ESTORE_MAX_DESCRIPTION_LENGTH);
		g_aCategories[g_iCategoriesCount][CategoryOrder] = SQL_FetchInt(hndl, 4);
		g_aCategories[g_iCategoriesCount][CategoryFlag] = SQL_FetchInt(hndl, 5);
		g_iCategoriesCount++;
	}

	Call_StartForward(g_hPreCacheOrRealoadCategoriesFinishedForward);
	Call_PushCell(g_iCategoriesCount);
	Call_Finish();
}

public Native_GetCategoryCount(Handle:plugin, num_params)
{
	if(g_iCategoriesCount <= 0)
	{
		return false;
	}
	SetNativeCellRef(1, g_iCategoriesCount);
	return true;
}

public Native_GetCategoryIndices(Handle:plugin, num_params)
{
	new any:data = 0;
	if(num_params == 3)
	{
		data = GetNativeCell(3);
	}
	GetCategoryIndices(EStore_GetIndicesCallback:GetNativeFunction(1), plugin, bool:GetNativeCell(2), data);
}

GetCategoryIndices(EStore_GetIndicesCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, bool:useCache = true, any:data = 0)
{
	if (useCache && g_iCategoriesCount > 0)
	{
		if (callback == INVALID_FUNCTION)
		{
			return;
		}

		new categories[g_iCategoriesCount];
		new count = 0;
		for (new category = 0; category < g_iCategoriesCount; category++)
		{
			categories[count++] = g_aCategories[category][CategoryIndex];
		}
		Call_StartFunction(plugin, callback);
		Call_PushArray(categories, count);
		Call_PushCell(count);
		Call_PushCell(data);
		Call_Finish();
	}
	else
	{
		new Handle:pack = CreateDataPack();
		WritePackFunction(pack, callback);
		WritePackCell(pack, plugin);
		WritePackCell(pack, data);

		decl String:query[255];
		Format(query, sizeof(query), "SELECT `index` FROM `estore_category` ORDER BY `order` LIMIT %d", ESTORE_MAX_CATEGORIES);

		SQL_TQuery(g_hSQL, T_GetCategoryIndicesCallback, query, pack, DBPrio_Normal);
	}
}

public T_GetCategoryIndicesCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(pack);

		EStore_LogError("GetCategoryIndicesCallback - %s", error);
		return;
	}

	ResetPack(pack);
	new EStore_GetIndicesCallback:callback = EStore_GetIndicesCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new any:data = ReadPackCell(pack);
	CloseHandle(pack);

	new categories[SQL_GetRowCount(hndl)];
	new count = 0;

	while (SQL_FetchRow(hndl))
	{
		categories[count++] = SQL_FetchInt(hndl, 0);
	}
	if(callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushArray(categories, count);
		Call_PushCell(count);
		Call_PushCell(data);
		Call_Finish();
	}
}

public Native_GetCategoryInfo(Handle:plugin, num_params)
{
	new any:data = 0;
	if(num_params == 4)
	{
		data = GetNativeCell(4);
	}

	GetCategoryInfo(GetNativeCell(1), EStore_GetCategoryInfoCallback:GetNativeFunction(2), plugin, bool:GetNativeCell(3), data);
}

public Native_GetCategoryInfo2(Handle:plugin, num_params)
{
	new index = GetNativeCell(1);
	if(0 <= index < g_iCategoriesCount)
	{
		SetNativeCellRef(2, g_aCategories[index][CategoryIndex]);
		SetNativeString(3, g_aCategories[index][CategoryName], ESTORE_MAX_NAME_LENGTH);
		SetNativeString(4, g_aCategories[index][CategoryRequirePlugin], ESTORE_MAX_REQUIREPLUGIN_LENGTH);
		SetNativeString(5, g_aCategories[index][CategoryDescription], ESTORE_MAX_DESCRIPTION_LENGTH);
		SetNativeCellRef(6, g_aCategories[index][CategoryOrder]);
		SetNativeCellRef(7, g_aCategories[index][CategoryFlag]);
		return true;
	}
	return false;
}

GetCategoryInfo(index, EStore_GetCategoryInfoCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, bool:useCache = true, any:data = 0)
{
	if (useCache && 0 <= index < g_iCategoriesCount)
	{
		if(callback != INVALID_FUNCTION)
		{
			Call_StartFunction(plugin, callback);
			Call_PushCell(g_aCategories[index][CategoryIndex]);
			Call_PushString(g_aCategories[index][CategoryName]);
			Call_PushString(g_aCategories[index][CategoryRequirePlugin]);
			Call_PushString(g_aCategories[index][CategoryDescription]);
			Call_PushCell(g_aCategories[index][CategoryOrder]);
			Call_PushCell(g_aCategories[index][CategoryFlag]);
			Call_Finish();
		}
	}
	else if(!useCache)
	{
		new Handle:pack = CreateDataPack();
		WritePackFunction(pack, callback);
		WritePackCell(pack, plugin);
		WritePackCell(pack, data);

		decl String:query[255];
		Format(query, sizeof(query), "SELECT `index`, `name`, `require_plugin`, `description`, `order`, `flags` FROM `estore_category` WHERE `index` = %d LIMIT 1", index);
		SQL_TQuery(g_hSQL, T_GetCategoryInfoCallback, query, pack, DBPrio_Normal);
	}
}

public T_GetCategoryInfoCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(pack);

		EStore_LogError("GetCategoryInfoCallback - %s", error);
		return;
	}

	ResetPack(pack);
	new EStore_GetCategoryInfoCallback:callback = EStore_GetCategoryInfoCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new any:data = ReadPackCell(pack);
	CloseHandle(pack);

	if (SQL_FetchRow(hndl))
	{
		decl String:cName[ESTORE_MAX_NAME_LENGTH];
		SQL_FetchString(hndl, 1, cName, sizeof(cName));
		decl String:cRequirePlugin[ESTORE_MAX_REQUIREPLUGIN_LENGTH];
		SQL_FetchString(hndl, 2, cRequirePlugin, sizeof(cRequirePlugin));
		decl String:cDescription[ESTORE_MAX_DESCRIPTION_LENGTH];
		SQL_FetchString(hndl, 3, cDescription, sizeof(cDescription));
		if(callback != INVALID_FUNCTION)
		{
			Call_StartFunction(plugin, callback);
			Call_PushCell(SQL_FetchInt(hndl, 0));
			Call_PushString(cName);
			Call_PushString(cRequirePlugin);
			Call_PushString(cDescription);
			Call_PushCell(SQL_FetchInt(hndl, 4));
			Call_PushCell(SQL_FetchInt(hndl, 5));
			Call_PushCell(data);
			Call_Finish();
		}
	}
}

public Native_GiveUserItem(Handle:plugin, num_params)
{
	new any:data = 0;
	if(num_params == 4)
	{
		data = GetNativeCell(4);
	}
	GiveUserItem(GetNativeCell(1), GetNativeCell(2), EStore_GiveUserItemCallback:GetNativeFunction(3), plugin, data);
}

GiveUserItem(client, itemIndex, EStore_GiveUserItemCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:pack = CreateDataPack();
	WritePackCell(pack, client);
	WritePackCell(pack, itemIndex);
	WritePackFunction(pack, callback);
	WritePackCell(pack, plugin);
	WritePackCell(pack, data);

	decl String:query[255];
	Format(query, sizeof(query), "INSERT INTO `estore_user_item` (`estore_user_index`, `estore_item_index`, `acquire_method`) VALUES ((SELECT eu.`index` FROM `estore_user` eu WHERE eu.`steam_id` = %d LIMIT 1), %d, 'shop')", GetSteamAccountID(client), itemIndex);
	SQL_TQuery(g_hSQL, T_GiveUserItem, query, pack, DBPrio_Normal);
}

public T_GiveUserItem(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	ResetPack(pack);
	new client = ReadPackCell(pack);
	new itemIndex = ReadPackCell(pack);
	new EStore_GiveUserItemCallback:callback = EStore_GiveUserItemCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new any:data = ReadPackCell(pack);
	CloseHandle(pack);

	new bool:success = true;

	if (hndl == INVALID_HANDLE)
	{
		success = false;
	}

	if(callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(client);
		Call_PushCell(itemIndex);
		Call_PushCell(success);
		Call_PushCell(data);
		Call_Finish();
	}
}

public Native_GetItemsInfo(Handle:plugin, num_params)
{
	new any:data = 0;
	if(num_params == 4)
	{
		data = GetNativeCell(4);
	}

	GetItemsInfo(GetNativeCell(1), GetNativeCell(2), EStore_GetInfoCallback:GetNativeFunction(3), plugin, data);
}

GetItemsInfo(categoryIndex, Handle:filter = INVALID_HANDLE, EStore_GetInfoCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:pack = CreateDataPack();
	WritePackFunction(pack, callback);
	WritePackCell(pack, plugin);
	WritePackCell(pack, data);

	/*"SELECT 
		`index`, 
		`name`, 
		`description`, 
		`price`, 
		`estore_category_index`, 
		`type`, 
		`is_buyable_from`, 
		`is_tradeable_to`, 
		`is_refundable`, 
		`team_only`, 
		`flags`, 
		LENGTH(`data`), `data`, 
		`expire_after` 
	FROM `estore_item` WHERE `estore_category_index` = %d", categoryIndex);*/
	
	decl String:query[512];
	Format(query, sizeof(query), "SELECT `index`, `name`, `price`, `expire_after` FROM `estore_item` WHERE `estore_category_index` = %d", categoryIndex);

	if(filter != INVALID_HANDLE)
	{
		new team;
		if (GetTrieValue(filter, "team_only", team))
		{
			Format(query, sizeof(query), "%s AND (`team_only` = %d OR `team_only` = 0)", query, team);
		}
		new isBuyableFrom;
		if (GetTrieValue(filter, "is_buyable_from", isBuyableFrom))
		{
			Format(query, sizeof(query), "%s AND (`is_buyable_from` & %d = %d)", query, isBuyableFrom, isBuyableFrom);
		}
		new isTradeableTo;
		if (GetTrieValue(filter, "is_tradeable_to", isTradeableTo))
		{
			Format(query, sizeof(query), "%s AND (`is_tradeable_to` & %d = %d)", query, isTradeableTo, isTradeableTo);
		}
		new isRefundable;
		if (GetTrieValue(filter, "is_refundable", isRefundable))
		{
			Format(query, sizeof(query), "%s AND `is_refundable` = %d", query, isRefundable);
		}
		new flags;
		if (GetTrieValue(filter, "flags", isRefundable))
		{
			Format(query, sizeof(query), "%s AND (`flags` & %d = %d)", query, flags, flags);
		}
		CloseHandle(filter);
	}

	SQL_TQuery(g_hSQL, T_GetItemsInfoCallback, query, pack, DBPrio_Normal);
}

public T_GetItemsInfoCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(pack);

		EStore_LogError("GetItemsInfoCallback - %s", error);
		return;
	}

	ResetPack(pack);
	new EStore_GetInfoCallback:callback = EStore_GetInfoCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new any:data = ReadPackCell(pack);
	CloseHandle(pack);

	new count = SQL_GetRowCount(hndl);
	new Handle:results[count];
	new iResultCount = 0;
	while (SQL_FetchRow(hndl))
	{
		decl String:iName[ESTORE_MAX_NAME_LENGTH];
		SQL_FetchString(hndl, 1, iName, sizeof(iName));
		
		new Handle:info = CreateDataPack();
		WritePackCell(info, SQL_FetchInt(hndl, 0));
		WritePackString(info, iName);
		WritePackCell(info, SQL_FetchInt(hndl, 2));
		WritePackCell(info, SQL_FetchInt(hndl, 3));
		results[iResultCount++] = CloneHandle(info, plugin);
		CloseHandle(info);
	}

	if(callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushArray(results, count);
		Call_PushCell(count);
		Call_PushCell(data);
		Call_Finish();
	}
}

public Native_GetUserItemsOfCategory(Handle:plugin, num_params)
{
	new any:data = 0;
	if(num_params == 5)
	{
		data = GetNativeCell(5);
	}
	GetUserCategoryItems(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3), EStore_GetInfoCallback:GetNativeFunction(4), plugin , data);
}

GetUserCategoryItems(client, categoryIndex, Handle:filter = INVALID_HANDLE, EStore_GetInfoCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:pack = CreateDataPack();
	WritePackFunction(pack, callback);
	WritePackCell(pack, plugin);
	WritePackCell(pack, data);

	decl String:query[768];
	Format(query, sizeof(query), "SELECT ei.`index`, ei.`name`, ei.`type`, IF(ei.`expire_after` > 0, GREATEST(ei.`expire_after` * 24 * 60 * 60 - TIMESTAMPDIFF(SECOND, eui.`acquire_timestamp`, now()), 0), -1) AS 'expire_in' FROM `estore_item` ei JOIN `estore_user_item` eui ON (ei.`index` = eui.`estore_item_index`) JOIN `estore_user` eu ON (eu.`index` = eui.`estore_user_index`) WHERE ((ei.`expire_after` > 0 AND TIMESTAMPDIFF(SECOND, eui.`acquire_timestamp`, now()) <= (ei.`expire_after` * 24 * 60 * 60)) OR ei.`expire_after` = 0) AND ei.`estore_category_index` = %d AND eu.`steam_id` = %d", categoryIndex, GetSteamAccountID(client));

	if(filter != INVALID_HANDLE)
	{
		new team;
		if (GetTrieValue(filter, "team_only", team))
		{
			Format(query, sizeof(query), "%s AND (ei.`team_only` = %d OR ei.`team_only` = 0)", query, team);
		}
		new isBuyableFrom;
		if (GetTrieValue(filter, "is_buyable_from", isBuyableFrom))
		{
			Format(query, sizeof(query), "%s AND (ei.`is_buyable_from` & %d = %d)", query, isBuyableFrom, isBuyableFrom);
		}
		new isTradeableTo;
		if (GetTrieValue(filter, "is_tradeable_to", isTradeableTo))
		{
			Format(query, sizeof(query), "%s AND (ei.`is_tradeable_to` & %d = %d)", query, isTradeableTo, isTradeableTo);
		}
		new isRefundable;
		if (GetTrieValue(filter, "is_refundable", isRefundable))
		{
			Format(query, sizeof(query), "%s AND ei.`is_refundable` = %d", query, isRefundable);
		}
		new flags;
		if (GetTrieValue(filter, "flags", isRefundable))
		{
			Format(query, sizeof(query), "%s AND (ei.`flags` & %d = %d)", query, flags, flags);
		}
		CloseHandle(filter);
	}

	SQL_TQuery(g_hSQL, T_GetUserCategoryItemsCallback, query, pack, DBPrio_Normal);
}

public T_GetUserCategoryItemsCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(pack);

		EStore_LogError("GetUserCategoryItemsCallback - %s", error);
		return;
	}

	ResetPack(pack);
	new EStore_GetInfoCallback:callback = EStore_GetInfoCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new any:data = ReadPackCell(pack);
	CloseHandle(pack);

	new count = SQL_GetRowCount(hndl);
	new Handle:results[count];
	new iResultCount = 0;
	while (SQL_FetchRow(hndl))
	{
		decl String:iName[ESTORE_MAX_NAME_LENGTH];
		SQL_FetchString(hndl, 1, iName, sizeof(iName));
		decl String:iType[ESTORE_MAX_TYPE_LENGTH];
		SQL_FetchString(hndl, 2, iType, sizeof(iType));
		
		new Handle:info = CreateDataPack();
		WritePackCell(info, SQL_FetchInt(hndl, 0));
		WritePackString(info, iName);
		WritePackString(info, iType);
		WritePackCell(info, SQL_FetchInt(hndl, 3));
		results[iResultCount++] = CloneHandle(info, plugin);
		CloseHandle(info);
	}

	if(callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushArray(results, count);
		Call_PushCell(count);
		Call_PushCell(data);
		Call_Finish();
	}
}

public Native_GetItemData(Handle:plugin, num_params)
{
	new any:data = 0;
	if(num_params == 3)
	{
		data = GetNativeCell(3);
	}

	GetItemData(GetNativeCell(1), EStore_GetItemDataCallback:GetNativeFunction(2), plugin, data);
}

GetItemData(itemIndex, EStore_GetItemDataCallback:callback = INVALID_FUNCTION, Handle:plugin, any:data = 0)
{
	new Handle:pack = CreateDataPack();
	WritePackFunction(pack, callback);
	WritePackCell(pack, plugin);
	WritePackCell(pack, data);

	decl String:query[255];
	Format(query, sizeof(query), "SELECT LENGTH(`data`), `data` FROM `estore_item` WHERE `index` = %d LIMIT 1;", itemIndex);
	SQL_TQuery(g_hSQL, T_GetItemDataCallback, query, pack, DBPrio_Normal);
}

public T_GetItemDataCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(pack);

		EStore_LogError("GetItemDataCallback - %s", error);
		return;
	}

	ResetPack(pack);
	new EStore_GetUserBankInfoCallback:callback = EStore_GetUserBankInfoCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new any:data = ReadPackCell(pack);
	CloseHandle(pack);

	if (SQL_FetchRow(hndl))
	{
		if(callback != INVALID_FUNCTION)
		{
			new iDataLenght = SQL_FetchInt(hndl, 0) + 1;
			decl String:iData[iDataLenght];
			SQL_FetchString(hndl, 1, iData, iDataLenght);

			Call_StartFunction(plugin, callback);
			Call_PushString(iData);
			Call_PushCell(iDataLenght);
			Call_PushCell(data);
			Call_Finish();
		}
	}
}


public Native_GetUserBankInfo(Handle:plugin, num_params)
{
	new any:data = 0;
	if(num_params == 3)
	{
		data = GetNativeCell(3);
	}

	GetUserBankInfo(GetNativeCell(1), EStore_GetUserBankInfoCallback:GetNativeFunction(2), plugin, data);
}

GetUserBankInfo(client, EStore_GetUserBankInfoCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:pack = CreateDataPack();
	WritePackCell(pack, client);
	WritePackFunction(pack, callback);
	WritePackCell(pack, plugin);
	WritePackCell(pack, data);

	decl String:query[255];
	Format(query, sizeof(query), "SELECT eb.`money`, eb.`auto_deposit`, eb.`auto_withdraw` FROM `estore_banking` eb JOIN `estore_user` eu ON (eu.`index` = eb.`estore_user_index`) WHERE eu.`steam_id` = %d LIMIT 1;", GetSteamAccountID(client));
	SQL_TQuery(g_hSQL, T_GetUserBankInfoCallback, query, pack, DBPrio_Normal);
}

public T_GetUserBankInfoCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(pack);

		EStore_LogError("GetUserBankInfoCallback - %s", error);
		return;
	}

	ResetPack(pack);
	new client = ReadPackCell(pack);
	new EStore_GetUserBankInfoCallback:callback = EStore_GetUserBankInfoCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new any:data = ReadPackCell(pack);
	CloseHandle(pack);

	if (SQL_FetchRow(hndl))
	{
		if(callback != INVALID_FUNCTION)
		{
			Call_StartFunction(plugin, callback);
			Call_PushCell(client);
			Call_PushCell(SQL_FetchInt(hndl, 0));
			Call_PushCell(SQL_FetchInt(hndl, 1));
			Call_PushCell(SQL_FetchInt(hndl, 2));
			Call_PushCell(data);
			Call_Finish();
		}
	}
}

public Native_DepositUserBankMoney(Handle:plugin, num_params)
{
	DepositUserBankMoney(GetNativeCell(1), GetNativeCell(2));
}

DepositUserBankMoney(client, money)
{
	decl String:query[255];
	Format(query, sizeof(query), "UPDATE `estore_banking` eb JOIN `estore_user` eu ON (eu.`index` = eb.`estore_user_index`) SET eb.`money` = eb.`money` + %d WHERE eu.`steam_id` = %d;", money, GetSteamAccountID(client));
	SQL_TQuery(g_hSQL, T_DepositUserBankMoneyCallback, query, _, DBPrio_Normal);
}

public T_DepositUserBankMoneyCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		EStore_LogError("DepositUserBankMoneyCallback - %s", error);
		return;
	}
}

public Native_WithdrawUserBankMoney(Handle:plugin, num_params)
{
	WithdrawUserBankMoney(GetNativeCell(1), GetNativeCell(2));
}

WithdrawUserBankMoney(client, money)
{
	decl String:query[255];
	Format(query, sizeof(query), "UPDATE `estore_banking` eb JOIN `estore_user` eu ON (eu.`index` = eb.`estore_user_index`) SET eb.`money` = eb.`money` - %d WHERE eu.`steam_id` = %d;", money, GetSteamAccountID(client));
	SQL_TQuery(g_hSQL, T_WithdrawUserBankMoneyCallback, query, _, DBPrio_Normal);
}

public T_WithdrawUserBankMoneyCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		EStore_LogError("WithdrawUserBankMoneyCallback - %s", error);
		return;
	}
}

public Native_GetTop10Bank(Handle:plugin, num_params)
{
	new any:data = 0;
	if(num_params == 2)
	{
		data = GetNativeCell(2);
	}
	GetTop10Bank(EStore_GetInfoCallback:GetNativeFunction(1), plugin, data);
}

GetTop10Bank(EStore_GetInfoCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:pack = CreateDataPack();
	WritePackFunction(pack, callback);
	WritePackCell(pack, plugin);
	WritePackCell(pack, data);

	decl String:query[255];
	Format(query, sizeof(query), "SELECT eu.`name`, eb.`money` FROM `estore_banking` eb JOIN `estore_user` eu ON (eu.`index` = eb.`estore_user_index`) ORDER BY eb.`money` DESC LIMIT 10;");
	SQL_TQuery(g_hSQL, T_GetTop10BankCallback, query, pack, DBPrio_Normal);
}

public T_GetTop10BankCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		ResetPack(pack);
		EStore_LogError("GetTop10BankCallback - %s", error);
		return;
	}

	ResetPack(pack);
	new EStore_GetInfoCallback:callback = EStore_GetInfoCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new any:data = ReadPackCell(pack);
	CloseHandle(pack);

	new count = SQL_GetRowCount(hndl);
	new Handle:results[count];
	new iResultCount = 0;
	while (SQL_FetchRow(hndl))
	{
		decl String:iName[ESTORE_MAX_NAME_LENGTH];
		SQL_FetchString(hndl, 0, iName, sizeof(iName));
		
		new Handle:info = CreateDataPack();
		WritePackString(info, iName);
		WritePackCell(info, SQL_FetchInt(hndl, 1));
		results[iResultCount++] = CloneHandle(info, plugin);
		CloseHandle(info);
	}

	if(callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushArray(results, count);
		Call_PushCell(count);
		Call_PushCell(data);
		Call_Finish();
	}
}

public Native_GetTop10Store(Handle:plugin, num_params)
{
	new any:data = 0;
	if(num_params == 2)
	{
		data = GetNativeCell(2);
	}
	GetTop10Store(EStore_GetInfoCallback:GetNativeFunction(1), plugin, data);
}

GetTop10Store(EStore_GetInfoCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:pack = CreateDataPack();
	WritePackFunction(pack, callback);
	WritePackCell(pack, plugin);
	WritePackCell(pack, data);

	decl String:query[255];
	Format(query, sizeof(query), "SELECT `name`, `credits` FROM `estore_user` ORDER BY `credits` DESC LIMIT 10;");
	SQL_TQuery(g_hSQL, T_GetTop10StoreCallback, query, pack, DBPrio_Normal);
}

public T_GetTop10StoreCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		ResetPack(pack);
		EStore_LogError("GetTop10StoreCallback - %s", error);
		return;
	}

	ResetPack(pack);
	new EStore_GetInfoCallback:callback = EStore_GetInfoCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new any:data = ReadPackCell(pack);
	CloseHandle(pack);

	new count = SQL_GetRowCount(hndl);
	new Handle:results[count];
	new iResultCount = 0;
	while (SQL_FetchRow(hndl))
	{
		decl String:iName[ESTORE_MAX_NAME_LENGTH];
		SQL_FetchString(hndl, 0, iName, sizeof(iName));
		
		new Handle:info = CreateDataPack();
		WritePackString(info, iName);
		WritePackCell(info, SQL_FetchInt(hndl, 1));
		results[iResultCount++] = CloneHandle(info, plugin);
		CloseHandle(info);
	}

	if(callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushArray(results, count);
		Call_PushCell(count);
		Call_PushCell(data);
		Call_Finish();
	}
}

public Native_PrecacheAllItems(Handle:plugin, num_params)
{
	new any:data = 0;
	if(num_params == 2)
	{
		data = GetNativeCell(2);
	}
	PrecacheAllItems(EStore_GetInfoCallback:GetNativeFunction(1), plugin, data);
}

PrecacheAllItems(EStore_GetInfoCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:pack = CreateDataPack();
	WritePackFunction(pack, callback);
	WritePackCell(pack, plugin);
	WritePackCell(pack, data);

	decl String:query[96];
	Format(query, sizeof(query), "SELECT `type`, LENGTH(`data`), `data` FROM `estore_item` WHERE `flags` & 1 = 1;");
	SQL_TQuery(g_hSQL, T_PrecacheAllItemsCallback, query, pack, DBPrio_Normal);
}

public T_PrecacheAllItemsCallback(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	if (hndl == INVALID_HANDLE)
	{
		ResetPack(pack);
		EStore_LogError("PrecacheAllItemsCallback - %s", error);
		return;
	}

	ResetPack(pack);
	new EStore_GetInfoCallback:callback = EStore_GetInfoCallback:ReadPackFunction(pack);
	new Handle:plugin = Handle:ReadPackCell(pack);
	new any:data = ReadPackCell(pack);
	CloseHandle(pack);

	new count = SQL_GetRowCount(hndl);
	new Handle:results[count];
	new iResultCount = 0;
	while (SQL_FetchRow(hndl))
	{
		decl String:iType[ESTORE_MAX_TYPE_LENGTH];
		SQL_FetchString(hndl, 0, iType, sizeof(iType));

		new dataLenght = SQL_FetchInt(hndl, 1) + 1;
		decl String:iData[dataLenght];
		SQL_FetchString(hndl, 2, iData, dataLenght);
		
		new Handle:info = CreateDataPack();
		WritePackString(info, iType);
		WritePackCell(info, dataLenght);
		WritePackString(info, iData);
		results[iResultCount++] = CloneHandle(info, plugin);
		CloseHandle(info);
	}

	if(callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushArray(results, count);
		Call_PushCell(count);
		Call_PushCell(data);
		Call_Finish();
	}
}