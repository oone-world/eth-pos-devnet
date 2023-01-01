LogLevel=info
# Set interop to 'true' if you need to revert to original repository state, anything else is considered false
interop=false

function Log() {
	echo
	echo "--> $1"
}
function KillAll() {
	Log "Kill All Apps"
	killall geth beacon-chain validator
	pkill -f ./prysm.*
	cd /home/adigium/eth-pos-devnet/
	docker compose down
}
function PrepareEnvironment() {
	Log "Preparing Environment"
	
	KillAll

	# Clean Folders
	git clean -fxd
	#rm execution/bootnodes.txt consensus/bootnodes.txt

	test -d logs || mkdir logs
	cp -R ../validator_keys .

	my_ip=`curl ifconfig.me 2>/dev/null` && Log "my_ip=$my_ip"
}
function InitGeth()
{
	Log "Initializing geth $1"
	geth --datadir=execution init execution/genesis.json
}
function CreateAccount {
	Log "Creating Account"
	#curl http://localhost:8005/api/account/new > execution/account_geth.txt
	echo account_geth_address=0xF359C69a1738F74C044b4d3c2dEd36c576A34d9f > execution/account_geth.txt
	echo account_geth_privateKey=0x28fb2da825b6ad656a8301783032ef05052a2899a81371c46ae98965a6ecbbaf >> execution/account_geth.txt

	source execution/account_geth.txt
	
	echo $account_geth_privateKey | sed s/0x//g > execution/account_geth_privateKey
}
function ImportAccount {
	Log "Importing Account"
	geth --datadir=execution account import --password execution/geth_password.txt execution/account_geth_privateKey
}

function RunGeth()
{
	Log "Running geth"
	local bootnodes=$(cat execution/bootnodes.txt 2>/dev/null | tr '\n' ',' | sed s/,$//g)
	echo "Geth Bootnodes = $bootnodes"
	nohup geth --networkid=123456 \
		--http \
		--http.api=eth,net,web3,personal,miner \
		--http.addr=0.0.0.0 \
		--http.vhosts=* \
		--http.corsdomain=* \
		--authrpc.vhosts=* \
		--authrpc.addr=0.0.0.0 \
		--authrpc.jwtsecret=execution/jwtsecret \
		--datadir=execution \
		--allow-insecure-unlock \
		--unlock=$account_geth_address \
		--password=execution/geth_password.txt \
		--syncmode=full \
		--bootnodes= \
		--mine \
		> logs/geth.log &	
	sleep 5 # Set to 5 seconds to allow the geth to bind to the external IP before reading enode
	local my_enode=$(geth attach --exec "admin.nodeInfo.enode" execution/geth.ipc | sed s/^\"// | sed s/\"$//)
	echo my_enode=$my_enode
	echo $my_enode >> execution/bootnodes.txt
}
function StoreGethHash() {
	Log "Storing Genesis Hash"
	genesis_hash=`geth attach --exec "eth.getBlockByNumber(0).hash" execution/geth.ipc | sed s/^\"// | sed s/\"$//`

	echo $genesis_hash > execution/genesis_hash.txt
	echo $genesis_hash > consensus/deposit_contract_block.txt
	sed -i s/TERMINAL_BLOCK_HASH:.*/"TERMINAL_BLOCK_HASH: $genesis_hash"/g consensus/config.yml
	#cat consensus/config.yaml|grep TERMINAL_BLOCK_HASH
	Log "genesis_hash = $genesis_hash"
}
function GenerateGenesisSsz1() {
	Log "Generating Empty Genesis"
	docker compose -f docker-initialize.yml run --rm create-beacon-chain-genesis
}
function GenerateGenesisSsz2()
{
	Log "Generating Beaconchain Genesis With Validators"
	./eth2-testnet-genesis merge \
	  --config "./consensus/config.yaml" \
	  --eth1-config "./execution/genesis.json" \
	  --mnemonics "./consensus/mnemonic.yaml" \
	  --state-output "./consensus/genesis.ssz" \
	  --tranches-dir "./consensus/tranches"
}
function RunBeacon() {
	Log "Running Beacon $1"
	local bootnodes=`cat consensus/bootnodes.txt 2>/dev/null | grep . | tr '\n' ',' | sed s/,$//g`
	echo "Beacon Bootnodes = $bootnodes"
	
	if [[ $interop == "true" ]]; then
		genesis_flags="--interop-genesis-state=consensus/genesis.ssz --interop-eth1data-votes"
	else
		genesis_flags="--genesis-state=consensus/genesis.ssz"
	fi
		
	nohup ./prysm.sh beacon-chain \
		--datadir=consensus/beacondata \
		--min-sync-peers=0 \
		$genesis_flags \
		--bootstrap-node= \
		--contract-deployment-block=0 \
		--chain-config-file=consensus/config.yml \
		--config-file=consensus/config.yml \
		--rpc-host=0.0.0.0 \
		--grpc-gateway-host=0.0.0.0 \
		--monitoring-host=0.0.0.0 \
		--execution-endpoint=http://localhost:8551 \
		--chain-id=32382 \
		--accept-terms-of-use \
		--jwt-secret=execution/jwtsecret \
		--suggested-fee-recipient=$account_geth_address \
		--p2p-host-ip=$my_ip \
		> logs/beacon.log &
		
	sleep 1
	echo Waiting for Beacon enr ...
	local my_enr=''
	while [[ -z $my_enr ]]
	do
		sleep 1
		local my_enr=$(curl localhost:8080/p2p 2>/dev/null | grep ^self= | sed s/self=//g | sed s/,\\/ip4.*//g)
	done
	echo "My Enr = $my_enr"
	echo $my_enr >> consensus/bootnodes.txt
}

function CheckGeth()
{
	echo Checking Geth $1
	test -z $my_ip || my_ip=`curl ifconfig.me 2>/dev/null` && Log "my_ip=$my_ip"
	geth attach --exec "admin.nodeInfo.enode" execution/geth.ipc | sed s/^\"// | sed s/\"$//
	geth attach --exec "admin.peers" execution/geth.ipc | grep "remoteAddress" | grep $my_ip
}

function CreateWallet() {
	# Import Wallet and Accounts
	mkdir wallet_dir
	echo "John.Risk" > wallet_dir/password.txt
	#cp /root/prysm/validator .

	./prysm.sh validator \
		accounts \
		import \
		--accept-terms-of-use \
		--keys-dir=validator_keys/ \
		--wallet-dir=wallet_dir \
		--wallet-password-file=wallet_dir/password.txt \
		--account-password-file=wallet_dir/password.txt
}
function CreateValidatorKeys {
	Log "Creating Validator Keys"
	# Get Validator Keys
	#./deposit --language English new-mnemonic --mnemonic_language English --num_validators 1 --chain mainnet
	#echo "YOUR"MNEMONIC" > validator_keys/mnemonic
	#cp -R validator_keys/ ..
	cp -R ../validator_keys .
}

function MakeDeposit {
	Log "Making Deposit"
	echo {\"keys\":$(cat `ls -rt validator_keys/deposit_data* | tail -n 1`), \"address\":\"$account_geth_address\", \"privateKey\": \"$account_geth_privateKey\"} > validator_keys/payload.txt
	curl -X POST -H "Content-Type: application/json" -d @validator_keys/payload.txt http://localhost:8005/api/account/stake
}

function CheckBeacon()
{
	Log "Checking Beacon $1"
	#echo My ID: `curl http://localhost:$((9596 + $1))/eth/v1/node/identity 2>/dev/null | jq -r ".data.peer_id"`
	#echo My enr: `curl http://localhost:$((9596 + $1))/eth/v1/node/identity 2>/dev/null | jq -r ".data.enr"`
	#echo Peer Count: `curl http://localhost:$((9596 + $1))/eth/v1/node/peers 2>/dev/null | jq -r ".meta.count"`
	#curl http://localhost:$((9596 + $1))/eth/v1/node/syncing 2>/dev/null | jq
	curl localhost:8080/p2p
	curl http://localhost:8080/healthz
	curl http://localhost:3500/eth/v1/node/syncing 2>/dev/null | jq
	curl http://localhost:3500/eth/v1alpha1/node/eth1/connections 2>/dev/null | jq
}
function CheckAll()
{
	CheckGeth 0; #CheckGeth 1; CheckGeth 2; CheckGeth 3
	CheckBeacon 0; #CheckBeacon 1; CheckBeacon 2; CheckBeacon 3
}
function RunValidator()
{
	Log "Running Validators $1"
	if [[ $interop == "true" ]]; then
		interop_flags="--interop-num-validators=64 --interop-start-index=0"
	else
		interop_flags=""
	fi

	nohup ./prysm.sh validator \
		--beacon-rpc-provider=localhost:4000 \
		--datadir=consensus/validatordata \
		--accept-terms-of-use \
        $interop_flags \
		--chain-config-file=consensus/config.yml \
		--wallet-dir=wallet_dir \
		--wallet-password-file=wallet_dir/password.txt \
		> logs/validator.log &
}

PrepareEnvironment

InitGeth
CreateAccount
ImportAccount
RunGeth

StoreGethHash
GenerateGenesisSsz1
RunBeacon

CreateValidatorKeys
MakeDeposit
CreateWallet
RunValidator

CheckAll

echo "
clear && tail -f logs/geth.log -n1000
clear && tail -f logs/beacon.log -n1000
clear && tail -f logs/validator.log -n1000

curl localhost:8080/p2p
curl http://localhost:8080/healthz
curl http://localhost:3500/eth/v1/node/syncing 2>/dev/null | jq
curl http://localhost:3500/eth/v1alpha1/node/eth1/connections 2>/dev/null | jq
"
