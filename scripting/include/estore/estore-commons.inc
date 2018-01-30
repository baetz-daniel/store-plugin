#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

stock bool:IsValidClient(int client)
{
    if (!(0 < client <= MaxClients) ||
		!IsClientConnected(client) ||
		!IsClientInGame(client) ||
		IsFakeClient(client))
	{
		return false;
	}
    return true;
}

new String:sColorCodes[15][] =
{
    "\x01", "\x02", "\x03", "\x04", "\x05", "\x06", "\x07", "\x08", "\x09", "\x0A", "\x0B", "\x0C", "\x0D", "\x0E", "\x0F"
};
new String:sColorNames[15][] =
{
    "{default}", "{lred}", "{dpurple}", "{lgreen}", "{dgreen}", "{dgreen2}", "{red}", "{gray}", "{yellow}", "{gray2}", "{lblue}", "{blue}", "{blue2}", "{purple}", "{dred}"
};

stock CPrintToChat(client, const String:format[], any:...)
{
	decl String:buffer[512];
	VFormat(buffer, sizeof(buffer), format, 3);
    for(new i = 0; i < 15; i++)
    {
    	ReplaceString(buffer, sizeof(buffer), sColorNames[i], sColorCodes[i], false);
    }

	PrintToChat(client, buffer);
}

stock CPrintToChatAll(const String:format[], any:...)
{
	decl String:buffer[512];
	VFormat(buffer, sizeof(buffer), format, 2);
    for(new i = 0; i < 15; i++)
    {
    	ReplaceString(buffer, sizeof(buffer), sColorNames[i], sColorCodes[i], false);
    }

	PrintToChatAll(buffer);
}

stock EStore_GetRealWeaponName(String:weaponName[32]) 
{
	if(ReplaceString(weaponName, sizeof(weaponName), "weapon_knife_", "", false) != 0) 
	{
		return; 
	}
	ReplaceString(weaponName, sizeof(weaponName), "weapon_", "", false);
}


new const String:g_weaponAmmoMax[20][] =
{
    "ammo_50AE_max",         //Deagle,RB8
    "ammo_762mm_max",   	 //AK,SSG08,G3SG1,AUG,SCAR20
    "ammo_556mm_max",        //SG553,Galil,M4A4,FAMAS
    "ammo_556mm_small_max",  //M4A1-S
    "ammo_556mm_box_max",    //M249
    "ammo_338mag_max",       //AWP
    "ammo_9mm_max",          //Tec9,Glock,DualBarrets,MP7,Bizon,MP9
    "ammo_buckshot_max",     //Xm1014
    "ammo_45acp_max",        //Mac10,Ump45
    "",
    "ammo_357sig_small_max", //USP
    "ammo_357sig_min_max",   //CZ75A
    "ammo_57mm_max",         //P90,Five-Seven
    "",
    "",
    "",
    "",
    "",
    "",
    "ammo_357sig_max"       //p250
};

stock EStore_RefillWeaponMaxAmmo(client, weapon)
{
    new m_iPrimaryAmmoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType", _, 0);
    if(!(0 < m_iPrimaryAmmoType <= 20))
    {
        return;
    }

    new Handle:conHndl = Handle:FindConVar(g_weaponAmmoMax[m_iPrimaryAmmoType - 1]);
    if(conHndl == INVALID_HANDLE)
    {
        return;
    }
    SetEntProp(client, Prop_Send, "m_iAmmo", GetConVarInt(conHndl), _, m_iPrimaryAmmoType);
}

stock EStore_GetPlayerEntities(client, const String:sEntityName[], pnEntityIDs[], String:psEntityNames[][], nMaxEntityCount, nMaxEntityNameSize)
{
	new iEntities = 0;
	if(FindSendPropInfo("CBaseCombatCharacter", sEntityName, _, _, iEntities) <= 0)
	{
		return 0;
	}
	if(iEntities != -1)
	{
		new nEntityCount = 0;
		new nEntityID = -1;
		for(new i = 0; i <= 128; i += 4)
		{
			nEntityID = GetEntDataEnt2(client, (iEntities + i));
			if(!IsValidEdict(nEntityID))
			{
				continue;
			}
			GetEdictClassname(nEntityID, psEntityNames[nEntityCount], nMaxEntityNameSize);
			pnEntityIDs[nEntityCount] = nEntityID;
			nEntityCount++;
		}
		return nEntityCount;
	}

	return 0;
}


stock bool:EStore_RemoveWeaponFromSlot(client, slot)
{
	new nEntityID = GetPlayerWeaponSlot(client, slot);
	if(nEntityID < 0)
    {
		return false;
    }

	decl String:sEntityName[32];
	GetEdictClassname(nEntityID, sEntityName, sizeof(sEntityName));

	if(strcmp(sEntityName, "weapon_knife") == 0)
    {
		return true;
    }

	RemovePlayerItem(client, nEntityID);
	RemoveEdict(nEntityID);

	return true;
}

stock bool:EStore_RemoveRandomWeaponFromSlot(client, String:sItem[], maxlenght)
{
	new String:sWeaponNames[32][32];
	new pnWeaponIDs[32];
	new nWeaponCount = EStore_GetPlayerEntities(client, "m_hMyWeapons", pnWeaponIDs, sWeaponNames, 32, 32);

	new nValidWeaponCount = 0;
	new piValidWeapon[32];
	for(new i = 0; i < nWeaponCount; i++)
	{
		if(strcmp(sWeaponNames[i], "weapon_knife") != 0 && strcmp(sWeaponNames[i], "weapon_c4") != 0 && pnWeaponIDs[i] != 0)
		{
			piValidWeapon[nValidWeaponCount++] = i;
		}
	}

	if(nValidWeaponCount > 0)
	{
		new iRemove = piValidWeapon[GetRandomInt(1, nValidWeaponCount) - 1];
		new nRemoveWeapon = pnWeaponIDs[iRemove];

		RemovePlayerItem(client, nRemoveWeapon);
		RemoveEdict(nRemoveWeapon);

		EStore_EquipKnife(client, false);

		strcopy(sItem, maxlenght, sWeaponNames[iRemove]);

		return true;
	}

	return false;
}

stock bool:EStore_EquipKnife(client, bool:bRemoveOther)
{
    new iItems = 0;
    if(FindSendPropInfo("CBaseCombatCharacter", "m_hMyWeapons", _, _, iItems) <= 0)
    {
        return false;
    }

    new nEntityID = -1;
    new String:sEntityName[32];
    new nEntityIDKnife = -1;
    for(new i = 0; i <= 128; i += 4)
	{
		nEntityID = GetEntDataEnt2(client, (iItems+i));
		if(!IsValidEdict(nEntityID))
		{
			continue;
		}
		GetEdictClassname(nEntityID, sEntityName, sizeof(sEntityName));

		if(strcmp(sEntityName, "weapon_knife") == 0)
		{
			nEntityIDKnife = nEntityID;
			if(!bRemoveOther)
			{
				break;
			}
		}
		else if(bRemoveOther && strcmp(sEntityName, "weapon_c4") != 0)
		{
			RemovePlayerItem(client, nEntityID);
			RemoveEdict(nEntityID);
		}
	}
    if(nEntityIDKnife != -1)
    {
        EquipPlayerWeapon(client, nEntityIDKnife);
        return true;
    }

    return false;
}

stock EStore_SetVisibility(client, bool:visible = true, value = 20, RenderMode:rMode = RENDER_TRANSCOLOR)
{
	new RenderMode:mode = RENDER_NORMAL;
	new alpha = 255;
	if (visible)
	{
		mode = rMode;
		alpha = value;
	}
	SetEntityRenderColor(client, 255, 255, 255, alpha);
	SetEntityRenderMode(client, mode);
	new weapon;
	for (new slot = 0; slot < 4; slot++)
	{
		if ((weapon = GetPlayerWeaponSlot(client, slot)) != -1)
		{
			SetEntityRenderMode(weapon, mode);
			SetEntityRenderColor(weapon, 255, 255, 255, alpha);
		}
	}
}

stock EStore_SetGlow(client, r = 255, g = 255, b = 255, a = 255, RenderFx:fx = RENDERFX_GLOWSHELL, RenderMode:render = RENDER_GLOW)
{
	SetEntityRenderFx(client, fx);
	SetEntityRenderMode(client, render);
	SetEntityRenderColor(client, r, g, b, a);
}

stock bool:EStore_GetClientMoney(client, &money)
{
    if(IsValidClient(client))
    {
        money = GetEntProp(client, Prop_Send, "m_iAccount", _, 0);
        return true;
    }
    return false;
}

stock bool:EStore_SetClientMoney(client, money)
{
    if(IsValidClient(client))
    {
        SetEntProp(client, Prop_Send, "m_iAccount", money, _, 0);
        return true;
    }
    return false;
}

stock EStore_ShakeClient(client, Float:flDuration, Float:flAmplitude, Float:flFrequency)
{
	new Handle:message = StartMessageOne("Shake", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);

	if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf) 
	{
		PbSetInt(message, "command", 0);
		PbSetFloat(message, "local_amplitude", flAmplitude);
		PbSetFloat(message, "frequency", flFrequency);
		PbSetFloat(message, "duration", flDuration);
	}
	else
	{
		BfWriteByte(message, 0);
		BfWriteFloat(message, flAmplitude);
		BfWriteFloat(message, flFrequency);
		BfWriteFloat(message, flDuration);
	}
	
	EndMessage();	
}