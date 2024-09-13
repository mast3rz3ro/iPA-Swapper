#!/bin/env bash


# This script are part of iPA-Swapper which is licensed under LGPL-2.1
# Copyright (c) 2024 mast3rz3ro

usage ()
{
	printf "Usage: whatsapp_media_organizer.sh [path]\n\n"
	printf "How to use in details:
	1. cp ./whatsapp_media_organizer.sh /usr/bin/whatsapp_media_organizer
	2. cd './net.whatsapp.WhatsApp/Message/Media'
	3. ./whatsapp_media_organizer\n"
	exit 0
}

move ()
{
	for y in $(find . -name *."$s"); do mv "$y" "$d"; done
}

remove ()
{
	for t in $(find . -name *."$s"); do rm "$t"; done
}

emptydir ()
{
	for e in $(find . -type d); do rmdir "$e"; done
}

sortdir ()
{
	for e in $(find . -type d); do mv "$e" $(printf "$e" | awk -F '@' '{print $1}'); done
}

if [ "$1" = "--h" ] || [ "$1" = "--help" ]; then
	usage
fi

for i in $(ls); do
	cd "$i"
	mkdir -p voices videos photos music others
	s="opus"; d="voices"; move
	s="jpg"; d="photos"; move
	s="mp4"; d="videos"; move
	s="m4a"; d="music"; move
	#s="thumb"; remove
	s="thumb"; d="others"; move
	s="webp"; d="others"; move
	s="zip"; d="others"; move
	s="mmsthumb"; d="others"; move
	emptydir
	cd ..
done

emptydir
sortdir