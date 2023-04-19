#!/bin/bash

# hastebin_token=$HASTEBIN_API_TOKEN #replace this with your API token

hastebin_url="https://hastebin.com"
# cb_provider="lemonade"
debug_mode=false

clipboard=false
declare -A available_providers
available_providers=(["lemonade"]="lemonade copy" ["wl"]="wl-copy" ["wc"]="waycopy" ["doit"]="doitclient"])

input_files=()
cb_provider=""
# Functions we'll need
usage() {
  echo "Usage: hastebin [options] filename(s)
        
        Options:
        -t --token    Set Hastebin API token 
        -c --copy     Copy to clipboard
        -p --provider Specify a clipboard provider
        -d --debug    Debug mode: Disable file uploading

        Clipboard Providers:
        'lemonade'  - Lemonade copy
        'xclip'     - X11 clipboard
        'wl'        - wl-copy
        'wc'        - waycopy
        'doit'      - doitclien
        'wl'        - wl-copy
        'wc'        - waycopy
        'doit'      - doitclient"
  exit 2
}

debug(){
  if [ $debug_mode = true ] ; then
    printf "$1\n"
  fi
}

# Check for required tools
getopt -T 
if [ "$?" -ne 4 ]; then
  echo "Error: getopt isn't version 4"
  exit 1 
fi 

if ! [ -x "$(command -v jq)" ]; then
	  echo 'Error: jq is not installed.' >&2
	    exit 1
fi

if ! [ -x "$(command -v curl)" ]; then
	  echo 'Error: curl is not installed.' >&2
	    exit 1
fi


# Fetch parameters

params=$(getopt -o 'cdp:t:' --long 'copy,debug,provider:,token:' -- "$@")
if [ $# -eq 0 ]; then 
  usage 
fi

eval set -- "$params"
while [ "$#" -gt 0 ]; do 
  case "$1" in
    -c) 
      clipboard=true
      shift;;
    -d) 
      hastebin_url=""
      debug_mode=true
      shift;;
    -p)
      case "$2" in 
        "${!available_providers[@]}")
          debug "incoming provider: $2"
          cb_provider=$2
          ;;
        '')
          printf "Error: Illegal clipboard provider specified: $2\n"
          exit 1 
          ;;
      esac
      shift 2;;
    -t|--token) 
      case "$2" in 
        '')
          printf "\n -t argument: $#\n"
          printf "WARN: No API token supplied"
          ;;
        *)
          hastebin_token=$2
          shift 2;;
      esac
      shift 2;;
    --)
      shift;;
    *)
      printf "adding file"
      input_files+="$1 "
      shift;;
 esac
done



config_exists=false
file_token=""
file_clipboard=""
if [ -r "$HOME/.hastebin" ]; then
  debug "Existing config found"
  config_exists=true
  while read -r line; do 
    case "$line" in 
      token*)
        file_token="${line#*=}"
        ;;
      clipboard*)
        file_clipboard="${line#*=}"
        ;;
      *)
        debug "Unknown config line found: $line"
        ;;
    esac
  done < "$HOME/.hastebin"
elif [ -e "$HOME/.hastebin" ]; then
  debug "Config exists but is unreadable"
fi 


if [ -z "$hastebin_token" ]; then
  debug "No Token defined, checking Config"
  if [ $config_exists = false ]; then 
    printf "Error: No API token found. Use hastebin [-t | --token] to set one."
    exit 1 
  else 
    debug "Fetching token from config: $file_token"
    hastebin_token=$file_token
  fi 
else
  debug "Token found: $hastebin_token"
  file_token=$hastebin_token
fi   

if [ $clipboard = true ] && [ -z "$cb_provider" ]; then
  cb_provider=$file_clipboard
fi 

debug "provider: $cb_provider"
# Check that the specified clipboard provider works
if [ -z "$cb_provider" ]; then
  cb_provider="${available_providers["lemonade"]}"
fi; 
while  [ $clipboard = true ]  && ! [ -n "$(command -v ${available_providers[$cb_provider]})" ]; do 
  debug "Provider not found: ${available_providers[$cb_provider]}\n"
  for prov in "${available_providers[@]}"; do
    debug "looking for provider ${available_providers[$cb_provider]}"
    if  [ -x "$(command -v $prov)" ]; then
      debug "Found provider: $prov\n"
      cb_provider=$prov
      break 2;
    fi
    debug "Couldn't find clipboard provider: $prov"
  done
  printf "Error: Clipboard requested, but no clipboard provider found!"
  exit 1
done

file_clipboard=$cb_provider
echo "token=$file_token" > "$HOME/.hastebin"
echo "clipboard=$file_clipboard" >> "$HOME/.hastebin"


links=()
# Upload all supplied files to hastebin
for input in $input_files 
do 
  debug "Inputted files: $input"
  json=$(curl --request POST $hastebin_url/documents --header "content-type:text/plain"  --header "Authorization: Bearer $hastebin_token" --data "$(cat $input)")
  if ! [ "$(echo $json | jq '.message')" = null ]; then
    printf "Paste failed: $(echo $json | jq '.message')"
    exit 1 
  fi
  printf $json
  key=$(echo $json | jq '.key' | sed -e 's/^"//' -e 's/"$//')
  links+="$hastebin_url/share/$key"$'\n'
done

printf "Your files can be accessed at \n$links"

if [ "$clipboard" = true ]; then
  case $cb_provider in 
    lemonade)
      echo "$links" | lemonade copy
      ;; 
    wl)
      # TODO: implement wl-copy support
      ;;
    wc)
      # TODO: implement waycopy support
      ;;
    xclip)
      # TODO: implement xclip support
      ;;
  esac

  debug "copying to $cb_provider\n"
  printf "Hastebin links have been copied to clipboard\n"
fi
