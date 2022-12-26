set -e 
cd /home/adigium/eth-pos-devnet/

docker compose down

# Clean Folders
git clean -fxd
#rm -rf consensus/beacondata/ consensus/genesis.ssz consensus/validatordata/ execution/geth/

# Initialize Genesis
#docker compose -f docker-initialize.yml up && docker compose -f docker-initialize.yml down
docker compose -f docker-initialize.yml run --rm geth-genesis
docker compose -f docker-initialize.yml run --rm create-beacon-chain-genesis

# Create Account
#curl http://localhost:8005/api/account/new > execution/account_geth.txt
echo account_geth_address=0xF359C69a1738F74C044b4d3c2dEd36c576A34d9f > execution/account_geth.txt
echo account_geth_privateKey=0x28fb2da825b6ad656a8301783032ef05052a2899a81371c46ae98965a6ecbbaf >> execution/account_geth.txt

# Load Account info
source execution/account_geth.txt
echo $account_geth_privateKey | sed s/0x//g > execution/account_geth_privateKey
docker compose -f docker-initialize.yml run --rm geth-account 

# Add account to .env file
#sed -i /^account_geth_address/d .env
echo account_geth_address=$account_geth_address >> .env


# Run Geth
docker compose -f docker-run.yml up geth -d
sleep 5
docker compose -f docker-run.yml up beacon-chain -d
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

# Make the deposit
echo {\"keys\":$(cat `ls -rt validator_keys/deposit_data* | tail -n 1`), \"address\":\"$account_geth_address\", \"privateKey\": \"$account_geth_privateKey\"} > validator_keys/payload.txt
curl -X POST -H "Content-Type: application/json" -d @validator_keys/payload.txt http://localhost:8005/api/account/stake

# Import Wallet and Accounts
mkdir wallet_dir
echo "John.Risk" > /home/adigium/eth-pos-devnet/wallet_dir/password.txt
cp /root/prysm/validator .
./validator wallet create --wallet-dir=wallet_dir --wallet-password-file=wallet_dir/password.txt
./validator accounts import --keys-dir=validator_keys/ --wallet-dir=wallet_dir --wallet-password-file=wallet_dir/password.txt --account-password-file=wallet_dir/password.txt
./validator --datadir=consensus/validatordata --accept-terms-of-use --chain-config-file=consensus/config.yml --wallet-dir=wallet_dir --wallet-password-file=wallet_dir/password.txt
#docker compose -f docker-run.yml up validator -d

# Write node info
scripts/collectNodeInfo.sh > /var/www/html/adigium/nodeinfo.txt
cp consensus/genesis.ssz /var/www/html/adigium/ 

# Show Log Commands
echo You can watch the log file
echo "	docker logs eth-pos-devnet-geth-1 -f"
echo "	docker logs eth-pos-devnet-beacon-chain-1 -f"
echo "	docker logs eth-pos-devnet-validator-1 -f"
