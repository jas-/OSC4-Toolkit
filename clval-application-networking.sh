#!/bin/bash

# Ensure path is robust
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/cluster/bin


###############################################
# Bootstrap the environment
###############################################

if [ ! -f $(dirname $0)/bootstrap.sh ]; then
  echo "Unable to find bootstrap.sh"
  exit 1
fi

# Load our source
source $(dirname)/bootstrap.sh


###############################################
# Define an array holder for errors & get Networking specific resources from our cached report
###############################################

# Declare an error holding array for cluster specific errors
declare -a errors 
 
# Get an array of objects
declare -a objects
objects=( $(cut -d, -f3,5,6,9,10,11 ${report} | sort -u | tr ' ' '^' | egrep 'HostnameList|Port_|ONS' | sort -u) )


###############################################
# Begin ${objects[@]} iterator
###############################################

# Iterate ${objects[@]}
for object in ${objects[@]}; do
  

  ###############################################
  # We need to break ${object} up to perform examination
  #  - clname: This is the cluster name
  #  - zname: This is the zone name associated/based on ${clname}
  #  - clnets: An array of 'net' objects defined for the cluster
  #  - clrsips: An array of IP addresses defined as resource properties
  #  - clrsstatus: The current status of the resource(s)
  #  - clrshosts: An array of hostnames defined as resource properties
  #  - clrsips: An array of IP addresses defined as resource properties
  #  - clrsports: An array of ports that should be in a LISTEN state defined as resource properties
  #  - clrsnodes: An array of ONS_NODES that can be evaluated
  ###############################################

  # Chop ${object}
  clname="$(echo "${object}" | cut -d, -f1)"
  zname="$(zlogin ${clname} 'uname -n')"
  clrgname="$(echo "${object}" | cut -d, -f3)"
  clrsname="$(echo "${object}" | cut -d, -f4)"
  clrsstatus=$(echo "${object}" | cut -d, -f5 | sed "s|:\([Online|Offline]\)|,\1|g" | tr ':' '\n' | grep -i "^${zname}," | grep -c "Online")
  clrshosts=( $(echo "${object}" | cut -d, -f6 | tr '^' '\n' | grep ^HostnameList | cut -d: -f2) )
  clrsips=( $(echo "${object}" | cut -d, -f6 | tr '^' '\n' | grep ^IPList | cut -d: -f2) )
  clrsports=( $(echo "${object}" | cut -d, -f6 | tr '^' '\n' | grep ^Port_ | cut -d: -f2 | tr '/' ':') )
  clrsnodes=( $(echo "${object}" | cut -d, -f6 | tr '^' '\n' | grep ^ONS | cut -d: -f2,3) )

  
  ###############################################
  # Begin the ${clrshosts[@]} iterator
  ###############################################

  # Iterate ${clrshosts[@]}
  for clrshost in ${clrshosts[@]}; do
  

    # Define the severity level as LOW by default
    severity="LOW"

    ###############################################
    # Perform connectivity via ICMP from the zone (${clname}) to the resource hostname (${clrshost})
    ###############################################

    if [ "${1}" == "debug" ]; then
      echo "Testing connectivity; ICMP request to logical hostname defined as resource"
      echo "  ${clname},${clrgname},${clrsname},${clrshost}"
    fi

    # Ping the damn thing already
    ping=$(zlogin ${clname} "ping ${clrshost} 1 2>&1" | egrep -c 'no answer|unknown host')
    if [ ${ping:=1} -gt 0 ]; then

      # Set the test type name
      test_type="ICMPTest"

      # Since we have an issue determine severity
      [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
        severity="CRITICAL"

      # Add to the errors array
      errors+=("${severity},Application,${clname},${test_type},${clrgname},${clrsname},${clrshost}")
    fi
  done


  ###############################################
  # If dealing with an active node dig deeper into connectivity
  ###############################################
  
  if [ ${clrsstatus:=0} -gt 0 ]; then

    ###############################################
    # Begin the ${clrsports[@]} iterator
    ###############################################

    # Iterate ${clrsports[@]}
    for clrsport in ${clrsports[@]}; do
  
      # Split ${clrsport} into the port and protocol
      proto="$(echo "${clrsport}" | cut -d: -f2)"
      port="$(echo "${clrsport}" | cut -d: -f1)"
    

      # Define the severity level as LOW by default
      severity="LOW"

      ###############################################
      # Examine LISTENing sockets
      ###############################################

      if [ "${1}" == "debug" ]; then
        echo "Testing listening port; Examines cluster zone for configured listening ports defined as a resource"
        echo "  ${clname},${clrgname},${clrsname},${proto}/${port}"
      fi

      # Get an boolean meeting the criteria; LISTENing socket per cluster zone based on ${port} & ${proto}
      bound=$(zlogin ${clname} "netstat -anP ${proto}" | grep LISTEN |
        awk '{print $1}' | sed "s|.*\.\(.*\)$|\1|g" | grep -c "${port}")

      # Is ${port} / ${proto} in a LISTEN state?
      if [ ${bound:=0} -eq 0 ]; then

        # Set the test type name
        test_type="ListeningPort"

        # Since we have an issue determine severity
        [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
          severity="CRITICAL"

        # Add to the errors array
        errors+=("${severity},Application,${clname},${test_type},${clrgname},${clrsname},${proto}/${port}")
      fi
    done


    ###############################################
    # Begin the ${clrips[@]} iterator
    ###############################################

    # Iterate ${clrsips[@]}
    for clrsip in ${clrsips[@]}; do

      # Define the severity level as LOW by default
      severity="LOW"

      ###############################################
      # Examine configured IP's
      ###############################################

      if [ "${1}" == "debug" ]; then
        echo "Testing IP configuration; Examines cluster zone for the configured IP address"
        echo "  ${clname},${clrgname},${clrsname},${clrsip}"
      fi

      # Get an array of ip's assocated with ${clname}
      zips=( $(zlogin ${clname} "ipadm" | awk 'NR>1 && $NF !~ /127.0.0.1|::|--/{print $NF}' |
        sed "s|\(.*\)\/.*$|\1|g" | sort -u) )

      # Is ${clrsip} exist in ${zips[@]} array?
      if [ $(in_array "${clrsip//./_}" "${zips[@]//./_}") -ne 0 ]; then

        # Set the test type name
        test_type="MissingIP"

        # Since we have an issue determine severity
        [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
          severity="CRITICAL"

        # Add to the errors array
        errors+=("${severity},Application,${clname},${test_type},${clrgname},${clrsname},${clrsip}")
      fi
    done
  fi

  ###############################################
  # Begin the ${clrsnodes[@]} iterator
  ###############################################

  # Iterate ${clrsnodes[@]}
  for clrsnode in ${clrsnodes[@]}; do
  
    # Split ${clrsnode} into the port and protocol
    port="$(echo "${clrsnode}" | cut -d: -f2)"
    host="$(echo "${clrsnode}" | cut -d: -f1)"
    proto="tcp" # Since nothing is defined we are assuming TCP


    # Define the severity level as LOW by default
    severity="LOW"


    ###############################################
    # Test socket connectivity from ${clname} to ${host} on ${port}
    ###############################################

    if [ "${1}" == "debug" ]; then
      echo "Testing connectivity; Examines end to end SYN/FIN connections for ONS_NODE resources"
      echo "  ${clname},${clrgname},${clrsname},${clrsnode},${proto}/${host}/${port}"
    fi

    # Get the ${clname} path in order to create a temporary test with
    zpath="$(zoneadm list -v | grep "${clname}" | awk '{printf("%s/root/var/tmp", $4)}')"

    # Create a temporary gawk script which will perform the end of end connectivity test
    cat <<EOF > ${zpath}/${clname}.sh
#!/bin/bash
gawk 'BEGIN {
  svc = "/inet/${proto}/0/${host}/${port}"
  PROCINFO[svc, "READ_TIMEOUT"] = 10
  PROCINFO[svc, "GAWK_READ_TIMEOUT"] = 10
  PROCINFO[svc, "GAWK_SOCK_RETRIES"] = 3
  PROCINFO[svc, "GAWK_MSEC_SLEEP"] = 5
  if ((svc |& getline) > 0) {
    print \$0
  } else if (ERRNO != "") {
    print ERRNO
  }
  close(svc)
}'
EOF

    # Get an boolean as results from end to end socket comm
    conn=$(zlogin ${clname} "/bin/bash /var/tmp/${clname}.sh" | grep -c "^0$")

    # Clean up after yourself
    [ -f ${zpath}/${clname}.sh ] && rm ${zpath}/${clname}.sh

    # Was it successful?
    if [ ${conn:=0} -eq 0 ]; then

      # Set the test type name
      test_type="Connectivity"

      # Since we have an issue determine severity
      [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
        severity="CRITICAL"

      # Add to the errors array
      errors+=("${severity},Application,${clname},${test_type},${clrgname},${clrsname},${clrsnode}")
    fi
  done
done

[ "${1}" == "debug" ] && echo


###############################################
# If either ${errors[@]} and > 0 provide the info
###############################################

# Print issues and bail
if [ ${#errors[@]} -gt 0 ]; then
  cat <<EOF
${header}
$(echo "${errors[@]}" | tr ' ' '\n')
EOF

  exit ${#errors[@]}
fi


# All systems up!
exit 0
