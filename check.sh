#!/usr/bin/env bash
bdip=$(curl https://loupde.github.io/bdip.txt --speed-time 10 --speed-limit 1)
if [ -z "$bdip" ]
then
      echo "\$bdip is empty"

else
    #替换第一行,   destAddr
    sed -i '' '28c\
    destAddr = '$bdip':443;
' filename.conf
    echo "\$bdip is NOT empty"
fi
