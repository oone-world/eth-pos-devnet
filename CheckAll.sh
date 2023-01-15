source Config.sh

######## Checker Functions
function Log() {
	echo
	echo "--> $@"
}
function CheckGeth()
{
	Log "Checking Geth $1"
	test -z $my_ip && my_ip=`curl ifconfig.me 2>/dev/null` && Log "my_ip=$my_ip"
	geth attach --exec "admin.nodeInfo.enode" data/execution/$1/geth.ipc | sed s/^\"// | sed s/\"$//
	echo Peers: `geth attach --exec "admin.peers" data/execution/$1/geth.ipc | grep "remoteAddress" | grep -e $my_ip -e "127.0.0.1"`
	echo Block Number: `geth attach --exec "eth.blockNumber" data/execution/$1/geth.ipc`
}
function CheckBeacon()
{
	Log "Checking Beacon $1"
	#curl http://localhost:$((5052+$1))/eth/v1/node/identity 2>/dev/null | jq
	#curl http://localhost:$((5052+$1))/eth/v1/node/peers 2>/dev/null | jq
	#curl http://localhost:$((5052+$1))/eth/v1/node/syncing	2>/dev/null | jq
	#curl http://localhost:$((5052+$1))/eth/v1/node/health 2>/dev/null | jq
	echo My ID: `curl http://localhost:$((5052 + $1))/eth/v1/node/identity 2>/dev/null | jq -r ".data.peer_id"`
	echo My enr: `curl http://localhost:$((5052 + $1))/eth/v1/node/identity 2>/dev/null | jq -r ".data.enr"`
	echo Peer Count: `curl http://localhost:$((5052 + $1))/eth/v1/node/peers 2>/dev/null | jq -r ".meta.count"`
	curl http://localhost:$((5052 + $1))/eth/v1/node/syncing 2>/dev/null | jq
}
function CheckBeacon_Prysm()
{
	Log "Checking Beacon $1"
	curl localhost:$((8000 + $1))/p2p
	curl http://localhost:$((8000 + $1))/healthz
	curl http://localhost:$((3500 + $1))/eth/v1/node/syncing 2>/dev/null | jq
}
function CheckAll()
{
	for i in $(seq 0 $(($NodesCount-1))); do
		CheckGeth $i
	done
	for i in $(seq 0 $(($NodesCount-1))); do
		CheckBeacon $i
	done
}
########
echo "
clear && tail -f logs/geth_0.log -n1000
clear && tail -f logs/geth_1.log -n1000
clear && tail -f logs/beacon_0.log -n1000
clear && tail -f logs/beacon_1.log -n1000
clear && tail -f logs/validator_0.log -n1000
clear && tail -f logs/validator_1.log -n1000

curl http://localhost:9596/eth/v1/node/identity | jq
curl http://localhost:9596/eth/v1/node/peers | jq
curl http://localhost:9596/eth/v1/node/syncing | jq
"

CheckAll
