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

#define ESTORE_COLOR_FLAG_GLOW 		1 << 0
#define ESTORE_COLOR_FLAG_SMOKE 	1 << 1
#define ESTORE_COLOR_FLAG_LASER 	1 << 2

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("estore-color");
	return APLRes_Success;
}

public Plugin:myinfo =
{
	name = "[ES] Color",
	author = ESTORE_AUTHOR,
	description = "Color component for [ES]",
	version = ESTORE_VERSION,
	url = ESTORE_URL
};

enum COLOR_PlayerInfo
{
	COLOR_Flags,
	any:COLOR_Data[3],
};
new g_aColorPlayerInfos[MAXPLAYERS + 1][COLOR_PlayerInfo];

new g_iPrechachedLaserModelIndex = 0;

new Float:g_fLaserColorLifetime = 0.4;
new Float:g_fLaserColorStartWidth = 0.4;
new Float:g_fLaserColorEndWidth = 0.4;
new Float:g_fLaserColorAmplitude = 0.1;
new String:g_sLaserColorModel[PLATFORM_MAX_PATH];


//new Handle:g_hEstoreGameConfig = INVALID_HANDLE;
//new Handle:g_hGetAttachmentPrepSDKCall = INVALID_HANDLE;
//new Handle:g_hLookupAttachmentPrepSDKCall = INVALID_HANDLE;

public OnPluginStart()
{
	PrintToServer("[ES] COLOR COMPONENT LOADED.");

	LoadConfig();

	HookEvent("smokegrenade_detonate", OnSmokeDetonateEvent, EventHookMode_Pre);
	HookEvent("bullet_impact", OnBulletImpactEvent);

	/*g_hEstoreGameConfig = LoadGameConfigFile("estore.games");
	if(g_hEstoreGameConfig == INVALID_HANDLE)
	{
		SetFailState("LoadGameConfigFile 'estore.games' failed!");
	}*/

	/*StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(g_hEstoreGameConfig, SDKConf_Signature, "GetAttachment");
	PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByValue);
    PrepSDKCall_AddParameter(SDKType_PlainOldData , SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Vector , SDKPass_ByValue);
    PrepSDKCall_AddParameter(SDKType_QAngle , SDKPass_ByValue);
	if((g_hGetAttachmentPrepSDKCall = EndPrepSDKCall()) == INVALID_HANDLE)
	{
		SetFailState("EndPrepSDKCall 'g_hGetAttachmentPrepSDKCall' failed!");
	}*/

	/*StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(g_hEstoreGameConfig, SDKConf_Signature, "LookupAttachment");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if((g_hLookupAttachmentPrepSDKCall = EndPrepSDKCall()) == INVALID_HANDLE)
	{
		SetFailState("EndPrepSDKCall 'g_hLookupAttachmentPrepSDKCall' failed!");
	}*/
}

public OnMapStart()
{
	if((g_iPrechachedLaserModelIndex = PrecacheModel(g_sLaserColorModel, true)) == 0)
	{
		EStore_LogError("Can't precache model:'%s'", g_sLaserColorModel);
	}
	AddFileToDownloadsTable(g_sLaserColorModel);
}

public OnClientDisconnect(client)
{
	g_aColorPlayerInfos[client][COLOR_Flags] = 0;
}

public EStore_OnInventoryPluginLoaded()
{
	switch(EStore_RegisterItemType("glowcolor"))
	{
		case ESTORE_REGISTER_ITEM_TYPE_SUCCESS:
		{
			EStore_LogInfo("Successfully registered item type 'glowcolor'!");
		}
		case ESTORE_REGISTER_ITEM_TYPE_ERROR:
		{
			EStore_LogError("RegisterItemType 'glowcolor' failed!");
		}
		case ESTORE_REGISTER_ITEM_TYPE_ALREADY_REGISTERED:
		{
			EStore_LogWarning("RegisterItemType 'glowcolor' is already registered!");
		}
	}
	switch(EStore_RegisterItemType("smokecolor"))
	{
		case ESTORE_REGISTER_ITEM_TYPE_SUCCESS:
		{
			EStore_LogInfo("Successfully registered item type 'smokecolor'!");
		}
		case ESTORE_REGISTER_ITEM_TYPE_ERROR:
		{
			EStore_LogError("RegisterItemType 'smokecolor' failed!");
		}
		case ESTORE_REGISTER_ITEM_TYPE_ALREADY_REGISTERED:
		{
			EStore_LogWarning("RegisterItemType 'smokecolor' is already registered!");
		}
	}
	switch(EStore_RegisterItemType("lasercolor"))
	{
		case ESTORE_REGISTER_ITEM_TYPE_SUCCESS:
		{
			EStore_LogInfo("Successfully registered item type 'lasercolor'!");
		}
		case ESTORE_REGISTER_ITEM_TYPE_ERROR:
		{
			EStore_LogError("RegisterItemType 'lasercolor' failed!");
		}
		case ESTORE_REGISTER_ITEM_TYPE_ALREADY_REGISTERED:
		{
			EStore_LogWarning("RegisterItemType 'lasercolor' is already registered!");
		}
	}
}

LoadConfig()
{
	new Handle:kv = CreateKeyValues("root");

	decl String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/estore/estore_color.cfg");

	if (!FileToKeyValues(kv, path))
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	KvGetString(kv, "laser_color_model", g_sLaserColorModel, sizeof(g_sLaserColorModel), "materials/sprites/laserbeam.vmt");
	KvGetNum(kv, "main_menu_item_order", 0);

	g_fLaserColorLifetime = KvGetFloat(kv, "laser_color_lifetime", 0.4);
	g_fLaserColorStartWidth = KvGetFloat(kv, "laser_color_startwidth", 0.4);
	g_fLaserColorEndWidth = KvGetFloat(kv, "laser_color_endwidth", 0.4);
	g_fLaserColorAmplitude = KvGetFloat(kv, "laser_color_amplitude", 0.1);

	CloseHandle(kv);
}

public Action:EStore_OnUseItem(client, itemIndex, const String:itemtype[ESTORE_MAX_TYPE_LENGTH])
{
	if(strcmp("glowcolor", itemtype, false) == 0)
	{
		if(IsValidClient(client))
		{
			EStore_GetItemData(itemIndex, OnGlowColorGetItemDataCallback, client);
			return Plugin_Handled;
		}
	}
	else if(strcmp("smokecolor", itemtype, false) == 0)
	{
		if(IsValidClient(client))
		{
			EStore_GetItemData(itemIndex, OnSmokeColorGetItemDataCallback, client);
			return Plugin_Handled;
		}
	}
	else if(strcmp("lasercolor", itemtype, false) == 0)
	{
		if(IsValidClient(client))
		{
			EStore_GetItemData(itemIndex, OnLaserColorGetItemDataCallback, client);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

bool:GetRGBAFromJson(const String:json[], &r, &g, &b, &a)
{
	new Handle:hJson = DecodeJSON(json);
	if(hJson == INVALID_HANDLE) 
	{ 
		EStore_LogError("failed to decode json: %s", json);
		return false;
	}
	if(!JSONGetInteger(hJson, "r", r))
	{
		EStore_LogError("failed to retrieve 'r' key from json: %s", json);
		return false;
	}
	if(!JSONGetInteger(hJson, "g", g))
	{
		EStore_LogError("failed to retrieve 'g' key from json: %s", json);
		return false;
	}
	if(!JSONGetInteger(hJson, "b", b))
	{
		EStore_LogError("failed to retrieve 'b' key from json: %s", json);
		return false;
	}
	if(!JSONGetInteger(hJson, "a", a))
	{
		EStore_LogError("failed to retrieve 'a' key from json: %s", json);
		return false;
	}
	DestroyJSON(hJson);
	return true;
}

public OnGlowColorGetItemDataCallback(const String:json[], jsonLenght, any:client)
{
	if(!IsValidClient(client))
	{
		return;
	}
	new r, g, b , a;
	if(GetRGBAFromJson(json, r, g, b, a))
	{
		if(!(g_aColorPlayerInfos[client][COLOR_Flags] & ESTORE_COLOR_FLAG_SMOKE == ESTORE_COLOR_FLAG_SMOKE))
		{
			g_aColorPlayerInfos[client][COLOR_Flags] = g_aColorPlayerInfos[client][COLOR_Flags] | ESTORE_COLOR_FLAG_GLOW;
		}
		g_aColorPlayerInfos[client][COLOR_Data][0] = r << 24 | g << 16 | b << 8 | a;
		EStore_SetGlow(client, r, g, b, a);
	}
}

public OnSmokeColorGetItemDataCallback(const String:json[], jsonLenght, any:client)
{
	if(!IsValidClient(client))
	{
		return;
	}
	new r, g, b , a;
	if(GetRGBAFromJson(json, r, g, b, a))
	{
		if(!(g_aColorPlayerInfos[client][COLOR_Flags] & ESTORE_COLOR_FLAG_SMOKE == ESTORE_COLOR_FLAG_SMOKE))
		{
			g_aColorPlayerInfos[client][COLOR_Flags] = g_aColorPlayerInfos[client][COLOR_Flags] | ESTORE_COLOR_FLAG_SMOKE;
		}
		g_aColorPlayerInfos[client][COLOR_Data][1] = r << 24 | g << 16 | b << 8 | a; 
	}
}

public OnLaserColorGetItemDataCallback(const String:json[], jsonLenght, any:client)
{
	if(!IsValidClient(client))
	{
		return;
	}
	new r, g, b , a;
	if(GetRGBAFromJson(json, r, g, b, a))
	{
		if(!(g_aColorPlayerInfos[client][COLOR_Flags] & ESTORE_COLOR_FLAG_LASER == ESTORE_COLOR_FLAG_LASER))
		{
			g_aColorPlayerInfos[client][COLOR_Flags] = g_aColorPlayerInfos[client][COLOR_Flags] | ESTORE_COLOR_FLAG_LASER;
		}
		g_aColorPlayerInfos[client][COLOR_Data][2] = r << 24 | g << 16 | b << 8 | a; 
	}
}

public Action:OnSmokeDetonateEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}
	if(!(g_aColorPlayerInfos[client][COLOR_Flags] & ESTORE_COLOR_FLAG_SMOKE == ESTORE_COLOR_FLAG_SMOKE))
	{
		return Plugin_Continue;
	}
	new entityID = GetEventInt(event, "entityid");
	if(!IsValidEntity(entityID))
	{
		return Plugin_Continue;
	}
	new Float:x = GetEventFloat(event, "x");
	new Float:y = GetEventFloat(event, "y");
	new Float:z = GetEventFloat(event, "z");

	new color = g_aColorPlayerInfos[client][COLOR_Data][1];
	new r = (color >> 24) & 0xFF;
	new g = (color >> 16) & 0xFF;
	new b = (color >> 8) & 0xFF;
	new a = color & 0xFF;

	return Plugin_Continue;
}

public Action:OnBulletImpactEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}
	if(!(g_aColorPlayerInfos[client][COLOR_Flags] & ESTORE_COLOR_FLAG_LASER == ESTORE_COLOR_FLAG_LASER))
	{
		return Plugin_Continue;
	}

	new color = g_aColorPlayerInfos[client][COLOR_Data][2];
	new aColor[4];
	aColor[0] = (color >> 24) & 0xFF;
	aColor[1] = (color >> 16) & 0xFF;
	aColor[2] = (color >> 8) & 0xFF;
	aColor[3] = color & 0xFF;

	new Float:bulletDestination[3];
	bulletDestination[0] = GetEventFloat(event, "x");
	bulletDestination[1] = GetEventFloat(event, "y");
	bulletDestination[2] = GetEventFloat(event, "z");


	new Float:origin[3];
	GetClientAbsOrigin(client, origin);
	origin[2] += 50;

	/*new weaponEnt = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", 0);
	if(IsValidEntity(weaponEnt))
	{
		//new Float:f_pos[3], Float:f_ang[3];
		SDKCall(g_hLookupAttachmentPrepSDKCall, client, "forward");
		//CPrintToChat(client, "%f %f %f", f_pos[0], f_pos[1], f_pos[2]);
	}*/

	TE_SetupBeamPoints(
		origin, 
		bulletDestination,
		g_iPrechachedLaserModelIndex,
		0,
		0,
		0,
		g_fLaserColorLifetime,		//duration
		g_fLaserColorStartWidth, 	//width
		g_fLaserColorEndWidth,		//end width
		1,							//fade duration
		g_fLaserColorAmplitude,		//amplitude
		aColor,
		1);
	TE_SendToAll();
	return Plugin_Continue;
}