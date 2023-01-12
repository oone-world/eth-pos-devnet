NodesCount=2
LogLevel=debug
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
function AdjustTimestamps {
	timestamp=`date +%s`	
	timestampHex=`printf '%x' $timestamp`
	Log "timestamp=$timestamp"
	Log "timestampHex=$timestampHex"

	sed -i s/\"timestamp\":.*/\"timestamp\":\"0x$timestampHex\",/g execution/genesis.json
	sed -i s/MIN_GENESIS_TIME:.*/"MIN_GENESIS_TIME: $timestamp"/g consensus/config.yml
}
function InitGeth()
{
	Log "Initializing geth $1"
	geth init \
	  --datadir "./data/execution/$1" \
	  ./execution/genesis.json
}
function ImportGethAccount()
{
	Log Importing Account ${Accounts[$1]}
	echo "password" > data/execution/geth_password.txt
	echo ${PrivateKeys[0]} > data/execution/account_geth_privateKey
	geth --datadir=data/execution/$1 account import --password data/execution/geth_password.txt data/execution/account_geth_privateKey
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
function StoreGethHash() {
	genesis_hash=`geth attach --exec "eth.getBlockByNumber(0).hash" data/execution/1/geth.ipc | sed s/^\"// | sed s/\"$//`

	echo $genesis_hash > execution/genesis_hash.txt
	echo $genesis_hash > consensus/deposit_contract_block.txt
	sed -i s/TERMINAL_BLOCK_HASH:.*/"TERMINAL_BLOCK_HASH: $genesis_hash"/g consensus/config.yml
	cat consensus/config.yml|grep TERMINAL_BLOCK_HASH
	Log "genesis_hash = $genesis_hash"
}
function DeployContract {
	Log "Deploying Contract"
	local deposit_contract_output=`lcli deploy-deposit-contract --eth1-http http://localhost:8545 -d testnet`
	#deposit_contract_output='Deposit contract address: "0xb95786752127082c2120a2c118f0aabb4091c70a"'
	echo $deposit_contract_output
	deposit_contract_address=`echo $deposit_contract_output | sed s/\"$//g | sed s/.*\"//g`
	echo deposit_contract_address = $deposit_contract_address
	local deposit_contract_log_line=`cat logs/geth_0.log | grep "Submitted contract creation"|grep -i $deposit_contract_address`
	local deposit_contract_transaction_hash=`echo $deposit_contract_log_line | sed s/.*hash=//g | sed s/' '.*//g`
	echo deposit_contract_transaction_hash = $deposit_contract_transaction_hash
	deposit_contract_block_number=`GetGethInfoFromFirstNode "eth.getTransaction('$deposit_contract_transaction_hash').blockNumber"`
	echo deposit_contract_block_number = $deposit_contract_block_number
	local deposit_contract_block_hash=`GetGethInfoFromFirstNode "eth.getTransaction('$deposit_contract_transaction_hash').hash"`
	echo deposit_contract_block_hash = $deposit_contract_block_hash
}
function UseInitialContract {
	deposit_contract_address=0x4242424242424242424242424242424242424242
	deposit_contract_block_number=0
}
function CreateBeaconTestNetConfig {
	lcli new-testnet \
		--testnet-dir data/testnet \
		--deposit-contract-address $deposit_contract_address \
		--deposit-contract-deploy-block $deposit_contract_block_number \
		--eth1-follow-distance 1 \
		--min-deposit-amount 10000000 \
		--force \
		--altair-fork-epoch 0 \
		--merge-fork-epoch 1 \
		--genesis-delay 10 \
		--max-effective-balance 3200000000 \
		--min-genesis-active-validator-count 8 \
		--min-genesis-time $timestamp \
		--spec mainnet \
		--seconds-per-slot 6\
		--eth1-id 32382
	
	sed -i s/TERMINAL_TOTAL_DIFFICULTY.*/'TERMINAL_TOTAL_DIFFICULTY: 64'/g data/testnet/config.yaml
		# --genesis-fork-version 0x01030307 \
		# --genesis-time
		# --seconds-per-eth1-block \
		# --seconds-per-slot
}
function GetGethInfoFromFirstNode {
	local value=$(geth attach --exec "$1" data/execution/0/geth.ipc | sed s/^\"// | sed s/\"$//)
	echo $value
}
function GenerateGenesisSSZ()
{
	Log "Generating Beaconchain Genesis"
	./eth2-testnet-genesis merge \
	  --config "./consensus/config.yml" \
	  --eth1-config "./execution/genesis.json" \
	  --mnemonics "./consensus/mnemonic.yaml" \
	  --state-output "./consensus/genesis.ssz" \
	  --tranches-dir "./consensus/tranches"
}
function RunBeacon() {
	Log "Running Beacon $1"
	local bootnodes=`cat consensus/bootnodes.txt 2>/dev/null | grep . | tr '\n' ',' | sed s/,$//g`
	echo "Beacon Bootnodes = $bootnodes"
	
	if [[ ! -z $bootnodes ]]; then
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

function RunBeacon_Prysm() {
	Log "Running Beacon $1"
	local bootnodes=`cat consensus/bootnodes.txt 2>/dev/null | grep . | tr '\n' ',' | sed s/,$//g`
	echo "Beacon Bootnodes = $bootnodes"
	
	nohup clients/beacon-chain \
	  --min-sync-peers=$i \
	  --suggested-fee-recipient "0xCaA29806044A08E533963b2e573C1230A2cd9a2d" \
	  --execution-endpoint=http://localhost:$((8551 + $1)) \
	  --jwt-secret "./data/execution/$1/geth/jwtsecret" \
	  --datadir "./data/consensus/$1" \
	  --chain-config-file=consensus/config.yml \
	  --config-file=consensus/config.yml \
	  --genesis-state "./consensus/genesis.ssz" \
	  --contract-deployment-block=0 \
	  --verbosity $LogLevel \
	  --bootstrap-node=$bootnodes \
	  --rpc-host=0.0.0.0 \
	  --grpc-gateway-host=0.0.0.0 \
	  --monitoring-host=0.0.0.0 \
	  --p2p-host-ip=$my_ip \
	  --accept-terms-of-use \
	  --chain-id=32382 \
	  --rpc-port=$((4010 + $1)) \
	  --p2p-tcp-port=$((13000 + $1)) \
	  --p2p-udp-port=$((12000 + $1)) \
	  --grpc-gateway-port=$((3500 + $1)) \
	  --monitoring-port=$((8000 + $1)) \
	  > ./logs/beacon_$1.log &

	echo Waiting for Beacon enr ...
	local my_enr=''
	while [[ -z $my_enr ]]
	do
		sleep 1
		my_enr=$(curl localhost:8000/p2p 2>/dev/null | grep ^self= | sed s/self=//g | sed s/,\\/ip4.*//g)
	done
	echo "My Enr = $my_enr"
	echo $my_enr >> consensus/bootnodes.txt
}

function RunBeacon_Lighthouse() {
	Log "Running Beacon $1"
	local bootnodes=`cat consensus/bootnodes.txt 2>/dev/null | grep . | tr '\n' ',' | sed s/,$//g`
	echo "Beacon Bootnodes = $bootnodes"
	
	nohup lighthouse beacon \
		--eth1 \
		--http \
		--reset-payload-statuses \
		--staking \
		--subscribe-all-subnets \
		--validator-monitor-auto \
		--enable-private-discovery \
		--boot-nodes=$bootnodes \
		--datadir "./data/consensus/$1" \
		--debug-level $LogLevel \
		--eth1-endpoints "http://127.0.0.1:$((8545 + $1))" \
		--execution-endpoint "http://127.0.0.1:$((8551 + $1))" \
		--execution-jwt "./data/execution/$1/geth/jwtsecret" \
		--graffiti "John.Risk" \
		--http-allow-origin * \
		--http-port $((5052 + $1)) \
		--port $((9000 + $1)) \
		--suggested-fee-recipient "0xCaA29806044A08E533963b2e573C1230A2cd9a2d" \
		--target-peers $1 \
		--testnet-dir consensus \


	  --paramsFile "./consensus/config.yml" \
	  --genesisStateFile "./consensus/genesis.ssz" \
	  > ./logs/beacon_$1.log &

	echo Waiting for Beacon enr ...
	local my_enr=''
	while [[ -z $my_enr ]]
	do
		sleep 1
		my_enr=`curl http://localhost:$((9596 + $1))/eth/v1/node/identity 2>/dev/null | jq -r ".data.enr"`
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
function RunValidator_Prysm()
{
	Log "Running Validators $1"
	cp -R consensus/validator_keys consensus/validator_keys_$1
	CreateWallet_Prysm $1
	nohup clients/validator \
	  --datadir "./data/consensus/$1" \
	  --beacon-rpc-provider=localhost:$((4010 + $1)) \
	  --beacon-rpc-gateway-provider=localhost:$((3500 + $1)) \
	  --accept-terms-of-use \
  	  --graffiti "YOLO MERGEDNET GETH LODESTAR" \
	  --suggested-fee-recipient "0xCaA29806044A08E533963b2e573C1230A2cd9a2d" \
	  --chain-config-file "./consensus/config.yml" \
	  --wallet-dir=data/wallet_dir/$1 \
	  --wallet-password-file=consensus/validator_keys_$1/password.txt \
	  --verbosity $LogLevel \
	  > ./logs/validator_$1.log &
}
function CreateWallet_Prysm() {
	# Import Wallet and Accounts
	mkdir data/wallet_dir/$1
	#cp /root/prysm/validator .

	clients/validator \
		accounts \
		import \
		--accept-terms-of-use \
		--keys-dir=consensus/validator_keys_$1/ \
		--wallet-dir=data/wallet_dir/$1 \
		--wallet-password-file=consensus/validator_keys_$1/password.txt \
		--account-password-file=consensus/validator_keys_$1/password.txt
}
function RunStaker {
	echo {\"keys\":$(cat `ls -rt /root/validator_keys1/deposit_data* | tail -n 1`), \"address\":\"${Accounts[1]}\", \"privateKey\": \"${PrivateKeys[1]}\"} > /root/validator_keys1/payload.txt
	
	curl -X POST -H "Content-Type: application/json" -d @/root/validator_keys1/payload.txt http://localhost:8005/api/account/stake

	nohup clients/lodestar validator \
	  --dataDir "./data/consensus/1" \
	  --beaconNodes "http://127.0.0.1:9597" \
	  --suggestedFeeRecipient "${Accounts[1]}" \
	  --graffiti "YOLO MERGEDNET GETH LODESTAR" \
	  --paramsFile "./consensus/config.yml" \
	  --importKeystores "/root/validator_keys1" \
	  --importKeystoresPassword "/root/validator_keys1/password.txt" \
	  --logLevel $LogLevel \
	  > ./logs/validator_1.log &
	  
	tail -f logs/validator_1.log -n1000 
}
function CreateWallet {
	echo 123456789012 > data/wallet_dir/password.txt
	lighthouse account wallet create \
		--testnet-dir data/testnet \
		--datadir data/wallet_dir \
		--password-file data/wallet_dir/password.txt \
		--name John \
		--mnemonic-output-path data/wallet_dir/mnemonic.txt
}
function CreateValidator {
	lighthouse account validator create \
		--at-most 16 \
		--testnet-dir data/testnet \
        --wallet-name John \
        --wallet-password data/wallet_dir/password.txt \
        --wallets-dir data/wallet_dir/wallets		
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
function WaitForPosTransition {
	Log "Waiting for POS Transition at slot 32. This could take a while (6.4 minutes) ..."
	date
	local pos=''
	while [[ -z $pos ]]
	do
		sleep 10
		pos=`cat logs/beacon_0.log | grep "Proof of Stake Activated" || :`
	done
	echo $pos
	date
}
#git clone https://github.com/q9f/mergednet.git
#cd mergednet

PrepareEnvironment
set -e
AdjustTimestamps

for i in $(seq 0 $(($NodesCount-1))); do
	InitGeth $i
	if [[ $i == 0 ]]; then
		ImportGethAccount
	fi
	RunGeth $i
done

#StoreGethHash
#DeployContract
UseInitialContract

CreateBeaconTestNetConfig
#GenerateGenesisSSZ

#for i in $(seq 0 $(($NodesCount-1))); do
#	RunBeacon $i
#done

#CreateWallet
RunBeacon 0
MakeDeposit 0 # deposit is needed to get enr
ExtractENR # enr is needed to connect a peer beacon
RunBeacon 1 # second beacon node is needed to sync with execution

sleep 5
#for i in $(seq 0 $(($NodesCount-1))); do
#	RunValidator $i
#done
ImportValidator 0
RunValidator 0 # validator is needed to move to pos

WaitForPosTransition

MakeDeposit 1
ImportValidator 1
RunValidator 1

#RunStaker


CheckAll

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