set -e 
cd /home/adigium/eth-pos-devnet/

docker compose down

# Clean Folders
#git clean -fxd
rm -rf consensus/beacondata/ consensus/genesis.ssz consensus/validatordata/ execution/geth/

# Initialize Genesis
#docker compose -f docker-initialize.yml up && docker compose -f docker-initialize.yml down
docker compose -f docker-initialize.yml run --rm geth-genesis
docker compose -f docker-initialize.yml run --rm create-beacon-chain-genesis

# Run Nodes
#docker compose -f docker-run.yml up -d
docker compose -f docker-run.yml up geth -d
sleep 5
docker compose -f docker-run.yml up beacon-chain -d
sleep 5
docker compose -f docker-run.yml up validator -d

# Write node info
scripts/collectNodeInfo.sh > /var/www/html/adigium/nodeinfo.txt
cp consensus/genesis.ssz /var/www/html/adigium/ 

# Show Log Commands
echo You can watch the log file
echo "	docker logs eth-pos-devnet-geth-1 -f"
echo "	docker logs eth-pos-devnet-beacon-chain-1 -f"
echo "	docker logs eth-pos-devnet-validator-1 -f"
