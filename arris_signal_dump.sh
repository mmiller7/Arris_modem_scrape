#!/bin/bash

# Default password is last 8 digits of serial number
username="admin"
password="P@ssw0rd"

# Then we base-64 encode it to get a token from the modem
# Note: must not have any newlines
auth_hash=`echo -n "${username}:${password}" | base64`
#echo "The auth_hash is $auth_hash"

# An initial request seems to help get the modem ready to properly respond
curl -s --insecure  https://192.168.100.1/ >> /dev/null

# Now we need to ask the modem for a token
# the --insecure because it is self-signed cert
token=$(curl -s --insecure  https://192.168.100.1/cmconnectionstatus.html?${auth_hash})
#echo "The token is $token"

# Finally, we can request the page
# TODO: I need to figure out a good way to parse this into something more useful
result=$(curl -s --insecure "https://192.168.100.1/cmconnectionstatus.html" -H "Cookie: HttpOnly: true, Secure: true; credential=${token}")

if echo "$result" | grep --quiet '<title>Login</title>'; then
	echo "Login failed."
	exit 1
fi

#echo "Raw:"
#echo -e "$result"

#echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g' | awk -F "<tableclass=['\"]simpleTable['\"]>|</table>" '{print "\nOverall:\n" $2 "\n\nDown\n" $4 "\n\nUp\n" $6 "\n" }'
overall_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/<[/]\?strong>//g;s/<![^>]*>//g;s/<[/]\?[bui]>//g' | awk -F "<tableclass=['\"]simpleTable['\"]>|</table>" '{print $2}')
downlink_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/<[/]\?strong>//g;s/<![^>]*>//g' | awk -F "<tableclass=['\"]simpleTable['\"]>|</table>" '{print $4}')
uplink_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/<[/]\?strong>//g;s/<![^>]*>//g' | awk -F "<tableclass=['\"]simpleTable['\"]>|</table>" '{print $6}')

# Break out by line
overall_rows=$(echo "$overall_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
downlink_rows=$(echo "$downlink_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
uplink_rows=$(echo "$uplink_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')

# Break out columns
echo ""
echo "Overall:"
echo "$overall_rows" | sed 's/<th[^>]*>[^<]*<\/th>//g;s/^<td[^>]*>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g' | grep -v "^$"

echo ""
echo "Downlink:"
echo "$downlink_rows" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/  \t/g'

echo ""
echo "Uplink:"
echo "$uplink_rows" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/  \t/g'

echo ""
