#!/bin/bash

# Default password is last 8 digits of serial number
username="admin"
password="12345678"

# Then we base-64 encode it to get a token from the modem
# Note: must not have any newlines
auth_hash=`echo -n "${username}:${password}" | base64`

echo "The auth_hash is $auth_hash"

# Now we need to ask the modem for a token
# the --insecure because it is self-signed cert
token=$(curl -s --insecure  https://192.168.100.1/cmconnectionstatus.html?${auth_hash})

echo "The token is $token"

# Finally, we can request the page
# TODO: I need to figure out a good way to parse this into something more useful
curl --insecure "https://192.168.100.1/cmconnectionstatus.html" -H "Cookie: HttpOnly: true, Secure: true; credential=

