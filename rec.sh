#!/bin/sh

PID=$$
DATE=`date '+%Y%m%d_%H%M'`
URL=http://radiko.jp/player/swf/player_3.0.0.01.swf
PLAYER="/tmp/player.swf"
KEYFILE="/tmp/authkey.png"
LOGFILE="${HOME}/radio/log/rec.log"
home_dir="${HOME}/radio/data"

echo "Start $DATE : $0 $1 $2 $3" | tee -a ${LOGFILE}

CHANNEL=$1
if [ $# -eq 2 ]; then
  FILENAME="${CHANNEL}_${DATE}"
elif [ $# -eq 3 ]; then
  FILENAME=$3_${DATE}
else
  echo "usage : $0 channel_name duration(minuites) [file name]" | tee -a ${LOGFILE}
  exit 1
fi

DURATION=`expr $2 \* 60`


# get player
if [ ! -f $PLAYER ]; then
  wget -q -O $PLAYER $URL

  if [ $? -ne 0 ]; then
    echo "failed get player" | tee -a ${LOGFILE}
    exit 1
  fi
fi

# get keydata (need swftool)
if [ ! -f $KEYFILE ]; then
  swfextract -b 14 $PLAYER -o $KEYFILE

  if [ ! -f $KEYFILE ]; then
    echo "failed get keydata" | tee -a ${LOGFILE}
    exit 1
  fi
fi

if [ -f auth1_fms_${PID} ]; then
  rm -f auth1_fms_${PID}
fi

# access auth1_fms
wget -q \
     --header="pragma: no-cache" \
     --header="X-Radiko-App: pc_1" \
     --header="X-Radiko-App-Version: 2.0.1" \
     --header="X-Radiko-User: test-stream" \
     --header="X-Radiko-Device: pc" \
     --post-data='\r\n' \
     --no-check-certificate \
     --save-headers \
     -O auth1_fms_${PID} \
     https://radiko.jp/v2/api/auth1_fms

if [ $? -ne 0 ]; then
  echo "failed auth1 process" | tee -a ${LOGFILE}
  exit 1
fi

#
# get partial key
authtoken=`perl -ne 'print $1 if(/x-radiko-authtoken: ([\w-]+)/i)' auth1_fms_${PID}`
offset=`perl -ne 'print $1 if(/x-radiko-keyoffset: (\d+)/i)' auth1_fms_${PID}`
length=`perl -ne 'print $1 if(/x-radiko-keylength: (\d+)/i)' auth1_fms_${PID}`

partialkey=`dd if=${KEYFILE} bs=1 skip=${offset} count=${length} 2> /dev/null | base64`

echo "authtoken: ${authtoken} \noffset: ${offset} length: ${length} \npartialkey: $partialkey" | tee -a ${LOGFILE}

rm -f auth1_fms_${PID}

if [ -f auth2_fms_${PID} ]; then
  rm -f auth2_fms_${PID}
fi

# access auth2_fms
wget -q \
     --header="pragma: no-cache" \
     --header="X-Radiko-App: pc_1" \
     --header="X-Radiko-App-Version: 2.0.1" \
     --header="X-Radiko-User: test-stream" \
     --header="X-Radiko-Device: pc" \
     --header="X-Radiko-Authtoken: ${authtoken}" \
     --header="X-Radiko-Partialkey: ${partialkey}" \
     --post-data='\r\n' \
     --no-check-certificate \
     -O auth2_fms_${PID} \
     https://radiko.jp/v2/api/auth2_fms

if [ $? -ne 0 -o ! -f auth2_fms_${PID} ]; then
  echo "failed auth2 process" | tee -a ${LOGFILE}
  exit 1
fi

echo "authentication success" | tee -a ${LOGFILE}

areaid=`perl -ne 'print $1 if(/^([^,]+),/i)' auth2_fms_${PID}`
echo "areaid: $areaid" | tee -a ${LOGFILE}

rm -f auth2_fms_${PID}

# get stream-url
if [ -f ${CHANNEL}.xml ]; then
  rm -f ${CHANNEL}.xml
fi

wget -q "http://radiko.jp/v2/station/stream/${CHANNEL}.xml" 

stream_url=`echo "cat /url/item[1]/text()" | xmllint --shell ${CHANNEL}.xml | tail -2 | head -1`
url_parts=(`echo ${stream_url} | perl -pe 's!^(.*)://(.*?)/(.*)/(.*?)$/!$1://$2 $3 $4!'`)

rm -f ${CHANNEL}.xml


TMP_FILE="/tmp/${FILENAME}"
#
# rtmpdump
echo "  ==== start rtmpdump ==== " | tee -a ${LOGFILE}
/usr/local/bin/rtmpdump -v \
         -r ${url_parts[0]} \
         --app ${url_parts[1]} \
         --playpath ${url_parts[2]} \
         -W $playerurl \
         -C S:"" -C S:"" -C S:"" -C S:$authtoken \
         --live \
	 --timeout 120 \
         --stop ${DURATION} \
         --flv ${TMP_FILE} \
	 --resume
echo "  == end rtmpdump == " | tee -a ${LOGFILE}

if [ ! -e ${TMP_FILE} ]; then
	echo "rtmpdump command failed (exit)" | tee -a ${LOGFILE}
	exit 1
fi

# ffmpeg
echo "  ==== start ffmpeg ==== " | tee -a ${LOGFILE}
/usr/local/bin/ffmpeg -y -i ${TMP_FILE} -acodec mp3 -ab 32K -ac 1 "${home_dir}/${FILENAME}.mp3"
echo "  ==== end ffmpeg ==== " | tee -a ${LOGFILE}

if [ $? = 0 ]; then
  rm -f "/tmp/${CHANNEL}_${DATE}"
fi

DATE=`date '+%Y-%m-%d-%H%M'`
echo "End $DATE : success ${home_dir}/${CHANNEL}_${DATE}.mp3" | tee -a ${LOGFILE}
echo "" | tee -a ${LOGFILE}
