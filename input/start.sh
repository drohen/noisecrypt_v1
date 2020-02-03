#!/bin/bash

#######################################
#                                     #
#   _noisecrypt   (input)             #
#   author: Sludge, the Omnificent    #
#   date: 2020-01-06                  #
#                                     #
#######################################

# Prevent running in case of failures
set -euf -o pipefail

# Dep check flag

HAS_DEPS=0
hasDep() {
    if ! type "$1" > /dev/null; then
        echo "$1 not found."
        HAS_DEPS=1
    fi
}

# Check if all deps are on the machine

echo "Checking dependencies..."

hasDep "curl"
hasDep "icecast2"
hasDep "oggfwd"
hasDep "opusenc"
hasDep "openssl"

if ! test $HAS_DEPS; then exit 1; fi

echo "All dependencies are available."

# Get Host 

read -rp "What is your Host's IP address or URL? " HOST

if test "$HOST" = ""; then
    echo "You need a valid host."
    exit 1
fi

# Setup icecast config

USER="$(whoami)"
GROUP="$(id -g -n)"
HOSTNAME="$(hostname -I | cut -f1 -d ' ')"

# Create large random password
ADMIN_PASS="$(openssl rand -hex 64)"
SOURCE_PASS="$(openssl rand -hex 64)"

# Ensure the port is free

PORT="5482"

while true; do
    if ! netstat -an | grep "$PORT" &> /dev/null; then
        break
    fi

    read -rp "Port $PORT is currently in use. Please free this port in a separate shell then press ENTER, or press q then ENTER to quit. " CONFIRM

    if test "$CONFIRM" = "q"; then
        exit 0
    fi
done

# Generate (overwrite) icecast config

sed -e "s/{{source_pass}}/${SOURCE_PASS}/" \
    -e "s/{{admin_pass}}/${ADMIN_PASS}/" \
    -e "s/{{port}}/${PORT}/" \
    -e "s/{{user}}/${USER}/" \
    -e "s/{{group}}/${GROUP}/" \
    -e "s@{{host_name}}@${HOSTNAME}@" \
    icecast.template.xml > icecast.xml

mkdir -p log

# Run icecast in the background

sudo icecast2 -b -c icecast.xml

# Create a safe file name

TODAY="$( date +"%Y%m%d" )"
COUNT=0

SAVE_FILE="$TODAY.opus"

while test -e "$SAVE_FILE"; do
    printf -v SAVE_FILE -- '%s-%02d.opus' "$TODAY" "$(( ++COUNT ))"
done

HOST_PORT="2845"

# Send stream open cmd to API server

curl -X POST "$HOST:$HOST_PORT"

# On quit

EXIT_ALL() {
    trap - INT TERM ERR EXIT # clear trap
    
    # Kill processes
    pkill -9 icecast2 || true
    pkill -9 arecord || true
    
    # Send end cmd to API server
    curl -X DELETE "$HOST:$HOST_PORT"
}

trap "EXIT_ALL" INT TERM ERR EXIT

# Open stream

arecord -t raw -f cd -D plughw:1,0 \
    | opusenc --raw --raw-rate 44100 --comp 0 - - --quiet \
    | tee "$SAVE_FILE" \
    | oggfwd "$HOSTNAME" "$PORT" "$SOURCE_PASS" "/noisecrypt.opus"
