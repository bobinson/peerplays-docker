This is a quick cloene of # Steem-in-a-box by @someguy123 for PeerPlays


 
 
# Usage

NOTE: Right now install, build, start & restart works fine.
ie 
./run.sh install
./run.sh build
./run.sh start
./run.sh restart

To install a witness or seed node:

```bash
git clone https://github.com/bobinson/peerplays-docker.git
cd peerplays-docker
# If you don't already have a docker installation, this will install it for you
./run.sh install_docker

# This downloads/updates the low-memory docker image for Steem
./run.sh install

# If you are a witness, you need to adjust the configuration as needed
# e.g. witness name, private key, logging config, turn off p2p-endpoint etc.
# If you're running a seed, then don't worry about the config, it will just work
nano data/witness_node_data_dir/config.ini

# (optional) Setting the .env file up (see the env settings section of this readme)
# will help you to adjust settings for steem-in-a-box
nano .env



# You'll also want to set the shared memory size (use sudo if not logged in as root). 
# Adjust 64G to whatever size is needed for your type of server and make sure to leave growth room.
# Please be aware that the shared memory size changes constantly. Ask in a witness chatroom if you're unsure.
#TODO
#./run.sh shm_size 64G

# It's recommended to set vm.swappiness to 1, which tells the system to avoid using swap 
# unless absolutely necessary. To persist on reboot, place in /etc/sysctl.conf
sysctl -w vm.swappiness=1


# If you DON'T want to replay, use "start" instead
./run.sh start
```

You may want to persist the /dev/shm size (shared memory) across reboots. To do this, you can edit `/etc/fstab`, please be very careful, as any mistakes in this file will cause your system to become unbootable.

Simply add this to the bottom of the file on a new line. Be sure not to damage any other lines in the file. Adjust "64G" to whatever size you would like /dev/shm to be.

```
tmpfs   /dev/shm         tmpfs   nodev,nosuid,size=64G          0  0
```


# Checking the status of your node

You can use the `logs` command to see the output from steemd:

```
./run.sh logs
```

#TODO: needs testing
You can also connect the local wallet using:

```
./run.sh wallet
```

Be aware, you can't connect cli_wallet until your steemd has finished replaying.

# Environment options

By default, `run.sh` will attempt to load variables from `.env` in the same directory as run.sh.

Anything which is not set in .env will fall back to a default value specified at the top of run.sh.

The most common .env which is recommended for witnesses is the following:


```
DOCKER_NAME=witness
PORTS=
```

The above `.env` file will set your docker container name to "witness", instead of the default "seed", and will also disable port forwarding, preventing exposure of the p2p port in the event you forget to turn off p2p-endpoint.

Full list of possible configuration options:

 - **PORTS** - default `2001` - a comma separated list of ports in steemd to forward to the internet
 - **DOCKER_NAME** - default `seed` - the container name to use for your steemd server
 - **DOCKER_DIR** - default `$DIR/dkr` - The directory to build the low memory node docker image from
 - **SHM_DIR** - default `/dev/shm` - override the location of shared_memory.bin and 

# Commands

Full list of `./run.sh` commands:

 - **start** - start a stopped steem-docker instance
 - **stop** - shutdown a steem-docker instance
 - **restart** - restart a steem-docker instance (will also start it if it's already stopped)
 - **wallet** - connect to the local container wallet
 - **remote_wallet** - connect to a remote wallet (default is wss://steemd.privex.io - @privex load balancer)
   - be aware, due to the way load balancing works, this may raise an error at first. just run it again a few times and eventually it will connect. note that external servers often have a 60 second connection limit, so you may be disconnected within 60 seconds.
 - **replay** - replay a steem-docker instance (run `stop` first) 
 - **dlblocks** - download blocks from gtg (gandalf)'s block log server and install them into the blockchain directory
 - **shm_size (size)** - change the size of /dev/shm, e.g. `./run.sh shm_size 64G` for 64 gigabytes
 - **install** - install or update the steem docker image from docker hub
 - **install_full** - install or update the full node steem docker image from docker hub
 - **build** - build the low memory mode version of steem into a docker image from source
 - **build_full** - build the full node version of steem into a docker image from source
 - **logs** - display the logs of the container with automatic follow. press ctrl-c to exit
 - **enter** - open a bash prompt inside of the container for debugging

# Steemit Post

Steemit Post for installing HF19: https://steemit.com/steem/@someguy123/your-guide-to-setting-up-a-witness-server-steem-in-a-box-hf19

# LICENSE

Steem-in-a-box and the associated docker images were built by @someguy123 ([github](https://github.com/someguy123) [steemit](https://steemit.com/@someguy123) [twitter](https://twitter.com/@compgenius999))

GNU Affero General Public License v3.0

SEE LICENSE FILE FOR MORE INFO
