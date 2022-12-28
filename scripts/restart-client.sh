set -e
cd /home/adigium/eth-pos-devnet/

docker compose down

# Clean Folders
#git clean -fxd
rm -rf consensus/beacondata/ consensus/genesis.ssz consensus/validatordata/ execution/geth/

# Get BootNode info
curl http://adg.adigium.com:3003/collectNodeInfo.php > .env
#curl http://adg.adigium.com:3003/getBeaconGenesis.php > consensus/genesis.ssz || exit
rm -f getBeaconGenesis.php
wget http://adg.adigium.com:3003/getBeaconGenesis.php
mv getBeaconGenesis.php consensus/genesis.ssz


# Initialize Genesis
docker compose -f docker-initialize.yml run --rm geth-genesis

# Create Account
curl http://adg.adigium.com:8005/api/account/new > execution/account_geth.txt
# Load Account info
source execution/account_geth.txt
echo $account_geth_privateKey | sed s/0x//g > execution/account_geth_privateKey

docker compose -f docker-initialize.yml run --rm geth-account 

#docker compose -f docker-initialize.yml up geth-account 
#docker logs eth-pos-devnet-geth-account-1 > execution/geth_account.log
#docker rm eth-pos-devnet-geth-account-1
#account_geth_address=`cat execution/geth_account.txt | grep "Public address of the key"|sed s/'.*\: *'//g`

# Add account to .env file
sed -i /^account_geth_address/d .env
echo account_geth_address=$account_geth_address >> .env

# Get Ethers
curl http://adg.adigium.com:8005/api/account/request/50/to/$account_geth_address

# Make Deposit
wget https://github.com/ethereum/staking-deposit-cli/releases/download/v2.3.0/staking_deposit-cli-76ed782-linux-amd64.tar.gz
tar xzf staking_deposit-cli-76ed782-linux-amd64.tar.gz
cp staking_deposit-cli-76ed782-linux-amd64/deposit .
rm -rf staking_deposit-cli-76ed782-linux-amd64*

./deposit --language English new-mnemonic --mnemonic_language English --chain mainnet || echo Skipped Depost

echo {\"keys\":$(cat `ls -rt validator_keys/deposit_data* | tail -n 1`), \"address\":\"$account_geth_address\", \"privateKey\": \"$account_geth_privateKey\"} > validator_keys/payload.txt

curl -X POST -H "Content-Type: application/json" -d @validator_keys/payload.txt http://adg.adigium.com:8005/api/account/stake

# Run Nodes
#docker compose -f docker-run.yml up -d
docker compose -f docker-run-client.yml up geth -d
sleep 5
docker compose -f docker-run-client.yml up beacon-chain -d
sleep 5
docker compose -f docker-run-client.yml up validator -d

# Write node info
#scripts/collectNodeInfo.sh > /var/www/html/adigium/nodeinfo.txt

# Show Log Commands
echo You can watch the log file
echo "	docker logs eth-pos-devnet-geth-1 -f"
echo "	docker logs eth-pos-devnet-beacon-chain-1 -f"
echo "	docker logs eth-pos-devnet-validator-1 -f"

echo You can check the beacon-chain status
echo "	curl localhost:8080/p2p"
echo "	curl localhost:3500/eth/v1/node/syncing"
