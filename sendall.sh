function GatherGethBootnodes {
	rm execution/bootnodes.txt
	my_enode=$(geth attach --exec "admin.nodeInfo.enode" data/execution/0/geth.ipc | sed s/^\"// | sed s/\"$//)
	echo $my_enode >> execution/bootnodes.txt
	my_enode=$(geth attach --exec "admin.nodeInfo.enode" data/execution/1/geth.ipc | sed s/^\"// | sed s/\"$//)
	echo $my_enode >> execution/bootnodes.txt
	echo "Execution Bootnodes:"
	cat execution/bootnodes.txt
}
function GatherBeaconBootnodes {
	rm consensus/bootnodes.txt

	my_enode=$(curl http://localhost:5052/eth/v1/node/identity 2>/dev/null | jq -r ".data.enr")
	echo $my_enode >> consensus/bootnodes.txt
	my_enode=$(curl http://localhost:5053/eth/v1/node/identity 2>/dev/null | jq -r ".data.enr")
	echo $my_enode >> consensus/bootnodes.txt
	echo "Consensus Bootnodes:"
	cat consensus/bootnodes.txt
}
function SendFiles {
	scp /home/adigium/eth-pos-devnet/execution/genesis* root@adigium.innuva.com:/home/adigium/eth-pos-devnet/execution/
	scp /home/adigium/eth-pos-devnet/execution/bootnodes.txt root@adigium.innuva.com:/home/adigium/eth-pos-devnet/execution/
	
	scp /home/adigium/eth-pos-devnet/consensus/bootnodes.txt root@adigium.innuva.com:/home/adigium/eth-pos-devnet/consensus/
	
	scp /home/adigium/eth-pos-devnet/data/testnet/* root@adigium.innuva.com:/home/adigium/eth-pos-devnet/data/testnet/
}

GatherGethBootnodes
GatherBeaconBootnodes
SendFiles
