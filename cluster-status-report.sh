#!/bin/bash

# Ensure path is robust
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/cluster/bin


###############################################
# Zone configuration properties to acquire
###############################################

# Define an array of important zone properties
declare -a zone_properties
zone_properties+=("zonepath")
zone_properties+=("autoboot")
zone_properties+=("limitpriv")
zone_properties+=("ip-type")
zone_properties+=("resource_security")
zone_properties+=("net")
zone_properties+=("dataset")

# Create a filter based on the zone properties we care about
zone_prop_filter="$(echo "${zone_properties[@]}" | tr ' ' '\n' | awk '{printf("^%s:$\n", $1)}' | tr '\n' '|')"
zone_prop_filter="$(echo "${zone_prop_filter}" | sed 's/|$//g')"


###############################################
# Resource Group properties to acquire
###############################################

# Define an array of important resource group properties
declare -a rg_properties
rg_properties+=("Auto_start_on_new_cluster")
rg_properties+=("RG_affinities")
rg_properties+=("RG_dependencies")
rg_properties+=("RG_project_name")
rg_properties+=("Desired_primaries")
rg_properties+=("RG_state")
rg_properties+=("Priority")

# Create a filter based on the resource group properties we care about
rg_prop_filter="$(echo "${rg_properties[@]}" | tr ' ' '|')"


###############################################
# Resource properties to acquire
###############################################

# Define an array of important resource properties
declare -a resources
resources+=("NetIfList")
resources+=("Resource_dependencies.*")
resources+=("HostnameList")
resources+=("IPList")
resources+=("Port_list")
resources+=("SID")
resources+=("INSTANCE_NAME")
resources+=("INSTANCE_NUMBER")
resources+=("SAP_USER")
resources+=("HOST")
resources+=("Zpools")
resources+=("FileSystemType")
resources+=("MountPointDir")
resources+=("FilesystemMountPoints")
resources+=("TargetFileSystem")
resources+=("MountOptions")
resources+=("ONS_NODES")
resources+=("Db_unique_name")
resources+=("Oracle_Sid")
resources+=("Oracle_Home")
resources+=("Dataguard_role")
resources+=("Connect_string")
resources+=("Validate_command")
resources+=("Network_aware")
resources+=("Scalable")
resources+=("Start_timeout")
resources+=("Stop_timeout")
resources+=("Start_command")
resources+=("Stop_command")
resources+=("Child_mon_level")
resources+=("Failover_enabled")
resources+=("Stop_signal")


# Create a resource filter on the resource properties we care about
resource_filter="$(echo "${resources[@]}" | tr ' ' '\n' | awk '{printf("^%s:$\n", $1)}' | tr '\n' '|')"
resource_filter="$(echo "${resource_filter}" | sed 's/|$//g')"


###############################################
# Bootstrap by acquiring the tools we need to inspect clusters
###############################################

# Acquire some additional paths for cluster specific tools
declare -a tools
tools=( $(find /usr /ora* /u0* -type d \( -name grid -o -name cluster \) 2>/dev/null | awk '{printf("%s/bin\n", $1)}') )
tools=( $(echo "${tools[@]}" | tr ' ' '\n' | sort -u) )
tools="$(echo "${tools[@]}" | tr ' ' ':')"

# Bail if tools aren't available
[ $(which clzc &>/dev/null;echo $?) -ne 0 ] && exit 1
[ $(which clnode &>/dev/null;echo $?) -ne 0 ] && exit 2
[ $(which clrg &>/dev/null;echo $?) -ne 0 ] && exit 3
[ $(which clrs &>/dev/null;echo $?) -ne 0 ] && exit 4

# Modify PATH once again
PATH=$PATH:${tools}



###############################################
# Begin report generation
###############################################

# If we are operating on a global
if [ $(zonename | grep -c "^global$") -gt 0 ]; then


  ###############################################
  # Since we are a global we need to inspect all running zones
  ###############################################

  # Running zones
  declare -a zones
  zones=( $(zoneadm list | grep -v global) )

  declare -a nodes
  nodes=( $(clnode list | tr '\n' ':') )


  ###############################################
  # Iterate the array of running zones
  ###############################################

  # Iterate ${zones[@]}
  for zone in ${zones[@]}; do

    # Reset the array's
    zrgs=()
    zrs=()

    ###############################################
    # Acquire details of the zone; hostname, status & configuration
    #   Also retrieve an array of resource groups available for the zone
    ###############################################

    # Get the zones hostname
    hostname="$(zlogin ${zone} 'uname -n')"
  
    # Get the nodes associated with ${zone}
    zone_nodes=( $(zlogin ${zone} 'PATH=$PATH:/usr/cluster/bin;clnode list' | tr '\n' ':') )

    # Get the current status of ${zone}
    status="$(clnode status -Z ${zone} | awk 'NR>7' | cut -d: -f2 | awk 'length($1) != 0{x=$1":"$2;getline;printf("%s:%s:%s\n", x, $1, $2)}')"
  
    # Get a blob of the ${zone} configuration
    zblob="$(clzc show ${zone})"

    # Get the zone properties
    zone_props=( $(echo "${zblob}" | egrep ${zone_prop_filter} | awk '{printf("%s%s^", $1, $2)}') )

    # Handle the 'ResourceName' ${zone} properties differently
    zone_props+=( $(echo "${zblob}" | awk '$0 ~ /Resource Name/{type=$3;getline;printf("%s:%s^", type, $2)}') )

    # Fix ${zone_props[@}}
    zone_props=( $(echo "${zone_props[@]}" | sed "s| ||g") )

    # Get the resource groups per ${zone}
    zrgs+=( $(clrg list -Z ${zone} | cut -d: -f2) )


    ###############################################
    # Iterate the array of resource groups
    ###############################################

    # Iterate ${zrgs[@]}
    for zrg in ${zrgs[@]}; do


      ###############################################
      # Acquire details of the resource group; status & configuration
      #   Also retrieve an array of resources available for the resource group
      ###############################################

      # Get the status for the ${zrg} resource group based using ${zone}
      zrg_status="$(clrg status -Z ${zone} | nawk -v rg="${zrg}" '$1 ~ rg{x=$2":"$3":"$NF;getline;printf("%s:%s:%s:%s", x, $1, $2, $NF)}')"

      # Get the important properties for the ${zrg} resource group based using ${zone}
      zrg_props=( $(clrg show -v -Z ${zone} ${zrg} | nawk -v filter="${rg_prop_filter}" '$1 ~ filter && $2 !~ /NULL/{printf("%s%s^", $1, $2)}') )
      
      # Obtain the resources for ${zrg}
      zrs=( $(clrs list -v -Z ${zone} -g ${zrg} | cut -d: -f2 | awk 'NR>2{printf("%s:%s\n", $1, $2)}' | sed 's/\(.*\):.*$/\1/g') )
   

      # if ${#zrs[@]} is empty make sure the empty resource group still gets logged
      if [ ${#zrs[@]} -eq 0 ]; then
        report+=( "$(uname -n),${nodes[@]},${zone},${status},${zone_props[@]},${zrg},${zrg_status},${zrg_props[@]},," )
      fi


      ###############################################
      # Iterate the array of resources for the zone and resource group
      ###############################################

      # Iterate ${zrs[@]}
      for zr in ${zrs[@]}; do

        ###############################################
        # Acquire details of the resource; status & configuration
        ###############################################

        # Get the resource status and members status
        clrsstatus="$(clrs status -Z ${zone} -g ${zrg} | nawk -v f="${zr}" '$1 ~ f{x=$2":"$3;getline;x=x":"$1":"$2;printf("%s,%s\n", f, x)}')"

        # Get a list of resource types based on the ${resource_filter}
        clresources=( $(clrs show -v -Z ${zone} ${zr} |
          nawk -v filter="${resource_filter}" '$1 ~ filter && $2 !~ /NULL/{for(i=1;i<=NF;i++){if(i==NF){gsub(/,/, "^", $i);printf("%s^", $i)}else{gsub(/,/, "^", $i);printf("%s:", $i)}}}') )

        report+=( "$(uname -n),${nodes[@]},${zone},${status},${zone_props[@]},${zrg},${zrg_status},${zrg_props[@]},${clrsstatus},${clresources[@]}" )
      done
    done
  done

  # Report header for LDOM specific runs
  header="LDOM,LDOM Cluster Nodes,Cluster,Cluster Nodes & Status,Cluster Configuration Properties,Resource Group,Resource Group Status,Resource Group Properties & Values,Resource,Resource & Node Status,Resource Properties & Values"
else

  ###############################################
  # When ran from a zone we can only acquire the zone status, resource groups & their resources
  ###############################################

  # Get the hostname
  hostname="$(uname -n)"
  
  # Get the nodes associated with ${zone}
  zone_nodes=( $(clnode list | tr '\n' ':') )

  # Get the current status of ${zone}
  status="$(clnode status | awk 'NR>7 && length($1) != 0{x=$1":"$2;getline;printf("%s:%s:%s\n", x, $1, $2)}')"
  
  # Get the resource groups per ${zone}
  zrgs=( $(clrg list | cut -d: -f2) )


  ###############################################
  # Iterate the array of resource groups
  ###############################################

  # Iterate ${zrgs[@]}
  for zrg in ${zrgs[@]}; do

    ###############################################
    # Acquire details of the resource group; status & configuration
    #   Also retrieve an array of resources available for the resource group
    ###############################################

    # Get the status for the ${zrg} resource group based using ${zone}
    zrg_status="$(clrg status ${zrg} | awk 'NR>5 && length($2) != 0{x=$2":"$NF;getline;printf("%s:%s:%s", x, $1, $NF)}')"

    # Obtain the resources for ${zrg}
    zrs=( $(clrs list -v -g ${zrg} | awk 'NR>2{printf("%s:%s\n", $1, $2)}' | sed 's/\(.*\):.*$/\1/g') )
   

    # if ${#zrs[@]} is empty make sure the empty resource group still gets logged
    if [ ${#zrs[@]} -eq 0 ]; then
      report+=( "${hostname},${status},${zrg},${zrg_status},,," )
    fi


    ###############################################
    # Iterate the resource groups resources
    ###############################################

    # Iterate ${zrs[@]}
    for zr in ${zrs[@]}; do

      ###############################################
      # Acquire details of the resource; status & configuration
      ###############################################

      # Get the resource name from ${zr}
      rname="$(echo "${zr}" | cut -d: -f1)"

      # Get the resource status and members status
      clrsstatus="$(clrg status | nawk -v rg="${zrg}" '$1 ~ rg{x=$2":"$NF;getline;printf("%s:%s:%s", x, $1, $NF)}')"

      # Get a list of resource types based on the ${resource_filter}
      clresources=( $(clrs show -v ${rname} | nawk -v filter="${resource_filter}" '$1 ~ filter && $2 !~ /NULL/{printf("%s%s^", $1, $2)}') )

      report+=( "${hostname},${status},${zrg},${zrg_status},${zr},${clrsstatus},${clresources[@]}" )
    done
  done

  # Zone specific header 
  header="CHIP,Cluster Nodes & Status,Resource Group,Resource Group Status,Resource,Resource & Node Status,Resource Properties & Values"
fi


###############################################
# Regardless of the run type print the defined header and report
###############################################

# Print everything
cat <<EOF
${header}
$(echo "${report[@]}" | tr ' ' '\n' | sed 's/:,/,/g' | sed 's/ ,/,/g' | sed 's/\^/ /g' | sed 's/ ,/,/g' | sed 's/::/:/g')
EOF


# Exit gracefully
exit 0
