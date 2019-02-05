
# version name reference: https://www.ubuntu.com/about/release-cycle
FROM ubuntu:14.04

# cd ~/dkr && docker build -t steem .
# docker run -p 0.0.0.0:2001:2001 -v $PWD/data:/steem -d -t steem

ARG STEEM_STATIC_BUILD=ON
ENV STEEM_STATIC_BUILD ${STEEM_STATIC_BUILD}

RUN apt-get update && \
	apt-get install -y gcc g++ cmake make libbz2-dev libdb++-dev libdb-dev  && \
	apt-get install -y libssl-dev openssl libreadline-dev autoconf libtool git gdb liblz4-tool wget jq   && \
	apt-get install -y autotools-dev build-essential autotools-dev build-essential g++ libbz2-dev libicu-dev python-dev g++ libbz2-dev libicu-dev python-dev doxygen python3 python3-dev python3-pip libboost-all-dev curl && \
	apt-get install libncurses5-dev &&  \
        apt-get clean -qy && \
        pip3 install jinja2

# P2P (seed) port
EXPOSE 2001
# RPC ports
EXPOSE 5000
EXPOSE 8090

ARG steemd_version=master

RUN cd ~ && \
	git clone https://github.com/PBSA/peerplays.git && \
	cd peerplays && \
	BOOST_ROOT=$HOME/opt/boost_1_57_0 &&\
	wget -c 'http://sourceforge.net/projects/boost/files/boost/1.57.0/boost_1_57_0.tar.bz2/download' -O boost_1_57_0.tar.bz2 &&\
	tar xjf boost_1_57_0.tar.bz2 &&\
	cd boost_1_57_0/ &&\
	./bootstrap.sh "--prefix=$BOOST_ROOT" &&\
	./b2 install &&\
	git checkout ${steemd_version} && \
	git submodule update --init --recursive && \
        cd ~/peerplays && \
	cmake -DBOOST_ROOT="$BOOST_ROOT" -DCMAKE_BUILD_TYPE=Release . &&\
	make -j$(nproc) && make install && rm -rf ~/peerplays
VOLUME /peerplays
WORKDIR /peerplays
RUN echo "Please configure me! You need to mount a data directory onto /steem of this container to it to function correctly. (if you're using Steem-in-a-box most of this is handled automatically)"
CMD ["sh", "-c", "/usr/local/bin/steemd"]
