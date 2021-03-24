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
objects=( $(cut -d, -f3,5,6,9,11 ${report} | sort -u | tr ' ' '^' | sed 's/\^$//g' | grep IPList | sort -u) )


###############################################
# Obtain a list of IPMP & networking
###############################################

# Get an array of IPMP & physical interfaces
ifs=( $(ipmpstat -iPo INTERFACE,ACTIVE,GROUP,LINK,STATE) )
pifs=( $(dladm show-link -p -o LINK,CLASS,STATE,OVER | tr ' ' ',') )


###############################################
# Begin ${objects[@]} iterator
###############################################

# Iterate ${objects[@]}
for object in ${objects[@]}; do
  

  ###############################################
  # We need to break ${object} up to perform examination
  #  - clname: This is the cluster name
  #  - clnets: An array of 'net' objects defined for the cluster
  #  - clrshosts: An array of hostnames defined as resource properties
  ###############################################

  # Chop ${object}
  clname="$(echo "${object}" | cut -d, -f1)"
  clnets=( $(echo "${object}" | cut -d, -f2 | tr '^' '\n' | grep ^net | cut -d: -f2) )
  clrgname="$(echo "${object}" | cut -d, -f3)"
  clrsname="$(echo "${object}" | cut -d, -f4)"
  clifs=( $(echo "${object}" | cut -d, -f5 | tr '^' '\n' | grep ^NetIfList | cut -d: -f2,3 | tr ':' '\n' | sed "s|\@.*$||g" | sort -u) )
  clrshosts=( $(echo "${object}" | cut -d, -f5 | tr '^' '\n' | grep ^HostnameList | cut -d: -f2) )


  ###############################################
  # Begine the ${clrshosts[@]} iterator
  ###############################################

  # Iterate ${clrshosts[@]}
  for clrshost in ${clrshosts[@]}; do
  
    # Define the severity level as LOW by default
    severity="LOW"


    ###############################################
    # Ensures the resource defined hostname exists in the cluster configuration as a net object
    ###############################################

    if [ "${1}" == "debug" ]; then
      echo "Testing logical hostname; examines the available cluster zone configuration anet for matching resource hostname"
      echo "  ${clname},${clrgname},${clrsname},${clrshost}"
    fi

    # Examine ${clnets} to ensure ${clrshost} is in the zone configuration
    if [ $(echo "${clnets[@]}" | tr ' ' '\n' | grep -c ${clrshost}) -eq 0 ]; then

      # Set the test type name
      test_type="ZoneConfiguration"

      # Since we have an issue determine severity
      [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
        severity="CRITICAL"

      # Add to the errors array
      errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clrshost}")
    fi


    ###############################################
    # Iterator for ${clifs[@]} array
    ###############################################

    # Iterate over ${clifs[@]}
    for clif in ${clifs[@]}; do

      ###############################################
      # Ensure the zones (${clname}) resources for 'NetIfList' is found in the LDOM's network configuration (${ifs[@]})
      ###############################################

      if [ "${1}" == "debug" ]; then
        echo "Testing defined interfaces: Tests LDOM interfaces for matching values defined as resources (NetIFList)"
        echo "  ${clname},${clrgname},${clrsname},${clif}"
      fi

      # Make sure the resource defined IPMP group ${clif} is found in the LDOM configured IPMP groups ${ifs[@]}
      if [ $(echo "${ifs[@]}" "${pifs[@]}" | tr ' ' '\n' | grep -c ":${clif}:") -eq 0 ]; then

        # Set the test type name
        test_type="InterfaceConfiguration"

        # Since we have an issue determine severity
        [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
          severity="CRITICAL"

        # Add to the errors array
        errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clif}")
      fi


      ###############################################
      # Get IPMP information & status
      ###############################################

      # Get the IPMP details
      ipmp_blob=( $(echo "${ifs[@]}" | tr ' ' '\n' | egrep ":${clif}:|^${clif}:") )
      ipmp_status=$(echo "${ipmp_blob[@]}" | tr ' ' '\n' | grep -c "^.*:yes:.*:up:ok$")
  
      ###############################################
      # Ensure the zones (${clname}) IPMP status shows as valid
      ###############################################

      if [ "${1}" == "debug" ]; then
        echo "Testing defined interfaces: Tests IPMP group status (supports active/passive and LACP modes)"
        echo "  ${clname},${clrgname},${clrsname},${clif}"
      fi

      # Ensure the IPMP group status is ok
      if [ ${ipmp_status:=0} -eq 0 ]; then

        # Set the test type name
        test_type="IPMPStatus"

        # Since we have an issue determine severity
        [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
          severity="CRITICAL"

        # Add to the errors array
        errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clif}")
      fi


      ###############################################
      # Get 802.1q configuration associated with the IPMP interface
      ###############################################

      # Get the bonded interface name from ${ipmp_blob}
      phys_names=( $(echo "${ipmp_blob[@]}" | tr ' ' '\n' | cut -d: -f1) )
      
      ###############################################
      # Iterator for the 802.1q array of configurations
      ###############################################

      for phys_name in ${phys_names[@]}; do

        if [ "${1}" == "debug" ]; then
          echo "Testing defined interfaces: Tests underlying configuration of IPMP group"
          echo "  ${clname},${clrgname},${clrsname},${phys_name}"
        fi

        # Get the matching 802.1q data (${phys_name}) from the found ipmp blob (${ipmp_blob)
        phys_blob="$(echo "${pifs[@]}" | tr ' ' '\n' | grep "${phys_name}:")"
        phys_status=$(echo "${phys_blob}" | grep -c ":up:")

        ###############################################
        # Test the 802.1q status
        ###############################################

        # Ensure the 802.1q connectivity is ok
        if [ ${phys_status:=1} -eq 0 ]; then

          # Set the test type name
          test_type="802.1QStatus"

          # Since we have an issue determine severity
          [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
            severity="CRITICAL"

          # Add to the errors array
          errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${phys_name}")
        fi


        ###############################################
        # Get the underlying links associated with the 802.1q configuration
        ###############################################

        if [ "${1}" == "debug" ]; then
          echo "Testing defined interfaces: Tests underlying phyiscal interfaces of IPMP group"
          echo "  ${clname},${clrgname},${clrsname},${links}"
        fi

        # Create a filter of physical links associated with ${phys_name}
        links="$(echo "${phys_blob}" | awk '{print $NF}' | tr ',' '|')"
        links_status=$(echo "${pifs[@]}" | tr ' ' '\n' | egrep ${links} | grep -c ":up:")

        ###############################################
        # Test the 802.1q status
        ###############################################

        # Ensure the paths are up
        if [ ${links_status:=1} -eq 0 ]; then

          # Set the test type name
          test_type="PhsyicalLinkStatus"

          # Since we have an issue determine severity
          [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
            severity="CRITICAL"

          # Add to the errors array
          errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${links}")
        fi
      done
    done


    ###############################################
    # Ensure a forward DNS lookup succeeds for zone (${clname}) to the resource hostname (${clrshost})
    ###############################################

    if [ "${1}" == "debug" ]; then
      echo "Testing connectivity; forward/reverse DNS lookup for logical hostname resources"
      echo "  ${clname},${clrgname},${clrsname},${clrshost}"
    fi

    # Examine availability of DNS for ${clrshost} in ${clname} (we should only have to care about forwards)
    forward="$(zlogin ${clname} "nslookup ${clrshost} 2>/dev/null" | awk '$1 ~ /^Name:/{getline;print $2}')"
    if [ "${forward}" == "" ]; then

      # Set the test type name
      test_type="DNSForwardLookup"

      # Since we have an issue determine severity
      [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
        severity="CRITICAL"

      # Add to the errors array
      errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clrshost}")
    fi


    ###############################################
    # Examine the zone (${clname}) to the resource hostname (${clrshost}) is defined locally (nsswitch hosts option)
    ###############################################

    if [ "${1}" == "debug" ]; then
      echo "Testing connectivity; local hosts lookup for logical hostname resources"
      echo "  ${clname},${clrgname},${clrsname},${clrshost}"
    fi

    # Examine availability of hosts for ${clrshost} in ${clname}
    hosts=( $(zlogin ${clname} "getent hosts ${clrshost}" | sort -u) )
    if [ ${#hosts[@]} -eq 0 ]; then

      # Set the test type name
      test_type="LocalHostsLookup"

      # Since we have an issue determine severity
      [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
        severity="CRITICAL"

      # Add to the errors array
      errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clrshost}")
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
