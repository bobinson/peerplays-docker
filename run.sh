#!/bin/bash
#
# Steem node manager
# Released under GNU AGPL by Someguy123
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
: ${DOCKER_DIR="$DIR/dkr"}
: ${FULL_DOCKER_DIR="$DIR/dkr_fullnode"}
: ${DATADIR="$DIR/data"}
: ${DOCKER_NAME="seed"}

# the tag to use when running/replaying steemd
: ${DOCKER_IMAGE="steem"}


# HTTP or HTTPS url to grab the blockchain from. Set compression in BC_HTTP_CMP
: ${BC_HTTP="http://files.privex.io/steem/block_log.lz4"}

# Compression type, can be "xz", "lz4", or "no" (for no compression)
# Uses on-the-fly de-compression while downloading, to conserve disk space
# and save time by not having to decompress after the download is finished
: ${BC_HTTP_CMP="lz4"}

# Anonymous rsync daemon URL to the raw block_log, for repairing/resuming
# a damaged/incomplete block_log. Set to "no" to disable rsync when resuming.
: ${BC_RSYNC="rsync://files.privex.io/steem/block_log"}

BOLD="$(tput bold)"
RED="$(tput setaf 1)"
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"
BLUE="$(tput setaf 4)"
MAGENTA="$(tput setaf 5)"
CYAN="$(tput setaf 6)"
WHITE="$(tput setaf 7)"
RESET="$(tput sgr0)"
: ${DK_TAG="someguy123/steem:latest"}
: ${DK_TAG_FULL="someguy123/steem:latest-full"}
: ${SHM_DIR="/dev/shm"}
: ${REMOTE_WS="wss://steemd.privex.io"}

# default. override in .env
: ${PORTS="2001"}

if [[ -f .env ]]; then
    source .env
fi

# blockchain folder, used by dlblocks
: ${BC_FOLDER="$DATADIR/witness_node_data_dir/blockchain"}

: ${EXAMPLE_CONF="$DATADIR/witness_node_data_dir/config.ini.example"}
: ${CONF_FILE="$DATADIR/witness_node_data_dir/config.ini"}

# if the config file doesn't exist, try copying the example config
if [[ ! -f "$CONF_FILE" ]]; then
    if [[ -f "$EXAMPLE_CONF" ]]; then
        echo "${YELLOW}File config.ini not found. copying example (seed)${RESET}"
        cp -v "$DATADIR/witness_node_data_dir/config.ini.example" "$DATADIR/witness_node_data_dir/config.ini" 
        echo "${GREEN} > Successfully installed example config for seed node.${RESET}"
        echo " > You may want to adjust this if you're running a witness, e.g. disable p2p-endpoint"
    else
        echo "${YELLOW}WARNING: You don't seem to have a config file and the example config couldn't be found...${RESET}"
        echo "${YELLOW}${BOLD}You may want to check these files exist, or you won't be able to launch Steem${RESET}"
        echo "Example Config: $EXAMPLE_CONF"
        echo "Main Config: $CONF_FILE"
    fi
fi

IFS=","
DPORTS=()
for i in $PORTS; do
    if [[ $i != "" ]]; then
	    DPORTS+=("-p0.0.0.0:$i:$i")
    fi
done

# load docker hub API
source scripts/000_docker.sh

help() {
    echo "Usage: $0 COMMAND [DATA]"
    echo
    echo "Commands: 
    start - starts steem container
    dlblocks - download and decompress the blockchain to speed up your first start
    replay - starts steem container (in replay mode)
    shm_size - resizes /dev/shm to size given, e.g. ./run.sh shm_size 10G 
    stop - stops steem container
    status - show status of steem container
    restart - restarts steem container
    install_docker - install docker
    install - pulls latest docker image from server (no compiling)
    install_full - pulls latest (FULL NODE FOR RPC) docker image from server (no compiling)
    rebuild - builds steem container (from docker file), and then restarts it
    build - only builds steem container (from docker file)
    logs - show all logs inc. docker logs, and steem logs
    wallet - open cli_wallet in the container
    remote_wallet - open cli_wallet in the container connecting to a remote seed
    enter - enter a bash session in the currently running container
    shell - launch the steem container with appropriate mounts, then open bash for inspection
    "
    echo
    exit
}

APT_UPDATED="n"
pkg_not_found() {
    # check if a command is available
    # if not, install it from the package specified
    # Usage: pkg_not_found [cmd] [apt-package]
    # e.g. pkg_not_found git git
    if [[ $# -lt 2 ]]; then
        echo "${RED}ERR: pkg_not_found requires 2 arguments (cmd) (package)${NORMAL}"
        exit
    fi
    local cmd=$1
    local pkg=$2
    if ! [ -x "$(command -v $cmd)" ]; then
        echo "${YELLOW}WARNING: Command $cmd was not found. installing now...${NORMAL}"
        if [[ "$APT_UPDATED" == "n" ]]; then
            sudo apt update -y
            APT_UPDATED="y"
        fi
        sudo apt install -y "$pkg"
    fi
}

optimize() {
    echo    75 | sudo tee /proc/sys/vm/dirty_background_ratio
    echo  1000 | sudo tee /proc/sys/vm/dirty_expire_centisecs
    echo    80 | sudo tee /proc/sys/vm/dirty_ratio
    echo 30000 | sudo tee /proc/sys/vm/dirty_writeback_centisecs
}

# Build standard low memory node as a docker image
# Usage: ./run.sh build [version]
# Version is prefixed with v, matching steem releases
# e.g. build v0.20.6
build() {
    if (( $# == 1 )); then
        BUILD_VER=$1
        echo "${BLUE}CUSTOM BUILD SPECIFIED. Building from branch/tag ${BUILD_VER}${RESET}"
        sleep 2
        cd $DOCKER_DIR
        CUST_TAG="steem:$BUILD_VER"
        docker build --build-arg "steemd_version=$BUILD_VER" -t "$CUST_TAG" .
        echo "${RED}
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
        For your safety, we've tagged this image as $CUST_TAG
        To use it in this steem-docker, run: 
        ${GREEN}${BOLD}
        docker tag $CUST_TAG steem:latest
        ${RESET}${RED}
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
        ${RESET}
        "
        return
    fi
    echo $GREEN"Building docker container"$RESET
    cd $DOCKER_DIR
    docker build -t "$DOCKER_IMAGE" .
}

# Build full memory node (for RPC nodes) as a docker image
# Usage: ./run.sh build_full [version]
# Version is prefixed with v, matching steem releases
# e.g. build_full v0.20.6
build_full() {
    if (( $# == 1 )); then
        BUILD_VER=$1
        echo $BLUE"CUSTOM (FULL NODE) BUILD SPECIFIED. Building from branch/tag $BUILD_VER"$RESET
        sleep 2
        cd $FULL_DOCKER_DIR
        CUST_TAG="steem:$BUILD_VER-full"
        docker build --build-arg "steemd_version=$BUILD_VER" -t "$CUST_TAG" .
        echo "${RED}
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
        For your safety, we've tagged this image as $CUST_TAG
        To use it in this steem-docker, run: 
        ${GREEN}${BOLD}
        docker tag $CUST_TAG steem:latest
        ${RESET}${RED}
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
        ${RESET}
        "
        return
    fi
    echo $GREEN"Building full-node docker container"$RESET
    cd $FULL_DOCKER_DIR
    docker build -t "$DOCKER_IMAGE" .
}

# Usage: ./run.sh dlblocks [override_dlmethod] [url] [compress]
# Download the block_log from a remote server and de-compress it on-the-fly to save space, 
# then places it correctly into $BC_FOLDER
# Automatically attempts to resume partially downloaded block_log's using rsync, or http if
# rsync is disabled in .env
# 
#   override_dlmethod - use this to force downloading a certain way (OPTIONAL)
#                     choices:
#                       - rsync - download via rsync, resume if exists, using append-verify and ignore times
#                       - rsync-replace - download whole file via rsync, delete block_log before download
#                       - http - download via http. if uncompressed, try to resume when possible
#                       - http-replace - do not attempt to resume. delete block_log before download
#
#   url - Download/install block log using the supplied dlmethod from this url. (OPTIONAL)
#
#   compress -  Only valid for http/http-replace. Decompress the file on the fly. (OPTIONAL)
#               options: xz, lz4, no (no compression) 
#               if a custom url is supplied, but no compression method, it is assumed it is raw and not compressed.
#
# Example: The default compressed lz4 download failed, but left it's block_log in place. 
# You don't want to use rsync to resume, because your network is very fast
# Instead, you can continue your download using the uncompressed version over HTTP:
#
#   ./run.sh dlblocks http "http://files.privex.io/steem/block_log"
#
# Or just re-download the whole uncompressed file instead of resuming:
#
#   ./run.sh dlblocks http-replace "http://files.privex.io/steem/block_log"
#
dlblocks() {
    pkg_not_found rsync rsync
    pkg_not_found lz4 liblz4-tool
    pkg_not_found xz xz-utils
    
    [[ ! -d "$BC_FOLDER" ]] && mkdir -p "$BC_FOLDER"
    [[ -f "$BC_FOLDER/block_log.index" ]] && echo "Removing old block index" && sudo rm -vf "$BC_FOLDER/block_log.index" 2> /dev/null

    if (( $# > 0 )); then
        custom-dlblocks "$@"
        return $?
    fi
    if [[ -f "$BC_FOLDER/block_log" ]]; then
        echo "${YELLOW}It looks like block_log already exists${RESET}"
        if [[ "$BC_RSYNC" == "no" ]]; then
            echo "${RED}As BC_RSYNC is set to 'no', we're just going to try to retry the http download${RESET}"
            echo "If your HTTP source is uncompressed, we'll try to resume it"
            dl-blocks-http "$BC_HTTP" "$BC_HTTP_CMP"
            return
        else
            echo "${GREEN}We'll now use rsync to attempt to repair any corruption, or missing pieces from your block_log.${RESET}"
            dl-blocks-rsync "$BC_RSYNC"
            return
        fi
    fi
    echo "No existing block_log found. Will use standard http to download, and will also 
decompress lz4 while downloading, to save time."
    echo "If you encounter an error while downloading the block_log, just run dlblocks again, 
and it will use rsync to resume and repair it"
    dl-blocks-http "$BC_HTTP" "$BC_HTTP_CMP" 
    echo "FINISHED. Blockchain installed to ${BC_FOLDER}/block_log (make sure to check for any errors above)"
    echo "${RED}If you encountered an error while downloading the block_log, just run dlblocks again
    and it will use rsync to resume and repair it${RESET}"
    echo "Remember to resize your /dev/shm, and run with replay!"
    echo "$ ./run.sh shm_size SIZE (e.g. 8G)"
    echo "$ ./run.sh replay"
}

custom-dlblocks() {
    local compress="no" # to be overriden if we have 2+ args
    local dlvia="$1"
    local url;

    if (( $# > 1 )); then
        url="$2"
    else
        if [[ "$dlvia" == "rsync" ]]; then url="$BC_RSYNC"; else url="$BC_HTTP"; fi
        compress="$BC_HTTP_CMP"
    fi
    (( $# >= 3 )) && compress="$3"

    case "$dlvia" in
        rsync)
            dl-blocks-rsync "$url"
            return $?
            ;;
        rsync-replace)
            echo "Removing old block_log..."
            sudo rm -vf "$BC_FOLDER/block_log"
            dl-blocks-rsync "$url"
            return $?
            ;;
        http)
            dl-blocks-http "$url" "$compress"
            return $? 
            ;;
        http-replace)
            echo "Removing old block_log..."
            sudo rm -vf "$BC_FOLDER/block_log"
            dl-blocks-http "$url" "$compress"
            return $?
            ;;
        *)
            echo "Invalid download method"
            echo "Valid options are http, http-replace, rsync, or rsync-replace"
            return 1
            ;;
    esac 
}

# Internal use
# Usage: dl-blocks-rsync blocklog_url
dl-blocks-rsync() {
    local url="$1"
    echo "This may take a while, and may at times appear to be stalled. ${YELLOW}${BOLD}Be patient, it takes time (3 to 10 mins) to scan the differences.${RESET}"
    echo "Once it detects the differences, it will download at very high speed depending on how much of your block_log is intact."
    echo -e "\n==============================================================="
    echo -e "${BOLD}Downloading via:${RESET}\t${url}"
    echo -e "${BOLD}Writing to:${RESET}\t\t${BC_FOLDER}/block_log"
    echo -e "===============================================================\n"
    # I = ignore timestamps and size, vv = be more verbose, h = human readable
    # append-verify = attempt to append to the file, but make sure to verify the existing pieces match the server
    rsync -Ivvh --append-verify --progress "$url" "${BC_FOLDER}/block_log"
    ret=$?
    if (($ret==0)); then
        echo "FINISHED. Blockchain downloaded via rsync (make sure to check for any errors above)"
    else
        echo "${RED}An error occurred while downloading via rsync... please check above for errors${RESET}"
    fi
    return $ret
}

# Internal use
# Usage: dl-blocks-http blocklog_url [compress_type]
dl-blocks-http() {
    local url="$1"
    local compression="no"
    (( $# < 1 )) && echo "ERROR: no url specified for dl-blocks-http"
    if (( $# == 2 )); then
        compression="$2"
        if [[ "$2" != "lz4" && "$2" != "xz" && "$2" != "no" ]]; then
            echo "${RED}ERROR: Unknown compression type '$2' passed to dl-blocks-http.${RESET}"
            echo "Please correct your http compression type."
            echo "Choices: lz4, xz, no (for uncompressed)"
            return 1
        fi
    fi
    echo -e "\n==============================================================="
    echo -e "${BOLD}Downloading via:${RESET}\t${url}"
    echo -e "${BOLD}Writing to:${RESET}\t\t${BC_FOLDER}/block_log"
    [[ "$compression" != "no" ]] && \
        echo -e "${BOLD}Compression:${RESET}\t\t$compression"
    echo -e "===============================================================\n"

    if [[ "$compression" != "no" ]]; then 
        echo "${GREEN}${BOLD}Downloading and de-compressing block log on-the-fly...${RESET}"
    else
        echo "${GREEN}${BOLD}Downloading raw block log...${RESET}"
    fi

    case "$compression" in 
        lz4)
            wget "$url" -O - | lz4 -dv - "$BC_FOLDER/block_log"
            ;;
        xz)
            wget "$url" -O - | xz -dvv - "$BC_FOLDER/block_log"
            ;;
        no)
            wget -c "$url" -O "$BC_FOLDER/block_log"
            ;;
    esac
    ret=$?
    if (($ret==0)); then
        echo "FINISHED. Blockchain downloaded and decompressed (make sure to check for any errors above)"
    else
        echo "${RED}An error occurred while downloading... please check above for errors${RESET}"
    fi
    return $ret
}

# Usage: ./run.sh install_docker
# Downloads and installs the latest version of Docker using the Get Docker site
# If Docker is already installed, it should update it.
install_docker() {
    sudo apt update
    # curl/git used by docker, xz/lz4 used by dlblocks, jq used by tslogs/pclogs
    sudo apt install curl git xz-utils liblz4-tool jq
    curl https://get.docker.com | sh
    if [ "$EUID" -ne 0 ]; then 
        echo "Adding user $(whoami) to docker group"
        sudo usermod -aG docker $(whoami)
        echo "IMPORTANT: Please re-login (or close and re-connect SSH) for docker to function correctly"
    fi
}

# Usage: ./run.sh install [tag]
# Downloads the Steem low memory node image from someguy123's official builds, or a custom tag if supplied
#
#   tag - optionally specify a docker tag to install from. can be third party
#         format: user/repo:version    or   user/repo   (uses the 'latest' tag)
#
# If no tag specified, it will download the pre-set $DK_TAG in run.sh or .env
# Default tag is normally someguy123/steem:latest (official builds by the creator of steem-docker).
#
install() {
    if (( $# == 1 )); then
        DK_TAG=$1
    fi
    echo $BLUE"NOTE: You are installing image $DK_TAG. Please make sure this is correct."$RESET
    sleep 2
    docker pull $DK_TAG 
    echo "Tagging as steem"
    docker tag $DK_TAG steem
    echo "Installation completed. You may now configure or run the server"
}

# Usage: ./run.sh install_full
# Downloads the Steem full node image from the pre-set $DK_TAG_FULL in run.sh or .env
# Default tag is normally someguy123/steem:latest-full (official builds by the creator of steem-docker).
#
install_full() {
    echo "Loading image from someguy123/steem"
    docker pull $DK_TAG_FULL 
    echo "Tagging as steem"
    docker tag $DK_TAG_FULL steem
    echo "Installation completed. You may now configure or run the server"
}

# Internal Use Only
# Checks if the container $DOCKER_NAME exists. Returns 0 if it does, -1 if not.
# Usage:
# if seed_exists; then echo "true"; else "false"; fi
#
seed_exists() {
    seedcount=$(docker ps -a -f name="^/"$DOCKER_NAME"$" | wc -l)
    if [[ $seedcount -eq 2 ]]; then
        return 0
    else
        return -1
    fi
}

# Internal Use Only
# Checks if the container $DOCKER_NAME is running. Returns 0 if it's running, -1 if not.
# Usage:
# if seed_running; then echo "true"; else "false"; fi
#
seed_running() {
    seedcount=$(docker ps -f 'status=running' -f name=$DOCKER_NAME | wc -l)
    if [[ $seedcount -eq 2 ]]; then
        return 0
    else
        return -1
    fi
}

# Usage: ./run.sh start
# Creates and/or starts the Steem docker container
start() {
    echo $GREEN"Starting container..."$RESET
    seed_exists
    if [[ $? == 0 ]]; then
        docker start $DOCKER_NAME
    else
        docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/peerplays -d --name $DOCKER_NAME -t "$DOCKER_IMAGE" witness_node --data-dir=/peerplays/witness_node_data_dir
    fi
}

# Usage: ./run.sh replay
# Replays the blockchain for the Steem docker container
# If steem is already running, it will ask you if you still want to replay
# so that it can stop and remove the old container
#
replay() {
    seed_running
    if [[ $? == 0 ]]; then
        echo $RED"WARNING: Your Steem server ($DOCKER_NAME) is currently running"$RESET
	echo
        docker ps
	echo
	read -p "Do you want to stop the container and replay? (y/n) > " shouldstop
        if [[ "$shouldstop" == "y" ]]; then
		stop
	else
		echo $GREEN"Did not say 'y'. Quitting."$RESET
		return
	fi
    fi 
    echo "Removing old container"
    docker rm $DOCKER_NAME
    echo "Running steem with replay..."
    docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t "$DOCKER_IMAGE" steemd --data-dir=/steem/witness_node_data_dir --replay
    echo "Started."
}

# Usage: ./run.sh shm_size size
# Resizes the ramdisk used for storing Steem's shared_memory at /dev/shm
# Size should be specified with G (gigabytes), e.g. ./run.sh shm_size 64G
#
shm_size() {
    if (( $# != 1 )); then
        echo $RED"Please specify a size, such as ./run.sh shm_size 64G"
    fi
    echo "Setting /dev/shm to $1"
    sudo mount -o remount,size=$1 /dev/shm
    if [[ $? -eq 0 ]]; then
        echo "${GREEN}Successfully resized /dev/shm${RESET}"
    else
        echo "${RED}An error occurred while resizing /dev/shm...${RESET}"
        echo "Make sure to specify size correctly, e.g. 64G. You can also try using sudo to run this."
    fi
}

# Usage: ./run.sh stop
# Stops the Steem container, and removes the container to avoid any leftover
# configuration, e.g. replay command line options
#
stop() {
    echo $RED"Stopping container..."$RESET
    docker stop $DOCKER_NAME
    echo $RED"Removing old container..."$RESET
    docker rm $DOCKER_NAME
}

# Usage: ./run.sh enter
# Enters the running docker container and opens a bash shell for debugging
#
enter() {
    docker exec -it $DOCKER_NAME bash
}

# Usage: ./run.sh shell
# Runs the container similar to `run` with mounted directories, 
# then opens a BASH shell for debugging
# To avoid leftover containers, it uses `--rm` to remove the container once you exit.
#
shell() {
    docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem --rm -it "$DOCKER_IMAGE" bash
}


# Usage: ./run.sh wallet
# Opens cli_wallet inside of the running Steem container and
# connects to the local steemd over websockets on port 8090
#
wallet() {
    docker exec -it $DOCKER_NAME cli_wallet -s ws://127.0.0.1:8090
}

# Usage: ./run.sh remote_wallet [wss_server]
# Connects to a remote websocket server for wallet connection. This is completely safe
# as your wallet/private keys are never sent to the remote server.
#
# By default, it will connect to wss://steemd.privex.io:443 (ws = normal websockets, wss = secure HTTPS websockets)
# See this link for a list of WSS nodes: https://www.steem.center/index.php?title=Public_Websocket_Servers
# 
#    wss_server - a custom websocket server to connect to, e.g. ./run.sh remote_wallet wss://rpc.steemviz.com
#
remote_wallet() {
    if (( $# == 1 )); then
        REMOTE_WS=$1
    fi
    docker run -v "$DATADIR":/steem --rm -it "$DOCKER_IMAGE" cli_wallet -s "$REMOTE_WS"
}

# Usage: ./run.sh logs
# Shows the last 30 log lines of the running steem container, and follows the log until you press ctrl-c
#
logs() {
    echo $BLUE"DOCKER LOGS: (press ctrl-c to exit) "$RESET
    docker logs -f --tail=30 $DOCKER_NAME
    #echo $RED"INFO AND DEBUG LOGS: "$RESET
    #tail -n 30 $DATADIR/{info.log,debug.log}
}

# Usage: ./run.sh pclogs
# (warning: may require root to work properly in some cases)
# Used to watch % replayed during blockchain replaying.
# Scans and follows a large portion of your steem logs then filters to only include the replay percentage
#   example:    2018-12-08T23:47:16    22.2312%   6300000 of 28338603   (60052M free)
#
pclogs() {
    if [[ ! $(command -v jq) ]]; then
        echo $RED"jq not found. Attempting to install..."$RESET
        sleep 3
        sudo apt update
        sudo apt install -y jq
    fi
    local LOG_PATH=$(docker inspect $DOCKER_NAME | jq -r .[0].LogPath)
    local pipe=/tmp/dkpipepc.fifo
    trap "rm -f $pipe" EXIT
    if [[ ! -p $pipe ]]; then
        mkfifo $pipe
    fi
    # the sleep is a dirty hack to keep the pipe open

    sleep 10000 < $pipe &
    tail -n 5000 -f "$LOG_PATH" &> $pipe &
    while true
    do
        if read -r line <$pipe; then
            # first grep the data for "M free" to avoid
            # needlessly processing the data
            L=$(grep --colour=never "M free" <<< "$line")
            if [[ $? -ne 0 ]]; then
                continue
            fi
            # then, parse the line and print the time + log
            L=$(jq -r ".time +\" \" + .log" <<< "$L")
            # then, remove excessive \r's causing multiple line breaks
            L=$(sed -e "s/\r//" <<< "$L")
            # now remove the decimal time to make the logs cleaner
            L=$(sed -e 's/\..*Z//' <<< "$L")
            # and finally, strip off any duplicate new line characters
            L=$(tr -s "\n" <<< "$L")
            printf '%s\r\n' "$L"
        fi
    done
}

# Usage: ./run.sh tslogs
# (warning: may require root to work properly in some cases)
# Shows the Steem logs, but with UTC timestamps extracted from the docker logs.
# Scans and follows a large portion of your steem logs, filters out useless data, and appends a 
# human readable timestamp on the left. Time is normally in UTC, not your local. Example:
#
#   2018-12-09T01:04:59 p2p_plugin.cpp:212            handle_block         ] Got 21 transactions 
#                   on block 28398481 by someguy123 -- Block Time Offset: -345 ms
#
tslogs() {
    if [[ ! $(command -v jq) ]]; then
        echo $RED"jq not found. Attempting to install..."$RESET
        sleep 3
        sudo apt update
        sudo apt install -y jq
    fi
    local LOG_PATH=$(docker inspect $DOCKER_NAME | jq -r .[0].LogPath)
    local pipe=/tmp/dkpipe.fifo
    trap "rm -f $pipe" EXIT
    if [[ ! -p $pipe ]]; then
        mkfifo $pipe
    fi
    # the sleep is a dirty hack to keep the pipe open

    sleep 10000 < $pipe &
    tail -n 100 -f "$LOG_PATH" &> $pipe &
    while true
    do
        if read -r line <$pipe; then
            # first, parse the line and print the time + log
            L=$(jq -r ".time +\" \" + .log" <<<"$line")
            # then, remove excessive \r's causing multiple line breaks
            L=$(sed -e "s/\r//" <<< "$L")
            # now remove the decimal time to make the logs cleaner
            L=$(sed -e 's/\..*Z//' <<< "$L")
            # remove the steem ms time because most people don't care
            L=$(sed -e 's/[0-9]\+ms //' <<< "$L")
            # and finally, strip off any duplicate new line characters
            L=$(tr -s "\n" <<< "$L")
            printf '%s\r\n' "$L"
        fi
    done
}

# Internal use only
# Used by `ver` to pretty print new commits on origin/master
simplecommitlog() {
    local commit_format;
    local args;
    commit_format=""
    commit_format+="    - Commit %Cgreen%h%Creset - %s %n"
    commit_format+="      Author: %Cblue%an%Creset %n"
    commit_format+="      Date/Time: %Cblue%ai%Creset%n"
    if [[ "$#" -lt 1 ]]; then
        echo "Usage: simplecommitlog branch [num_commits]"
        echo "invalid use of simplecommitlog. exiting"
        exit -1
    fi
    branch="$1"
    args="$branch"
    if [[ "$#" -eq 2 ]]; then
        count="$2"
        args="-n $count $args"
    fi
    git log --pretty=format:"$commit_format" $args
}


# Usage: ./run.sh ver
# Displays information about your Steem-in-a-box version, including the docker container
# as well as the scripts such as run.sh. Checks for updates using git and DockerHub API.
#
ver() {
    LINE="==========================="
    ####
    # Update git, so we can detect if we're outdated or not
    # Also get the branch to warn people if they're not on master
    ####
    git remote update >/dev/null
    current_branch=$(git branch | grep \* | cut -d ' ' -f2)
    git_update=$(git status -uno)


    ####
    # Print out the current branch, commit and check upstream 
    # to return commits that can be pulled
    ####
    echo "${BLUE}Current Steem-in-a-box version:${RESET}"
    echo "    Branch: $current_branch"
    if [[ "$current_branch" != "master" ]]; then
        echo "${RED}WARNING: You're not on the master branch. This may prevent you from updating${RESET}"
        echo "${GREEN}Fix: Run 'git checkout master' to change to the master branch${RESET}"
    fi
    # Warn user of modified core files
    git_status=$(git status -s)
    modified=0
    while IFS='' read -r line || [[ -n "$line" ]]; do
        if grep -q " M " <<< $line; then
            modified=1
        fi
    done <<< "$git_status"
    if [[ "$modified" -ne 0 ]]; then
        echo "    ${RED}ERROR: Your steem-in-a-box core files have been modified (see 'git status'). You will not be able to update."
        echo "    Fix: Run 'git reset --hard' to reset all core files back to their originals before updating."
        echo "    This will not affect your running witness, or files such as config.ini which are supposed to be edited by the user${RESET}"
    fi
    echo "    ${BLUE}Current Commit:${RESET}"
    simplecommitlog "$current_branch" 1
    echo
    echo
    # Check for updates and let user know what's new
    if grep -q "up-to-date" <<< "$git_update"; then
        echo "    ${GREEN}Your steem-in-a-box core files (run.sh, Dockerfile etc.) up to date${RESET}"
    else
        echo "    ${RED}Your steem-in-a-box core files (run.sh, Dockerfile etc.) are outdated!${RESET}"
        echo
        echo "    ${BLUE}Updates in the current published version of Steem-in-a-box:${RESET}"
        simplecommitlog "HEAD..origin/master"
        echo
        echo
        echo "    Fix: ${YELLOW}Please run 'git pull' to update your steem-in-a-box. This should not affect any running containers.${RESET}"
    fi
    echo $LINE

    ####
    # Show the currently installed image information
    ####
    echo "${BLUE}Steem image installed:${RESET}"
    # Pretty printed docker image ID + creation date
    dkimg_output=$(docker images -f "reference=steem:latest" --format "Tag: {{.Repository}}, Image ID: {{.ID}}, Created At: {{.CreatedSince}}")
    # Just the image ID
    dkimg_id=$(docker images -f "reference=steem:latest" --format "{{.ID}}")
    # Used later on, for commands that depend on the image existing
    got_dkimg=0
    if [[ $(wc -c <<< "$dkimg_output") -lt 10 ]]; then
        echo "${RED}WARNING: We could not find the currently installed image (steem:lateset)${RESET}"
        echo "${RED}Make sure it's installed with './run.sh install' or './run.sh build'${RESET}"
    else
        echo "    $dkimg_output"
        got_dkimg=1
        echo "${BLUE}Checking for updates...${RESET}"
        remote_docker_id="$(get_latest_id)"
        if [[ "$?" == 0 ]]; then
            remote_docker_id="${remote_docker_id:7:12}"
            if [[ "$remote_docker_id" != "$dkimg_id" ]]; then
                echo "    ${YELLOW}An update is available for your Steem installation"
                echo "    Your image ID: $dkimg_id    Image ID on Docker Hub: ${remote_docker_id}"
                echo "    NOTE: If you have built manually with './run.sh build', your image will not match docker hub."
                echo "    To update, use ./run.sh install - a replay may or may not be required (ask in #witness on steem.chat)${RESET}"
            else
                echo "${GREEN}Your installed docker image ($dkimg_id) matches Docker Hub ($remote_docker_id)"
                echo "You're running the latest version of Steem from @someguy123's builds${RESET}"
            fi
        else
            echo "    ${YELLOW}An error occurred while checking for updates${RESET}"
        fi

    fi

    echo $LINE


    echo "${BLUE}Steem version currently running:${RESET}"
    # Verify that the container exists, even if it's stopped
    if seed_exists; then
        _container_image_id=$(docker inspect "$DOCKER_NAME" -f '{{.Image}}')
        # Truncate the long SHA256 sum to the standard 12 character image ID
        container_image_id="${_container_image_id:7:12}"
        echo "    Container $DOCKER_NAME is running on docker image ID ${container_image_id}"
        # If the docker image check was successful earlier, then compare the image to the current container 
        if [[ "$got_dkimg" == 1 ]]; then
            if [[ "$container_image_id" == "$dkimg_id" ]]; then
                echo "    ${GREEN}Container $DOCKER_NAME is running image $container_image_id, which matches steem:latest ($dkimg_id)"
                echo "    Your container will not change Steem version on restart${RESET}"
            else
                echo "    ${YELLOW}Warning: Container $DOCKER_NAME is running image $container_image_id, which DOES NOT MATCH steem:latest ($dkimg_id)"
                echo "    Your container may change Steem version on restart${RESET}"
            fi
        else
            echo "    ${YELLOW}Could not get installed image earlier. Skipping image/container comparison.${RESET}"
        fi
        echo "    ...scanning logs to discover blockchain version - this may take 30 seconds or more"
        l=$(docker logs "$DOCKER_NAME")
        if grep -q "blockchain version" <<< "$l"; then
            echo "  " $(grep "blockchain version" <<< "$l")
        else
            echo "    ${RED}Could not identify blockchain version. Not found in logs for '$DOCKER_NAME'${RESET}"
        fi
    else
        echo "    ${RED}Unfortunately your Steem container doesn't exist (start it with ./run.sh start or replay)..."
        echo "    We can't identify your blockchain version unless the container has been started at least once${RESET}"
    fi

}

# Usage: ./run.sh start
# Very simple status display, letting you know if the container exists, and if it's running.
status() {
    
    if seed_exists; then
        echo "Container exists?: "$GREEN"YES"$RESET
    else
        echo "Container exists?: "$RED"NO (!)"$RESET 
        echo "Container doesn't exist, thus it is NOT running. Run '$0 install && $0 start'"$RESET
        return
    fi

    if seed_running; then
        echo "Container running?: "$GREEN"YES"$RESET
    else
        echo "Container running?: "$RED"NO (!)"$RESET
        echo "Container isn't running. Start it with '$0 start' or '$0 replay'"$RESET
        return
    fi

}

if [ "$#" -lt 1 ]; then
    help
fi

case $1 in
    build)
        echo "You may want to use '$0 install' for a binary image instead, it's faster."
        build "${@:2}"
        ;;
    build_full)
        echo "You may want to use '$0 install_full' for a binary image instead, it's faster."
        build_full "${@:2}"
        ;;
    install_docker)
        install_docker
        ;;
    install)
        install "${@:2}"
        ;;
    install_full)
        install_full
        ;;
    start)
        start
        ;;
    replay)
        replay
        ;;
    shm_size)
        shm_size $2
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 5
        start
        ;;
    rebuild)
        stop
        sleep 5
        build
        start
        ;;
    optimize)
        echo "Applying recommended dirty write settings..."
        optimize
        ;;
    status)
        status
        ;;
    wallet)
        wallet
        ;;
    remote_wallet)
        remote_wallet "${@:2}"
        ;;
    dlblocks)
        dlblocks "${@:2}"
        ;;
    enter)
        enter
        ;;
    shell)
        shell
        ;;
    logs)
        logs
        ;;
    pclogs)
        pclogs
        ;;
    tslogs)
        tslogs
        ;;
    ver|version)
        ver
        ;;
    *)
        echo "Invalid cmd"
        help
        ;;
esac

