#!/bin/bash

# set -ex
TOKEN=$NETBOX_TOKEN
DATE=$(date)
LOGFILE=/tmp/kea-hook-runscript-debug.log

for s in $(echo $1 | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]" ); do
    export $s
done

COMMAND=$KEA_COMMAND

echo "Command: $COMMAND"

check-ip() {
  IP="$KEA_LEASE4_ADDRESS/$KEA_SUBNET4_PREFIXLEN"
  IP_ADDRESSES_URL="http://$NETBOX_HOSTNAME/api/ipam/ip-addresses/?q=$KEA_LEASE4_ADDRESS"

  while [ $IP_ADDRESSES_URL != null ]; do
    IP_ADDRESSES=$(get-ips $IP_ADDRESSES_URL)
    for row in $(echo $IP_ADDRESSES | jq -r ".results[] | select(.address | startswith(\"$KEA_LEASE4_ADDRESS\")) | @base64"); do
      CURRENT_IP=$(echo $row | base64 --decode | jq -r ".address" | cut -d '/' -f 1)
      CURRENT_ID=$(echo $row | base64 --decode | jq -r ".id")
      if [ "$CURRENT_IP" = "$KEA_LEASE4_ADDRESS" ]; then echo -n $CURRENT_ID; return 0; fi
    done
    IP_ADDRESSES_URL=$(echo $IP_ADDRESSES | jq '.next' | sed s/\"//g | sed s/localhost/$NETBOX_HOSTNAME/)
  done
  echo -n
  return 1
}

tenant-from-hostname() {
 HOSTNAME=$1 

 if [ -z "$HOSTNAME" ] || [ "$HOSTNAME" = "" ]; then echo -n $DEFAULT_TENANT; return 1; fi

 for row in $(cat $TENANT_FILE | jq -r ".[] | select(.hostname==\"$HOSTNAME\") | @base64"); do
     CURRENT_TENANT=$(echo $row | base64 --decode | jq -r ".tenant")
     echo -n $CURRENT_TENANT
     return 0
 done
 echo -n $DEFAULT_TENANT
 return 1
}

tenant-to-id() {
 SLUG=$1

 TENANTS=$(get-tenants)
 for row in $(echo $TENANTS | jq -r '.results[] | @base64'); do
      CURRENT_SLUG=$(echo $row | base64 --decode | jq -r ".slug" | cut -d '/' -f 1)
      CURRENT_ID=$(echo $row | base64 --decode | jq -r ".id")
      if [ "$CURRENT_SLUG" = "$SLUG" ]; then echo -n $CURRENT_ID; return 0; fi
 done
 echo -n 'null'
 return 1
}

create-ip() {
  curl -X POST "http://$NETBOX_HOSTNAME/api/ipam/ip-addresses/" \
    -H "Content-Type: application/json" \
    -H "Authorization: Token $TOKEN" \
    -H "Accept: application/json; indent=4" \
    -H "X-Session-Key: $KEY" \
    -d "{ \"address\": \"$KEA_LEASE4_ADDRESS/$KEA_SUBNET4_PREFIXLEN\", \"status\": 5, \"description\": \"$KEA_LEASE4_HOSTNAME\", \"tenant\": $TENANT_ID }"
}

delete-ip() {
  ID=$1
  curl -X DELETE "http://$NETBOX_HOSTNAME/api/ipam/ip-addresses/$ID/" \
    -H "Content-Type: application/json" \
    -H "Authorization: Token $TOKEN" \
    -H "Accept: application/json; indent=4" \
    -H "X-Session-Key: $KEY"
}

get-tenants() {
  curl -s -X GET "http://$NETBOX_HOSTNAME/api/tenancy/tenants/" \
    -H "Content-Type: application/json" \
    -H "Authorization: Token $TOKEN" \
    -H "Accept: application/json; indent=4" \
    -H "X-Session-Key: $KEY"
}

get-ips() {
  URL=$1
  curl -s -X GET $URL \
    -H "Content-Type: application/json" \
    -H "Authorization: Token $TOKEN" \
    -H "Accept: application/json; indent=4" \
    -H "X-Session-Key: $KEY"
}

get-session-key() {
  curl -s -X POST "http://$NETBOX_HOSTNAME/api/secrets/get-session-key/" \
    -H "Authorization: Token $TOKEN" \
    -H "Accept: application/json; indent=4" \
    --data-urlencode "private_key@id_rsa" | jq '.session_key'
}

logger() {
  echo "$DATE $COMMAND: $KEA_LEASE4_ADDRESS" >> $LOGFILE
}

update-ip() {
  ID=$1
  IP="$KEA_LEASE4_ADDRESS/$KEA_SUBNET4_PREFIXLEN"
  curl -X PUT "http://$NETBOX_HOSTNAME/api/ipam/ip-addresses/$ID/" \
    -H "Content-Type: application/json" \
    -H "Authorization: Token $TOKEN" \
    -H "Accept: application/json; indent=4" \
    -H "X-Session-Key: $KEY" \
    -d "{ \"address\": \"$IP\", \"description\": \"$KEA_LEASE4_HOSTNAME\", \"tenant\": $TENANT_ID }"
}

if [ "$DEBUG" -eq 1 ]; then
    echo $COMMAND >> $LOGFILE
    echo $DATE >> $LOGFILE
    env >> $LOGFILE
    echo >> $LOGFILE
    echo >> $LOGFILE
fi

case "$COMMAND" in
"lease4_select" | "lease4_renew" )
  if [ "$KEA_FAKE_ALLOCATION" == "1" ]; then
    # echo "Fake allocation $KEA_LEASE4_ADDRESS" >> $LOGFILE
    exit 0
  fi
  KEY=$(get-session-key)
  ID=$(check-ip)
  TENANT=$(tenant-from-hostname $KEA_LEASE4_HOSTNAME)
  TENANT_ID=$(tenant-to-id $TENANT)
  logger

  echo "Tenant: $TENANT Id: $TENANT_ID Hostname: $KEA_LEASE4_HOSTNAME"

  if [ "$ID" == "" ]; then
    create-ip
  else
    update-ip $ID
  fi
;;

"lease4_expire" )
  KEY=$(get-session-key)
  ID=$(check-ip)
  logger
  delete-ip $ID
;;

esac
