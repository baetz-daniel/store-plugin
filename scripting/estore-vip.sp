#pragma semicolon 1
#pragma tabsize 0

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <estore/estore-commons>

#if !defined REQUIRE_PLUGIN
	#define REQUIRE_PLUGIN
#endif

#include <estore/estore-core>
#include <estore/estore-backend>
#include <estore/estore-logging>

#define ESTORE_DEFAULT_HEALTH 	100
#define ESTORE_DEFAULT_ARMOR 	100

#define ESTORE_HEGRENADE_OFFSET 		14
#define ESTORE_FLASHBANG_OFFSET 		15
#define ESTORE_SMOKEGRENADE_OFFSET		16
#define	ESTORE_INCENDERYGRENADE_OFFSET	17
#define	ESTORE_DECOYGRENADE_OFFSET		18

#define ESTORE_ROLL_THE_DICE_FLAG_SUNGLASSES 		1 << 0
#define ESTORE_ROLL_THE_DICE_FLAG_INVISIBLE 		1 << 1
#define ESTORE_ROLL_THE_DICE_FLAG_MIRROR_DAMAGE 	1 << 2
#define ESTORE_ROLL_THE_DICE_FLAG_VAMPIRE 			1 << 3
#define ESTORE_ROLL_THE_DICE_FLAG_DRUG 				1 << 4

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("estore-vip");
	return APLRes_Success;
}

public Plugin:myinfo =
{
	name = "[ES] VIP",
	author = ESTORE_AUTHOR,
	description = "VIP component for [ES]",
	version = ESTORE_VERSION,
	url = ESTORE_URL
};

new g_aVipGroupIndices[ESTORE_MAX_GROUPS] = {-1, ...};
new g_aBonusHealth[ESTORE_MAX_GROUPS];
new g_aBonusArmor[ESTORE_MAX_GROUPS];
new Float:g_aBonusMoveSpeed[ESTORE_MAX_GROUPS];
new Float:g_aFallDamageReduction[ESTORE_MAX_GROUPS];
new Float:g_aLifeScrewPerGrenadeDamage[ESTORE_MAX_GROUPS];

new g_iMaxHegrenades = 2;
new g_iMaxFlashbangs = 3;
new g_iMaxSmokegrenades = 1;
new g_iMaxIncenderygrenades = 1;
new g_iMaxDecoygrenades = 1;

new g_iRollTheDiceCommandCount;
new String:g_aRollTheDiceCommands[6][32];
new g_iRollTheDiceAnouncementCount = 3;
new g_aRollTheDiceAmountChecker[MAXPLAYERS + 1];

enum RTD_PlayerInfo
{
	RTD_Flags,
	any:RTD_Data[6],
};
new g_aRollTheDicePlayerInfos[MAXPLAYERS + 1][RTD_PlayerInfo];

new String:g_sOnHitSound[PLATFORM_MAX_PATH + 1];
new String:g_sOnHitSoundRelative[PLATFORM_MAX_PATH + 1];

new Float:g_DrugAngles[20] = {0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 20.0, 15.0, 10.0, 5.0, 0.0, -5.0, -10.0, -15.0, -20.0, -25.0, -20.0, -15.0, -10.0, -5.0};

public OnPluginStart()
{
	PrintToServer("[ES] VIP COMPONENT LOADED.");

	LoadConfig();

	// FORCE sv_disable_immunity_alpha to 1 or rtd_invisible is disabled
	new Handle:disableImmunityAlpha = Handle:FindConVar("sv_disable_immunity_alpha");
	SetConVarInt(disableImmunityAlpha, 1, true, true);

	LoadTranslations("common.phrases");
	LoadTranslations("estore.vip.phrases");

	AddCommandListener(CmdSayCallback, "say");
	AddCommandListener(CmdSayCallback, "say_team");

	HookEvent("player_spawn", OnPlayerSpawnEvent);
    HookEvent("round_start", OnRoundStartEvent);

    HookEvent("player_blind", OnPlayerBlindEvent);
	HookEvent("item_pickup", OnItemPickupEvent);

	HookEvent("weapon_reload", OnWeaponReload, EventHookMode_Pre);

	AddCommandListener(Command_LookAtWeapon, "+lookatweapon");
}

LoadConfig()
{
	new Handle:kv = CreateKeyValues("root");

	decl String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/estore/estore_vip.cfg");

	if (!FileToKeyValues(kv, path))
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}
	decl String:vipGroupIndices[ESTORE_MAX_GROUPS * 3];
	KvGetString(kv, "group_indices", vipGroupIndices, sizeof(vipGroupIndices), "1 2");
	decl String:vipGroupIndicesE[ESTORE_MAX_GROUPS][2];
	new vipGroupIndicesCount = ExplodeString(vipGroupIndices, " ", vipGroupIndicesE, sizeof(vipGroupIndicesE), sizeof(vipGroupIndicesE[]));

    for(new i = 0; i < vipGroupIndicesCount; i++)
    {
        new index = StringToInt(vipGroupIndicesE[i]);
        g_aVipGroupIndices[index] = i;
    }

    decl String:bonusHealth[ESTORE_MAX_GROUPS * 5];
    KvGetString(kv, "bonus_health", bonusHealth, sizeof(bonusHealth), "5 10");
    decl String:bonusHealthE[ESTORE_MAX_GROUPS][4];
    new bonusHealthCount = ExplodeString(bonusHealth, " ", bonusHealthE, sizeof(bonusHealthE), sizeof(bonusHealthE[]));

    if(bonusHealthCount != vipGroupIndicesCount)
    {
        SetFailState("config file error bonus_health does not match group_indices");
    }

    for(new i = 0; i < bonusHealthCount; i++)
    {
        g_aBonusHealth[i] = StringToInt(bonusHealthE[i]);
    }

    decl String:bonusArmor[ESTORE_MAX_GROUPS * 5];
    KvGetString(kv, "bonus_armor", bonusArmor, sizeof(bonusArmor), "5 10");
    decl String:bonusArmorE[ESTORE_MAX_GROUPS][4];
    new bonusArmorCount = ExplodeString(bonusArmor, " ", bonusArmorE, sizeof(bonusArmorE), sizeof(bonusArmorE[]));

    if(bonusArmorCount != vipGroupIndicesCount)
    {
        SetFailState("config file error bonus_armor does not match group_indices");
    }

    for(new i = 0; i < bonusArmorCount; i++)
    {
        g_aBonusArmor[i] = StringToInt(bonusArmorE[i]);
    }

    decl String:bonusMoveSpeed[ESTORE_MAX_GROUPS * 5];
    KvGetString(kv, "bonus_move_speed", bonusMoveSpeed, sizeof(bonusMoveSpeed), "0.10 0.05");
    decl String:bonusMoveSpeedE[ESTORE_MAX_GROUPS][4];
    new bonusMoveSpeedCount = ExplodeString(bonusMoveSpeed, " ", bonusMoveSpeedE, sizeof(bonusMoveSpeedE), sizeof(bonusMoveSpeedE[]));

    if(bonusMoveSpeedCount != vipGroupIndicesCount)
    {
        SetFailState("config file error bonus_move_speed does not match group_indices");
    }

    for(new i = 0; i < bonusMoveSpeedCount; i++)
    {
        g_aBonusMoveSpeed[i] = StringToFloat(bonusMoveSpeedE[i]);
    }

    decl String:fallDamageReduction[ESTORE_MAX_GROUPS * 6];
    KvGetString(kv, "fall_damage_reduction", fallDamageReduction, sizeof(fallDamageReduction), "1.0 0.0");
    decl String:fallDamageReductionE[ESTORE_MAX_GROUPS][5];
    new fallDamageReductionCount = ExplodeString(fallDamageReduction, " ", fallDamageReductionE, sizeof(fallDamageReductionE), sizeof(fallDamageReductionE[]));

    if(fallDamageReductionCount != vipGroupIndicesCount)
    {
        SetFailState("config file error fall_damage_reduction does not match group_indices");
    }

    for(new i = 0; i < fallDamageReductionCount; i++)
    {
        g_aFallDamageReduction[i] = StringToFloat(fallDamageReductionE[i]);
    }

    decl String:lifeScrewPerGrenadeDamage[ESTORE_MAX_GROUPS * 6];
    KvGetString(kv, "life_screw_per_grenade_damage", lifeScrewPerGrenadeDamage, sizeof(lifeScrewPerGrenadeDamage), "0.04 0.00");
    decl String:lifeScrewPerGrenadeDamageE[ESTORE_MAX_GROUPS][5];
    new lifeScrewPerGrenadeDamageCount = ExplodeString(lifeScrewPerGrenadeDamage, " ", lifeScrewPerGrenadeDamageE, sizeof(lifeScrewPerGrenadeDamageE), sizeof(lifeScrewPerGrenadeDamageE[]));

    if(lifeScrewPerGrenadeDamageCount != vipGroupIndicesCount)
    {
        SetFailState("config file error life_screw_per_grenade_damage does not match group_indices");
    }

    for(new i = 0; i < lifeScrewPerGrenadeDamageCount; i++)
    {
        g_aLifeScrewPerGrenadeDamage[i] = StringToFloat(lifeScrewPerGrenadeDamageE[i]);
    }

    g_iMaxHegrenades = KvGetNum(kv, "max_hegrenades", 2);
    g_iMaxFlashbangs = KvGetNum(kv, "max_flashbangs", 3);
    g_iMaxSmokegrenades = KvGetNum(kv, "max_smokegrenades", 1);
    g_iMaxIncenderygrenades = KvGetNum(kv, "max_incenderygrenades", 1);
    g_iMaxDecoygrenades = KvGetNum(kv, "max_decoygrenades", 1);

    decl String:rollTheDiceCommand[6 * 33];
	KvGetString(kv, "roll_the_dice_commands", rollTheDiceCommand, sizeof(rollTheDiceCommand), "!dice /dice !roll /roll !rtd /rtd");
	g_iRollTheDiceCommandCount = ExplodeString(rollTheDiceCommand, " ", g_aRollTheDiceCommands, sizeof(g_aRollTheDiceCommands), sizeof(g_aRollTheDiceCommands[]));
	KvGetString(kv, "on_hit_sound", g_sOnHitSound, sizeof(g_sOnHitSound));
	Format(g_sOnHitSoundRelative, sizeof(g_sOnHitSoundRelative), "*/%s", g_sOnHitSound);

	CloseHandle(kv);
}

public Action:Command_LookAtWeapon(client, const String:command[], argc)
{
	if(!IsValidClient(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	new groupIndex = 0;
    new String:groupName[ESTORE_MAX_NAME_LENGTH];
	EStore_GetClientGroup(client, groupIndex, groupName, sizeof(groupName));

	new groupOffset = g_aVipGroupIndices[groupIndex];
	if (groupOffset != -1)
    {
		SetEntProp(client, Prop_Send, "m_fEffects", GetEntProp(client, Prop_Send, "m_fEffects") ^ 4);
	}
	return Plugin_Continue;
}

public OnClientPostAdminCheck(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamageEvent);
}

public OnClientDisconnect(client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamageEvent);
}

public OnMapStart()
{
	Format(g_sOnHitSoundRelative, sizeof(g_sOnHitSoundRelative), "%s", g_sOnHitSound);
	ReplaceString(g_sOnHitSoundRelative, sizeof(g_sOnHitSoundRelative), "sound/", "*/", false);

	if(!PrecacheSound(g_sOnHitSoundRelative, true))
	{
		EStore_LogError("PrecacheSound: '%s' failed!", g_sOnHitSoundRelative);
		return;
	}
	AddFileToDownloadsTable(g_sOnHitSound);
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

	for (new i = 0; i < g_iRollTheDiceCommandCount; i++)
	{
		if (StrEqual(g_aRollTheDiceCommands[i], text))
		{
			RollTheDice(client);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public Action:OnWeaponReload(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}
	new groupIndex = 0;
    new String:groupName[ESTORE_MAX_NAME_LENGTH];
    EStore_GetClientGroup(client, groupIndex, groupName, sizeof(groupName));

    new groupOffset = g_aVipGroupIndices[groupIndex];
    if(groupOffset != -1)
    {
		new weaponEnt = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", 0);
		if(weaponEnt != -1 )
		{
			EStore_RefillWeaponMaxAmmo(client, weaponEnt);
		}
	}
	return Plugin_Continue;
}

public Action:OnRoundStartEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
    if(g_iRollTheDiceAnouncementCount-- <= 0)
    {
        CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_anouncement", g_aRollTheDiceCommands[0]);
        g_iRollTheDiceAnouncementCount = 3;
    }
}

RollTheDice(client)
{
    if(IsFakeClient(client) || IsClientObserver(client) || !IsPlayerAlive(client))
    {
        return;
    }

    new groupIndex = 0;
    new String:groupName[ESTORE_MAX_NAME_LENGTH];
    EStore_GetClientGroup(client, groupIndex, groupName, sizeof(groupName));

    new groupOffset = g_aVipGroupIndices[groupIndex];
    if(groupOffset == -1)
    {
        CPrintToChat(client, "%s%t", ESTORE_PREFIX, "roll_the_dice_vip_only", g_aRollTheDiceCommands[0]);
        return;
    }

    if(g_aRollTheDiceAmountChecker[client]++ < 1)
    {
        new rnd = GetRandomInt(0,100) % 20;
        switch(rnd)
        {
            case 4: //increase HP
            {
				new nHealth = GetRandomInt(10, 50);
				new maxHealth = GetClientHealth(client) + nHealth;
				SetEntityHealth(client, maxHealth);
				g_aRollTheDicePlayerInfos[client][RTD_Data][0] = maxHealth;
				CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_health_increase", client, rnd, nHealth);
            }
            case 5: //decrease HP
            {
				new nHealth = GetRandomInt(10, 50);
				new maxHealth = GetClientHealth(client) - nHealth;
				if(maxHealth <= 0)
				{
					ForcePlayerSuicide(client);
				}
				SetEntityHealth(client, maxHealth);
				g_aRollTheDicePlayerInfos[client][RTD_Data][0] = maxHealth;
				CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_health_decrease", client, rnd, nHealth);
            }
            case 6: //sunglasses
            {
                g_aRollTheDicePlayerInfos[client][RTD_Flags] = g_aRollTheDicePlayerInfos[client][RTD_Flags] | ESTORE_ROLL_THE_DICE_FLAG_SUNGLASSES;
                CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_sunglasses", client, rnd);
            }
            case 7: //increase movement speed
            {
                new Float:nBonusSpeed = GetRandomFloat(0.10, 0.5);
                SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 0) + nBonusSpeed, 0);
                CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_movementspeed_increase", client, rnd, RoundToCeil(nBonusSpeed * 100.0));
            }
            case 8: //decrease movement speed
            {
                new Float:nBonusSpeed = GetRandomFloat(0.10, 0.5);
                SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 0) - nBonusSpeed, 0);
                CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_movementspeed_decrease", client, rnd, RoundToCeil(nBonusSpeed * 100.0));
            }
			case 9: //increase money
            {
                new nCash = GetRandomInt(500, 4000);
                SetEntProp(client, Prop_Send, "m_iAccount", GetEntProp(client, Prop_Send, "m_iAccount", 0) + nCash, 0);
                CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_money_increase", client, rnd, nCash);
            }
			case 10: //decrease money
            {
                new nCash = GetRandomInt(500, 4000);
				new currentCash = GetEntProp(client, Prop_Send, "m_iAccount", 0) - nCash;
                SetEntProp(client, Prop_Send, "m_iAccount", currentCash >= 0 ? currentCash : 0, 0);
                CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_money_decrease", client, rnd, nCash);
            }
			case 11: //invisible
			{
				new nInvisible = GetRandomInt(125, 225);
				g_aRollTheDicePlayerInfos[client][RTD_Flags] = g_aRollTheDicePlayerInfos[client][RTD_Flags] | ESTORE_ROLL_THE_DICE_FLAG_INVISIBLE;
				g_aRollTheDicePlayerInfos[client][RTD_Data][1] = nInvisible;
				EStore_SetVisibility(client, true, nInvisible);
				CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_invisible", client, rnd, RoundToCeil(float(nInvisible) / 255.0 * 100.0));
			}
			case 12: //gravity
			{
				new Float:nGravity = GetRandomFloat(0.50, 2.00);
				SetEntityGravity(client, nGravity);
				CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_gravity", client, rnd, nGravity);
			}
			case 13: //mirror damage
			{
				new Float:nMirrorDamage = GetRandomFloat(0.05, 0.20);
				g_aRollTheDicePlayerInfos[client][RTD_Flags] = g_aRollTheDicePlayerInfos[client][RTD_Flags] | ESTORE_ROLL_THE_DICE_FLAG_MIRROR_DAMAGE;
				g_aRollTheDicePlayerInfos[client][RTD_Data][2] = nMirrorDamage;
				CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_mirror_damage", client, rnd, RoundToCeil(nMirrorDamage * 100));
			}
			case 14: //vampire
			{
				new Float:nVampire = GetRandomFloat(0.05, 0.20);
				g_aRollTheDicePlayerInfos[client][RTD_Flags] = g_aRollTheDicePlayerInfos[client][RTD_Flags] | ESTORE_ROLL_THE_DICE_FLAG_VAMPIRE;
				g_aRollTheDicePlayerInfos[client][RTD_Data][3] = nVampire;
				CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_vampire", client, rnd);
			}
			case 15: //drug
			{
				new nDrugTime = GetRandomInt(10, 40);
				g_aRollTheDicePlayerInfos[client][RTD_Flags] = g_aRollTheDicePlayerInfos[client][RTD_Flags] | ESTORE_ROLL_THE_DICE_FLAG_DRUG;
				g_aRollTheDicePlayerInfos[client][RTD_Data][4] = CreateTimer(1.0, RTD_DrugTimerCallback, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
				g_aRollTheDicePlayerInfos[client][RTD_Data][5] = nDrugTime;
				CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_drug", client, rnd, nDrugTime);
			}
			case 16: //burn
			{
				new nTime = GetRandomInt(1, (GetClientHealth(client) / 5) - 2);		 
				IgniteEntity(client, float(nTime), false);
				CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_burn", client, rnd, nTime);
			}
			case 17: //freeze
			{
				new nTime = GetRandomInt(15, 30);
				RTD_SetFreeze(client, true, float(nTime));
				CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_freeze", client, rnd, nTime);
			}
			case 18: //rnd weapon loose
			{
				decl String:sItem[32];
				if(EStore_RemoveRandomWeaponFromSlot(client, sItem, sizeof(sItem)))
				{
					EStore_GetRealWeaponName(sItem);
					CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_take_item", client, rnd, sItem);
				}
				else
				{
					CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_nothing_to_loose", client, rnd);
				}
			}
			default:
			{
				CPrintToChatAll("%s%t", ESTORE_PREFIX, "roll_the_dice_nothing", client, rnd);
			}
        }
    }
    else
    {
        CPrintToChat(client, "%s%t", ESTORE_PREFIX, "roll_the_dice_already_used_this_round");
    }
}

void RTD_KillDrugTimer(client)
{
	if(g_aRollTheDicePlayerInfos[client][RTD_Data][4] != INVALID_HANDLE)
	{
		KillTimer(g_aRollTheDicePlayerInfos[client][RTD_Data][4]);	
		g_aRollTheDicePlayerInfos[client][RTD_Data][4] = INVALID_HANDLE;
	}
}

void RTD_KillDrug(client)
{
	RTD_KillDrugTimer(client);
	
	new Float:angs[3];
	GetClientEyeAngles(client, angs);
	
	angs[2] = 0.0;
	
	TeleportEntity(client, NULL_VECTOR, angs, NULL_VECTOR);	

	new color[4] = { 0, 0, 0, 0 };

	new Handle:message = StartMessageOne("Fade", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("duration", 1536);
		pb.SetInt("hold_time", 1536);
		pb.SetInt("flags", (0x0001 | 0x0010));
		pb.SetColor("clr", color);
	}
	else
	{	
		BfWrite bf = UserMessageToBfWrite(message);
		bf.WriteShort(1536);
		bf.WriteShort(1536);
		bf.WriteShort((0x0001 | 0x0010));
		bf.WriteByte(color[0]);
		bf.WriteByte(color[1]);
		bf.WriteByte(color[2]);
		bf.WriteByte(color[3]);
	}
	
	EndMessage();
}

public Action:RTD_DrugTimerCallback(Handle:timer, any:client)
{
	if (!IsValidClient(client))
	{
		RTD_KillDrugTimer(client);
		return Plugin_Handled;
	}
	
	if (!IsPlayerAlive(client))
	{
		RTD_KillDrug(client);	
		return Plugin_Handled;
	}

	if(g_aRollTheDicePlayerInfos[client][RTD_Data][5]-- <= 0)
	{
		RTD_KillDrug(client);
		return Plugin_Handled;
	}
	
	float angs[3];
	GetClientEyeAngles(client, angs);
	
	angs[2] = g_DrugAngles[GetRandomInt(0,100) % 20];
	
	TeleportEntity(client, NULL_VECTOR, angs, NULL_VECTOR);
	
	new color[4] = { 0, 0, 0, 128 };
	color[0] = GetRandomInt(0, 255);
	color[1] = GetRandomInt(0, 255);
	color[2] = GetRandomInt(0, 255);

	new Handle:message = StartMessageOne("Fade", client);
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("duration", 255);
		pb.SetInt("hold_time", 255);
		pb.SetInt("flags", 0x0002);
		pb.SetColor("clr", color);
	}
	else
	{
		BfWriteShort(message, 255);
		BfWriteShort(message, 255);
		BfWriteShort(message, 0x0002);
		BfWriteByte(message, color[0]);
		BfWriteByte(message, color[1]);
		BfWriteByte(message, color[2]);
		BfWriteByte(message, color[3]);
	}
	
	EndMessage();
		
	return Plugin_Handled;
}

RTD_SetFreeze(client, bool:freeze = true, Float:time = 0.0)
{
	if (freeze)
	{
		SetEntityMoveType(client, MOVETYPE_NONE);

		if (time > 0)
		{
			CreateTimer(time, FreezeOffCallback, client, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	else
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}
}

public Action:FreezeOffCallback(Handle:timer, any:client)
{
	RTD_SetFreeze(client, false);
	return Plugin_Handled;
}


public Action:OnItemPickupEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}
	if(g_aRollTheDicePlayerInfos[client][RTD_Flags] & ESTORE_ROLL_THE_DICE_FLAG_INVISIBLE == ESTORE_ROLL_THE_DICE_FLAG_INVISIBLE)
    {
        EStore_SetVisibility(client, true, g_aRollTheDicePlayerInfos[client][RTD_Data][1]);
    }

	return Plugin_Continue;
}

public Action:OnPlayerSpawnEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client =  GetClientOfUserId(GetEventInt(event, "userid", 0));
    if(!IsValidClient(client) || IsClientObserver(client))
    {
        return Plugin_Continue;
    }

	//RESET GRAVITY
	SetEntityGravity(client, 1.0);

    new groupIndex = 0;
    new String:groupName[ESTORE_MAX_NAME_LENGTH];
    EStore_GetClientGroup(client, groupIndex, groupName, sizeof(groupName));

    new groupOffset = g_aVipGroupIndices[groupIndex];

    if(groupOffset != -1)
    {
		//NÖTIG?
		if(g_aRollTheDicePlayerInfos[client][RTD_Flags] & ESTORE_ROLL_THE_DICE_FLAG_INVISIBLE == ESTORE_ROLL_THE_DICE_FLAG_INVISIBLE)
		{
			EStore_SetVisibility(client, false);
		}
		if(g_aRollTheDicePlayerInfos[client][RTD_Flags] & ESTORE_ROLL_THE_DICE_FLAG_DRUG == ESTORE_ROLL_THE_DICE_FLAG_DRUG)
		{
			RTD_KillDrug(client);
		}

		g_aRollTheDiceAmountChecker[client] = 0;
		g_aRollTheDicePlayerInfos[client][RTD_Flags] = 0;
		g_aRollTheDicePlayerInfos[client][RTD_Data][0] = ESTORE_DEFAULT_HEALTH + g_aBonusHealth[groupOffset];
		g_aRollTheDicePlayerInfos[client][RTD_Data][1] = 0;
		g_aRollTheDicePlayerInfos[client][RTD_Data][2] = 0;
		g_aRollTheDicePlayerInfos[client][RTD_Data][3] = 0;
		g_aRollTheDicePlayerInfos[client][RTD_Data][4] = INVALID_HANDLE;
		g_aRollTheDicePlayerInfos[client][RTD_Data][5] = 0;

        SetEntityHealth(client, g_aRollTheDicePlayerInfos[client][RTD_Data][0]);
        SetEntProp(client, Prop_Send, "m_ArmorValue", ESTORE_DEFAULT_ARMOR + g_aBonusArmor[groupOffset], _, 0);
        SetEntProp(client, Prop_Send, "m_bHasHelmet", 1, _, 0);
		if(GetClientTeam(client) == CSGO_TEAM_CT)
		{
			SetEntProp(client, Prop_Send, "m_bHasDefuser", 1, _, 0);
		}
        SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0 + g_aBonusMoveSpeed[groupOffset], 0);
    }

    return Plugin_Continue;
}

public Action:OnPlayerBlindEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(IsClientObserver(client) || IsFakeClient(client))
    {
        return Plugin_Continue;
    }

    if(g_aRollTheDicePlayerInfos[client][RTD_Flags] & ESTORE_ROLL_THE_DICE_FLAG_SUNGLASSES == ESTORE_ROLL_THE_DICE_FLAG_SUNGLASSES)
    {
        SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", 0.5, 0);
    }

	return Plugin_Continue;
}

public Action:OnTakeDamageEvent(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
	if(IsValidClient(attacker))
	{
		if (g_aRollTheDicePlayerInfos[attacker][RTD_Flags] & ESTORE_ROLL_THE_DICE_FLAG_MIRROR_DAMAGE == ESTORE_ROLL_THE_DICE_FLAG_MIRROR_DAMAGE)
		{
			if(!IsValidClient(attacker))
			{
				return Plugin_Continue;
			}
			if(GetClientTeam(attacker) != GetClientTeam(victim))
			{
				new Float:mirrorDamage = Float:g_aRollTheDicePlayerInfos[attacker][RTD_Data][2];
				new nHealth = GetClientHealth(attacker) - RoundToCeil(damage * mirrorDamage);
				if(nHealth <= 0)
				{
					ForcePlayerSuicide(attacker);
					return Plugin_Continue;
				}
				else
				{
					SetEntityHealth(attacker, nHealth);
				}
			}

		}
		if (g_aRollTheDicePlayerInfos[attacker][RTD_Flags] & ESTORE_ROLL_THE_DICE_FLAG_VAMPIRE == ESTORE_ROLL_THE_DICE_FLAG_VAMPIRE)
		{
			if(!IsValidClient(attacker))
			{
				return Plugin_Continue;
			}
			if(GetClientTeam(attacker) != GetClientTeam(victim))
			{
				new Float:vampire = Float:g_aRollTheDicePlayerInfos[attacker][RTD_Data][3];
				new nHealth = GetClientHealth(attacker) + RoundToCeil(damage * vampire);
				if(nHealth <= 0)
				{
					ForcePlayerSuicide(attacker);
					return Plugin_Continue;
				}
				else
				{
					new maxHealth = g_aRollTheDicePlayerInfos[attacker][RTD_Data][0];
					SetEntityHealth(attacker, nHealth <= maxHealth ? nHealth : maxHealth);
				}
			}
		}
	}

	if(damagetype & DMG_BULLET == DMG_BULLET)
    {
		if(!IsValidClient(attacker) || !IsValidClient(victim))
		{
			return Plugin_Continue;
		}
		if(GetClientTeam(attacker) != GetClientTeam(victim))
		{
			new groupIndex = 0;
			new String:groupName[ESTORE_MAX_NAME_LENGTH];
			EStore_GetClientGroup(attacker, groupIndex, groupName, sizeof(groupName));

			new groupOffset = g_aVipGroupIndices[groupIndex];
			if(groupOffset != -1)
			{
				EmitSoundToClient(attacker, g_sOnHitSoundRelative);
			}
		}
	}
    else if(damagetype & DMG_FALL == DMG_FALL)
    {
		if(!IsValidClient(victim))
        {
            return Plugin_Continue;
        }
        new groupIndex = 0;
        new String:groupName[ESTORE_MAX_NAME_LENGTH];
        EStore_GetClientGroup(victim, groupIndex, groupName, sizeof(groupName));

        new groupOffset = g_aVipGroupIndices[groupIndex];
        if(groupOffset != -1)
        {
            damage = damage - (damage * g_aFallDamageReduction[groupOffset]);
            return Plugin_Changed;
        }
    }
    else if(damagetype & DMG_BLAST == DMG_BLAST)
    {
		if(!IsValidClient(attacker) || !IsValidClient(victim))
		{
			return Plugin_Continue;
		}
		new groupIndex = 0;
		new String:groupName[ESTORE_MAX_NAME_LENGTH];
		EStore_GetClientGroup(attacker, groupIndex, groupName, sizeof(groupName));

		new groupOffset = g_aVipGroupIndices[groupIndex];
		if(groupOffset == -1)
		{
			return Plugin_Continue;
		}
		if(attacker == victim)
		{
			damage = 0.0;
			return Plugin_Changed;
		}

		if(GetClientTeam(attacker) != GetClientTeam(victim))
		{
	        new nHealth = GetClientHealth(attacker) + RoundToCeil(damage * g_aLifeScrewPerGrenadeDamage[groupOffset]);
	        new maxHealth = g_aRollTheDicePlayerInfos[attacker][RTD_Data][0];
	        SetEntityHealth(attacker, nHealth < maxHealth ? nHealth : maxHealth);
		}
    }
    return Plugin_Continue;
}
