#if defined _estore_backend_included
#endinput
#endif
#define _estore_backend_included

#define ESTORE_MAX_NAME_LENGTH			32
#define ESTORE_MAX_REQUIREPLUGIN_LENGTH	32
#define ESTORE_MAX_DESCRIPTION_LENGTH	128

#define ESTORE_MAX_TYPE_LENGTH			32

//#define ESTORE_MAX_LOADOUTSLOT_LENGTH 32
//#define ESTORE_MAX_LOADOUTGAME_LENGTH 32
//#define ESTORE_MAX_LOADOUTCLASS_LENGTH 32

enum EStore_AcquireMethod
{
	EStore_Shop,
	EStore_Trade,
	EStore_Gift,
	EStore_Admin
}

forward EStore_OnDatabaseInitialized();
forward EStore_OnSetUserGroup_Post(client);
forward EStore_PreCacheOrRealoadCategoriesStart();
forward EStore_PreCacheOrRealoadCategoriesFinished(count);

functag EStore_GetUserInfoCallback public(client, credits, erg_index, const String:erg_name[ESTORE_MAX_NAME_LENGTH], erg_flag, any:data);
functag EStore_SetUserGroupCallback public(error, admin, client, const String:group_name[ESTORE_MAX_NAME_LENGTH + 2]);
functag EStore_CheckDailyLoginCallback  public(client, bool:dailyBonus, credits, erg_index, const String:erg_name[ESTORE_MAX_NAME_LENGTH], erg_flag);

functag EStore_GetIndicesCallback public(indices[], count, any:data);
functag EStore_GetInfoCallback public(Handle:infos[], count, any:data);
functag EStore_GetCategoryInfoCallback public(index, String:name[ESTORE_MAX_NAME_LENGTH], String:require_plugin[ESTORE_MAX_REQUIREPLUGIN_LENGTH], order, flags, any:data);
functag EStore_GetItemDataCallback public(String:data[], dataLenght, any:data);

functag EStore_GetUserBankInfoCallback public(client, money, auto_deposit, auto_withdraw, any:data);

functag EStore_GiveUserItemCallback public(client, itemIndex, bool:success, any:data);

native EStore_Register(accountID, const String:name[] = "", credits = 0);
native EStore_RegisterUser(client, credits = 0);

native EStore_GetUserInfo(client, EStore_GetUserInfoCallback:callback, any:data = 0);
native EStore_GiveCreditsToUser(accountID, creditsToAdd);
native EStore_TakeCreditsFromUser(accountID, creditsToTake);

native EStore_SetUserGroup(admin, client, const String:group_name[ESTORE_MAX_NAME_LENGTH+2], EStore_SetUserGroupCallback:callback);

native EStore_CheckDailyLogin(client, EStore_CheckDailyLoginCallback:callback);

native EStore_PreCacheCategoriesOrReload();
native EStore_GetCategoryIndices(EStore_GetIndicesCallback:callback = INVALID_FUNCTION, bool:useCache = true, any:data = 0);
native bool:EStore_GetCategoryCount(&count);
native EStore_GetCategoryInfo(index, EStore_GetCategoryInfoCallback:callback = INVALID_FUNCTION, bool:useCache = true, any:data = 0);
native bool:EStore_GetCategoryInfo2(index, &categoryIndex, String:categoryName[ESTORE_MAX_NAME_LENGTH], String:categoryRequirePlugin[ESTORE_MAX_REQUIREPLUGIN_LENGTH], String:categoryDescription[ESTORE_MAX_DESCRIPTION_LENGTH], &categoryOrder, &categoryFlag);

native EStore_GiveUserItem(client, itemIndex, EStore_GiveUserItemCallback:callback = INVALID_FUNCTION, any:data = 0);
native EStore_GetItemsInfo(categoryIndex, Handle:filter = INVALID_HANDLE, EStore_GetInfoCallback:callback = INVALID_FUNCTION, any:data = 0);
native EStore_GetUserItemsOfCategory(client, categoryIndex, Handle:filter = INVALID_HANDLE, EStore_GetInfoCallback:callback = INVALID_FUNCTION, any:data = 0);
native EStore_GetItemData(itemIndex, EStore_GetItemDataCallback:callback = INVALID_FUNCTION, any:data = 0);

native EStore_GetUserBankInfo(client, EStore_GetUserBankInfoCallback:callback = INVALID_FUNCTION, any:data = 0);
native EStore_DepositUserBankMoney(client, money);
native EStore_WithdrawUserBankMoney(client, money);
native EStore_GetTop10Bank(EStore_GetInfoCallback:callback = INVALID_FUNCTION, any:data = 0);
native EStore_GetTop10Store(EStore_GetInfoCallback:callback = INVALID_FUNCTION, any:data = 0);

native EStore_PrecacheAllItems(EStore_GetInfoCallback:callback = INVALID_FUNCTION, any:data = 0);

public SharedPlugin:__pl_estore_backend =
{
	name = "estore-backend",
	file = "estore-backend.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_estore_backend_SetNTVOptional()
{
	MarkNativeAsOptional("EStore_Register");
	MarkNativeAsOptional("EStore_RegisterUser");
	MarkNativeAsOptional("EStore_GetTop10Store");

	MarkNativeAsOptional("EStore_GetUserInfo");
	MarkNativeAsOptional("EStore_GiveCreditsToUser");
	MarkNativeAsOptional("EStore_TakeCreditsFromUser");

	MarkNativeAsOptional("EStore_SetUserGroup");

	MarkNativeAsOptional("EStore_CheckDailyLogin");

	MarkNativeAsOptional("EStore_PreCacheCategoriesOrReload");
	MarkNativeAsOptional("EStore_GetCategoryIndices");
	MarkNativeAsOptional("EStore_GetCategoryCount");
	MarkNativeAsOptional("EStore_GetCategoryInfo");
	MarkNativeAsOptional("EStore_GetCategoryInfo2");

	MarkNativeAsOptional("EStore_GiveUserItem");
	MarkNativeAsOptional("EStore_GetItemsInfo");
	MarkNativeAsOptional("EStore_GetUserItemsOfCategory");
	MarkNativeAsOptional("EStore_GetItemData");

	MarkNativeAsOptional("EStore_GetUserBankInfo");
	MarkNativeAsOptional("EStore_DepositUserBankMoney");
	MarkNativeAsOptional("EStore_WithdrawUserBankMoney");
	MarkNativeAsOptional("EStore_GetTop10Bank");´

	MarkNativeAsOptional("EStore_PrecacheAllItems");
}
#endif
