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

# Get the report header
header="Severity,AOR,Cluster,Cluster Node Status,Resource Group,Resource Group Status,Resource Name,Resource Status"


###############################################
# Copy ${report} into an array
###############################################

# Define an array for the report
declare -a report
report=( $(awk 'NR>1' ${report} | tr ' ' '^' | sort -u) )


###############################################
# Acquire a list of priority systems that indicate both resource groups & resources as OFFLINE
###############################################

# Filter ${report[@]} based on the ${monitor_filter} to generate a CRITICAL list of issues
declare -a critical_report
critical_report=( $(echo "${report[@]}" | tr ' ' '\n' | egrep ${monitor_filter} |
  awk -F, '$7 !~ /.*:Online:.*:Online/ && ($10 !~ /Online/ && $9 != ""){printf("CRITICAL,Application,%s,(%s),%s,(%s),%s,(%s)\n", $3, $4, $6, $7, $9, $10)}' |
  sed 's/:,/,/g' | sed 's/\^/ /g') )


###############################################
# Acquire a list of non-priority systems that indicate both resource groups & resources as OFFLINE
###############################################

# Filter ${report[@]} based on the ${monitor_filter} to generate a LOW list of issues
declare -a general_report
general_report=( $(echo "${report[@]}" | tr ' ' '\n' | egrep -v ${monitor_filter} |
  awk -F, '$7 !~ /.*:Online:.*:Online/ && ($10 !~ /Online/ && $9 != ""){printf("LOW,Application,%s,(%s),%s,(%s),%s,(%s)\n", $3, $4, $6, $7, $9, $10)}' |
  sed 's/:,/,/g' | sed 's/\^/ /g') )


###############################################
# If either ${critical_report[@]} ${general_report[@]} and > 0 provide the info
###############################################

# Print issues and bail
if [[ ${#critical_report[@]} -gt 0 ]] || [[ ${#general_report[@]} -gt 0 ]]; then
  cat <<EOF
${header}
$(echo "${critical_report[@]}" "${general_report[@]}" | tr ' ' '\n')
EOF

  exit $(( ${#critical_report[@]} + ${#general_report[@]} ))
fi


# All systems up!
exit 0
