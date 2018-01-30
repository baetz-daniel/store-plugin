#if defined _estore_core_included
#endinput
#endif
#define _estore_core_included

#define ESTORE_VERSION "0.0.0.1-alpha"

#define ESTORE_AUTHOR "Sa[I]ka"
#define ESTORE_URL "http://trident-games.com"

#define ESTORE_PREFIX " \x04[ES] \x01"

#define ESTORE_MAX_MENU_ITEMS 32
#define ESTORE_MAX_GROUPS 16
#define ESTORE_MAX_CREDIT_INT_LENGTH 4

#define ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT 32
#define ESTORE_MAX_MENUITEM_VALUE_LENGHT 64

#if !defined CSGO_TEAM_NONE
	#define CSGO_TEAM_NONE 0
#endif
#if !defined CSGO_TEAM_SPECTATOR
	#define CSGO_TEAM_SPECTATOR 1
#endif
#if !defined CSGO_TEAM_T
	#define CSGO_TEAM_T 2
#endif
#if !defined CSGO_TEAM_CT
	#define CSGO_TEAM_CT 3
#endif

functag EStore_MenuItemPressedCallback public(client, const String:value[ESTORE_MAX_MENUITEM_VALUE_LENGHT]);

native EStore_GetClientGroup(client, &groupIndex, String:groupName[], maxLength);
native EStore_GetCurrencyName(String:currencyName[], maxLength);

native EStore_AddMainMenuItem(const String:displayName[ESTORE_MAX_MENUITEM_DISPLAYNAME_LENGHT], const String:value[ESTORE_MAX_MENUITEM_VALUE_LENGHT] = "", EStore_MenuItemPressedCallback:callback, order = 32);

public SharedPlugin:__pl_estore =
{
	name = "estore-core",
	file = "estore-core.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_estore_SetNTVOptional()
{
	MarkNativeAsOptional("EStore_GetClientGroup");
	MarkNativeAsOptional("EStore_GetCurrencyName");

	MarkNativeAsOptional("EStore_GetCurrencyName");
}
#endif
