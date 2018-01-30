#if defined _estore_shop_included
#endinput
#endif
#define _estore_shop_included

forward EStore_OnShopBuyItem(client, itemId, bool:success);

native EStore_OpenShop(client);
native EStore_OpenShopCategory(client, categoryID);

public SharedPlugin:__pl_estore_shop =
{
	name = "estore-shop",
	file = "estore-shop.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_estore_shop_SetNTVOptional()
{
    MarkNativeAsOptional("EStore_OpenShop");
    MarkNativeAsOptional("EStore_OpenShopCategory");
}
#endif
