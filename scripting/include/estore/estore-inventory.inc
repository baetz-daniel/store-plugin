#if defined _estore_inventory_included
#endinput
#endif
#define _estore_inventory_included

#define ESTORE_REGISTER_ITEM_TYPE_SUCCESS 				0
#define ESTORE_REGISTER_ITEM_TYPE_ERROR 				1
#define ESTORE_REGISTER_ITEM_TYPE_ALREADY_REGISTERED 	2

forward Action:EStore_OnUseItem(client, itemIndex, const String:itemType[ESTORE_MAX_TYPE_LENGTH]);
forward EStore_OnInventoryPluginLoaded();

functag EStore_PrecacheItemTypeCallback public(const String:json[], jsonLenght);

native _:EStore_RegisterItemType(const String:type[], EStore_PrecacheItemTypeCallback:callback = INVALID_FUNCTION);
native bool:EStore_IsItemTypeRegistered(const String:type[]);

public SharedPlugin:__pl_estore_inventory =
{
	name = "estore-inventory",
	file = "estore-inventory.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_estore_inventory_SetNTVOptional()
{
    MarkNativeAsOptional("EStore_RegisterItemType");
}
#endif
