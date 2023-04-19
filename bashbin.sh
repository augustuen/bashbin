#!/bin/bash

# hastebin_token=$HASTEBIN_API_TOKEN #replace this with your API token

hastebin_url="https://hastebin.com"
# cb_clipboard="lemonade"
debug_mode=false

clipboard=false
declare -A available_clipboards
available_clipboards=(["lemonade"]="lemonade copy" ["wl"]="wl-copy" ["wc"]="waycopy" ["doit"]="doitclient"])
description="Created with Bashbin script"
privacy=false

input_files=()
cb_clipboard=""
# Functions we'll need
usage() {
  echo "Usage: hastebin [options] filename(s)
        
        Options:
        -t --token        Set authoritzation token 
        -c --copy         Copy link to clipboard. Include [provider] to use a clipboard other than your default 
        -p --provider     Specify pastebin other than set in config
        -D --debug        Debug mode: Disable file uploading
        -d --description  Include a description for your paste. Not supported by all hosts

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
  printf "Debug triggered: $debug_mode"'\n'
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

params=$(getopt -o 'c:dp:t:' --long 'copy,debug,provider,token' -- "$@")
if [ $# -eq 0 ]; then 
  usage 
fi

printf "parameters:$params"'\n'
eval set -- "$params"
while [ "$#" -gt 0 ]; do 
  case "$1" in
    -c|--clipboard) 
      clipboard=true
      case "$2" in 
        "${!available_clipboards[@]}")
          debug "incoming clipboard provider: $2"
          cb_clipboard=$2
          ;;
        '')
          printf "Error: Illegal clipboard provider specified: $2\n"
          exit 1 
          ;;
      esac
      shift;;
    -D|--debug) 
      pastebin_host="debug"
      debug_mode=true
      shift;;
    -d|--description)
      # TODO: Implement description parameter 
      shift;;
    -p|--provider)
      printf "provider specified"
      pastebin_host=$2
      shift 2;;
    -t|--token)
      debug "Incoming token: $2"
      case "$2" in 
        '')
          printf "\n -t argument: $#\n"
          printf "WARN: No API token supplied"
          ;;
        github*)
          github_token=$2
          pastebin_host="github"
          shift 2;;
        *)
          hastebin_token=$2
          shift 2;;
      esac
      shift 2;;
    --)
      shift;;
    *)
      debug "adding file"
      input_files+="$1 "
      shift;;
 esac
done

debug "Debug mode enabled" 

config_exists=false
file_hastebin_token=""
file_github_token=""
file_clipboard=""
if [ -r "$HOME/.hastebin" ]; then
  printf "Existing config found"
  config_exists=true
  while read -r line; do 
    printf "Read line: $line"'\n'
    case "$line" in 
      pastebin*)
        privacy=false
        pastebin_host="${line#*=}"
        printf "found pastebin in config: $pastebin"
        ;;
      hastebin_token*)
        printf "found hastebin token"
        file_hastebin_token="${line#*=}"
        ;;
      github_token*)
        file_github_token="${line#*=}"
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
    debug "Error: No API token found. Use hastebin [-t | --token] to set one."
  else 
    debug "Fetching token from config: $file_hastebin_token"
    hastebin_token=$file_hastebin_token
  fi 
else
  debug "Hastebin token found: $hastebin_token"
  file_hastebin_token=$hastebin_token
fi   

if [ -z "$github_token" ]; then
  debug "No github token defined, checking Config"
  if [ $config_exists = false ]; then
    debug "Warn: No Github token found"
  else 
    debug "Fetching token from config: $file_github_token"
    github_token=$file_github_token
  fi 
else 
  debug "Found github token: $github_token"
  file_github_token=$hastebin_token
fi 

if [ $clipboard = true ] && [ -z "$cb_clipboard" ]; then
  cb_clipboard=$file_clipboard
fi 

# Check that the specified clipboard provider works
if [ -z "$cb_clipboard" ]; then
  cb_clipboard="${available_clipboards["lemonade"]}"
fi 
while  [ $clipboard = true ]  && ! [ -n "$(command -v ${available_clipboards[$cb_clipboard]})" ]; do 
  debug "Provider not found: ${available_clipboards[$cb_clipboard]}\n"
  for prov in "${available_clipboards[@]}"; do
    debug "looking for provider ${available_clipboards[$cb_clipboard]}"
    if  [ -x "$(command -v $prov)" ]; then
      debug "Found provider: $prov\n"
      cb_clipboard=$prov
      break 2;
    fi
    debug "Couldn't find clipboard provider: $prov"
  done
  printf "Error: Clipboard requested, but no clipboard provider found!"
  exit 1
done

file_clipboard=$cb_clipboard
echo "hastebin_token=$hastebin_token" > "$HOME/.hastebin"
echo "github_token=$github_token" >> "$HOME/.hastebin"
echo "clipboard=$file_clipboard" >> "$HOME/.hastebin"
echo "pastebin=$pastebin_host" >> "$HOME/.hastebin"


links=()
printf "pastebin_host: $pastebin_host"
# Upload all supplied files to hastebin
if [ "$pastebin_host" = "hastebin" ]; then
  debug "Uploading to hastebin. pastebin_host:$pastebin_host" 
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
elif [ "$pastebin_host" = "github" ]; then
  debug "Creating Github gist"
  files="" 
  for input in $input_files 
  do
    printf "Reading $input"
    if [ -r "$input" ]; then
      while read -r content_line; do 
        content+="$content_line"'\n'
      done < "$input"
    else 
      printf "Error: Couldn't read file: $input"
    fi
      file_name=$input 
      files+='"'"$file_name"'":{ "content":"'"$content"'"},'
  done 
  files=${files::-1}
  request_data='{"description":"'"$description"'", "public":"'"$privacy"'","files":{'"$files"'}}'
  printf "Data: $request_data"
  json=$(curl --request POST "https://api.github.com/gists"\
    --header "Accept: application/vnd.github+json"\
    --header "Authorization: Bearer $github_token" \
    --data "$request_data")
  printf "Response from github: $json"

  # Handle response
  links+=$(echo $json | jq '.html_url' | sed -e 's/^"//' -e 's/"$//')
  printf "Github finished"
else 
  debug "Invalid pastebin specified: $pastebin_host"
fi 

printf "Your files can be accessed at \n$links"

if [ "$clipboard" = true ]; then
  case $cb_clipboard in 
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

  debug "copying to $cb_clipboard\n"
  printf "Hastebin links have been copied to clipboard\n"
fi
