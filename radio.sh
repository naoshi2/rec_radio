#!/bin/sh

PID=$$
date=`date '+%Y%m%d_%H%M'`
playerurl=http://radiko.jp/player/swf/player_3.0.0.01.swf
playerfile="/tmp/player.swf"
keyfile="/tmp/authkey.png"
LOGFILE="${HOME}/radio/log/rec.log"
home_dir="${HOME}/radio/data"

function rtmpdump_radiko()
{
    # $1: url_parts,   $2: authtoken,
    # $3: Duration, $4: TMP_FILE
    echo "  ==== start rtmpdump ==== " | tee -a ${LOGFILE}
    /usr/local/bin/rtmpdump -v \
         -r $1\
         --app $2 \
         --playpath $3 \
         -W $playerurl \
         -C S:"" -C S:"" -C S:"" -C S:$4\
         --live \
	 --timeout 120 \
         --stop $5 \
         --flv $6 \
	 --resume
     echo "  == end rtmpdump == " | tee -a ${LOGFILE}

     if [ ! -e ${TMP_FILE} ]; then
	echo "rtmpdump command failed (exit)" | tee -a ${LOGFILE}
	exit 1
     fi
}

function encode_mp3()
{
     echo "  ==== start ffmpeg ==== " | tee -a ${LOGFILE}
     /usr/local/bin/ffmpeg -y -i $1 -acodec mp3 -ab 32K -ac 1 "${home_dir}/$2.mp3"
     echo "  ==== end ffmpeg ==== " | tee -a ${LOGFILE}
}

########################################
# $0: program name, $1: Channel
# $2: Duration (minute),     $3: Output file name
########################################
echo "Start $date : $0 $1 $2 $3" | tee -a ${LOGFILE}

if [ $# -eq 2 ]; then
  FILENAME="$1_${date}"
elif [ $# -eq 3 ]; then
  FILENAME=$3_${date}
else
  echo "usage : $0 channel_name duration(minuites) [file name]" | tee -a ${LOGFILE}
  exit 1
fi

channel=$1
DURATION=`expr $2 \* 60`

# get player
if [ ! -f $playerfile ]; then
  wget -q -O $playerfile $playerurl

  if [ $? -ne 0 ]; then
    echo "failed get player" | tee -a ${LOGFILE}
    exit 1
  fi
fi

# get keydata (need swftool)
if [ ! -f $keyfile ]; then
  swfextract -b 14 $playerfile -o $keyfile

  if [ ! -f $keyfile ]; then
    echo "failed get keydata" | tee -a ${LOGFILE}
    exit 1
  fi
fi

#### prep #####
rm -f auth1_fms_${PID} >/dev/null 2>&1
rm -f auth2_fms_${PID} >/dev/null 2>&1
rm -f ${channel}.xml >/dev/null 2>&1

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

# get partial key
authtoken=`perl -ne 'print $1 if(/x-radiko-authtoken: ([\w-]+)/i)' auth1_fms_${PID}`
offset=`perl -ne 'print $1 if(/x-radiko-keyoffset: (\d+)/i)' auth1_fms_${PID}`
length=`perl -ne 'print $1 if(/x-radiko-keylength: (\d+)/i)' auth1_fms_${PID}`
partialkey=`dd if=$keyfile bs=1 skip=${offset} count=${length} 2> /dev/null | base64`
echo "authtoken: ${authtoken} \noffset: ${offset} length: ${length} \npartialkey: $partialkey" | tee -a ${LOGFILE}

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

wget -q "http://radiko.jp/v2/station/stream/${channel}.xml" 

stream_url=`echo "cat /url/item[1]/text()" | xmllint --shell ${channel}.xml | tail -2 | head -1`
url_parts=(`echo ${stream_url} | perl -pe 's!^(.*)://(.*?)/(.*)/(.*?)$/!$1://$2 $3 $4!'`)

### clean up
rm -f auth1_fms_${PID}
rm -f auth2_fms_${PID}
rm -f ${channel}.xml

TMP_FILE="/tmp/${FILENAME}"

# rtmpdump
rtmpdump_radiko ${url_parts[0]} ${url_parts[1]} ${url_parts[2]} ${authtoken} ${DURATION} ${TMP_FILE}

# ffmpeg
encode_mp3 ${TMP_FILE} ${FILENAME}

date=`date '+%Y-%m-%d-%H%M'`
echo "End $date : success ${home_dir}/${FILENAME}.mp3" | tee -a ${LOGFILE}
echo "" | tee -a ${LOGFILE}
