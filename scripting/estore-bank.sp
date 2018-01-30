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

#include <estore/estore-bank>


public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("estore-bank");
	return APLRes_Success;
}

public Plugin:myinfo =
{
	name = "[ES] Bank",
	author = ESTORE_AUTHOR,
	description = "Bank component for [ES]",
	version = ESTORE_VERSION,
	url = ESTORE_URL
};

new g_iBankCommandCount = 0;
new String:g_sBankCommands[6][32];

new g_aVipGroupIndices[ESTORE_MAX_GROUPS] = {-1, ...};

public OnPluginStart()
{
	PrintToServer("[ES] BANK COMPONENT LOADED.");

	LoadConfig();

	LoadTranslations("common.phrases");
	LoadTranslations("estore.bank.phrases");

	AddCommandListener(CmdSayCallback, "say");
	AddCommandListener(CmdSayCallback, "say_team");
}

public OnAllPluginsLoaded()
{
    EStore_AddMainMenuItem("bank", _, OnMainMenuBankItemPressed, 1);
}

LoadConfig()
{
	new Handle:kv = CreateKeyValues("root");

	decl String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/estore/estore_bank.cfg");

	if (!FileToKeyValues(kv, path))
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	decl String:bankCommands[6 * 33];
	KvGetString(kv, "bank_commands", bankCommands, sizeof(bankCommands), "!bank /bank");
	g_iBankCommandCount = ExplodeString(bankCommands, " ", g_sBankCommands, sizeof(g_sBankCommands), sizeof(g_sBankCommands[]));

	decl String:vipGroupIndices[ESTORE_MAX_GROUPS * 3];
	KvGetString(kv, "vip_group_indices", vipGroupIndices, sizeof(vipGroupIndices), "1 2");
	decl String:vipGroupIndicesE[ESTORE_MAX_GROUPS][2];
	new vipGroupIndicesCount = ExplodeString(vipGroupIndices, " ", vipGroupIndicesE, sizeof(vipGroupIndicesE), sizeof(vipGroupIndicesE[]));

    for(new i = 0; i < vipGroupIndicesCount; i++)
    {
        new index = StringToInt(vipGroupIndicesE[i]);
        g_aVipGroupIndices[index] = i;
    }

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

	for (new i = 0; i < g_iBankCommandCount; i++)
	{
		if (StrEqual(g_sBankCommands[i], text))
		{
			OpenBankMenu(client);
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public OnMainMenuBankItemPressed(client, const String:value[ESTORE_MAX_MENUITEM_VALUE_LENGHT])
{
    OpenBankMenu(client);
}

OpenBankMenu(client)
{
	if(IsValidClient(client))
	{
		EStore_GetUserBankInfo(client, GetUserBankInfoCallback);
	}
}

public GetUserBankInfoCallback(client, money, auto_deposit, auto_withdraw, any:data)
{
	new Handle:menu = CreateMenu(BankMenuSelectHandleCallback);
	SetMenuTitle(menu, "%t", "bank_menu_titel", money);
	SetMenuPagination(menu, 6);
	{
		decl String:text[255];
		Format(text, sizeof(text), "%t", "bank_withdraw");
		decl String:info[11 + 8];
		Format(info, sizeof(info), "%d,%s", money, "withdraw");
		AddMenuItem(menu, info, text, ITEMDRAW_DEFAULT);
	}

	{
		decl String:text[255];
		Format(text, sizeof(text), "%t", "bank_deposit");
		decl String:info[11 + 8];
		Format(info, sizeof(info), "%d,%s", money, "deposit");
		AddMenuItem(menu, info, text, ITEMDRAW_DEFAULT);
	}

	{
		decl String:text[255];
		Format(text, sizeof(text), "%t", "bank_transfer");
		decl String:info[11 + 8];
		Format(info, sizeof(info), "%d,%s", money, "transfer");
		AddMenuItem(menu, info, text, ITEMDRAW_DEFAULT);
	}

	{
		decl String:text[255];
		Format(text, sizeof(text), "%t", "bank_settings");
		decl String:info[11 + 8];
		Format(info, sizeof(info), "%d,%s", money, "settings");
		AddMenuItem(menu, info, text, ITEMDRAW_DEFAULT);
	}
	
	{
		decl String:text[255];
		Format(text, sizeof(text), "%t", "bank_top10");
		decl String:info[11 + 8];
		Format(info, sizeof(info), "%d,%s", money, "top10");
		AddMenuItem(menu, info, text, ITEMDRAW_DEFAULT);
	}

	{
		decl String:text[255];
		Format(text, sizeof(text), "%t", "bank_information");
		decl String:info[11 + 8];
		Format(info, sizeof(info), "%d,%s", money, "information");
		AddMenuItem(menu, info, text, ITEMDRAW_DEFAULT);
	}

	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 0);
}

BankMenuSelectHandleCallback(Handle:menu, MenuAction:action, client, item)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			decl String:info[11 + 8 + ESTORE_MAX_NAME_LENGTH + 1];
			if(!GetMenuItem(menu, item, info, sizeof(info), _, _, _))
			{
				EStore_LogError("BankMenuSelectHandleCallback - GetMenuItem failed...");
				return;
			}
			switch(item)
			{
				case 0, 1: //Withdraw, Deposit
				{
					MoneyAmountMenuSelection(client, info);
				}
				case 2: //Transfer
				{
					TransferPlayerMenuSelection(client, info);
				}
				case 3: //Settings
				{

				}
				case 4: //top 10
				{
					ShowTop10(client);
				}
				case 5: //information
				{

				}
			}
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public MoneyAmountMenuSelection(client, String:info[11 + 8 + ESTORE_MAX_NAME_LENGTH + 1])
{
	decl String:infos[3][ESTORE_MAX_NAME_LENGTH];
	if(!(2 <= ExplodeString(info, ",", infos, sizeof(infos), sizeof(infos[])) <= 3))
	{
		EStore_LogError("MoneyAmountMenuSelection - ExplodeString invalid count...");
		return;
	}

	new Handle:menu = CreateMenu(MoneyAmountMenuSelectHandleCallback);
	SetMenuTitle(menu, "%t", "bank_money_amount_menu_titel", StringToInt(infos[0]), infos[1]);

	AddMenuItem(menu, info, "500$", ITEMDRAW_DEFAULT);
	AddMenuItem(menu, info, "1000$", ITEMDRAW_DEFAULT);
	AddMenuItem(menu, info, "2000$", ITEMDRAW_DEFAULT);
	AddMenuItem(menu, info, "4000$", ITEMDRAW_DEFAULT);
	AddMenuItem(menu, info, "6000$", ITEMDRAW_DEFAULT);
	AddMenuItem(menu, info, "8000$", ITEMDRAW_DEFAULT);
	AddMenuItem(menu, info, "10000$", ITEMDRAW_DEFAULT);
	AddMenuItem(menu, info, "16000$", ITEMDRAW_DEFAULT);

	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public MoneyAmountMenuSelectHandleCallback(Handle:menu, MenuAction:action, client, item)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			decl String:info[11 + 8 + ESTORE_MAX_NAME_LENGTH + 1];
			if(!GetMenuItem(menu, item, info, sizeof(info), _, _, _))
			{
				EStore_LogError("MoneyAmountMenuSelectHandleCallback - GetMenuItem failed...");
				return;
			}

			decl String:infos[3][ESTORE_MAX_NAME_LENGTH];
			if(!(2 <= ExplodeString(info, ",", infos, sizeof(infos), sizeof(infos[])) <= 3))
			{
				EStore_LogError("MoneyAmountMenuSelection - ExplodeString invalid count...");
				return;
			}

			new menuMoneyValue = 0;
			switch(item)
			{
				case 0: { menuMoneyValue = 500; }
				case 1: { menuMoneyValue = 1000; }
				case 2: { menuMoneyValue = 2000; }
				case 3: { menuMoneyValue = 4000; }
				case 4: { menuMoneyValue = 6000; }
				case 5: { menuMoneyValue = 8000; }
				case 6: { menuMoneyValue = 10000; }
				case 7: { menuMoneyValue = 16000; }
			}

			new clientMoney = 0;
			EStore_GetClientMoney(client, clientMoney);

			new bankMoney = StringToInt(infos[0]);

			if(strcmp(infos[1], "withdraw", false) == 0)
			{
				new maxMoneyValue = 16000 - clientMoney;
				maxMoneyValue = maxMoneyValue < menuMoneyValue ? maxMoneyValue : menuMoneyValue;
				maxMoneyValue = maxMoneyValue < bankMoney ? maxMoneyValue : bankMoney;

				EStore_WithdrawUserBankMoney(client, maxMoneyValue);
				EStore_SetClientMoney(client, clientMoney + maxMoneyValue);
				CPrintToChat(client, "%s%t", ESTORE_PREFIX, "bank_withdraw_message", maxMoneyValue);
			}
			else if(strcmp(infos[1], "deposit", false) == 0)
			{
				new maxMoneyValue = clientMoney < menuMoneyValue ? clientMoney : menuMoneyValue;

				EStore_SetClientMoney(client, clientMoney - maxMoneyValue);
				EStore_DepositUserBankMoney(client, maxMoneyValue);
				CPrintToChat(client, "%s%t", ESTORE_PREFIX, "bank_deposit_message", maxMoneyValue);
			}
			else if(strcmp(infos[1], "transfer", false) == 0)
			{
				if(bankMoney >= menuMoneyValue)
				{
					decl String:target_name[MAX_TARGET_LENGTH];
					decl target_list[MAXPLAYERS];
					decl target_count;
					decl bool:tn_is_ml;

					if ((target_count = ProcessTargetString(
							infos[2],
							0,
							target_list,
							MAXPLAYERS,
							0,
							target_name,
							sizeof(target_name),
							tn_is_ml)) <= 0)
					{
						ReplyToTargetError(client, target_count);
						return;
					}

					if(target_count > 0)
					{
						if (IsValidClient(target_list[0]))
						{
							EStore_WithdrawUserBankMoney(client, menuMoneyValue);
							CPrintToChat(client, "%s%t", ESTORE_PREFIX, "bank_transfer_message", target_list[0], menuMoneyValue);
							EStore_DepositUserBankMoney(target_list[0], menuMoneyValue);
							CPrintToChat(target_list[0], "%s%t", ESTORE_PREFIX, "bank_transfer_receive_message", client, menuMoneyValue);
						}
					}
				}
				else
				{
					CPrintToChat(client, "%s%t", ESTORE_PREFIX, "bank_transfer_message_error", bankMoney, menuMoneyValue);
				}
			}

		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public TransferPlayerMenuSelection(client, String:info[11 + 8 + ESTORE_MAX_NAME_LENGTH + 1]) 
{
	decl String:infos[3][ESTORE_MAX_NAME_LENGTH];
	if(!(2 <= ExplodeString(info, ",", infos, sizeof(infos), sizeof(infos[])) <= 3))
	{
		EStore_LogError("TransferPlayerMenuSelection - ExplodeString invalid count...");
		return;
	}
	new Handle:menu = CreateMenu(TransferPlayerMenuSelectHandleCallback);
	SetMenuTitle(menu, "%t", "bank_money_amount_menu_titel", StringToInt(infos[0]), infos[1]);

	for (new c = 1; c <= MaxClients; c++)
	{
	    if (c != client && IsValidClient(c))
	    {
			decl String:sNameBuffer[ESTORE_MAX_NAME_LENGTH];
			GetClientName(c, sNameBuffer, sizeof(sNameBuffer));
	        AddMenuItem(menu, info, sNameBuffer, ITEMDRAW_DEFAULT);
	    }
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public TransferPlayerMenuSelectHandleCallback(Handle:menu, MenuAction:action, client, item)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			new String:info[11 + 8 + ESTORE_MAX_NAME_LENGTH + 1];
			new String:display[ESTORE_MAX_NAME_LENGTH];
			if(!GetMenuItem(menu, item, info, sizeof(info), _, display, sizeof(display)))
			{
				EStore_LogError("TransferPlayerMenuSelectHandleCallback - GetMenuItem failed...");
				return;
			}
			Format(info, sizeof(info), "%s,%s", info, display);
			MoneyAmountMenuSelection(client, info);
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

ShowTop10(client)
{
	EStore_GetTop10Bank(ShowTop10Callback, client);
}

public ShowTop10Callback(Handle:infos[], count, any:client)
{
    new Handle:menu = CreateMenu(ShowTop10MenuSelectHandleCallback);
    SetMenuTitle(menu, "%t", "bank_show_top10_menu_titel");

    for(new i = 0; i < count; i++)
    {
        new Handle:info = infos[i];

        ResetPack(info);
        decl String:iName[ESTORE_MAX_NAME_LENGTH];
		ReadPackString(info, iName, sizeof(iName));
		new money = ReadPackCell(info);
        CloseHandle(info);
    
        decl String:text[128];
        Format(text, sizeof(text), "%t", "top10_info", iName, money);

        AddMenuItem(menu, "", text, ITEMDRAW_DEFAULT);
    }

    SetMenuExitButton(menu, true);
    DisplayMenu(menu, client, 0);
}

public ShowTop10MenuSelectHandleCallback(Handle:menu, MenuAction:action, client, item)
{
	switch (action)
	{
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

/* VIP CHECK

new groupIndex = 0;
new String:groupName[ESTORE_MAX_NAME_LENGTH];
EStore_GetClientGroup(client, groupIndex, groupName, sizeof(groupName));

new groupOffset = g_aVipGroupIndices[groupIndex];
if (groupOffset != -1)
{

}

*/

// Encoded Bank - Balance 2345$
// ----------------------------
// 1) withdraw
//  - store money on the global bank
// 2) deposit
//  - get money from the global bank
// 3) transfer
//  - transfer money a other bank account
// 4) settings
//	- setup your bank account
// 5) information
//	- show your current bank account information
// 9) exit
