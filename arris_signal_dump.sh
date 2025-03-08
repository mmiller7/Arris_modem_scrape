#!/bin/bash

# Default mqtt_password is last 8 digits of serial number
modem_username="admin"
modem_password="12345678"

# Settings for MQTT mqtt_broker to publish stats
mqtt_broker="192.168.1.221"
mqtt_username="your_mqtt_username_here"
mqtt_password="your_mqtt_password_here"
mqtt_topic="homeassistant/sensor/modemsignals"

# HomeAssistant doesn't expose this to the container so we have to hack it up
# Comment these out for a "normal" host that knows where mosquitto_pub is on its own
export LD_LIBRARY_PATH='/config/bin/mosquitto_deps/lib'
mqtt_pub_exe="/config/bin/mosquitto_deps/mosquitto_pub"
# Uncomment tthis for a "normal" host that knows where mosquitto_pub is on its own
#mqtt_pub_exe="mosquitto_pub"

# Cookie file path
cookie_path="$0.cookie"

#####################################
# Prep functions to interface modem #
#####################################

# This function publishes login status helpful for debugging
function loginStatus () {
	#echo "Modem login: $1"
	# Publish MQTT to announce status
	message="{ \"login\": \"$1\" }"
	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_topic}/login" -m "$message" || echo "MQTT-Pub Error!"
}

# This function gets a dynamic session-token (cookie?) from the modem
function getToken () {
# See if we have an existing token saved
if [ -f "$0.token" ]; then
	token=$(cat "$0.token")
else
	# We base-64 encode the user/mqtt_password to get a token from the modem
	# Note: must not have any newlines
	auth_hash=`echo -n "${modem_username}:${modem_password}" | base64`
	#echo "The auth_hash is [${auth_hash}]"

	# Now we need to ask the modem for a token
	# the --insecure because it is self-signed cert
	token=$(curl --connect-timeout 5 -s --insecure "https://${modem_ip}/cmconnectionstatus.html?login_${auth_hash}" -b "$cookie_path" -c "$cookie_path" -H 'Accept: */*' -H 'Content-Type: application/x-www-form-urlencoded; charset=utf-8' -H "Authorization: Basic ${auth_hash}" -H 'X-Requested-With: XMLHttpRequest' -H 'Cookie: HttpOnly: true, Secure: true')

	if [ "$?" == 28 ]; then 
		loginStatus "failed_timeout_no_token"
		exit 11
	# Check if the totken looks valid or is a login form rejected
	elif echo "$token" | grep -q '<title>Login</title>'; then
		# At this point, if we weren't successful, we give up - probably locked out or wrong auth_hash
		loginStatus "failed_rejected_no_token"
		exit 12
	else
		loginStatus "token_received"
	fi

	#echo "The token is [${token}]"

	# Save the token to reuse for later requests
	echo -n "$token" > "$0.token"
fi
}

# This function erases the saved session-token
function eraseToken () {
if [ -f "$0.token" ]; then
	rm -f "$0.token"
fi
}

# This function fetches the HTML status page from the modem for parsing
function getResult () {
# Finally, we can request the page
result=$(curl -s --insecure "https://${modem_ip}/cmconnectionstatus.html?ct_$token" -b "$cookie_path" -c "$cookie_path" -H "Cookie: HttpOnly: true, Secure: true")
}



#############################
# Log in and fetch the data #
#############################

# Get the token (saved, or from modem)
getToken;

# Get the result from the modem
getResult;

# See if we were successful
if [ "$(echo "$result" | grep -c '<title>Status</title>')" == "0" ]; then
	loginStatus "failed_retrying"

	# If we failed (got a login prompt) try once more for new token
	eraseToken;
	getToken;
	getResult;
fi

# See if we were successful
if [ "$(echo "$result" | grep -c '<title>Status</title>')" == "0" ]; then
	# At this point, if we weren't successful, we give up
	loginStatus "failed"
	exit 21
else
	loginStatus "success"
	mkdir -p "$0.log" 
	echo "$result" > "$0.log/$(date '+%H%M').html"
fi



####################
# Parse the result #
####################

#echo "Raw:"
#echo -e "$result"

#echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g' | awk -F "<tableclass=['\"]simpleTable['\"]>|</table>" '{print "\nStartup:\n" $2 "\n\nDown\n" $4 "\n\nUp\n" $6 "\n" }'
startup_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g;s/<[/]\?[bui]>//g' | awk -F "<tableclass=['\"]simpleTable['\"]>|</table>" '{print $2}')
downstream_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g' | awk -F "<tableclass=['\"]simpleTable['\"]>|</table>" '{print $4}')
upstream_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g' | awk -F "<tableclass=['\"]simpleTable['\"]>|</table>" '{print $6}')

# Break out by line
startup_rows=$(echo "$startup_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
downstream_rows=$(echo "$downstream_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
upstream_rows=$(echo "$upstream_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')


# Break out columns

# Parse out the startup status HTML table into JSON and publish
#echo "$startup_rows"
#echo "$startup_rows" | sed 's/<th[^>]*>[^<]*<\/th>//g;s/^<td[^>]*>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g' | grep -v "^$"
# Helper function to more easily build JSON per field
function pubStartupStatusValue () {
	# Break out field information
	procedure_name="$1"
	procedure_status="$2"
	procedure_comment="$3"
	# Build the message payload
	message=""
	# If exists, insert stattus
	if [ "$procedure_status" != "" ]; then
		if [[ "$procedure_status" =~ ^[0-9]+$ ]]; then
			message="${message} \"status\": $procedure_status"
		else
			message="${message} \"status\": \"$procedure_status\""
		fi
	fi
	# If exists, insert comment
	if [ "$procedure_comment" != "" ]; then
		# If message is not empty, insert separator comma
		if [ "$message" != "" ]; then
			message="${message}, "
		fi
		message="${message} \"comment\": \"$procedure_comment\""
	fi
	message="{ ${message} }"
	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_topic}/startup_procedure/${procedure_name}" -m "$message"
}
echo "$startup_rows" | grep -v "^$" | tail -n +3 | while read -r line; do
	to_parse=$(echo "$line" | sed 's/<th[^>]*>[^<]*<\/th>//g;s/^<td[^>]*>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g')
	procedure_name=$(echo $to_parse | awk '{print $1}')
	procedure_status=$(echo $to_parse | awk '{print $2}')
	procedure_comment=$(echo $to_parse | awk '{print $3}')
	pubStartupStatusValue "$procedure_name" "$procedure_status" "$procedure_comment"
done



# Parse out the downstream HTML table into JSON and publish
#echo "$downstream_rows" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g'
counter=0
echo "$downstream_rows" | tail -n +2 | while read -r line; do
	counter=$(($counter+1))
	#echo "${mqtt_topic}/downstream/$counter"
	to_parse=$(echo "$line" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g')
	message=$(
		echo "{"
		echo "$to_parse" | awk '{ print "\"ChannelID\": "$1","
															print "\"LockStatus\": \""$2"\","
															print "\"Modulation\": \""$3"\","
															print "\"Frequency\": "$4","
															print "\"Power\": "$5","
															print "\"SNR_MER\" :"$6","
															print "\"Corrected\" :"$7","
															print "\"Uncorrectable\" :"$8 }'
		echo "}"
	)
	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_topic}/downstream/${counter}" -m "$message"
done

# Parse out the upstream HTML table into JSON and publish
#echo "$upstream_rows" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g'
counter=0
echo "$upstream_rows" | tail -n +2 | while read -r line; do
	counter=$(($counter+1))
	#echo "${mqtt_topic}/upstream/$counter"
	to_parse=$(echo "$line" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g')
	message=$(
		echo "{"
		echo "$to_parse" | awk '{ print "\"Channel\": "$1","
															print "\"ChannelID\": "$2","
															print "\"LockStatus\": \""$3"\","
															print "\"USChannelType\": \""$4"\","
															print "\"Frequency\": "$5","
															print "\"Width\": "$6","
															print "\"Power\": "$7 }'
		echo "}"
	)
	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_topic}/upstream/${counter}" -m "$message"
done

#echo ""

