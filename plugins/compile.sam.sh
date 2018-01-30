#!/bin/bash

cd C:/Users/tjark/Documents/#Development/store-plugin/scripting
cp -R ./ C:/Users/tjark/Documents/#Development/sourcemod-1.8.0-git5973-windows/addons/sourcemod/scripting

cd C:/Users/tjark/Documents/#Development/sourcemod-1.8.0-git5973-windows/addons/sourcemod/scripting
find ./ -name 'estore*.sp' -exec ./spcomp '{}' \;

find ./ -name 'estore*.smx' -exec cp {} C:/Users/tjark/Documents/#Development/store-plugin/plugins \;
find ./ -name 'estore*.smx' -exec rm {} \;

echo "Press any key to exit..."
read -p "$*"