#pragma semicolon 1
#pragma tabsize 0

#include <sourcemod>
#include <estore/estore-commons>

#if !defined REQUIRE_PLUGIN
	#define REQUIRE_PLUGIN
#endif
#include <estore/estore-core>
#include <estore/estore-backend>
#include <estore/estore-logging>

#include <estore/estore-inventory>

new Handle:g_hOnItemUsedForward = INVALID_HANDLE;
new Handle:g_hOnPluginLoadedForward = INVALID_HANDLE;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    CreateNative("EStore_RegisterItemType", Native_RegisterItemType);
    CreateNative("EStore_IsItemTypeRegistered", Native_IsItemTypeRegistered);

    g_hOnItemUsedForward = CreateGlobalForward("EStore_OnUseItem", ET_Event, Param_Cell, Param_Cell, Param_String);
    g_hOnPluginLoadedForward = CreateGlobalForward("EStore_OnInventoryPluginLoaded", ET_Ignore);

	RegPluginLibrary("estore-inventory");
	return APLRes_Success;
}

public Plugin:myinfo =
{
	name = "[ES] Inventory",
	author = ESTORE_AUTHOR,
	description = "Inventory component for [ES]",
	version = ESTORE_VERSION,
	url = ESTORE_URL
};

new String:g_sCurrencyName[64];

new g_iInventoryCommandCount;
new String:g_sInventoryCommands[6][32];

new g_iMainMenuItemOrder = 0;

enum ItemTypeInfo
{
    EStore_PrecacheItemTypeCallback:ItemTypeInfoCallback,
    Handle:ItemTypeInfoPlugin
};
new g_aItemTypes[32][ItemTypeInfo];
new g_iItemTypeIndex = 0;
new Handle:g_hItemTypeOffset = INVALID_HANDLE;

new bool:g_bCategoryMenuReload = false;
new bool:g_bEnableCategoryDescriptions = false;

new bool:g_bIsDatabaseInitialized = false;


public OnPluginStart()
{
	PrintToServer("[ES] INVENTORY COMPONENT LOADED.");

	LoadConfig();

    LoadTranslations("common.phrases");
    LoadTranslations("estore.inventory.phrases");
    LoadTranslations("estore.categories.phrases");
    LoadTranslations("estore.items.phrases");

    AddCommandListener(CmdSayCallback, "say");
	AddCommandListener(CmdSayCallback, "say_team");
}

public OnAllPluginsLoaded()
{
    EStore_GetCurrencyName(g_sCurrencyName, sizeof(g_sCurrencyName));
    EStore_AddMainMenuItem("inventory", _, OnMainMenuInventoryItemPressed, g_iMainMenuItemOrder);

    Call_StartForward(g_hOnPluginLoadedForward);
    Call_Finish();
}

public OnMapStart()
{
    //NÖTIG?
    if(g_bIsDatabaseInitialized)
    {
        EStore_PrecacheAllItems(PrecacheAllItemsCallback);
    }
}

public EStore_OnDatabaseInitialized()
{
    g_bIsDatabaseInitialized = true;
	EStore_PrecacheAllItems(PrecacheAllItemsCallback);
}

public PrecacheAllItemsCallback(Handle:infos[], count, any:data)
{
    for(new i = 0; i < count; i++)
    {
        new Handle:info = infos[i];

        ResetPack(info);     
        decl String:iType[ESTORE_MAX_TYPE_LENGTH];
		ReadPackString(info, iType, sizeof(iType));
        new iDataLenght = ReadPackCell(info);
        decl String:iData[iDataLenght];
		ReadPackString(info, iData, iDataLenght);
        CloseHandle(info);

        new itemTypeOffset;
	    if(GetTrieValue(g_hItemTypeOffset, iType, itemTypeOffset))
        {          
            new EStore_PrecacheItemTypeCallback:callback = g_aItemTypes[itemTypeOffset][ItemTypeInfoCallback];
            if(callback != INVALID_FUNCTION)
            {
                Call_StartFunction(g_aItemTypes[itemTypeOffset][ItemTypeInfoPlugin], callback);
                Call_PushString(iData);
                Call_PushCell(iDataLenght);
                Call_Finish();
            }      
        }
    }
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
	BuildPath(Path_SM, path, sizeof(path), "configs/estore/estore_inventory.cfg");

	if (!FileToKeyValues(kv, path))
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

    decl String:inventoryCommands[6 * 33];
    KvGetString(kv, "inventory_commands", inventoryCommands, sizeof(inventoryCommands), "!inv /inv");
    g_iInventoryCommandCount = ExplodeString(inventoryCommands, " ", g_sInventoryCommands, sizeof(g_sInventoryCommands), sizeof(g_sInventoryCommands[]));

    g_iMainMenuItemOrder = KvGetNum(kv, "main_menu_item_order", 1);
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

	for (new i = 0; i < g_iInventoryCommandCount; i++)
	{
		if (StrEqual(g_sInventoryCommands[i], text))
		{
			OpenInventory(client);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public _:Native_RegisterItemType(Handle:plugin, num_params)
{
    decl String:itemType[ESTORE_MAX_TYPE_LENGTH];
    GetNativeString(1, itemType, sizeof(itemType));
    return RegisterItemType(itemType, EStore_PrecacheItemTypeCallback:GetNativeFunction(2), plugin);
}

_:RegisterItemType(const String:type[], EStore_PrecacheItemTypeCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE)
{
    if(g_hItemTypeOffset == INVALID_HANDLE)
    {
        g_hItemTypeOffset = CreateTrie();
    }

    new itemTypeOffset = -1;
    if(GetTrieValue(g_hItemTypeOffset, type, itemTypeOffset))
    {
        return ESTORE_REGISTER_ITEM_TYPE_ALREADY_REGISTERED;
    }

    if(!SetTrieValue(g_hItemTypeOffset, type, g_iItemTypeIndex))
    {
        return ESTORE_REGISTER_ITEM_TYPE_ERROR;
    }

    g_aItemTypes[g_iItemTypeIndex][ItemTypeInfoCallback] = callback;
    g_aItemTypes[g_iItemTypeIndex][ItemTypeInfoPlugin] = plugin;
    g_iItemTypeIndex++;
    return ESTORE_REGISTER_ITEM_TYPE_SUCCESS;
}

public Native_IsItemTypeRegistered(Handle:plugin, params)
{
	decl String:type[ESTORE_MAX_TYPE_LENGTH];
	GetNativeString(1, type, sizeof(type));

	new itemTypeOffset;
	return GetTrieValue(g_hItemTypeOffset, type, itemTypeOffset);
}

public OnMainMenuInventoryItemPressed(client, const String:value[ESTORE_MAX_MENUITEM_VALUE_LENGHT])
{
    OpenInventory(client);
}

OpenInventory(client)
{
    if(IsValidClient(client))
    {
        EStore_GetUserInfo(client, InventoryGetUserInfoCallback);
    }
}

public InventoryGetUserInfoCallback(client, credits, erg_index, const String:erg_name[ESTORE_MAX_NAME_LENGTH], erg_flag, any:data)
{
    if(g_bCategoryMenuReload)
    {
        CPrintToChat(client, "%s%t", ESTORE_PREFIX, "inventory_currently_unavailable");
        return;
    }
    new count = 0;
    if(!EStore_GetCategoryCount(count))
    {
        return;
    }

    new Handle:menu = CreateMenu(CategoryMenuSelectHandleCallback);
    SetMenuTitle(menu, "%t", "inventory_menu_titel", credits, g_sCurrencyName);

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
            decl String:value[11 + ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT + 1];
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
            decl String:sCategoryInfo[11 + ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT + 1];
            if(GetMenuItem(menu, item, sCategoryInfo, sizeof(sCategoryInfo), _, _, _))
            {
                decl String:sCategoryInfoE[2][ESTORE_MAX_NAME_LENGTH];
                if(ExplodeString(sCategoryInfo, ",", sCategoryInfoE, sizeof(sCategoryInfoE), sizeof(sCategoryInfoE[])) != 2)
                {
                    EStore_LogError("CategoryMenuSelectHandleCallback - ExplodeString invalid count...");
                    return;
                }
                OpenInventoryCategory(client, StringToInt(sCategoryInfoE[0]), sCategoryInfoE[1]);
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

OpenInventoryCategory(client, categoryIndex, String:categoryDisplayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT])
{
    if(IsValidClient(client))
    {
        new Handle:pack = CreateDataPack();
        WritePackCell(pack, client);
        WritePackString(pack, categoryDisplayName);

        new Handle:filter = CreateTrie();
        SetTrieValue(filter, "team_only", GetClientTeam(client), false);

        EStore_GetUserItemsOfCategory(client, categoryIndex, filter, OpenInventoryCategoryCallback, pack);     
    }
}

public OpenInventoryCategoryCallback(Handle:infos[], count, any:pack)
{
    decl String:categoryDisplayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
    ResetPack(pack);
    new client = ReadPackCell(pack);
    ReadPackString(pack, categoryDisplayName, sizeof(categoryDisplayName));
    CloseHandle(pack);

    new Handle:menu = CreateMenu(ItemMenuSelectHandleCallback);
    Format(categoryDisplayName, sizeof(categoryDisplayName), "%t", categoryDisplayName);
    SetMenuTitle(menu, "%t", "inventory_category_menu_titel", categoryDisplayName);

    for(new i = 0; i < count; i++)
    {
        new Handle:info = infos[i];

        ResetPack(info);
		new iIndex = ReadPackCell(info);
        decl String:iName[ESTORE_MAX_NAME_LENGTH];
		ReadPackString(info, iName, sizeof(iName));
        decl String:iType[ESTORE_MAX_TYPE_LENGTH];
		ReadPackString(info, iType, sizeof(iType));
		new expire_in = ReadPackCell(info);
        CloseHandle(info);

        // item_NAME
        decl String:iDisplayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT];
        Format(iDisplayName, sizeof(iDisplayName), "item_%s", iName);

        new String:iExpireText[32];
        if(expire_in >= 0)
        {
            new days = (expire_in % (86400 * 30)) / 86400;
            new hours = (expire_in % 86400) / 3600;
            new minutes = (expire_in % 3600) / 60;
            new seconds = (expire_in % 60);

            Format(iExpireText, sizeof(iExpireText), "%t", "item_expires_in", days, hours, minutes, seconds);
        }

        decl String:text[255];
        Format(text, sizeof(text), "%t%s", iDisplayName, iExpireText);

        decl String:value[11 + ESTORE_MAX_TYPE_LENGTH + 2];
        Format(value, sizeof(value), "%d,%s", iIndex, iType);

        AddMenuItem(menu, value, text, ITEMDRAW_DEFAULT);      
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
            decl String:sItemInfo[11 + ESTORE_MAX_TYPE_LENGTH + 2];
            if(GetMenuItem(menu, item, sItemInfo, sizeof(sItemInfo), _, _, _))
            {
                decl String:sItemInfoE[2][ESTORE_MAX_TYPE_LENGTH];
                if(ExplodeString(sItemInfo, ",", sItemInfoE, sizeof(sItemInfoE), sizeof(sItemInfoE[])) != 2)
                {
                    EStore_LogError("ItemMenuSelectHandleCallback - ExplodeString invalid count...");
                    return;
                }

                Call_StartForward(g_hOnItemUsedForward);
                Call_PushCell(client);
                Call_PushCell(StringToInt(sItemInfoE[0]));
                Call_PushString(sItemInfoE[1]);
                Call_Finish();
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