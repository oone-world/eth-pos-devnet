killall geth beacon-chain validator
pkill -f ./prysm.*

#set -e 
cd /home/adigium/eth-pos-devnet/

docker compose down

# Clean Folders
git clean -fxd
test -d logs || mkdir logs
#rm -rf consensus/beacondata/ consensus/genesis.ssz consensus/validatordata/ execution/geth/

# Initialize Genesis
geth --datadir=execution init execution/genesis.json
docker compose -f docker-initialize.yml run --rm create-beacon-chain-genesis
server_ip=`curl ifconfig.me 2>/dev/null` && echo server_ip=$server_ip

# Create Account
#curl http://localhost:8005/api/account/new > execution/account_geth.txt
echo account_geth_address=0xF359C69a1738F74C044b4d3c2dEd36c576A34d9f > execution/account_geth.txt
echo account_geth_privateKey=0x28fb2da825b6ad656a8301783032ef05052a2899a81371c46ae98965a6ecbbaf >> execution/account_geth.txt

# Load Account info
source execution/account_geth.txt
echo $account_geth_privateKey | sed s/0x//g > execution/account_geth_privateKey
geth --datadir=execution account import --password execution/geth_password.txt execution/account_geth_privateKey

# Add account to .env file
test -f .env && sed -i /^account_geth_address/d .env 
echo account_geth_address=$account_geth_address >> .env

cp jwtsecret execution/jwtsecret

# Run geth node
echo "Stating Geth Node"
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
	--mine \
	> logs/geth-1 &
sleep 5

#docker compose -f docker-run.yml up beacon-chain -d
echo "Stating Beacon Chain Node"
nohup ./prysm.sh beacon-chain \
	--datadir=consensus/beacondata \
	--min-sync-peers=0 \
	--genesis-state=consensus/genesis.ssz \
	--bootstrap-node= \
	--chain-config-file=consensus/config.yml \
	--config-file=consensus/config.yml \
	--rpc-host=0.0.0.0 \
	--grpc-gateway-host=0.0.0.0 \
	--monitoring-host=0.0.0.0 \
	--execution-endpoint=http://geth:8551 \
	--chain-id=32382 \
	--accept-terms-of-use \
	--jwt-secret=execution/jwtsecret \
	--suggested-fee-recipient=$account_geth_address \
	--p2p-host-ip=$server_ip \
	> logs/beacon-chain-1 &
	# --interop-eth1data-votes

sleep 5

# Get Ethers
#echo Getting 2200 Ethers
#curl http://localhost:8005/api/account/request/999/to/$account_geth_address
#curl http://localhost:8005/api/account/request/999/to/$account_geth_address
#curl http://localhost:8005/api/account/request/202/to/$account_geth_address

# Deploy Contracts
#cd /home/adigium/smart_contracts/
#cp truffle-config.example.js truffle-config.js
#truffle migrate | tee truffle.log
#cat truffle.log | grep "contract address" | tail -n1 | sed s/'.* '//g > deposit-contract-address
#cd /home/adigium/eth-pos-devnet/

# Get Validator Keys
#./deposit --language English new-mnemonic --mnemonic_language English --num_validators 1 --chain mainnet
#echo "YOUR"MNEMONIC" > validator_keys/mnemonic
#cp -R validator_keys/ ..
cp -R ../validator_keys .

echo "Making Deposit"
echo {\"keys\":$(cat `ls -rt validator_keys/deposit_data* | tail -n 1`), \"address\":\"$account_geth_address\", \"privateKey\": \"$account_geth_privateKey\"} > validator_keys/payload.txt
curl -X POST -H "Content-Type: application/json" -d @validator_keys/payload.txt http://localhost:8005/api/account/stake

# Import Wallet and Accounts
mkdir wallet_dir
echo "John.Risk" > wallet_dir/password.txt
#cp /root/prysm/validator .
#./validator wallet create --wallet-dir=wallet_dir --wallet-password-file=wallet_dir/password.txt

./prysm.sh validator \
	accounts \
	import \
	--accept-terms-of-use \
	--keys-dir=validator_keys/ \
	--wallet-dir=wallet_dir \
	--wallet-password-file=wallet_dir/password.txt \
	--account-password-file=wallet_dir/password.txt

echo "Stating Validator Node"
nohup ./prysm.sh validator \
	--beacon-rpc-provider=beacon-chain:4000 \
	--datadir=consensus/validatordata \
	--accept-terms-of-use \
	--chain-config-file=consensus/config.yml \
	--wallet-dir=wallet_dir \
	--wallet-password-file=wallet_dir/password.txt \
	> logs/validator-1 &

# Write node info
scripts/collectNodeInfo.sh > /var/www/html/adigium/nodeinfo.txt
cp consensus/genesis.ssz /var/www/html/adigium/ 

# Show Log Commands
echo You can watch the log file:
echo "	/home/adigium/eth-pos-devnet/tail -f logs/geth-1"
echo "	/home/adigium/eth-pos-devnet/tail -f logs/beacon-chain-1"
echo "	/home/adigium/eth-pos-devnet/tail -f logs/validator-1"
