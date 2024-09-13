#!/usr/bin/bash

#########################################################################################################################
#                                                                                                                       #
#                                                                                                                       #
# Script Name: iPA Swapper                                                                                              #
# Description: Backup & restore iPA data, dump iPA and repack it into their original state, swap linked AppleID in iPA. #
# License: GNU LESSER GENERAL PUBLIC LICENSE Version 2.1                                                                #
# Copyright (c) 2024 mast3rz3ro                                                                                         #
#                                                                                                                       #
#                                                                                                                       #
#########################################################################################################################



# Function 0 (Check device and init script)
func_check (){
		if [ "$pnum" = '' ]; then pnum='2222'; fi # default port number for palera1n
		if [ "$plistutil" = '' ]; then echo "[!] Warning the 'plistutil' variable are not sest !"; fi
		
		# Setup SSH/SCP commands
		# please note that the "HostKeyAlgorithms=+ssh-rsa" parameter are used to avoid the message: "no matching host key type found. Their offer: ssh-rsa"
		ssh_cmd="sshpass -p alpine ssh -o HostKeyAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no -p $pnum root@localhost"
		scp_cmd="sshpass -p alpine scp -o HostKeyAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no -P $pnum"
		
device_mode=$($ssh_cmd "ls '/'")
if echo "$device_mode" | grep -o 'private' >/dev/nul; then
		echo '[-] Detected device in normal mode !'
		dir='/private/var' # e.g /private/var/mobile/Containers/Shared/AppGroup/
elif echo "$device_mode" | grep -o 'mnt1' >/dev/nul; then
		echo '[-] Detected device in ramdisk mode !'
		dir='/mnt2' # e.g /mnt2/mobile/Containers/Shared/AppGroup/
else
		echo '[!] Error cannot detect device mode !'
		exit 1
fi

	if [ ! -d  './logs' ] || [ ! -d './backup' ]; then
		echo '[-] Creating working dir ..'
		mkdir -p './logs' './backup'
	fi

		echo '------------------------------------------------------------' #check_device
}


# Function 1 (search for installed apps)
func_buid (){

if [ "$stage" = '5' ]; then
		# local ipa
	if [ -s "$ipa_list" ]; then
		if [ "$convert_type" = '2' ]; then
		buid=$(unzip -pq "$ipa_list" 'iTunesMetadata.plist' | $plistutil -p - | grep -A1 'softwareVersionBundleId' | sed -n 1p | awk -F '": "' '{print $2}' | awk -F '",' '{print $1}')
		else
		buid=$(tar -xf "$ipa_list" './iTunesMetadata.plist' -O | $plistutil -p - | grep -A1 'softwareVersionBundleId' | sed -n 1p | awk -F '": "' '{print $2}' | awk -F '",' '{print $1}')
		fi

		if [ "$buid" != '' ]; then
			echo "[-] Found BundelID (Binary): $buid"
		else
		echo "[e] Ops, couldn't read the app's BUID !"
		echo '[!] Saving the metadata into: ./logs/iTunesMetadata.plist'
		if [ "$convert_type" = '2' ]; then
		unzip -oq "$ipa_list" './logs/iTunesMetadata.plist'
		else
		tar -xf "$ipa_list" './iTunesMetadata.plist' -C './logs/iTunesMetadata.plist'
		fi
		echo '[!] Please make sure to attach this file when you want to report this error !'
		exit 1
		fi
	else
		echo '[e] Input file does not exist !'
	fi
else
		# normal mode
		directory="$dir"/containers/Bundle/Application/ # Apps directory
		metadata=$($ssh_cmd "find '$directory' -name 'iTunesMetadata.plist'" | sed 's/$/ /')
		ipa_list=$(echo -n $metadata | sed 's/iTunesMetadata.plist//g')
for x in $metadata; do
		tmp_var=$($ssh_cmd "grep -A1 'softwareVersionBundleId' '$x'" | sed -n 2p | awk -F '>' '{print $2}' | awk -F '<' '{print $1}' | sed 's/$/ /')
if [ "$tmp_var" != '' ]; then
		buid+="$tmp_var"
		echo '[-] Found BundelID (Plain):' "$tmp_var"
elif [ "$x" != '' ] && [ "$tmp_var" = '' ]; then
		# Trying method 2
	if [ "$plistutil" = '' ]; then
		echo "[e] Error couldn't find plistutil with variable 'plistutil'"
		exit
	elif [ "$plistutil" != '' ]; then
		tmp_var=$($ssh_cmd "cat '$x'" | $plistutil -p - | grep 'softwareVersionBundleId' | awk -F '": "' '{print $2}' | awk -F '",' '{print $1}' | sed 's/$/ /')
	if [ "$tmp_var" != '' ]; then
		buid+="$tmp_var"
		echo '[-] Found BundelID (Binary):' "$tmp_var"
	else
		echo "[e] Ops, couldn't read the app's BUID !"
		echo '[!] Saving the metadata into: ./logs/iTunesMetadata.plist'
		$ssh_cmd "cat '$x'">'./logs/iTunesMetadata.plist'
		echo '[!] Please make sure to attach this file when you want to report this error !'
		read -p 'Press enter to continue ...'
	fi
	fi
fi
done
fi

		# single mode
if [ "$stage" = '1' ]; then
		tmp_var=$(echo "$buid" | tr ' ' '\n' | grep -wnF "$target_buid" | awk -F ':' '{print $1}') # get line number for ipa
		ipa_list=$(echo "$ipa_list" | tr ' ' '\n' | sed -n "$tmp_var"p) # get ipa path by line number
		tmp_var=$(echo "$buid" | tr ' ' '\n' | grep -o "$target_buid" | sed -n 1p)
	if [ "$tmp_var" = "$target_buid" ]; then
		buid="$tmp_var"
		dump="$ipa_list"
	else
		echo '[e] BUID not found !'
		exit 1
	fi
fi
		
		# logs
		printf '\n'>>'./logs/buid.log'; date>>'./logs/buid.log'
		printf '\n'>>'./logs/apps.log'; date>>'./logs/apps.log'
		echo "$buid" | tr ' ' '\n'>>'./logs/buid.log'
		echo "$ipa_list" | tr ' ' '\n'>>'./logs/apps.log'
		
		echo '------------------------------------------------------------' #list

}


# Function 2 (app data finder)
func_finder (){

		echo '------------------------------------------------------------' #bundel

		# Clean variable just in case
		result=
		
for x in $buid; do
				
	if [ "$stage" = '2' ]; then # search for data 1
		echo "[-] Searching data for BUID: $x"
		directory="$dir"/mobile/Containers/Data/Application/
		pattern="$x"'.plist'
	elif [ "$stage" = '3' ]; then # search for data 2
		echo "[-] Searching data2 for BUID: $x"
		pattern='group.'"$x"'.shared.plist'
		directory="$dir"/mobile/Containers/Shared/AppGroup/
	fi
		tmp_var=$($ssh_cmd "find '$directory' -name '$pattern'" | tr -d '\n')
	if [ "$tmp_var" != '' ]; then
		result+=$(printf "$tmp_var" | awk -F 'Library/' '{print $1}' | sed 's/$/ /')
	elif [ "$tmp_var" = '' ]; then
		result+=$(printf 'notfound ')
	fi
done

	# write into logs
	if [ "$stage" = '2' ]; then
		data="$result"
		# logs
		printf '\n'>>'./logs/data.log'; date>>'./logs/data.log'
		echo "$data" | tr ' ' '\n'>>'./logs/data.log'
	elif [ "$stage" = '3' ]; then
		data2="$result"
		# logs
		printf '\n'>>'./logs/data.log'; date>>'./logs/data2.log'
		echo "$data2" | tr ' ' '\n'>>'./logs/data2.log'
	fi
}

# Function 3 (dump app/data)
func_dump (){

	if [ "$stage" = '1' ]; then # dump app
		dump="$ipa_list"
	elif [ "$stage" = '2' ]; then # dump data 1
		dump="$data"
	elif [ "$stage" = '3' ]; then # dump data 2
		dump="$data2"
	fi
		# sort the var with $1
		set $buid

for x in $dump; do

if [ "$x" != 'notfound' ]; then
		guid=$(echo "$x" | awk -F '//' '{print $2}' | sed 's\/\\')
if [ "$stage" = '1' ] && [ "$x" != 'notfound' ]; then # dump app
	if [ ! -s './backup/bundel_'"$1"'.tar.gz' ]; then
		echo "[-] Dumping app: $1"
		$ssh_cmd "cd '$x'; tar -cf - . | gzip -n">'./backup/bundel_'"$1"'.tar.gz'
	elif [ -s './backup/bundel_'"$1"'.tar.gz' ]; then
		echo '[-] File already exist skipping:' 'bundel_'"$1"'.tar.gz';
	fi
	
elif [ "$stage" = '2' ] && [ "$x" != 'notfound' ]; then # dump data 1
	if [ ! -s './backup/data_'"$1"'.tar.gz' ]; then
		echo "[-] Dumping data for: $1"
		$ssh_cmd "cd '$x'; tar -cf - . | gzip -n">'./backup/data_'"$1"'.tar.gz'
	elif [ -s './backup/data_'"$1"'.tar.gz' ]; then
		echo '[-] File already exist skipping:' 'data_'"$1"'.tar.gz'
	fi

	
elif [ "$stage" = '3' ] && [ "$x" != 'notfound' ]; then # dump data 2
	if [ ! -s './backup/data2_'"$1"'.tar.gz' ]; then
		echo "[-] Dumping data2 for: $1"
		$ssh_cmd "cd '$x'; tar -cf - . | gzip -n">'./backup/data2_'"$1"'.tar.gz'
	elif [ -s './backup/data2_'"$1"'.tar.gz' ]; then
		echo '[-] File already exist skipping:' 'data2_'"$1"'.tar.gz';
	fi
fi
fi		
		shift # shift into next element in $1
done
}


# Function 4 (Restore data)
func_restore (){

	if [ "$stage" = '2' ]; then
		restore="$data"
	elif [ "$stage" = '3' ]; then
		restore="$data2"
	fi
	
		# sort the var in $1
		set $buid

for x in $restore; do
		
if [ "$stage" = '2' ] && [ "$x" != 'notfound' ]; then
	if [ -s './backup/data_'"$1"'.tar.gz' ]; then
		echo "[-] Restoring data for: $1"
		$ssh_cmd "rm -Rf '$x'/*"; cat './backup/data_'"$1"'.tar.gz' | $ssh_cmd "tar -xzf - -C '$x'"
	fi
elif [ "$stage" = '3' ] && [ "$x" != 'notfound' ]; then
	if [ -s './backup/data2_'"$1"'.tar.gz' ]; then
		echo "[-] Restoring data2 for: $1"
		$ssh_cmd "rm -Rf '$x'/*"; cat './backup/data2_'"$1"'.tar.gz' | $ssh_cmd "tar -xzf - -C '$x'"
	fi
elif [ "$x" = 'notfound' ] && [ "$stage" = '2' ]; then
		# Stage 2 are the more important one !
		echo "[e] Please install the app before restoring their data !"
fi
	if [ "$stage" = '2' ] && [ ! -s './backup/data_'"$1"'.tar.gz' ]; then
		echo '[x] File not exist:' 'data_'"$1"'.tar.gz'
	elif [ "$stage" = '3' ] && [ ! -s './backup/data2_'"$1"'.tar.gz' ]; then
		echo '[x] File not exist:' 'data2_'"$1"'.tar.gz'
	fi
		shift # shift into next element in $1
done
}


# Function 5 (Convert to ipa)
func_convert (){
if [ "$stage" = '4' ]; then # option --convert-all
		convert_list=$(find './backup/' -name 'bundel_*')
	if [ "$convert_list" = '' ]; then
		echo '[e] No backup to convert'
		exit 1
	else
		buid=$(echo "$convert_list" | awk -F '.tar' '{print $1}' | awk -F 'bundel_' '{print $2}')
	fi
		
elif [ "$stage" = '5' ]; then # option --convert-app
		convert_list="$ipa_list"
fi
	
		set $buid
for x in $convert_list; do
		
		echo '------------------------------------------------------------' #restore
		output="$1.ipa"

if [ -s "./converted_apps/$output" ]; then
		echo "[!] Skipping already converted: '$output'"
elif [ ! -s "./converted_apps/$output" ]; then
		echo '[!] Cleaning temp dir ...'; rm -Rf './converted_apps/temp/Payload'; mkdir -p './converted_apps/temp/Payload'
		echo "[x] Extracting: '$1'"
	if [ "$convert_type" = '2' ]; then
		unzip -oq "$x" -d './converted_apps/temp'
		echo '[-] Converting metadata ...'
		$plistutil -i './converted_apps/temp/iTunesMetadata.plist' -o './converted_apps/temp/iTunesMetadata.plist' -f xml # force convert metadata to plain text
	else
		tar -xzf "$x" -C './converted_apps/temp/Payload'
		echo '[-] Converting metadata ...'
		$plistutil -i './converted_apps/temp/Payload/iTunesMetadata.plist' -o './converted_apps/temp/iTunesMetadata.plist' -f xml # force convert metadata to plain text
	fi

	if [ "$swap_appleid" = 'yes' ]; then
		func_swap # call function
	fi
		echo "[x] Removing dummy files"
		# clean payload from other unnecessary files
		rm -f $(find './converted_apps/temp/Payload/' -name '._*') # remove somename.app/._somename
		rm -f './converted_apps/temp/Payload/'*.plist; rm -f './converted_apps/temp/Payload/'.*.app; rm -f './converted_apps/temp/Payload/'.*.plist
		echo "[z] Compressing: '$1'"
		cd './converted_apps/temp/'; zip -qr '../'"$1"'.ipa' '.'; cd '..'; cd '..'
fi
		shift # switch to next element
done
		echo '[!] Cleaning temp dir ...'; rm -Rf './converted_apps/temp/'
}

# Function 6 (Convert to ipa)
func_swap (){
if [ "$plistutil" = '' ]; then
		echo "[e] Error couldn't find plistutil with variable 'plistutil'"
		exit 1
elif [ ! -s './converted_apps/temp/iTunesMetadata.plist' ]; then
		echo "[!] Warning the selected IPA doesn't contain 'iTunesMetadata.plist'"
elif [ "$plistutil" != '' ] || [ -s './converted_apps/temp/Payload/iTunesMetadata.plist' ]; then
		echo '[-] Searching for linked AppleID ...'
		# logs
		printf '\n'>>'./logs/swap.log'; date>>'./logs/swap.log'
		grep -B10 '@' './converted_apps/temp/iTunesMetadata.plist'>>'./logs/swap.log'
	if (grep -o '<key>apple-id</key>' './converted_apps/temp/iTunesMetadata.plist' >/dev/null); then
		tmp_var=$(grep -A1 '<key>apple-id</key>' './converted_apps/temp/iTunesMetadata.plist' | sed -n 2p | awk -F '</' '{print $1}' | awk -F '>' '{print $2}')
	if [ "$tmp_var" != "$appleid" ]; then
		echo "[-] Swaping pattern 1: '$tmp_var' with '$appleid'"
		id1=$(grep -nA1 '<key>apple-id</key>' './converted_apps/temp/iTunesMetadata.plist' | sed -n 2p | awk -F '-' '{print $1}') # get line number
		sed -i "$id1""s_.*_\t<string>"$appleid"</string>_" './converted_apps/temp/iTunesMetadata.plist'
	fi
	fi
	if (grep -o '<key>appleId</key>' './converted_apps/temp/iTunesMetadata.plist' >/dev/null); then
		tmp_var=$(grep -A1 '<key>appleId</key>' './converted_apps/temp/iTunesMetadata.plist' | sed -n 2p | awk -F '</' '{print $1}' | awk -F '>' '{print $2}')
	if [ "$tmp_var" != "$appleid" ]; then
		echo "[-] Swaping pattern 2: '$tmp_var' with '$appleid'"
		id2=$(grep -nA1 '<key>appleId</key>' './converted_apps/temp/iTunesMetadata.plist' | sed -n 2p | awk -F '-' '{print $1}') # get line number
		sed -i "$id2""s_.*_\t<string>"$appleid"</string>_" './converted_apps/temp/iTunesMetadata.plist'
	fi
	fi
	if (grep -o '<key>AppleID</key>' './converted_apps/temp/iTunesMetadata.plist' >/dev/null); then
		tmp_var=$(grep -A1 '<key>AppleID</key>' './converted_apps/temp/iTunesMetadata.plist' | sed -n 2p | awk -F '</' '{print $1}' | awk -F '>' '{print $2}')
	if [ "$tmp_var" != "$appleid" ]; then
		echo "[-] Swaping pattern 3: '$tmp_var' with '$appleid'"
		id3=$(grep -nA1 '<key>AppleID</key>' './converted_apps/temp/iTunesMetadata.plist' | sed -n 2p | awk -F '-' '{print $1}') # get line number
		sed -i "$id3""s_.*_\t<string>"$appleid"</string>_" './converted_apps/temp/iTunesMetadata.plist'
	fi
	fi
	if (grep -io '<key>userName</key>' './converted_apps/temp/iTunesMetadata.plist' >/dev/null); then
		tmp_var=$(grep -A1 '<key>userName</key>' './converted_apps/temp/iTunesMetadata.plist' | sed -n 2p | awk -F '</' '{print $1}' | awk -F '>' '{print $2}')
	if [ "$tmp_var" != "$appleid" ]; then
		echo "[-] Swaping pattern 4: '$tmp_var' with '$appleid'"
		id4=$(grep -nA1 '<key>userName</key>' './converted_apps/temp/iTunesMetadata.plist' | sed -n 2p | awk -F '-' '{print $1}') # get line number
		sed -i "$id4""s_.*_\t<string>"$appleid"</string>_" './converted_apps/temp/iTunesMetadata.plist'
	fi
	fi
fi
}


func_help (){
		echo 'iPA Swapper v1.0'
		echo 'MIT License Copyright (c) 2024 mast3rz3ro'
		echo ''
		echo 'Usage: ipa-swapper.sh [options]'
		echo ''
		echo ' Main parameters:'
		echo '  -b, --backup     Backup specific app with data (App+Data)'
		echo "  -r, --restore    Restore specific app's data (Data only)"
		echo '  -l, --list       List installed apps (List Bundel IDs)'
		echo ''
		echo ' Batch operations:'
		echo '  --all-with-data'
		echo '              Backup all installed apps with their data'
		echo '  --all-without-data'
		echo '              Backup all apps without their data'
		echo '  --convert-all'
		echo '              Convert dumped apps into IPA'
		echo ''
		echo ' Advanced parameters:'
		echo '  --app-only     Backup specific app without data (App only)
		e.g --app-only com.someapp.name'
		echo '  --convert-app  Convert specific dumped app into IPA
		e.g --convert-app bundel_buid.tar.gz or --convert-app com.someapp.name.ipa
		Note: this parameter can be used for both dumped or normal iPA.
		'
		echo "  --appleid      Try to swap appleid used to download the iPA
		Requires: '--convert-all' or '--convert-app'"
		echo '  --port         Specify the port number to use in SSH command'
		echo ''
		echo '  -h, --help     Show this message'
		exit 1
}


		#######################
		# Optional parameters #
		#######################
		
while true; do
	case "$1" in
		--port) pnum="$2"; shift;;
		--appleid) appleid="$2"; shift;;
		*) break
	esac
shift
done

if [ "$appleid" != '' ]; then
		tmp_var=$(echo $appleid | grep -o '@')
	if [ "$tmp_var" = '@' ]; then
		swap_appleid='yes' # enable appleid swap
	else
		echo '[e] Please enter a valid AppleID (e.g example@gmail.com).'
		exit 1
	fi
fi

		###################
		# Main parameters #
		###################
	
while true; do
	case "$1" in
		-b|--backup) target_buid="$2"; task='-b'; shift;;
		-r|--restore) target_buid="$2"; task='-r'; shift;;
		--app-only) target_buid="$2"; task='--app-only'; shift;;
		-l|--list) func_check; func_buid; exit; shift;;
		--convert-all) stage='4'; func_convert; exit; shift;;
		--convert-app) target_buid="$2"; task='--convert-app'; shift;;
		--all-with-data) task='--all-with-data'; shift;;
		--all-without-data) task='--all-without-data'; shift;;
		-h|--help) func_help; shift;;
		*) break
	esac
shift
done


if [ "$target_buid" != '' ]; then
	if [ "$task" = '-b' ]; then
		func_check # call function
		stage='1'; func_buid; func_dump # call functions
		stage='2'; func_finder; func_dump # call functions
		stage='3'; func_finder; func_dump # call functions
		exit # exit after completed	
	elif [ "$task" = '-r' ]; then
		func_check # call function
		stage='1'; func_buid # call function
		stage='2'; func_finder; func_restore # call functions
		stage='3'; func_finder; func_restore # call functions
		exit # exit after completed
	elif [ "$task" = '--app-only' ]; then
		func_check # call function
		stage='1'; func_buid; func_dump # call functions
		exit # exit after completed
	elif [ "$task" = '--convert-app' ]; then
		tmp_var=$(echo "$target_buid" | grep -o '.tar.gz')
		tmp_var2=$(echo "$target_buid" | grep -o '.ipa')
	if [ "$tmp_var" = '.tar.gz' ] || [ "$tmp_var2" = '.ipa' ]; then
		if [ "$tmp_var" = '.tar.gz' ]; then convert_type='1'; fi
		if [ "$tmp_var2" = '.ipa' ]; then convert_type='2'; fi
		ipa_list="$target_buid"
		stage='5'; func_buid # call function
		stage='5'; func_convert # call function
		exit
	else
		echo '[e] The selected IPA is invalid.'
		exit 1
	fi
	else
		echo '[e] invalid BUID'
		exit 1
	fi
elif [ "$task" = '--all-without-data' ]; then
		func_check # call function
		func_buid # call function (do not call with stage 1)
		stage='1'; func_dump # call function
		exit # exit after completed
		
elif [ "$task" = '--all-with-data' ]; then
		func_check # call function
		func_buid # call function (do not call with stage 1)
		stage='1'; func_dump # call function
		stage='2'; func_finder; func_dump # call functions
		stage='3'; func_finder; func_dump # call functions
		exit # exit after completed
else
		echo '[e] Invalid parameter'
		exit 1
fi


