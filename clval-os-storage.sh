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
objects=( $(cut -d, -f3,5,6,9,10,11 ${report} | sort -u | tr ' ' '^' | egrep 'Zpool|TargetFileSystem|MountPointDir' | sort -u) )


###############################################
# Get some properties that will be used throughout
###############################################

# Get a blob of zpools
zpool_blob="$(zpool status)"


###############################################
# Begin ${objects[@]} iterator
###############################################

# Iterate ${objects[@]}
for object in ${objects[@]}; do
  

  ###############################################
  # We need to break ${object} up to perform examination
  #  - clname: This is the cluster name
  #  - zname: This is the zone name associated/based on ${clname}
  #  - cldatasets: An array of 'dataset' objects defined for the cluster
  #  - clrgname: The cluster resource group
  #  - clrsname: The cluster resource name
  #  - clrsstatus: The current status of the resource(s)
  #  - clrsmounts: An array of mounts (both zpools & NFS)
  ###############################################

  # Chop ${object}
  clname="$(echo "${object}" | cut -d, -f1)"
  zname="$(zlogin ${clname} 'uname -n')"
  cldatasets=( $(echo "${object}" | cut -d, -f2 | tr '^' '\n' | grep ^dataset | cut -d: -f2) )
  clrgname="$(echo "${object}" | cut -d, -f3)"
  clrsname="$(echo "${object}" | cut -d, -f4)"
  clrsstatus=$(echo "${object}" | cut -d, -f5 | sed "s|:\([Online|Offline]\)|,\1|g" | tr ':' '\n' | grep -i "^${zname}," | grep -c "Online")
  clrsmounts=( $(echo "${object}" | cut -d, -f6 | tr '^' '\n' | egrep '^Zpool|^TargetFileSystem|^MountPointDir' | cut -d: -f2,3 | tr '\n' '^') )


  ###############################################
  # Begin the ${clrsmounts[@]} iterator
  ###############################################

  # Iterate ${clrsmounts[@]}
  for clrsmount in ${clrsmounts[@]}; do
  
    # Clean up ${clrslocalmnt}
    clrsmount="$(echo "${clrsmount}" | sed 's/\^/:/g' | sed 's/\:$//g')"


    ###############################################
    # Handle the NFS mount formatting
    ###############################################

    # If ${clrsmount} has more than 1 ":" we need to break it up
    if [ $(echo "${clrsmount}" | grep -c ":") -ne 0 ]; then
    
      # Get the local mount path from ${clrsmount}
      clrslocalmnt="$(echo "${clrsmount}" | cut -d: -f3)"
      clrsmount="$(echo "${clrsmount}" | cut -d: -f1,2)"
    fi


    # Define the severity level as LOW by default
    severity="LOW"

    ###############################################
    # Use the resource group naming convention to determine the test type
    ###############################################

    # Are we dealing with a zpool dataset or an NFS scalmnt resource?
    type=$(echo "${clrgname}" | grep -c scalmnt)

    
    ###############################################
    # Since ${type} is 0 then we are dealing with a zpool dataset
    ###############################################

      # Zpool dataset test
    if [ ${type:=0} -eq 0 ]; then

      ###############################################
      # Ensure the resource dataset (zpool) exists in the zone configuration
      ###############################################

      if [ "${1}" == "debug" ]; then
        echo "Testing Zpool dataset defined as resource; must exist in cluster zone configuration as a dataset"
        echo "  ${clname},${clrgname},${clrsname},${clrsmount}"
      fi

      # Examine zone configuration for datasets (${cldatasets[@]}) to ensure the resource value exists (${clrsmount})
      if [ $(echo "${cldatasets[@]}" | tr ' ' '\n' | grep -c ${clrsmount}) -eq 0 ]; then

        # Set the test type name
        test_type="ZpoolClusterDatasetConfiguration"

        # Since we have an issue determine severity
        [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
          severity="CRITICAL"

        # Add to the errors array
        errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clrsmount}")
      fi


      ###############################################
      # If dealing with an active node dig deeper into the configuration and status of the zpool
      ###############################################
  
      if [ ${clrsstatus:=0} -gt 0 ]; then

        ###############################################
        # Ensure the actual disks exists vs. just being defined
        ###############################################

        if [ "${1}" == "debug" ]; then
          echo "Testing Zpool status; must be available"
          echo "  ${clname},${clrgname},${clrsname},${clrsmount}"
        fi

        # Examine zpool for the status of ${clrsmount}
        if [ $(echo "${zpool_blob}" | grep -v pool | grep -c "${clrsmount} ") -eq 0 ]; then

          # Set the test type name
          test_type="ZpoolConfiguration"

          # Since we have an issue determine severity
          [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
            severity="CRITICAL"

          # Add to the errors array
          errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clrsmount}")


          ###############################################
          # Ensure the actual disks exists and is online if the resource is active
          ###############################################

          if [ "${1}" == "debug" ]; then
            echo "Testing Zpool; the LUN must be available and online"
            echo "  ${clname},${clrgname},${clrsname},${clrsmount}"
          fi

          # Examine zpool for the status of ${clrsmount}
          if [[ $(echo "${zpool_blob}" | grep -v pool | grep -c "${clrsmount} " | grep -c "ONLINE") -eq 0 ]] && [[ ${clrsstatus} -eq 0 ]]; then

            # Set the test type name
            test_type="ZpoolStatus"

            # Since we have an issue determine severity
            [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
              severity="CRITICAL"

            # Add to the errors array
            errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clrsmount}")
          fi
        fi
      fi
    else

      ###############################################
      # Test for a static value in vfstab 
      ###############################################

      if [ "${1}" == "debug" ]; then
        echo "Testing NFS vfstab configuration; if defined must be disabled"
        echo "  ${clname},${clrgname},${clrsname},${clrsmount}:${clrslocalmnt}"
      fi

      # Obtain an integer value of the static configuration in vfstab for ${clrsmount}
      static_config=$(zlogin ${clname} "grep \"^${clrsmount} .* ${clrslocalmnt} \" /etc/vfstab" | grep -c "yes")

      # If ${static_config} > 0 then we have a potential issue on resource moves
      if [ ${static_config} -gt 0 ]; then

        # Set the test type name
        test_type="NFSDefinedInVFSTAB"

        # Since we have an issue determine severity
        [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
          severity="CRITICAL"

        # Add to the errors array
        errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clrsmount}:${clrslocalmnt}")
      fi


      ###############################################
      # Test for the actual mount point
      ###############################################

      if [ "${1}" == "debug" ]; then
        echo "Testing NFS local mount point; the folder must exist"
        echo "   ${clname},${clrgname},${clrsname},${clrsmount}:${clrslocalmnt}"
      fi

      # Obtain an integer value of the static configuration in vfstab for ${clrsmount}
      local_mnt=$(zlogin ${clname} "[ -d ${clrslocalmnt} ] && echo 1 || echo 0")

      # If ${static_config} > 0 then we have a potential issue on resource moves
      if [ ${local_mnt} -eq 0 ]; then

        # Set the test type name
        test_type="MissingLocalMountPoint"

        # Since we have an issue determine severity
        [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
          severity="CRITICAL"

        # Add to the errors array
        errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clrsmount}:${clrslocalmnt}")
      fi


      ###############################################
      # Since NFS requires some networking test the zone for DNS, local server resolution and ICMP
      ###############################################

      if [ "${1}" == "debug" ]; then
        echo "Testing NFS server connectivity; forward/reverse DNS lookup"
        echo "  ${clname},${clrgname},${clrsname},${clrshost}"
      fi

      # Get the NFS defined from ${clrsmount}
      clrshost="$(echo "${clrsmount}" | cut -d: -f1)"

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
        echo "Testing NFS server connectivity; examines local hosts for entry"
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


      ###############################################
      # Perform connectivity via ICMP from the zone (${clname}) to the resource hostname (${clrshost})
      ###############################################

      if [ "${1}" == "debug" ]; then
        echo "Testing NFS server connectivity; performs an ICMP test"
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
        errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clrshost}")
      fi


      ###############################################
      # Get all available NFS mounts from the zone
      ###############################################

      # Get all available mounts from NFS server (${clrshost}) from the Zone ${clname}
      remote_mounts=( $(zlogin ${clname} "showmount -e ${clrshost} 2>/dev/null" |
        awk 'NR>1{printf("%s:%s\n", $1, $2)}' | sed "s|\@||g") )


      ###############################################
      # Examine provided NFS server for a valid exported FS
      ###############################################

      if [ "${1}" == "debug" ]; then
        echo "Testing NFS server exports; tests for a valid exported file system matching the defined resource"
        echo "  ${clname},${clrgname},${clrsname},${clrshost}"
      fi

      # Examine ${clrsmount} to see if it exists in available mounts from NFS server
      if [ $(in_array "${clrsmount//*:/}" "${remote_mounts[@]//:*/}") -ne 0 ]; then

        # Set the test type name
        test_type="AvailableNFSExportMissing"

        # Since we have an issue determine severity
        [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
          severity="CRITICAL"

        # Add to the errors array
        errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clrsmount}")
      fi


      ###############################################
      # Get array's of exported NFS ACL's and the zones IP list
      ###############################################
      continue
      # Create an array of ACL's applied to the NFS exported filesystem
      exported_mount_acls=( $(echo "${remote_mounts[@]}" | tr ' ' '\n' |
        grep "^${clrsmount/*:/}:" | cut -d: -f2 | tr ',' ' ' | sort -u) )

      # Get the server IP so we can use it to limit the available IP's for the connection
      nfs_ip="$(getent hosts "$(echo "${clrsmount/:*/}")" | cut -d. -f1)"

      # Create an array of IP's configured in ${clname}
      conf_ips=( $(zlogin ${clname} 'ipadm' | 
        awk '$NF !~ /ADDR|--|::|127.0.0.1/{print $NF}' |
        grep "^${nfs_ip}" | sort -u) )


      ###############################################
      # Examine the configured zones ip's for ranges within the allowed ACL array
      ###############################################

      if [ "${1}" == "debug" ]; then
        echo "Testing NFS server exports; tests ACL's and zone's IP information for access"
        echo "  ${clname},${clrgname},${clrsname},${clrshost},${clrsmount}:${exported_mount_acls[@]}"
      fi


      # Reset the val() array to 0
      val=()

      # Iterator for ${conf_ips[@]}
      for conf_ip in ${conf_ips[@]}; do

        # Get the IP from ${conf_ip}
        ip="$(echo "${conf_ip}" | cut -d"/" -f1)"
        mask="$(calc_ipv4_cidr_subnet $(echo "${conf_ip}" | cut -d"/" -f2))"

        # Use only the first & second octet of ${ip}
        f_octet=$(echo "${ip}" | cut -d. -f1)
        s_octet=$(echo "${ip}" | cut -d. -f2)

        # Whittle down the ${exported_mount_acls[@]} array based on ${ip}
        filtered_acls=( $(echo "${exported_mount_acls[@]}" | tr ' ' '\n' |
          grep "^${f_octet}\." | grep "^${f_octet}\.${s_octet}\." | sort -u) )

        # Iterate ${filtered_acls[@]}
        for acl in ${filtered_acls[@]}; do

          # If we already have a value > 0 in ${val[@]} skip
          [ ${#val[@]} -gt 0 ] && continue

          # Get the CIDR from ${acl}
          acl_cidr=$(echo "${acl}" | cut -d"/" -f2)
          acl="$(echo "${acl}" | cut -d"/" -f1)"

          # Skip if ${acl} is not an IPv4 address
          [ $(is_ipv4 "${acl}") -ne 0 ] && continue


          # Convert ${acl} to a subnet notation
          acl_subnet="$(calc_ipv4_cidr_subnet "${acl_cidr}")"

echo "TEST: ${clrsmount}: ${acl}/${acl_subnet} ${ip} -> $(calc_ipv4_host_in_range "${acl}" "${acl_subnet}" "${ip}")"

          # Test ${ip} & ${subnet} against ${acl_host_addr} and skip if we can use it for a connection
          [ "$(calc_ipv4_host_in_range "${acl}" "${acl_subnet}" "${ip}")" == "true" ] &&
            val+=( "${clrsmount}:${ip}:${acl}/${acl_subnet}" )
        done
      done


      # Set the test type name
      test_type="NFSExportACL"

      # Since we have an issue determine severity
      [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
        severity="CRITICAL"


      # Add to the errors array
      [ ${#val[@]} -eq 0 ] &&
        errors+=("${severity},OS,${clname},${test_type},${clrgname},${clrsname},${clrsmount}:${ip}")
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
