#!/bin/bash

cd F:/SourcePawn/Kunden/Razer/store-plugin/scripting
cp -R ./ F:/SourcePawn/sourcemod-1.8.0-git5973-windows/addons/sourcemod/scripting

cd F:/SourcePawn/sourcemod-1.8.0-git5973-windows/addons/sourcemod/scripting
find ./ -name 'estore*.sp' -exec ./spcomp '{}' \;

find ./ -name 'estore*.smx' -exec cp {} F:/SourcePawn/Kunden/Razer/store-plugin/plugins \;
find ./ -name 'estore*.smx' -exec rm {} \;

echo "Press any key to exit..."
read -p "$*"