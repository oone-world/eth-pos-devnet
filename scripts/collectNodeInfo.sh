server_ip=`curl ifconfig.me 2>/dev/null` \
        && echo server_ip=$server_ip
echo
cd /home/adigium/eth-pos-devnet

bootgeth=`geth attach --exec "admin.nodeInfo.enode" execution/geth.ipc | sed s/^\"//g | sed s/\"$//g` \
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

