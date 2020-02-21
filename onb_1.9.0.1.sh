#!/bin/bash

printf "BEGIN: $(date)\n";

echo " "> JS.log;

#****************************************************

#Set Functions

#****************************************************

# @description  This function will remove quotes from XML input variables

# for processing in the script.  For example "10.0.0.10" is transformed

# to 10.0.0.10

# @arg $1 is the string with quotes.  The output is the same string

# with first and last quotes removed

function remove_quotes () {

        QUOTE_VAR=$1;

        QUOTE_VAR="${QUOTE_VAR%\"}";

        QUOTE_VAR="${QUOTE_VAR#\"}";

        echo $QUOTE_VAR;

}

# @description The retrieve_auth_token function will send a request to the

# BIGIP or the BIGIQ to retrieve an auth token.

# @arg $1 is the IP address of the device to retrieve the auth TOKEN

# @arg $2 is the username of the device login for token retrieval

# @arg $3 is the password of the device login for token retrieval

function retrieve_auth_token (){

        GET_TOKEN='{

                "username":"'"$2"'",

                "password":"'"$3"'",

                "loginProvidername":"tmos"

                }';



        #Retrieve Token

        TOKEN=$(curl -s -k -X POST -H "Content-type: application/json" -X POST https://${1}/mgmt/shared/authn/login -d "${GET_TOKEN}"|jq .token.token);



        TOKEN=$(remove_quotes $TOKEN);

        echo $TOKEN

}

# @description The save_sys_config function sends a request to the

# BIGIP to save the current configuration.

# NOTE:  username and password is not requried since an auth token has

# already been obtained

# @arg $1 is the IP address of the device to save the configuration

function save_sys_config (){

	SAVE_SYS_CONFIG_JS='

	{

 	    "command":"save"

 	}'



        SAVE_SYS_CONFIG=$(curl -s -k -X POST -H "${1}" -H "Content-type: application/json" -X POST https://localhost/mgmt/tm/sys/config -d "${SAVE_SYS_CONFIG_JS}");

	echo $SAVE_SYS_CONFIG;

}



# @description The create_vlan function creates the vlan

# @arg $1 is the Customer Number

# @arg $2 is the Vlan number

# @arg $3 is the interface (ie 1.1, 1.2)



function create_vlan () {

ADD_VLAN_JS='{

   "name": "VL_P'"$1"'-'"$2"'-PRD",

   "partition": "P'"$1"'",

   "tag": '"$2"',

   "tagged": true,

   "interfaces":[{"name":"'"$3"'","tagged":true}]

}';



ADD_VLAN=$(curl -s -k -X POST -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://localhost/mgmt/tm/net/vlan/ -H "Content-Type: application/json" -X POST -d "${ADD_VLAN_JS}");



echo "ADD_VLAN:$ADD_VLAN"; > /dev/stderr



}

# @description The create_self function creates the self ip addresses on the Big-IP

# @arg $1 is the Customer Number

# @arg $2 is the Vlan number

# @arg $3 is self IP

# @arg $4 is enabled/disabled (enable for floating ip)

function create_self () {

if [ "$4" = "enabled" ]; then

	TG="/Common/traffic-group-1";

else

	TG="/Common/traffic-group-local-only";

fi



CREATE_SELF_JS='{

  "name": "'"$3"'%'"$2"'",

  "partition": "P'"$1"'",

  "address": "'"$3"'%'"$2"'/24",

  "floating": "'"$4"'",

  "trafficGroup": "'"$TG"'",

  "vlan": "/P'"$1"'/VL_P'"$1"'-'"$2"'-PRD"

}'



CREATE_SELF=$(curl -s -k -X POST -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://localhost/mgmt/tm/net/self/ -H "Content-Type: application/json" -X POST -d "${CREATE_SELF_JS}");



echo "CREATE_SELF_JS: $CREATE_SELF_JS" >> JS.log;

echo "CREATE_SELF: $CREATE_SELF";

}



# @description The create_route function creates the default route for a route domain

# @arg $1 is the Customer Number

# @arg $2 is the Vlan number

# @arg $3 is Gateay IP

function create_route () {



CREATE_ROUTE_JS='{

    "name": "Route_VLAN'"$2"'",

    "partition": "P'"$1"'",

    "fullPath": "/P'"$1"'/Route_VLAN'"$2"'",

    "gw": "'"$3"'%'"$2"'",

    "network": "default%'"$2"'"

}'



CREATE_ROUTE=$(curl -s -k -X POST -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://localhost/mgmt/tm/net/route/ -H "Content-Type: application/json" -X POST -d "${CREATE_ROUTE_JS}");



echo "CREATE_ROUTE_JS: $CREATE_ROUTE_JS" >> JS.log;

echo "CREATE_ROUTE: $CREATE_ROUTE";

}



function valid_ip()

{

    local  ip=$1

    local  stat=1



    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then

        OIFS=$IFS

        IFS='.'

        ip=($ip)

        IFS=$OIFS

        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \

            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]

        stat=$?

    fi

    return $stat

}



function valid_vlan()

{

    local  vlan=$1

    local  stat=1



    if [[ $vlan =~ ^(([1-9][0-9]{0,2}|[1-3][0-9][0-9][0-9]|40([0-8][0-9]|9[0-6]))(,\s*[1-9][0-9]{0,2}|[1-3][0-9][0-9][0-9]|40([0-8][0-9]|9[0-6]))*)$

 ]]; then

        stat=0

    fi

    return $stat

}



###############################################

# @description The create_rd function creates the route domains

# @arg $1 is the Customer Number

# @arg $2 is the Vlan number



function create_rd () {



CREATE_RD_JS='{



  "name": "VRD'"$2"'",

  "partition": "P'"$1"'",

  "id": "'"$2"'",

  "description": "P'"$1"' - VRD'"$2"'",

  "vlans": [

    "/P'"$1"'/VL_P'"$1"'-'"$2"'-PRD"

  ]

}';



#echo "CREATE_RD_JS:  $CREATE_RD_JS" > /dev/stderr;



CREATE_RD=$(curl -s -k -X POST -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://localhost/mgmt/tm/net/route-domain/ -H "Content-Type: application/json" -X POST -d "${CREATE_RD_JS}");



}



#****************************************************

#Set Variables

#****************************************************

LOG=/var/tmp/DCO.log



BIGIQ_USERNAME=admin;

BIGIQ_PASSWORD=F4t80Y;



BIGIP_USERNAME=admin;

BIGIP_PASSWORD=admin;





red='\e[1;31m%s\e[0m\n';

green='\e[1;32m%s\e[0m\n';





if [ -e /var/tmp/vmout.xml ];then

	printf "The vmout.xml file exists in /var/tmp.  Reading from file\n";

	printf "*****NOTE**** if you are running the onboard script more than once and have made changes\n";

	printf "to the input data from in vmware.  Delete the vmout.xml file and re-run the onboard script\n"

else

	printf "The vmout.xml file does not exist in /var/tmp.  Creating file.\n";

   	VMOUT=`vmtoolsd --cmd "info-get guestinfo.ovfenv" > /var/tmp/vmout.xml`;

fi



OB_ERROR=0;

COUNTRY=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="COUNTRY"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

CUSTOMER_CC=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="CUSTOMER_CC"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

REGION=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="REGION"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

LOCALITY=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="LOCALITY"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_NET_1=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="FIRST_VLAN_IP_SUBNET"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_NET_2=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="SECOND_VLAN_IP_SUBNET"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_NET_3=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="THIRD_VLAN_IP_SUBNET"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_NET_4=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="FOURTH_VLAN_IP_SUBNET"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_NET_5=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="FIFTH_VLAN_IP_SUBNET"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_NET_6=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="SIXTH_VLAN_IP_SUBNET"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_ID_1=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="FIRST_VLAN_ID"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_ID_2=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="SECOND_VLAN_ID"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_ID_3=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="THIRD_VLAN_ID"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_ID_4=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="FOURTH_VLAN_ID"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_ID_5=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="FIFTH_VLAN_ID"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

VLAN_ID_6=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="SIXTH_VLAN_ID"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

HA_VLAN_ID=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="HA_VLAN_ID"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

BIGIP_MGMT_IP=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="MGMT_IP"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

LB_NUM=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="LB_UNIT"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));

BIGIP_LICENSE=$(remove_quotes $(xpath //var/tmp/vmout.xml '//Property[@oe:key="BIGIP_LICENSE"]/@oe:value' 2>/dev/null | awk '{split($0,a,"=");print a[2]}'));





BIGIP_HOSTNAME="$COUNTRY""$LOCALITY""VEcc$CUSTOMER_CC$LB_NUM.$LOCALITY.mcloud.entsvcs.net";

DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\"";

BIGIP_MGMT_SUBNET=22;

BIGIP_INTERFACE=1.2;



#BIGIQ_IP=$(echo "$BIGIP_MGMT_IP" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".60"}') ;

BIGIQ_IP=$(echo "$BIGIP_MGMT_IP" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".25"}') ;



BIGIP_MGMT_DFG=$(echo "$BIGIP_MGMT_IP" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".1"}') ;



BIGIP_CLUSTERNAME=$(echo "VECC$CUSTOMER_CC");



echo "Setting REGION and SYSLOG";

########################################

# set REGION and SYSLOG to lowercase   #

########################################

REGION=${REGION,,}

LOCALITY=${LOCALITY,,}





echo "Setting DNS";

##########

# DNS    #

##########

case "$REGION"  in

   lab) DNS="\"192.85.168.73\"";

        NTP="\"192.85.247.111\",\"30.7.88.1\""

   ;;

   ams) DNS="\"192.85.168.73\",\"138.35.151.115\"";

        NTP="\"192.85.247.111\",\"30.7.88.1\",\"138.35.151.176\""

   ;;

   emea) DNS="\"138.35.51.51\",\"138.35.51.115\""

         NTP="\"38.35.51.48\",\"138.35.51.112\",\"138.35.51.176\""

   ;;

   apj) DNS="\"138.35.251.51\",\"138.35.251.115\""

        NTP="\"38.35.251.48\",\"138.35.251.112\",\"138.35.251.176\""

   ;;

   *) echo "Region not defined-$REGION";

      DNS="\"8.8.8.8\",\"8.8.4.4\""

   ;;

esac



echo "Setting SYSLOG";

##########

# SYSLOG #

##########



case "$LOCALITY"  in

   acr) ARC="155.61.255.158"

	      NJUMP="155.61.254.252"

        DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   atc) ARC="155.61.239.158"

	      NJUMP="155.61.238.252"

        DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=22;

		;;

   bil) ARC="155.61.205.158"

	      NJUMP="155.61.204.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   bsi) ARC="15.84.45.158"

	NJUMP="15.84.44.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   crd) ARC="15.84.64.47"

	NJUMP="15.84.64.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   csi) ARC="15.84.80.47"

	NJUMP="15.84.80.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   dxs) ARC="15.84.68.47"

	NJUMP="15.84.68.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   edc) ARC="155.61.235.158"

	NJUMP="155.61.234.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   ge0) ARC="15.84.34.47"

	NJUMP="15.84.34.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   gre) ARC="155.61.230.47"

	NJUMP="155.61.230.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   ida) ARC="15.84.39.158"

	NJUMP="15.84.38.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   mcc) ARC="155.61.223.158"

	NJUMP="155.61.222.252"

		;;

   mui) ARC="15.84.48.47"

	NJUMP="15.84.48.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   roo) ARC="15.84.13.158"

	NJUMP="15.84.12.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   sph) ARC="15.84.11.158"

	NJUMP="15.84.10.252"

		;;

   swa) ARC="15.131.192.47"

	NJUMP="15.131.192.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   syz) ARC="155.61.225.158"

	NJUMP="155.61.224.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;

   tsm) ARC="138.35.179.158"

	NJUMP="138.35.177.252"

		;;

   tup) ARC="155.61.217.158"

	NJUMP="155.61.216.252"

		;;

   ult) ARC="15.84.50.47"

	NJUMP="15.84.50.252"

	DEVICE_GROUP="\"192.168.7.1\",\"192.168.7.2\",\"192.168.7.3\""

        BIGIP_MGMT_SUBNET=21;

		;;



   *) printf "\nLocality not defined-$LOCALITY\n";

	OB_ERROR=1

   ;;

esac



echo "Setting 4th OCTET";



case "$LB_NUM" in



	001) 	OCTET=5;

		IP_NET_1_F=$(echo "$VLAN_NET_1" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".4"}');

		IP_NET_2_F=$(echo "$VLAN_NET_2" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".4"}');

		IP_NET_3_F=$(echo "$VLAN_NET_3" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".4"}');

		IP_NET_4_F=$(echo "$VLAN_NET_4" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".4"}');

		IP_NET_5_F=$(echo "$VLAN_NET_5" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".4"}');

		IP_NET_6_F=$(echo "$VLAN_NET_6" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".4"}');

		HA_VLAN_IP=192.168.7.1;;

	002) 	OCTET=6;

		HA_VLAN_IP=192.168.7.2;;

	003) 	OCTET=7;

		HA_VLAN_IP=192.168.7.3;;

	*) printf "\nLB Nubmer is invalid - $LB_NUM";OB_ERROR=1;;

esac



IP_NET_1=$(echo "$VLAN_NET_1" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".'$OCTET'"}') ;

IP_NET_2=$(echo "$VLAN_NET_2" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".'$OCTET'"}') ;

IP_NET_3=$(echo "$VLAN_NET_3" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".'$OCTET'"}') ;

IP_NET_4=$(echo "$VLAN_NET_4" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".'$OCTET'"}') ;

IP_NET_5=$(echo "$VLAN_NET_5" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".'$OCTET'"}') ;

IP_NET_6=$(echo "$VLAN_NET_6" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".'$OCTET'"}') ;



IP_NET_ROUTE_1=$(echo "$VLAN_NET_1" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".1"}') ;

IP_NET_ROUTE_2=$(echo "$VLAN_NET_2" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".1"}') ;

IP_NET_ROUTE_3=$(echo "$VLAN_NET_3" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".1"}') ;

IP_NET_ROUTE_4=$(echo "$VLAN_NET_4" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".1"}') ;

IP_NET_ROUTE_5=$(echo "$VLAN_NET_5" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".1"}') ;

IP_NET_ROUTE_6=$(echo "$VLAN_NET_6" | awk '{split($0,a,".");print a[1]"."a[2]"."a[3]".1"}') ;



OFFERING=0;



if [[ $BIGIP_LICENSE = *"/"* ]];

then

        LICENSE_OFFERING=$(echo "$BIGIP_LICENSE"| awk '{split($0,a,"/");print a[2]}');

        BIGIP_LICENSE=$(echo "$BIGIP_LICENSE"| awk '{split($0,a,"/");print a[1]}');

	OFFERING=1;

fi



printf "Customer Number:$CUSTOMER_CC\n";

if [[ $CUSTOMER_CC =~ ^([0-9][0-9][0-9])$ ]];then printf "Valid Customer Number\n"; else printf "bad or invalid Customer Number\n"; OB_ERROR=1; fi

printf "CLUSTERNAME - $BIGIP_CLUSTERNAME\n";

printf "Region:$REGION\n";

printf "    DNS:$DNS\n";

printf "    NTP:$NTP\n";

printf "Locality:$LOCALITY\n";

printf "    ARC:$ARC\n";

printf "    NJUMP:$NJUMP\n";

printf "Country:$COUNTRY\n";



printf "FIRST_VLAN_IP_SUBNET:$VLAN_NET_1\t";if valid_ip $VLAN_NET_1; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "FIRST_VLAN_IP:$IP_NET_1\t\t";if valid_ip $IP_NET_1; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "FIRST_VLAN_ID:$VLAN_ID_1\t\t\t";if valid_vlan $VLAN_ID_1; then printf "$green" " - valid VLAN"; else printf "$red" " - BAD or VLAN ID.";OB_ERROR=1; fi



printf "SECOND_VLAN_IP_SUBNET:$VLAN_NET_2\t";if valid_ip $VLAN_NET_2; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values\n\nExiting script";OB_ERROR=1; fi

printf "SECOND_VLAN_IP:$IP_NET_2\t\t";if valid_ip $IP_NET_2; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "SECOND_VLAN_ID:$VLAN_ID_2\t\t\t";if valid_vlan $VLAN_ID_2; then printf "$green" " - valid VLAN"; else printf "$red" "- BAD or VLAN ID.";OB_ERROR=1; fi



printf "THIRD_VLAN_IP_SUBNET:$VLAN_NET_3\t";if valid_ip $VLAN_NET_3; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values. ";OB_ERROR=1; fi

printf "THIRD_VLAN_IP:$IP_NET_3\t\t";if valid_ip $IP_NET_3; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "THIRD_VLAN_ID:$VLAN_ID_3\t\t\t";if valid_vlan $VLAN_ID_3; then printf "$green" " - valid VLAN"; else printf "$red" "BAD or VLAN ID.";OB_ERROR=1; fi



printf "FOURTH_VLAN_IP_SUBNET:$VLAN_NET_4\t";if valid_ip $VLAN_NET_4; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "FOURTH_VLAN_IP:$IP_NET_4\t\t";if valid_ip $IP_NET_4; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "FOURTH_VLAN_ID:$VLAN_ID_4\t\t\t";if valid_vlan $VLAN_ID_4; then printf "$green" " - valid VLAN"; else printf "$red" "- BAD or VLAN ID.";OB_ERROR=1; fi



printf "FIFTH_VLAN_IP_SUBNET:$VLAN_NET_5\t";if valid_ip $VLAN_NET_5; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "FIFTH_VLAN_IP:$IP_NET_5\t\t";if valid_ip $IP_NET_5; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "FIFTH_VLAN_ID:$VLAN_ID_5\t\t\t";if valid_vlan $VLAN_ID_5; then printf "$green" " - valid VLAN"; else printf "$red" "- BAD or VLAN ID.";OB_ERROR=1; fi





printf "SIXTH_VLAN_IP_SUBNET:$VLAN_NET_6\t";if valid_ip $VLAN_NET_6; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "SIXTH_VLAN_IP:$IP_NET_6\t\t";if valid_ip $IP_NET_6; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "SIXTH_VLAN_ID:$VLAN_ID_6\t\t\t";if valid_vlan $VLAN_ID_6; then printf "$green" " - valid VLAN"; else printf "$red" "- BAD or VLAN ID. ";OB_ERROR=1; fi





if [ $LB_NUM = 001 ]; then

printf "FIRST_FLOATING_IP:$IP_NET_1_F\t\t";if valid_ip $IP_NET_1_F; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "SECOND_FLOATING_IP:$IP_NET_2_F\t\t";if valid_ip $IP_NET_2_F; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "THIRD_FLOATING_IP:$IP_NET_3_F\t\t";if valid_ip $IP_NET_3_F; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "FOURTH_FLOATING_IP:$IP_NET_4_F\t\t";if valid_ip $IP_NET_4_F; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "FIFTH_FLOATING_IP:$IP_NET_5_F\t\t";if valid_ip $IP_NET_5_F; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "SIXTH_FLOATING_ip:$IP_NET_6_F\t\t";if valid_ip $IP_NET_6_F; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

fi



printf "\nHA VLAN IP:$HA_VLAN_IP\t\t\t";if valid_ip $HA_VLAN_IP; then printf "$green" " - valid IP or Net"; else printf "$red"  " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi

printf "HA VLAN ID:$HA_VLAN_ID\t\t\t\t";if valid_vlan $HA_VLAN_ID; then printf "$green" " - valid VLAN"; else printf "$red" "BAD or VLAN ID. ";OB_ERROR=1; fi

#printf "IP DFG:$IP_DFG\t\t\t";if valid_ip $IP_DFG; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi



printf "MGMT:$BIGIP_MGMT_IP\t\t\t\t";if valid_ip $BIGIP_MGMT_IP; then printf "$green" " - valid IP or Net"; else printf "$red" " - BAD or MISSING IP, Please check entries in vmware and correct values.";OB_ERROR=1; fi



printf "LB_NUM:$LB_NUM\n";



printf "BIGIP_HOSTNAME:$BIGIP_HOSTNAME\n";

printf "BIGIQ_IP:$BIGIQ_IP";if valid_ip $BIGIQ_IP; then printf "$green" " - valid IP or Net"; else printf "$red"  " - BAD or MISSING IP, Please check entries in vmware and correct values. ";OB_ERROR=1; fi



if [ $OB_ERROR = 1 ]; then

printf "$red" "Error Encounterd Exiting script";

exit 2;

else

printf "$green" "All variables have passed.";

fi



#****************************************************

# This retrieves a security token from the Big_IP device and creates an auth header to be used for rest calls.

#****************************************************

echo -e "\n"

BIGIP_AUTH_HEADER='X-F5-AUTH-TOKEN:'$(retrieve_auth_token localhost $BIGIP_USERNAME $BIGIP_PASSWORD)'';

echo "**BIGIP_AUTH_HEADER: $BIGIP_AUTH_HEADER";



################################################################################



###################################################################################

###################################################################################





#****************************************************

# Disables DHCP

#****************************************************

BIGIP_DHCP_DISABLE_JS='{

  "mgmtDhcp": "disabled"

}'



BIGIP_DHCP_DISABLE=$(curl -s -k -X PATCH -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://localhost/mgmt/tm/sys/global-settings -d "${BIGIP_DHCP_DISABLE_JS}");

echo "BIGIP_DHCP_DISABLE=$BIGIP_DHCP_DISABLE";





#****************************************************

# SETS BIGIP MANAGEMENT address to be used to register with BIGIQ

#****************************************************

#

BIGIP_MGMT_JS='{

  "name": "'"$BIGIP_MGMT_IP"'/'"$BIGIP_MGMT_SUBNET"'",

  "fullPath": "'"$BIGIP_MGMT_IP"'/'"$BIGIP_MGMT_SUBNET"'",

  "description": "configured-statically"

}'



echo "BIGIP_MGMT_JS=$BIGIP_MGMT_JS";

#********************************************************************************************

BIGIP_MGMT=$(curl -s -k -X POST -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://localhost/mgmt/tm/sys/management-ip -d "${BIGIP_MGMT_JS}");



echo "BIGIP_MGMT=$BIGIP_MGMT";

#****************************************************

#SET BIGIP_MGMT Default Gateway

#****************************************************



BIGIP_MGMT_DFG_JS='{

  "name": "default",

  "partition": "Common",

  "fullPath": "/Common/default",

  "description": "configured-statically",

  "gateway": "'"$BIGIP_MGMT_DFG"'",

  "mtu": 0,

  "network": "default"

}'



echo "Configuring Management Route";

BIGIP_MGMT=$(curl -s -k -X POST -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://localhost/mgmt/tm/sys/management-route -d "${BIGIP_MGMT_DFG_JS}");



#****************************************************

# Validate that the BigIQ License and Offering exist on the Big-IQ

#****************************************************

BIGIQ_AUTH_HEADER='X-F5-AUTH-TOKEN:'$(retrieve_auth_token $BIGIQ_IP $BIGIQ_USERNAME $BIGIQ_PASSWORD)'';



BIGIQ_URI="https://${BIGIQ_IP}/mgmt/cm/device/licensing/pool/utility/licenses?)";

BIGIQ_LICENSE_CHECK=$(curl -s -k -X GET -H "${BIGIQ_AUTH_HEADER}" -H "Content-type: application/json" "$BIGIQ_URI");

BIGIQ_LICENSE_CHECK=$(echo $BIGIQ_LICENSE_CHECK | jq --arg BIGIP_LICENSE $BIGIP_LICENSE '.items[] | select(.name==$BIGIP_LICENSE)');

BIGIQ_OFFERING_CHECK=$(echo $BIGIQ_LICENSE_CHECK | jq --arg LICENSE_OFFERING $LICENSE_OFFERING '.licenseState.featureFlags[] | select(.featureValue==$LICENSE_OFFERING)| .featureValue');



if [ -z "${BIGIQ_LICENSE_CHECK}" ];then

        printf "$red" "Checked Big-IQ.  The license $BIGIP_LICENSE does not exist on the Big-IQ.  Please check the entries in vmware and compare to Big-IQ";

        exit 2;

else

        printf "$green" "The $BIGIP_LICENSE exists on Big-IQ";

fi



if [ $OFFERING ]; then

if [ -z "${BIGIQ_OFFERING_CHECK}" ];then

        printf "$red" "Checked Big-IQ.  The license offering $LICENSE_OFFERING does not exist under the license $BIGIP_LICENSE.  Please check the entries in vmware";

        exit 2;

else

        printf "$green" "The $LICENSE_OFFERING offering exists on the BigIQ";

fi



fi





###################################################################################

###################################################################################





DCO=1; #Set to 1 to install Declerative Onboarding file

if [[ $DCO = 1 ]];

then

########################################

# Copy over Declarative onboarding file   #

########################################



FILE_NAME_DO=f5-declarative-onboarding-1.9.0-1.noarch.rpm





LEN=$(wc -c $FILE_NAME_DO | cut -f 1 -d ' ')

echo " ";

echo "LEN:$LEN";



curl -ku $BIGIP_USERNAME:$BIGIP_PASSWORD https://localhost/mgmt/shared/file-transfer/uploads/$FILE_NAME_DO -H 'Content-Type: application/octet-stream' -H "Content-Range: 0-$((LEN - 1))/$LEN" -H "Content-Length: $LEN" -H 'Connection: keep-alive' --data-binary @$FILE_NAME_DO



DATA="{\"operation\":\"INSTALL\",\"packageFilePath\":\"/var/config/rest/downloads/$FILE_NAME_DO\"}"



curl -ku $BIGIP_USERNAME:$BIGIP_PASSWORD "https://localhost/mgmt/shared/iapp/package-management-tasks" -H "Origin: https://localhost" -H 'Content-Type: application/json;charset=UTF-8' --data $DATA





###################################################################################

# This checks the Declerative onboarding, and will pause the script until the DO has completed and the status has returned "OK"

###################################################################################

DO1_COUNTER=0

while [  $DO1_COUNTER -lt 120 ]; do

  let DO1_COUNTER=DO1_COUNTER+1



DO1_STATUS_CURL=$(curl -s -k -X GET -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://localhost/mgmt/shared/declarative-onboarding );

DO1_STATUS=$(echo $DO1_STATUS_CURL);

echo "DO1_STATUS: $DO1_STATUS - $DO1_COUNTER";



sleep 3;



if [[ $DO1_STATUS =~ .*declaration.* ]]; then

let DO1_COUNTER=200

fi



done



fi





###############################################

# Execute DCO

###############################################



BIGIP_DCO_JS='{

    "schemaVersion": "1.1.0",

    "class": "Device",

    "Common": {

        "class": "Tenant",

        "hostname": "'"$BIGIP_HOSTNAME"'",

        "myLicense": {

            "class": "License",

            "licenseType": "licensePool",

            "bigIqHost": "'"$BIGIQ_IP"'",

            "bigIqUsername": "'"$BIGIQ_USERNAME"'",

            "bigIqPassword": "'"$BIGIQ_PASSWORD"'",

            "licensePool": "'"$BIGIP_LICENSE"'",

            "skuKeyword1": "'"$LICENSE_OFFERING"'",

            "unitOfMeasure": "monthly",

            "reachable": true,

            "bigIpUsername": "'"$BIGIP_USERNAME"'",

            "bigIpPassword": "'"$BIGIP_PASSWORD"'"

        },

	"myDns": {

            "class": "DNS",

            "nameServers": [

                '"$DNS"'

            ],

            "search": [

                "mcloud.entsvcs.net"

            ]

        },

        "myNtp": {

            "class": "NTP",

            "servers": [

                '"$NTP"'

	    ],

            "timezone": "UTC"

        },

        "myProvisioning": {

            "class": "Provision",

            "ltm": "nominal",

	    "avr": "nominal"

        },

        "HA": {

            "class": "VLAN",

            "tag": "'"$HA_VLAN_ID"'",

            "mtu": 1500,

            "interfaces": [

                {

                    "name": "1.1",

                    "tagged": true

                }

            ]

        },

        "HA_IP": {

            "class": "SelfIp",

            "address": "'"$HA_VLAN_IP"'/29",

            "vlan": "HA",

            "allowService": "default",

            "trafficGroup": "traffic-group-local-only"

        },

        "configsync": {

            "class": "ConfigSync",

            "configsyncIp": "/Common/HA_IP/address"

        },

        "failoverAddress": {

            "class": "FailoverUnicast",

            "address": "/Common/HA_IP/address"

        },

        "failoverGroup": {

            "class": "DeviceGroup",

            "type": "sync-failover",
			
			"members": ["'"$COUNTRY"''"$LOCALITY"'VE'"$CUSTOMER_CC"'001.'"$LOCALITY"'.mcloud.entsvcs.net", "'"$COUNTRY"''"$LOCALITY"'VE'"$CUSTOMER_CC"'002.'"$LOCALITY"'.mcloud.entsvcs.net", "'"$COUNTRY"''"$LOCALITY"'VE'"$CUSTOMER_CC"'003.'"$LOCALITY"'.mcloud.entsvcs.net"],
			
			"owner": "/Common/failoverGroup/members/0",
			
			"autoSync": true,
			
			"saveOnAutoSync": true,
			
			"networkFailover": true,
			
			"fullLoadOnSync": false,
			
			"asmSync": false
        },
		
		"trust": {
		
		     "class": "DeviceTrust",
			 
			 "localUsername": "'"$BIGIP_USERNAME"'",
			 
			 "localPassword": "'"$BIGIP_PASSWORD"'",
			 
			 "remoteHost": "/Common/failoverGroup/members/0",
			 
			 "remoteUsername": "'"$BIGIP_USERNAME"'",
			 
			 "remotePassword": "'"$BIGIP_PASSWORD"'"
			 
		}
	
	}
	
}'




echo "$BIGIP_DCO_JS" > /var/tmp/dcob.txt;



BIGIP_DCO=$(curl -s -k -X POST -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://localhost/mgmt/shared/declarative-onboarding -d "${BIGIP_DCO_JS}");

echo "$BIGIP_DCO";



###################################################################################

# This checks the Declerative onboarding, and will pause the script until the DO has completed and the status has returned "OK"

###################################################################################

DO_COUNTER=0

while [  $DO_COUNTER -lt 75 ]; do

  let DO_COUNTER=DO_COUNTER+1



DO_STATUS_CURL=$(curl -s -k -X GET -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://localhost/mgmt/shared/declarative-onboarding );

DO_STATUS=$(echo $DO_STATUS_CURL |  jq '.result.status');

echo "DO_STATUS: $DO_STATUS - $DO_COUNTER";



sleep 3;



if [ "$DO_STATUS" = \"OK\" ]; then

echo "DO STATUS is $DO_STATUS";

let DO_COUNTER=100

fi



done

###################################################################################



#****************************************************

# SETS TACACS

#****************************************************

#

#BIGIP_TACACS_JS='{

#Add json for tacacs here

#}'



#echo "BIGIP_TACACS_JS=$BIGIP_TACACS_JS";

#********************************************************************************************

#BIGIP_TACACS=$(curl -s -k -X POST -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://localhost/mgmt/tm/????TACACS???? -d "${BIGIP_TACACS_JS}");



#echo "BIGIP_TACACS=$BIGIP_TACACS";



###############################################

# Create Partition

###############################################

PARTITION_JS='{

  "defaultRouteDomain": 0,

  "id":"'"$CUSTOMER_CC"'",

  "name": "P'"$CUSTOMER_CC"'"

}'



PARTITION=$(curl -s -k -X POST -H "${BIGIP_AUTH_HEADER}" -H "Content-type: application/json" https://$BIGIP_MGMT_IP/mgmt/tm/auth/partition/ -d "${PARTITION_JS}");



###############################################

# Create Vlans

###############################################

#(retrieve_auth_token localhost $BIGIP_USERNAME $BIGIP_PASSWORD);

(create_vlan $CUSTOMER_CC $VLAN_ID_1 1.2);

(create_vlan $CUSTOMER_CC $VLAN_ID_2 1.2);

(create_vlan $CUSTOMER_CC $VLAN_ID_3 1.2);

(create_vlan $CUSTOMER_CC $VLAN_ID_4 1.2);

(create_vlan $CUSTOMER_CC $VLAN_ID_5 1.2);

(create_vlan $CUSTOMER_CC $VLAN_ID_6 1.2);



###############################################

# Create Route Domain

###############################################

(create_rd $CUSTOMER_CC $VLAN_ID_1 30);

(create_rd $CUSTOMER_CC $VLAN_ID_2 32);

(create_rd $CUSTOMER_CC $VLAN_ID_3 34);

(create_rd $CUSTOMER_CC $VLAN_ID_4 36);

(create_rd $CUSTOMER_CC $VLAN_ID_5 38);

(create_rd $CUSTOMER_CC $VLAN_ID_6 3);



###############################################

# Create Self IP

###############################################

(create_self $CUSTOMER_CC $VLAN_ID_1 $IP_NET_1 disabled);

(create_self $CUSTOMER_CC $VLAN_ID_2 $IP_NET_2 disabled);

(create_self $CUSTOMER_CC $VLAN_ID_3 $IP_NET_3 disabled);

(create_self $CUSTOMER_CC $VLAN_ID_4 $IP_NET_4 disabled);

(create_self $CUSTOMER_CC $VLAN_ID_5 $IP_NET_5 disabled);

(create_self $CUSTOMER_CC $VLAN_ID_6 $IP_NET_6 disabled);



###############################################

# Create Floating IP

###############################################

if [[ $LB_NUM = 001 ]];

then

(create_self $CUSTOMER_CC $VLAN_ID_1 $IP_NET_1_F enabled);

(create_self $CUSTOMER_CC $VLAN_ID_2 $IP_NET_2_F enabled);

(create_self $CUSTOMER_CC $VLAN_ID_3 $IP_NET_3_F enabled);

(create_self $CUSTOMER_CC $VLAN_ID_4 $IP_NET_4_F enabled);

(create_self $CUSTOMER_CC $VLAN_ID_5 $IP_NET_5_F enabled);

(create_self $CUSTOMER_CC $VLAN_ID_6 $IP_NET_6_F enabled);

fi



###############################################

# Create routes

###############################################

(create_route $CUSTOMER_CC $VLAN_ID_1 $IP_NET_ROUTE_1);

(create_route $CUSTOMER_CC $VLAN_ID_2 $IP_NET_ROUTE_2);

(create_route $CUSTOMER_CC $VLAN_ID_3 $IP_NET_ROUTE_3);

(create_route $CUSTOMER_CC $VLAN_ID_4 $IP_NET_ROUTE_4);

(create_route $CUSTOMER_CC $VLAN_ID_5 $IP_NET_ROUTE_5);

(create_route $CUSTOMER_CC $VLAN_ID_6 $IP_NET_ROUTE_6);



echo "END: $(date)";
