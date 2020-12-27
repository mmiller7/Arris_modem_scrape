This has been tested on my Arris SB8200 firmware AB01.01.009.51_080720_183.0A.NSH

Been wanting to scrape my Arris SB8200 modem signals for monitoring over time, new firmware requires a login to access the signals.  Finally that was annoying enough I had to figure out how to automate it a bit - but first had to figure out how the login auth works.

New firmware, to see your signals and status requires login...here are the defaults:
Username: admin
Password: (the last 8 digits of your modem's serial number)

This script should allow you to scrape the modem status data and write it out to a MQTT broker where you can then use something like HomeAssistant to take actions based on the data (graph it, issue automations to cycle a smartplug, etc)

If you want to use this on an older firmware that does not have authenticatiton, you can PROBABLY just comment out the part where it gets a token and just have it fetch $result directly, but since my modem now needs a password I obviously can't test that anymore.


Files:
arris_modem_signal_dump.sh - the script which logs into tthe modem and scrapes/parses the data publishing JSON to MQTT
arris_modem_signgal.yaml - initial YAML to run the script periodically and import the startup status
sensor_gen.sh - allows you to quickly bulk-generate the YAML for sensors to import results for lots of channels (my modem has 33 downstream and 4 upstream).
