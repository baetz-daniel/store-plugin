#if defined _estore_bank_included
#endinput
#endif
#define _estore_bank_included


public SharedPlugin:__pl_estore_logging =
{
	name = "estore-bank",
	file = "estore-bank.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_estore_bank_SetNTVOptional()
{
}
#endif
