#!/bin/bash

# Ensure path is robust
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/cluster/bin


###############################################
# Defined time threshold for caching reports in minutes
###############################################

# Cached time
cached_time=60


###############################################
# Priority monitoring options; all methods are combined to determine a severity level
#  - Add important cluster names to the ${monitor[@]} array
#  - Use the ENV variable; MONITOR_HOSTS. ex. MONITOR_HOSTS+=("host1" "host2" ...)
#  - Use a line separated list of systems found @ $(pwd)/.monitor
###############################################

# Important items to monitor (can be LDOM's, nodes, cluster names, resource groups, resources, attributes etc)
declare -a monitor
monitor+=("ebspbh45")
monitor+=("ebscbh45")

# Import ENV systems
monitor+=( ${MONITOR_HOSTS[@]} )

# Import from $(pwd)/.monitor if found
[ -f $(pwd)/.monitor ] &&
  monitor+=( "$(cat $(pwd)/.monitor)" )

# Convert ${monitor[@]} items to a filter
monitor_filter="$(echo "${monitor[@]}" | tr ' ' '|')"


###############################################
# Define some additional variables such as report header, timestamp & current working directory
###############################################

# Get the report header
header="Severity,AOR,Cluster,Test Type,Resource Group,Resource Name,Property"

# Today as EPOCH
current_epoch=$(gawk 'BEGIN{print systime()}')

# Timestamp
ts="$(date +%Y%m%d)-${current_epoch}"

# Env specifics
cwd="$(pwd)"

# Convert ${cached_time} to seconds
cached_time=$(expr ${cached_time} \* 60)


###############################################
# Make sure the report generator exists first
###############################################

# Bail if $(pwd)/cluster-status-report.sh is missing
if [ ! -f ${cwd}/cluster-status-report.sh ]; then
  echo "Unable to find 'cluster-status-report.sh', exiting"
  exit 1
fi


###############################################
# Create a cached environment regarding the report to help speed things up (only daily inquisitions supported atm)
###############################################

# Report folder
rfolder="${cwd}/.reports/"
[ ! -d ${rfolder} ] && mkdir -p ${rfolder}

# Get list of files
reports=( $(ls ${rfolder}/* 2>/dev/null | awk '$1 ~ /^[0-9]+/') )

# If ${#reports[@]} is empty just run a new report
if [ ${#reports[@]} -eq 0 ]; then

  # Create new report var
  report="${rfolder}/${ts}"

  # Create a new report
  /bin/bash ${cwd}/cluster-status-report.sh > ${report}
else

  # Get the last element from ${reports[@]} in order to compare dates
  report="$(echo "${reports[@]}" | tr ' ' '\n' | sort -n | tail -1)"
  
  # Split the report name or run the report
  if [ $(echo "${report}" | awk -F"-" '{print NF}') -le 1 ]; then

    # Create new report var
    report="${rfolder}/${ts}"

    # Create a new report
    /bin/bash ${cwd}/cluster-status-report.sh > ${report}
  else
    
    # Get the epoch from ${report}
    last_epoch=$(echo "${report}" | cut -d"-" -f2)
    
    # Determine if threshold reached
    if [[ $(expr ${current_epoch} - ${last_epoch}) -ge ${cached_time} ]] || [[ "${1}" == "force" ]]; then

      # Create new report var
      report="${rfolder}/${ts}"

      # Create a new report
      /bin/bash ${cwd}/cluster-status-report.sh > ${report}
    fi
  fi
fi


###############################################
# Define a function to perform string comparisons against arrays
###############################################

# Search a haystack for the supplied needle
# Arguments:
#  args [Array]: Array of arguments supplied to in_array()
#  needle [String]: String to perform strict search on
#  haystack [Array]: Array of string(s) to search for ${string} in
# Returns [Boolean]
function in_array()
{
  local args=("${@}")
  local needle="${args[0]}"
  local haystack=("${args[@]:1}")

  for i in ${haystack[@]}; do
    if [[ ${i} == ${needle} ]]; then
      echo 0 && return 0
    fi
  done

  echo 1 && return 1
}


###############################################
# Function to handle acquisition of resource group type
###############################################

# Query the provided node & resource group for its type
# Arguments:
#  node [String]: Zone/Cluster name
#  rg [String]: Resource group name
# Returns [String]
function rg_types()
{
  local node="${1}"
  local rg="${2}"

  local -a blob=( $(clrg show -v -Z ${node} ${rg//\:*} 2>/dev/null | awk '$1 ~ /Resource:$/{getline;print $2}') )
  
  local first=$(echo "${blob[@]}" | tr ' ' '\n' |
    egrep -c 'LogicalHostname|HAStoragePlus')
  local second=$(echo "${blob[@]}" | tr ' ' '\n' |
    egrep -c 'ScalMountPoint|ORCL.oracle_external_proxy')
  local last=$(echo "${blob[@]}" | tr ' ' '\n' |
    egrep -cv 'ScalMountPoint|LogicalHostname|HAStoragePlus|ORCL.oracle_external_proxy')
  
  echo "${first},${second},${last}"
}


###############################################
# Get the primary node of the resource group
###############################################

# Query the provided node & resource group for its primary node
# Arguments:
#  node [String]: Zone/Cluster name
#  rg [String]: Resource group name
# Returns [String]
function rg_primary_node()
{
  local node="${1}"
  local rg="${2}"

  clrg show -v -Z ${node} ${rg//\:*/} 2>/dev/null | grep Nodelist | awk '{print $2}'
}


###############################################
# Iterate and print commands for resource group online ops
###############################################

# Query the provided node & resource group for its primary node
# Arguments:
#  rgs [Array]: Array of arguments supplied to in_array()
# Prints [String]
function start_rg()
{
  local -a args=("${@}")
  local node="${args[0]}"
  local rgs="${args[@]:1}"

  # Since we need to prioritize (makes some assumptions);
  #  Primary: # of SUNW.LogicalHostname resources per rg
  #  Secondary: # of SUNW.HAStoragePlus resources per rg
  #  Last: everything else

  # Perform a logical sort
  local -a sorted=( $(echo "${rgs[@]}" | tr ' ' '\n' | sort -nr -t, -k2 +2) )

  # Kick the can for all in sequential order
  start_rg_iterator "${node}" "${sorted[@]}"
}


###############################################
# Iterate and print commands for resource group online ops
###############################################

# Query the provided node & resource group for its primary node
# Arguments:
#  rgs [Array]: Array of arguments supplied to in_array()
# Prints [String]
function start_rg_iterator()
{
  local -a args=("${@}")
  local node="${args[0]}"
  local rgs="${args[@]:1}"

  
  # Iterate ${rgs[@]}
  for resource_group in ${rgs[@]}; do

    # Get the preferred node from ${affinities[@]} if it is defined as such
    #[ $(in_array "${resource_group//:*/}" "$(echo "${affinities[@]//:*/}" | sed "s|+||g")") -eq 0 ] &&
    #  preferred_node="$(rg_primary_node "${node}" "${resource_group//:*/}")" || preferred_node=""

    # is managed?
    is_managed=$(echo "${resource_group}" | awk -F: '{print $NF}')

    # If ${resource_group} requires an affinity do it there
    if [ "${preferred_node}" != "" ]; then
      [ ${is_managed} -eq 1 ] &&
        echo "clrg online -Z ${node} -n ${preferred_node} -eMm ${resource_group//:*/}" ||
        echo "clrg online -Z ${node} -n ${preferred_node} -em ${resource_group//:*/}"
    else
      [ ${is_managed} -eq 1 ] &&
        echo "clrg online -Z ${node} -eMm ${resource_group//:*/}" ||
        echo "clrg online -Z ${node} -em ${resource_group//:*/}"
    fi
  done
}


###############################################
# Common math functions
###############################################

# @description Addition
#
# @arg ${1} Integer
# @arg ${2} Integer
#
# @stdout Integer
function add()
{
  echo "${1} + ${2}" | bc 2>/dev/null
}


# @description Binary to decimal
#
# @arg ${1} Integer
#
# @stdout Integer
function bin2dec()
{
  printf '%d\n' "$(( 2#${1} ))"
}


# @description Convert decimal to binary for provided IPv4 octets
#
# @arg ${1} Integer
# @arg ${2} Integer
# @arg ${3} Integer Rounding
#
# @stdout Integer
function dec2bin4octet()
{
  local -a octets=( ${@} )
  local -a bin=({0..1}{0..1}{0..1}{0..1}{0..1}{0..1}{0..1}{0..1})
  local -a results

  # Iterate ${octets[@]}
  for octet in ${octets[@]}; do

    # Push ${bin[${octet}]} to ${results[@]}
    results+=("${bin[${octet}]}")
  done

  echo "${results[@]}"
}


# Bitwise AND calculator
function bitwise_and_calc()
{
  one="$(echo "${1}" | nawk '{gsub(/\(|\)/, "", $0);print}')"
  two="$(echo "${2}" | nawk '{gsub(/\(|\)/, "", $0);print}')"
  printf '%08X\n' "$(( 0x${one} & 0x${two} ))"
}


###############################################
# Networking functions; validation, CIDR to subnet calc, subnet address calc, address in range calc
###############################################

# @description Validate IPv4 addresses
#
# @arg ${1} IPv4 address
#
# @example
#   is_ipv4 192.168.2.15 (true = 0)
#   is_ipv4 192.168.2.256 (false = 1)
#
# @stdout boolean 1/0
#
# @exitcode 0 Success
# @exitcode 1 Error
function is_ipv4()
{
  local  ip="${1}"
  local  stat=1

  if [[ ${ip} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    ip=( $(echo "${ip}" | tr '.' ' ') )
    if [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]; then
      stat=0
    fi
  fi

  echo ${stat} && return ${stat}
}


# @description CIDR to subnet
#
# @arg ${1} CIDR notation
#
# @example
#   calc_ipv4_cidr_subnet 25
#
# @stdout String Reversed CIDR to mapped netmask
function calc_ipv4_cidr_subnet()
{
  local cidr="${1}"

  case "${cidr}" in
    0) net="0.0.0.0" ;;
    1) net="128.0.0.0" ;;
    2) net="192.0.0.0" ;;
    3) net="224.0.0.0" ;;
    4) net="240.0.0.0" ;;
    5) net="248.0.0.0" ;;
    6) net="252.0.0.0" ;;
    7) net="254.0.0.0" ;;
    8) net="255.0.0.0" ;;
    9) net="255.128.0.0" ;;
    10) net="255.192.0.0" ;;
    11) net="255.224.0.0" ;;
    12) net="255.240.0.0" ;;
    13) net="255.248.0.0" ;;
    14) net="255.252.0.0" ;;
    15) net="255.254.0.0" ;;
    16) net="255.255.0.0" ;;
    17) net="255.255.128.0" ;;
    18) net="255.255.192.0" ;;
    19) net="255.255.224.0" ;;
    20) net="255.255.240.0" ;;
    21) net="255.255.248.0" ;;
    22) net="255.255.252.0" ;;
    23) net="255.255.254.0" ;;
    24) net="255.255.255.0" ;;
    25) net="255.255.255.128" ;;
    26) net="255.255.255.192" ;;
    27) net="255.255.255.224" ;;
    28) net="255.255.255.240" ;;
    29) net="255.255.255.248" ;;
    30) net="255.255.255.252" ;;
    31) net="255.255.255.254" ;;
    32) net="255.255.255.255" ;;
    *) net="0.0.0.0"
  esac

  echo "${net}"
}


# @description Calculate the subnet host addr
#
# @arg ${1} IPv4 address
# @arg ${2} Subnet mask
#
# @example
#   calc_ipv4_host_addr 192.168.2.15 255.255.255.128
#
# @stdout String IPv4 host address
function calc_ipv4_host_addr()
{
  local -a ipv4=( $(dec2bin4octet $(echo "${1}" | tr '.' ' ')) )
  local -a netmask=( $(dec2bin4octet $(echo "${2}" | tr '.' ' ')) )
  local total=3
  local n=0
  local -a ip

  while [ ${n} -le ${total} ]; do
    ip+=( $(bin2dec $(bitwise_and_calc ${ipv4[${n}]} ${netmask[${n}]})) )
    n=$(add ${n} 1)
  done

  echo "${ip[@]}" | tr ' ' '.'
}


# @description Determine if provided IPv4 is in subnet range
#
# @arg ${1} IPv4 comparison address
# @arg ${2} Subnet comparison mask
# @arg ${3} IPv4 target address
#
# @example
#   calc_ipv4_host_in_range 192.168.2.15 255.255.255.128 192.168.15.67
#   calc_ipv4_host_in_range 192.168.2.15 255.255.255.128 192.168.2.18
#
# @stdout String IPv4 host address
function calc_ipv4_host_in_range()
{
  local ipv4="${1}"
  local netmask="${2}"

  local -a net=( $(dec2bin4octet $(echo "${3}" | tr '.' ' ')) )

  local -a host_addr=( $(dec2bin4octet $(echo $(calc_ipv4_host_addr "${ipv4}" "${netmask}") | tr '.' ' ')) )

  local -a t_net=( ${net[0]} ${net[1]} ${net[2]} ${net[3]:0:5} )
  local -a t_host_addr=( ${host_addr[0]} ${host_addr[1]} ${host_addr[2]} ${host_addr[3]:0:5} )

  local total=3
  local n=0
  local -a results

  while [ ${n} -le ${total} ]; do
    results+=( $(bitwise_and_calc ${t_net[${n}]} ${t_host_addr[${n}]}) )
    n=$(add ${n} 1)
  done

  results=( ${results[0]} ${results[1]} ${results[2]} ${results[3]:0:5} )

  [ "$(echo "${t_host_addr[@]}" | sed 's/ //g')" == "$(echo "${results[@]}" | sed 's/ //g')" ] &&
    echo true || echo false
}

