#pragma semicolon 1
#pragma tabsize 0

#include <sourcemod>
#include <sdktools>
#include <estore/estore-commons>
#include <json>

#if !defined REQUIRE_PLUGIN
	#define REQUIRE_PLUGIN
#endif
#include <estore/estore-core>
#include <estore/estore-backend>
#include <estore/estore-logging>
#include <estore/estore-inventory>

#define ESTORE_MODEL_FLAG_PLAYER_MODEL		1 << 0
#define ESTORE_MODEL_FLAG_GRENADE_MODEL		1 << 1

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("estore-model");
	return APLRes_Success;
}

public Plugin:myinfo =
{
	name = "[ES] Model",
	author = ESTORE_AUTHOR,
	description = "Model component for [ES]",
	version = ESTORE_VERSION,
	url = ESTORE_URL
};

enum MODEL_PlayerInfo
{
	MODEL_Flags,
    String:MODEL_PlayerModel[PLATFORM_MAX_PATH],
	String:MODEL_GrenadeModel[PLATFORM_MAX_PATH]
};
new g_aModelPlayerInfos[MAXPLAYERS + 1][MODEL_PlayerInfo];

public OnPluginStart()
{
	PrintToServer("[ES] MODEL COMPONENT LOADED.");

	LoadConfig();

	HookEvent("player_spawn", OnPlayerSpawnEvent, EventHookMode_Post);
	HookEvent("weapon_fire", OnWeaponFireEvent, EventHookMode_Post);
}

public OnClientDisconnect(client)
{
	g_aModelPlayerInfos[client][MODEL_Flags] = 0;
}

public EStore_OnInventoryPluginLoaded()
{
	switch(EStore_RegisterItemType("playermodel", OnPrecacheModel))
	{
		case ESTORE_REGISTER_ITEM_TYPE_SUCCESS:
		{
			EStore_LogInfo("Successfully registered item type 'playermodel'!");
		}
		case ESTORE_REGISTER_ITEM_TYPE_ERROR:
		{
			EStore_LogError("RegisterItemType 'playermodel' failed!");
		}
		case ESTORE_REGISTER_ITEM_TYPE_ALREADY_REGISTERED:
		{
			EStore_LogWarning("RegisterItemType 'playermodel' is already registered!");
		}
	}
	switch(EStore_RegisterItemType("grenademodel", OnPrecacheModel))
	{
		case ESTORE_REGISTER_ITEM_TYPE_SUCCESS:
		{
			EStore_LogInfo("Successfully registered item type 'grenademodel'!");
		}
		case ESTORE_REGISTER_ITEM_TYPE_ERROR:
		{
			EStore_LogError("RegisterItemType 'grenademodel' failed!");
		}
		case ESTORE_REGISTER_ITEM_TYPE_ALREADY_REGISTERED:
		{
			EStore_LogWarning("RegisterItemType 'grenademodel' is already registered!");
		}
	}
	EStore_LogDebug("test!");	
}

LoadConfig()
{
	new Handle:kv = CreateKeyValues("root");

	decl String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/estore/estore_model.cfg");

	if (!FileToKeyValues(kv, path))
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	CloseHandle(kv);
}

public OnPrecacheModel(const String:json[], jsonLenght)
{
	if(jsonLenght <= 2)
	{
		return;
	}

    decl String:model[PLATFORM_MAX_PATH];
    if(!GetModelFromJson(json, model))
    {
        EStore_LogError("GetModelFromJson: '%s' failed", json);
        return;
    }
    if(PrecacheModel(model, true) == 0)
    {
        EStore_LogError("PrecacheModel: '%s' failed", json);
        return;
    }
    AddFileToDownloadsTable(model);
	
}

public Action:EStore_OnUseItem(client, itemIndex, const String:itemtype[ESTORE_MAX_TYPE_LENGTH])
{
	if(strcmp("playermodel", itemtype, false) == 0)
	{
		if(IsValidClient(client))
		{
			EStore_GetItemData(itemIndex, OnPlayerModelGetItemDataCallback, client);
			return Plugin_Handled;
		}
	}
	else if(strcmp("grenademodel", itemtype, false) == 0)
	{
		if(IsValidClient(client))
		{
			EStore_GetItemData(itemIndex, OnGrenadeModelGetItemDataCallback, client);
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

bool:GetModelFromJson(const String:json[], String:model[PLATFORM_MAX_PATH])
{
	new Handle:hJson = DecodeJSON(json);
	if(hJson == INVALID_HANDLE) 
	{ 
		EStore_LogError("failed to decode json: %s",json);
		return false;
	}
	if(!JSONGetString(hJson, "model", model, sizeof(model)))
	{
		EStore_LogError("failed to retrieve 'model' key from json: %s", json);
		return false;
	}
	
	DestroyJSON(hJson);
	return true;
}

public OnPlayerModelGetItemDataCallback(const String:json[], jsonLenght, any:client)
{
	if(jsonLenght <= 2)
	{
		return;
	}
    if(!IsValidClient(client))
	{
		return;
	}
	decl String:model[PLATFORM_MAX_PATH];
    if(!GetModelFromJson(json, model))
    {
        EStore_LogError("GetModelFromJson: '%s' failed", json);
        return;
    }
	g_aModelPlayerInfos[client][MODEL_Flags] = g_aModelPlayerInfos[client][MODEL_Flags] | ESTORE_MODEL_FLAG_PLAYER_MODEL;
    strcopy(g_aModelPlayerInfos[client][MODEL_PlayerModel], PLATFORM_MAX_PATH, model);
    SetEntityModel(client, model);
}

public OnGrenadeModelGetItemDataCallback(const String:json[], jsonLenght, any:client)
{
	if(jsonLenght <= 2)
	{
		return;
	}
    if(!IsValidClient(client))
	{
		return;
	}
	decl String:model[PLATFORM_MAX_PATH];
    if(!GetModelFromJson(json, model))
    {
        EStore_LogError("GetModelFromJson: '%s' failed", json);
        return;
    }
	g_aModelPlayerInfos[client][MODEL_Flags] = g_aModelPlayerInfos[client][MODEL_Flags] | ESTORE_MODEL_FLAG_GRENADE_MODEL;
    strcopy(g_aModelPlayerInfos[client][MODEL_GrenadeModel], PLATFORM_MAX_PATH, model);
}


public Action:OnPlayerSpawnEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(g_aModelPlayerInfos[client][MODEL_Flags] & ESTORE_MODEL_FLAG_PLAYER_MODEL == ESTORE_MODEL_FLAG_PLAYER_MODEL)
    {
    	SetEntityModel(client, g_aModelPlayerInfos[client][MODEL_PlayerModel]);
	}
	return Plugin_Continue;
}


public Action:OnWeaponFireEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new String:weapon[12];
	GetEventString(event, "weapon", weapon, sizeof(weapon));
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}
	if (strcmp(weapon, "hegrenade", false) != 0)
	{
		return Plugin_Continue;
	}

	if(g_aModelPlayerInfos[client][MODEL_Flags] & ESTORE_MODEL_FLAG_GRENADE_MODEL == ESTORE_MODEL_FLAG_GRENADE_MODEL)
    {
		CreateTimer(0.1, SetGranadeModelCallback, client, TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

public Action:SetGranadeModelCallback(Handle:timer, any:client)
{
	if(IsValidClient(client))
	{
		new ent = -1;
		while((ent = FindEntityByClassname(ent, "hegrenade_projectile")) != -1)
		{
			if (IsValidEntity(ent) && GetEntPropEnt(ent, Prop_Send, "m_hThrower") == client)
			{
				SetEntityModel(ent, g_aModelPlayerInfos[client][MODEL_GrenadeModel]);
				break;		
			}
		}
	}
	return Plugin_Handled;
}