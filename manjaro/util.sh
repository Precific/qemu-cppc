
AUTOYES=0
for arg in "$@"; do
	if [[ "$arg" == "-y" ]]; then
		AUTOYES=1
	fi
done

function ask_continue_or_exit {
	if [ $AUTOYES -eq 1 ]; then
		return 0
	fi
	while true; do
		read -p "Do you want to continue? [y/n]: " answer
		if [[ "$answer" =~ ^[yY]$ ]]; then
			return 0
		elif [[ "$answer" =~ ^[nN]$ ]]; then
			echo "Aborted"
			exit 1
		fi
		echo "?"
	done
}