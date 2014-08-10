#!/bin/bash

URL="rtmpe://netradio-${1}-flash.nhk.jp"
HOMEDIR="${HOME}/radio/data"
TMPDIR="/tmp"
DATE=`date '+%Y%m%d_%H%M'`
if [ $# -lt 2 ]; then
	echo "Usage: ./${0} [r1|r2|fm] [REC_TIME] [FILENAME]"
	echo "       r1:ラジオ第一 / r2:ラジオ第二 / fm:NHK-FM"
	exit 1
elif [ $# -eq 2 ]
then
	if [ "$1" == "r1" ]
	then
		FILENAME="NHK1_${DATE}"
	elif [ "$1" == "r2" ]
	then
		FILENAME="NHK2_${DATE}"
	elif [ "$1" == "fm" ]
	then
		FILENAME="NHKFM_${DATE}"
	fi
elif [ $# -eq 3 ]
then
	FILENAME="$3_${DATE}"
fi

REC_TIME=`expr $2 \* 60`
TMPPATH="${TMPDIR}/${FILENAME}"

case $1 in
	r1) PLAYPATH='NetRadio_R1_flash@63346' ;;
	r2) PLAYPATH='NetRadio_R2_flash@63342' ;;
	fm) PLAYPATH='NetRadio_FM_flash@63343' ;;
	*) exit 1 ;;
esac

/usr/local/bin/rtmpdump --rtmp "${URL}" \
		 --playpath "${PLAYPATH}" \
		 --app "live" \
		 -W http://www3.nhk.or.jp/netradio/files/swf/rtmpe.swf \
		 --live \
		 --stop "${REC_TIME}" \
		 --timeout 120 \
		 --flv ${TMPPATH}

if [ -s ${TMPPATH} ]; 
then
	/usr/local/bin/ffmpeg -y -i ${TMPPATH} -acodec mp3 -ab 32K -ac 1 "${HOMEDIR}/${FILENAME}.mp3" 
else
	echo "ERROR: file is empty"
	rm -f ${TMPPATH}
fi
