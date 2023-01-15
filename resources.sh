while :
do
	date >> logs/resources.log
	free -ht >> logs/resources.log
	df /dev/sda >> logs/resources.log
	echo >> logs/resources.log
	sleep 60
done
