#pragma semicolon 1
#pragma tabsize 0

#include <sourcemod>
#include <sdktools>
#include <estore/estore-core>
#include <estore/estore-backend>
#include <estore/estore-logging>
#include <estore/estore-commons>
#include <estore/estore-shop>

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    CreateNative("EStore_OpenShop", Native_OpenShop);
    CreateNative("EStore_OpenShopCategory", Native_OpenShopCategory);

	RegPluginLibrary("estore-shop");
	return APLRes_Success;
}

public Plugin:myinfo =
{
	name = "[ES] Shop",
	author = ESTORE_AUTHOR,
	description = "Shop component for [ES]",
	version = ESTORE_VERSION,
	url = ESTORE_URL
};

new String:g_sCurrencyName[64];

new g_iShopCommandCount;
new String:g_sShopCommands[6][32];

new g_iMainMenuItemOrder = 0;

new bool:g_bCategoryMenuReload = false;
new bool:g_bEnableCategoryDescriptions = false;

public OnPluginStart()
{
	PrintToServer("[ES] SHOP COMPONENT LOADED.");

	LoadConfig();

    LoadTranslations("common.phrases");
	LoadTranslations("estore.shop.phrases");
    LoadTranslations("estore.categories.phrases");
    LoadTranslations("estore.items.phrases");

    AddCommandListener(CmdSayCallback, "say");
	AddCommandListener(CmdSayCallback, "say_team");
}

public OnAllPluginsLoaded()
{
    EStore_GetCurrencyName(g_sCurrencyName, sizeof(g_sCurrencyName));
    EStore_AddMainMenuItem("shop", _, OnMainMenuShopItemPressed, g_iMainMenuItemOrder);
}

public EStore_PreCacheOrRealoadCategoriesStart()
{
    g_bCategoryMenuReload = true;
}

public EStore_PreCacheOrRealoadCategoriesFinished(count)
{
    g_bCategoryMenuReload = false;
}

LoadConfig()
{
	new Handle:kv = CreateKeyValues("root");

	decl String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/estore/estore_shop.cfg");

	if (!FileToKeyValues(kv, path))
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

    decl String:shopCommands[6 * 33];
    KvGetString(kv, "shop_commands", shopCommands, sizeof(shopCommands), "!shop /shop");
    g_iShopCommandCount = ExplodeString(shopCommands, " ", g_sShopCommands, sizeof(g_sShopCommands), sizeof(g_sShopCommands[]));

    g_iMainMenuItemOrder = KvGetNum(kv, "main_menu_item_order", 0);
    g_bEnableCategoryDescriptions = bool:KvGetNum(kv, "enable_category_descriptions", 0);

	CloseHandle(kv);
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

	for (new i = 0; i < g_iShopCommandCount; i++)
	{
		if (StrEqual(g_sShopCommands[i], text))
		{
			OpenShop(client);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public OnMainMenuShopItemPressed(client, const String:value[ESTORE_MAX_MENUITEM_VALUE_LENGHT])
{
    OpenShop(client);
}

public Native_OpenShop(Handle:plugin, num_params)
{
	OpenShop(GetNativeCell(1));
}

OpenShop(client)
{
    if(IsValidClient(client))
    {
        EStore_GetUserInfo(client, ShopGetUserInfoCallback);
    }
}

public ShopGetUserInfoCallback(client, credits, erg_index, const String:erg_name[ESTORE_MAX_NAME_LENGTH], erg_flag, any:data)
{
    if(g_bCategoryMenuReload)
    {
        CPrintToChat(client, "%s%t", ESTORE_PREFIX, "shop_currently_unavailable");
        return;
    }
    new count = 0;
    if(!EStore_GetCategoryCount(count))
    {
        return;
    }

    new Handle:menu = CreateMenu(CategoryMenuSelectHandleCallback);
    SetMenuTitle(menu, "%t", "shop_menu_titel", credits, g_sCurrencyName);

    for(new index = 0; index < count; index++)
    {
        new catIndex = 0;
        decl String:catName[ESTORE_MAX_NAME_LENGTH];
        decl String:catRequirePlugin[ESTORE_MAX_REQUIREPLUGIN_LENGTH];
        decl String:catDescription[ESTORE_MAX_DESCRIPTION_LENGTH];
        new catOrder = 0;
        new catFlag = 0;
        if(EStore_GetCategoryInfo2(index, catIndex, catName, catRequirePlugin, catDescription, catOrder, catFlag))
        {
            // cat_NAME
            decl String:tDisplayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
            Format(tDisplayName, sizeof(tDisplayName), "cat_%s", catName);
            // cat_NAME_desc
            decl String:tDescription[ESTORE_MAX_DESCRIPTION_LENGTH];
            Format(tDescription, sizeof(tDescription), "cat_%s_desc", catName);

            decl String:text[255];
            Format(text, sizeof(text), "%t", tDisplayName);
            if(g_bEnableCategoryDescriptions)
            {
                Format(text, sizeof(text), "%s\n  - %t", text, tDescription);
            }
            decl String:value[11 + ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
            Format(value, sizeof(value), "%d,%s", catIndex, tDisplayName);

            AddMenuItem(menu, value, text, ITEMDRAW_DEFAULT);
        }
    }

    SetMenuExitButton(menu, true);
    DisplayMenu(menu, client, 0);
}


CategoryMenuSelectHandleCallback(Handle:menu, MenuAction:action, client, item)
{
	switch (action)
	{
		case MenuAction_Select:
		{
            decl String:sCategoryValue[11 + ESTORE_MAX_NAME_LENGTH];
            if(GetMenuItem(menu, item, sCategoryValue, sizeof(sCategoryValue), _, _, _))
            {
                decl String:sCategoryValueE[2][ESTORE_MAX_NAME_LENGTH];
                if(ExplodeString(sCategoryValue, ",", sCategoryValueE, sizeof(sCategoryValueE), sizeof(sCategoryValueE[])) != 2)
                {
                    EStore_LogError("CategoryMenuSelectHandleCallback - ExplodeString invalid count...");
                    return;
                }
                OpenShopCategory(client, StringToInt(sCategoryValueE[0]), sCategoryValueE[1]);
            }
            else
            {
                EStore_LogError("CategoryMenuSelectHandleCallback - GetMenuItem failed...");
            }
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Native_OpenShopCategory(Handle:plugin, num_params)
{
    decl String:categoryDisplayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
    GetNativeString(3, categoryDisplayName, sizeof(categoryDisplayName));
	OpenShopCategory(GetNativeCell(1), GetNativeCell(2), categoryDisplayName);
}

OpenShopCategory(client, categoryIndex, String:categoryDisplayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT])
{
    if(IsValidClient(client))
    {
        new Handle:pack = CreateDataPack();
        WritePackCell(pack, categoryIndex);
        WritePackString(pack, categoryDisplayName);
        EStore_GetUserInfo(client, CategoryGetUserInfoCallback, pack);
    }
}

public CategoryGetUserInfoCallback(client, credits, erg_index, const String:erg_name[ESTORE_MAX_NAME_LENGTH], erg_flag, any:cInfoPack)
{
    decl String:categoryDisplayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
    ResetPack(cInfoPack);
    new categoryIndex = ReadPackCell(cInfoPack);
    ReadPackString(cInfoPack, categoryDisplayName, sizeof(categoryDisplayName));
    CloseHandle(cInfoPack);

    new Handle:pack = CreateDataPack();
    WritePackCell(pack, client);
    WritePackCell(pack, credits);
    WritePackString(pack, categoryDisplayName);

    new Handle:filter = CreateTrie();
    SetTrieValue(filter, "team_only", GetClientTeam(client), false);
    SetTrieValue(filter, "is_buyable_from", erg_flag, false);

    EStore_GetItemsInfo(categoryIndex, filter, OpenShopCategoryCallback, pack);
}

public OpenShopCategoryCallback(Handle:infos[], count, any:pack)
{
    decl String:categoryDisplayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
    ResetPack(pack);
    new client = ReadPackCell(pack);
    new credits = ReadPackCell(pack);
    ReadPackString(pack, categoryDisplayName, sizeof(categoryDisplayName));
    CloseHandle(pack);

    new Handle:menu = CreateMenu(ItemMenuSelectHandleCallback);
    Format(categoryDisplayName, sizeof(categoryDisplayName), "%t", categoryDisplayName);
    SetMenuTitle(menu, "%t", "shop_category_menu_titel", credits, g_sCurrencyName, categoryDisplayName);

    for(new i = 0; i < count; i++)
    {
        new Handle:info = infos[i];

        ResetPack(info);
		new index = ReadPackCell(info);
        decl String:iName[ESTORE_MAX_NAME_LENGTH];
		ReadPackString(info, iName, sizeof(iName));
		new price = ReadPackCell(info);
		new expire_after = ReadPackCell(info);
        CloseHandle(info);

        // item_NAME
        decl String:iDisplayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
        Format(iDisplayName, sizeof(iDisplayName), "item_%s", iName);
        new String:iExpireText[32];
        if(expire_after > 0)
        {
            Format(iExpireText, sizeof(iExpireText), "%t", "item_expires_after", expire_after);
        }
        decl String:text[255];
        Format(text, sizeof(text), "%t%t", iDisplayName, "item_cost_info", price, g_sCurrencyName, iExpireText);

        decl String:value[21 + 11 + ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT + ESTORE_MAX_NAME_LENGTH + 3];
        Format(value, sizeof(value), "%d,%d,%s,%s", index, price, categoryDisplayName, iName);

        if(price <= credits)
        {
            AddMenuItem(menu, value, text, ITEMDRAW_DEFAULT);
        }
        else
        {
            AddMenuItem(menu, value, text, ITEMDRAW_DISABLED);
        }
    }

    SetMenuExitButton(menu, true);
    DisplayMenu(menu, client, 0);
}

ItemMenuSelectHandleCallback(Handle:menu, MenuAction:action, client, item)
{
	switch (action)
	{
		case MenuAction_Select:
		{
            decl String:sItemInfo[21 + 11 + ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT + ESTORE_MAX_NAME_LENGTH + 3];
            if(GetMenuItem(menu, item, sItemInfo, sizeof(sItemInfo), _, _, _))
            {
                decl String:sItemInfoE[4][ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
                if(ExplodeString(sItemInfo, ",", sItemInfoE, sizeof(sItemInfoE), sizeof(sItemInfoE[])) != 4)
                {
                    EStore_LogError("ItemMenuSelectHandleCallback - ExplodeString invalid count...");
                    return;
                }
                new Handle:pack = CreateDataPack();
                WritePackCell(pack, StringToInt(sItemInfoE[1]));
                WritePackString(pack, sItemInfoE[2]);
                WritePackString(pack, sItemInfoE[3]);

                EStore_GiveUserItem(client, StringToInt(sItemInfoE[0]), OnGiveUserItemCallback, pack);
            }
            else
            {
                EStore_LogError("ItemMenuSelectHandleCallback - GetMenuItem failed...");
            }
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public OnGiveUserItemCallback(client, itemIndex, bool:success, any:pack)
{
    decl String:categoryDisplayName[ESTORE_MAX_NAME_LENGTH];
    decl String:iDisplayName[ESTORE_MAX_NAME_LENGTH];

    ResetPack(pack);
    new price = ReadPackCell(pack);
    ReadPackString(pack, categoryDisplayName, sizeof(categoryDisplayName));
    ReadPackString(pack, iDisplayName, sizeof(iDisplayName));
    CloseHandle(pack);

    if(success)
    {
        EStore_TakeCreditsFromUser(GetSteamAccountID(client), price);
        CPrintToChat(client, "%s%t", ESTORE_PREFIX, "shop_buy_item_success", categoryDisplayName, iDisplayName);
    }
    else
    {
        CPrintToChat(client, "%s%t", ESTORE_PREFIX, "shop_buy_item_duplicate", categoryDisplayName, iDisplayName);
    }
}
