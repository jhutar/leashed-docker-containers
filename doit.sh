#!/bin/sh

# Pull image we are going to use
image="jhutar/spacewalk-client:rhel-7.2"
docker pull $image

# Configure and print variables
cmd=$( mktemp /tmp/command.XXXXXX )
echo 'echo Hello world' >>$cmd
logs=$( mktemp -d /tmp/logs.XXXXXX )
count=50
echo "INFO: Container logs: $logs"
echo "INFO: Command file: $cmd"
echo "INFO: Container count: $count"
echo "INFO: Image: $image"

# Start all the containers
attempt_max=60
attempt_sleep=1
for i in $( seq -w 1 $count ); do
  name="dockerb$i"
  :> $logs/docker$i.log
  tailf $cmd | docker run --interactive --hostname=$name.$(hostname) --name=$name --rm $image /bin/bash &>$logs/docker$i.log &
  echo "DEBUG: Started container $name. Wait till it executes first command."
  attempt=0
  while ! grep --quiet 'Hello world' $logs/docker$i.log; do
    if [ $attempt -ge $attempt_max ]; then
      echo "ERROR: Looks like container $name failed to start properly, here comes its log:"
      cat $logs/docker$i.log
      break
    fi
    sleep $attempt_sleep
    let attempt+=1
  done
  grep --quiet 'Hello world' $logs/docker$i.log \
    || echo "ERROR: Looks like container $name failed to start properly. See $logs/docker$i.log"
done
[ $count -eq "$( docker ps -q | wc -l )" ] \
  || echo "ERROR: Expected and actual number of containers differ"
echo "INFO: Listing containers"
docker ps

# Define function/hack to wait for commands to finish on all containers
function wait_for_finish() {
  token=$1   # should be unique because we want to be 100% we are checking exit code of correct command
  checks=''
  for i in $( seq -w 1 $count ); do
    checks+=" $i"
  done
  attempt=0
  attempt_max=360
  attempt_sleep=10
  while [ -n "$( echo "$checks" | sed 's/\s//g' )" ]; do
    if [ $attempt -ge $attempt_max ]; then
      echo "ERROR: We are out of tries when waiting command finish. These have not finished: $checks"
      break
    fi
    new_checks=''
    for i in $checks; do
      log="$logs/docker$i.log"
      line=$( tail -n 1 $log )
      if echo "$line" | grep "^$token "; then
        rc=$( echo "$line" | cut -d ' ' -f 2 )
        [ "$rc" -ne 0 ] \
          && echo "ERROR: Container docker$i should finish its job without error ($( tail -n 1 $log ))"
      else
        new_checks+=" $i"
      fi
    done
    checks="$new_checks"
    if [ -z "$checks" ]; then
      echo "INFO: All the containers finished"
      break
    fi
    sleep $attempt_sleep
    let attempt+=1
  done
}

# Do some work - run client registration into Satellite 5 on all containers
# in parallel
echo 'wget --quiet http://<satellite>/pub/RHN-ORG-TRUSTED-SSL-CERT -O /usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT; echo outwget $?' >>$cmd; wait_for_finish outwget
echo 'rhnreg_ks --username=<username> --password=<password> --serverUrl=https://<satellite>/XMLRPC --sslCACert=/usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT --norhnsd; echo outreg $?' >>$cmd; wait_for_finish outreg
