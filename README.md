The SB8200 script been tested on my Arris SB8200 firmware AB01.02.053.06_102121_193.0A.NSH

NOTE: The methods of authentication seem to vary by model, firmware number, and possibly other factors.  Unfortuniately I haven't found a good way to figure out how to debug this...I've got lucky and been able to use a mix of the browser developer console and google-searches finding other people who already solved some of the problems in other languages by searching some of the javascript URLs in the modem form.



Been wanting to scrape my Arris SB8200 modem signals for monitoring over time, new firmware requires a login to access the signals.  Finally that was annoying enough I had to figure out how to automate it a bit - but first had to figure out how the login auth works.

New firmware, to see your signals and status requires login...here are the defaults:
Username: admin
Password: (the last 8 digits of your modem's serial number)

This script should allow you to scrape the modem status data and write it out to a MQTT broker where you can then use something like HomeAssistant to take actions based on the data (graph it, issue automations to cycle a smartplug, etc)

If you want to use this on an older firmware that does not have authenticatiton, you can PROBABLY just comment out the part where it gets a token and just have it fetch $result directly, but since my modem now needs a password I obviously can't test that anymore.


Files:
arris_modem_signal_dump_sb8200.sh - the script which logs into the modem and scrapes/parses the data publishing JSON to MQTT
arris_modem_signgal.yaml - initial YAML to run the script periodically and import the startup status

NOTE: You probably need to adjust the YAML to match the number up/down stream channels your ISP has.  Mine was 33 down, 4 up.
