echo "Connecting to $MQTT_BROKER"
mosquitto_sub -h $MQTT_BROKER -t $MQTT_TOPIC | tr '\n' '\0' | xargs -0 -n1 ./wrapper.sh $1 
