#!/bin/bash

# Substitute configuration
for VARIABLE in `env | cut -f1 -d=`; do
  sed -i "s={{ $VARIABLE }}=${!VARIABLE}=g" /etc/postfix/*.cf
done

# Override Postfix configuration
if [ -f /config/main.cf ]; then
  while read line; do
    postconf -e "$line"
  done < /config/main.cf
  echo "Loaded 'config/main.cf'"
else
  echo "No extra postfix settings loaded because optional '/config/main.cf' not provided."
fi

# Include table-map files
if ls -A /config/*.map 1> /dev/null 2>&1; then
  cp /config/*.map /etc/postfix/
  postmap /etc/postfix/*.map
  rm /etc/postfix/*.map
  chown root:root /etc/postfix/*.db
  chmod 0600 /etc/postfix/*.db
  echo "Loaded 'map files'"
else
  echo "No extra map files loaded because optional '/config/*.map' not provided."
fi

# Actually run Postfix
rm -f /var/run/rsyslogd.pid
/usr/lib/postfix/master &
rsyslogd -n
