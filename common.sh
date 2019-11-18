#!/bin/bash

echo_header() {
  printf "\n\e[1;33m%s\e[0m\n" "$1"
}

echo_status() {
  printf "%s %s %s\n" "---" "$1" "---"
}

contains() {
    [[ $1 =~ (^|,)$2($|,) ]] && return 0 || return 1
}

check_command_exists() {
  CMD_NAME=$1
  CMD_INSTALL_WITH=$([ -z "$2" ] && echo "" || printf "\nInstall using '%s'" "$2")
  command -v "$CMD_NAME" > /dev/null || {
    echo "Command $CMD_NAME not exists$CMD_INSTALL_WITH"
    exit 1
  }
}

check_dir_exists() {
  DIR=$1
  if ! [ -d "$DIR" ]; then
    echo "Cannot find $DIR"
    exit 1
  fi
}

check_file_exists() {
  FILE=$1
  if ! [ -f "$FILE" ]; then
    echo "Cannot find $FILE"
    exit 1
  fi
}