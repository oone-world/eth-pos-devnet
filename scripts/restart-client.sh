cd /home/adigium/eth-pos-devnet/

docker compose down

# Clean Folders
#git clean -fxd
rm -rf consensus/beacondata/ consensus/genesis.ssz consensus/validatordata/ execution/geth/

# Initialize Genesis
docker compose -f docker-initialize.yml run --rm geth-genesis

# Get BootNode info
curl http://adg.adigium.com:3003/collectNodeInfo.php > .env
curl http://adg.adigium.com:3003/getBeaconGenesis.php > consensus/genesis.ssz

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
