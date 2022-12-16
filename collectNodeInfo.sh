export server_ip=`curl ifconfig.me 2>/dev/null` \
        && echo export server_ip=$server_ip
echo

export bootgeth=`docker logs eth-pos-devnet-geth-1 2>&1 | grep self=enode | sed s/.*self=//g | sed s/@127.0.0.1:30303/@${server_ip}:30303/g | tail -1` \
        && echo export bootgeth=$bootgeth
echo

export bootbeacon=`curl http://localhost:8080/p2p 2>/dev/null | grep self= | sed s/',\\'/'ip4.*'//g | sed s/'self='//g` \
        && echo export bootbeacon=$bootbeacon

