server_ip=`curl ifconfig.me 2>/dev/null` \
        && echo server_ip=$server_ip
echo

bootgeth=`docker logs eth-pos-devnet-geth-1 2>&1 | grep self=enode | sed s/.*self=//g | sed s/@127.0.0.1:30303/@${server_ip}:30303/g | tail -1` \
        && echo bootgeth=$bootgeth
echo

bootbeacon=`curl http://localhost:8080/p2p 2>/dev/null | grep self= | sed s/',\\'/'ip4.*'//g | sed s/'self='//g` \
        && echo bootbeacon=$bootbeacon
echo

bootipfs=/ip4/${server_ip}/tcp/4001/ipfs/`ipfs id|grep \"ID\"|sed s/'.*\"ID\": \"'//|sed s/'\",$'//` \
        && echo bootipfs=$bootipfs
echo

bootipfscluster=/ip4/${server_ip}/tcp/9096/ipfs/`ipfs-cluster-ctl id | grep IPFS | sed s/'.*IPFS: '//g` \
        && echo bootipfscluster=$bootipfscluster
echo

