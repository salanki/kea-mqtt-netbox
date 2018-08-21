#!/bin/bash

# set -ex -f
MQTT_BROKER=mqtt.loc.upnorthhost.com
MQTT_TOPIC=infra/dhcp

export KEA_COMMAND=$1

MSG="{"

for E in `env`; do
 if [[ $E = "KEA_"* ]]; then
   splits=(${E//=/ })
   escaped=$(printf "%q" ${splits[1]})
   MSG="$MSG\"${splits[0]}\": \"$escaped\", "
 fi
done;
MSG="$MSG\"source\": \"mqtt.sh\"}"

echo $MSG
mosquitto_pub -h $MQTT_BROKER -t $MQTT_TOPIC -m "$MSG"
