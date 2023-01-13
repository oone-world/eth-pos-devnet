NodesCount=1
LogLevel=info
Accounts=("0xF359C69a1738F74C044b4d3c2dEd36c576A34d9f" "0x88cfFd22aE99E4f7f1bC794E591BcB85b421B522")
PrivateKeys=("28fb2da825b6ad656a8301783032ef05052a2899a81371c46ae98965a6ecbbaf" "8b742d27695dc12d89922df3e7fb99e2b0f898db67e25d2c00c81725bf17eb86")
ValidatorKeys=("../validator_keys8" "../validator_keys8_2")
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

function KillAll() {
	Log "Kill All Apps"
	killall geth beacon-chain validator
	pkill -f ./prysm.*
	pkill -f lodestar.js
	pkill -f lighthouse
	docker compose -f /home/adigium/eth-pos-devnet/docker-run.yml down || echo Looks like docker is not running.
}
function PrepareEnvironment() {
	Log "Cleaning Environment"
	KillAll
	
	git clean -fxd
	rm execution/bootnodes.txt consensus/bootnodes.txt

	test -d logs || mkdir logs
	test -d data || mkdir data
	test -d consensus/validator_keys || mkdir consensus/validator_keys
	test -d data/wallet_dir || mkdir data/wallet_dir
	if [[ -d ../validator_keys8 ]]; then
		rm consensus/validator_keys/*
		cp -R ../validator_keys8/* consensus/validator_keys
	fi

	my_ip=`curl ifconfig.me 2>/dev/null` && Log "my_ip=$my_ip"
}
function InitGeth()
{
	Log "Initializing geth $1"
	geth init \
	  --datadir "./data/execution/$1" \
	  ./execution/genesis.json
}
function RunInBackground {
	local LogFile=$1
	shift
	echo "Running Command in Background: $@ > $LogFile &"
	nohup $@ > $LogFile &
}
function RunGeth()
{
	Log "Running geth $1 on port $((8551 + $1))"
	local bootnodes=$(cat execution/bootnodes.txt 2>/dev/null | tr '\n' ',' | sed s/,$//g)
	echo "Geth Bootnodes = $bootnodes"
	local unlock_account=
	if [[ $1 == 0 ]]; then
		local unlock_account="--allow-insecure-unlock --unlock=${Accounts[$1]} --password=data/execution/geth_password.txt --mine"
	fi
	RunInBackground ./logs/geth_$1.log geth \
		--http \
		--http.port $((8545 + $1)) \
		--http.api=eth,net,web3,personal,miner \
		--http.addr=0.0.0.0 \
		--http.vhosts=* \
		--http.corsdomain=* \
		$unlock_account \
	  --networkid 32382 \
	  --datadir "./data/execution/$1" \
	  --authrpc.port $((8551 + $1)) \
	  --port $((30303 + $1)) \
	  --syncmode full \
	  --bootnodes=$bootnodes
	sleep 1 # Set to 5 seconds to allow the geth to bind to the external IP before reading enode
	#local variablename="bootnode_geth_$1"
	#export $variablename=`geth attach --exec "admin.nodeInfo.enode" data/execution/$1/geth.ipc | sed s/^\"// | sed s/\"$//`
	#Log "$variablename = ${!variablename}"
	#echo ${!variablename} >> execution/bootnodes.txt
	local my_enode=$(geth attach --exec "admin.nodeInfo.enode" data/execution/$1/geth.ipc | sed s/^\"// | sed s/\"$//)
	echo $my_enode >> execution/bootnodes.txt
}
function RunBeacon() {
	Log "Running Beacon $1"
	local bootnodes=`cat consensus/bootnodes.txt 2>/dev/null | grep . | tr '\n' ',' | sed s/,$//g`	
	if [[ ! -z $bootnodes ]]; then
		echo "Beacon Bootnodes = $bootnodes"
		local bootnodes_command="--boot-nodes=$bootnodes"
	fi
	RunInBackground ./logs/beacon_$1.log lighthouse beacon \
		--testnet-dir "./data/testnet" \
		--datadir "./data/consensus/$1" \
		--execution-endpoint http://127.0.0.1:$((8551 + $1)) \
		--execution-jwt "./data/execution/$1/geth/jwtsecret" \
		--http \
		--http-port $((5052 + $1)) \
		--eth1 \
		--staking \
		--enable-private-discovery \
		--enr-address 127.0.0.1 \
		--enr-udp-port $((9000 + $1)) \
		--enr-tcp-port $((9000 + $1)) \
		--port $((9000 + $1)) \
		--disable-packet-filter \
		--graffiti "ProducedBy_Beacon_Node_$1" \
		"$bootnodes_command"
	return
	
	echo Waiting for Beacon enr ...
	local my_enr=''
	while [[ -z $my_enr ]]
	do
		sleep 1
		my_enr=`curl http://localhost:$((5052 + $1))/eth/v1/node/identity 2>/dev/null | jq -r ".data.enr"`
	done
	echo "My Enr = $my_enr"
	echo $my_enr >> consensus/bootnodes.txt
}

function ImportValidator()
{
	Log "Running Validators $1"
	#cp -R consensus/validator_keys consensus/validator_keys_$1
	
	lighthouse account validator import \
		--testnet-dir "./data/testnet" \
		--datadir "data/validator/$1" \
		--directory ${ValidatorKeys[$1]} \
		--password-file ${ValidatorKeys[$1]}/password.txt \
		--reuse-password
}
	
function RunValidator()
{

	RunInBackground ./logs/validator_$1.log lighthouse vc \
		--testnet-dir "./data/testnet" \
		--datadir "data/validator/$1" \
		--beacon-nodes http://localhost:$((5052 + $1)) \
		--graffiti "ProducedBy_Validator_$1" \
		--suggested-fee-recipient ${Accounts[$1]} 
		#--beacon-nodes
		#--unencrypted-http-transport
		#--allow-unsynced
}
function MakeDeposit {
	Log "Making Deposit for the Validators"
	echo {\"keys\":$(cat `ls -rt ${ValidatorKeys[$1]}/deposit_data* | tail -n 1`), \"address\":\"${Accounts[$1]}\", \"privateKey\": \"${PrivateKeys[$1]}\"} > ${ValidatorKeys[$1]}/payload.txt

	curl -X POST -H "Content-Type: application/json" -d @${ValidatorKeys[$1]}/payload.txt http://localhost:8005/api/account/stake
	echo
}
function ExtractENR {
	Log Waiting for Beacon enr ...
	local my_enr=''
	while [[ -z $my_enr ]]
	do
		sleep 1
		my_enr=`cat logs/beacon_0.log | grep "enr: enr:" | sed s/.*enr/enr/g | sed s/', service: libp2p'//g`
	done
	echo "My Enr = $my_enr"
	echo $my_enr >> consensus/bootnodes.txt

}

PrepareEnvironment
set -e

for i in $(seq 0 $(($NodesCount-1))); do
	InitGeth $i
	RunGeth $i
	RunBeacon $i
	MakeDeposit $i
	ImportValidator $i
	RunValidator $i
done

CheckAll

echo "
clear && tail -f logs/geth_0.log -n1000
clear && tail -f logs/beacon_0.log -n1000
clear && tail -f logs/validator_0.log -n1000

curl http://localhost:9596/eth/v1/node/identity | jq
curl http://localhost:9596/eth/v1/node/peers | jq
curl http://localhost:9596/eth/v1/node/syncing | jq
"