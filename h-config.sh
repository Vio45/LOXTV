#!/usr/bin/env bash

function miner_fork() {
	local MINER_FORK=$ETHMINER_FORK
	[[ -z $MINER_FORK ]] && MINER_FORK=$MINER_DEFAULT_FORK
	echo $MINER_FORK
}


function miner_ver() {
	local MINER_VER=$ETHMINER_VER
	if [[ -z $MINER_VER ]]; then
		local -n MINER_VER="MINER_LATEST_VER_${MINER_FORK^^}" # uppercase MINER_FORK
		local -n MINER_VER_CUDA11="MINER_LATEST_VER_${MINER_FORK^^}_CUDA11"
		[[ ! -z $MINER_VER_CUDA11 && $(nvidia-smi --help 2>&1 | head -n 1 | grep -oP "v\K[0-9]+") -ge 455 ]] &&
			MINER_VER=$MINER_VER_CUDA11
	fi
	echo $MINER_VER
}


function miner_config_echo() {
	export MINER_FORK=`miner_fork`
	local MINER_VER=`miner_ver`
	miner_echo_config_file "/hive/miners/$MINER_NAME/$MINER_FORK/$MINER_VER/ethminer.conf"
}


function miner_config_gen() {
	local MINER_CONFIG="$MINER_DIR/$MINER_FORK/$MINER_VER/ethminer.conf"
	mkfile_from_symlink $MINER_CONFIG

	#put default config settings
	#\n--farm-recheck 2000
	echo -e "--report-hashrate --api-port 3334" > $MINER_CONFIG
	[[ $ETHMINER_VER == "0.14.0" ]]; then
		echo -e "-HWMON" >> $MINER_CONFIG
	
	fi

	[[ $ETHMINER_OPENCL == 0 ]] && ETHMINER_OPENCL=
	[[ $ETHMINER_CUDA == 0 ]] && ETHMINER_CUDA=

	if [[ $ETHMINER_OPENCL == 1 && $ETHMINER_CUDA == 1 ]]; then #|| [[ -z $ETHMINER_OPENCL && -z $ETHMINER_CUDA ]]
		#autodetect gpu types
		[[ -z $GPU_COUNT_AMD ]] && GPU_COUNT_AMD=`gpu-detect AMD`
		[[ -z $GPU_COUNT_NVIDIA ]] && GPU_COUNT_NVIDIA=`gpu-detect NVIDIA`

		echo "Detected $GPU_COUNT_AMD AMD"
		echo "Detected $GPU_COUNT_NVIDIA Nvidia"
		[[ $GPU_COUNT_AMD > 0 ]] && ETHMINER_OPENCL=1 || ETHMINER_OPENCL=
		[[ $GPU_COUNT_NVIDIA > 0 ]] && ETHMINER_CUDA=1 || ETHMINER_CUDA=
	fi

	[[ "$(miner_ver)" =~ ^([0-9]+)\.([0-9]+)\. ]]
	# some options are not supported from version 0.18
	if [[ ${BASH_REMATCH[1]} -eq 0 && ${BASH_REMATCH[2]} -le 17 ]]; then
		[[ -z $ETHMINER_OPENCL && -z $ETHMINER_CUDA ]] && echo "--cuda-opencl --opencl-platform 1" >> $MINER_CONFIG
		[[ $ETHMINER_OPENCL == 1 && $ETHMINER_CUDA == 1 ]] && echo "--cuda-opencl" >> $MINER_CONFIG
	fi

	[[ $ETHMINER_OPENCL == 1 && -z $ETHMINER_CUDA ]] && echo "--opencl" >> $MINER_CONFIG
	[[ -z $ETHMINER_OPENCL && $ETHMINER_CUDA == 1 ]] && echo "--cuda" >> $MINER_CONFIG

#pre 0.14.0rc0
#	if [[ ! -z $ETHMINER_TEMPLATE ]]; then
#		echo -n "-O $ETHMINER_TEMPLATE" >> $MINER_CONFIG
#		[[ ! -z $ETHMINER_PASS ]] && echo -n ":$ETHMINER_PASS" >> $MINER_CONFIG
#		echo -en "\n" >> $MINER_CONFIG
#	fi
#
#	if [[ ! -z $ETHMINER_SERVER ]]; then
#		echo -n "-S $ETHMINER_SERVER" >> $MINER_CONFIG
#		[[ ! -z $ETHMINER_PORT ]] && echo -n ":$ETHMINER_PORT" >> $MINER_CONFIG
#		echo -en "\n" >> $MINER_CONFIG
#	fi

	case $MINER_FORK in
		quarkchain)
			if [[ ! -z $ETHMINER_TEMPLATE && ! -z $ETHMINER_SERVER ]]; then
				local url=
				local server=
				local hosts=($ETHMINER_SERVER)
				local ports=($ETHMINER_PORT)
				local host=${hosts[0]}
				local port=${ports[0]}

				grep -q -E '^(stratum|http|https).*://' <<< ${host}
				if [[ $? == 0 ]]; then
					protocol=$(awk -F '://' '{print $1"://"}' <<< ${host})
					server=$(awk -F '://' '{print $2}' <<< ${host})
				else #no protocol in server
					protocol="http://"
					server=${host}
				fi

				url="$protocol$server:$port"
				local wallet="--coinbase $ETHMINER_TEMPLATE"
				echo $url    >> $MINER_CONFIG
				echo $wallet >> $MINER_CONFIG
			fi
    ;;
	  *)
			if [[ ! -z $ETHMINER_TEMPLATE && ! -z $ETHMINER_SERVER ]]; then
				local url=
				local protocol=
				local server=
				local hosts=($ETHMINER_SERVER)
				local ports=($ETHMINER_PORT)
				local port=

				for (( i=0; i < ${#hosts[@]}; i++)); do
					grep -q -E '^(stratum|http|zil).*://' <<< ${hosts[$i]}
					if [[ $? == 0 ]]; then
						protocol=$(awk -F '://' '{print $1"://"}' <<< ${hosts[$i]})
						server=$(awk -F '://' '{print $2}' <<< ${hosts[$i]})
					else #no protocol in server
						protocol="stratum+tcp://"
						server=${hosts[$i]}
					fi

					url+=$protocol

					ETHMINER_TEMPLATE=$(sed 's/\//%2F/g' <<< $ETHMINER_TEMPLATE) #HTML special chars
					EMAIL=$(sed 's/@/%40/g' <<< $EMAIL) #HTML special chars

					url+=$ETHMINER_TEMPLATE
					[[ ! -z $ETHMINER_PASS ]] && url+=":$ETHMINER_PASS"

					[[ ! -z ${ports[$i]} ]] && port=${ports[$i]}

					url+="@$server:$port"

					echo "-P $url" >> $MINER_CONFIG

				done

			fi
	esac

	[[ ! -z $ETHMINER_USER_CONFIG ]] && echo "$ETHMINER_USER_CONFIG" >> $MINER_CONFIG

	#remove deprecated option
	conf=`cat $MINER_CONFIG | sed '/--stratum-protocol/d'`
	echo $conf > $MINER_CONFIG
}
