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
objects=( $(cut -d, -f3,6,8,9,11 ${report} | sort -u | tr ' ' '^' | egrep -i 'dependenc|affinit' | sort -u) )


###############################################
# Get a unique array of resource groups & resources
###############################################

# Get an array of resource group dependencies
declare -a resource_groups
resource_groups=( $(echo "${objects[@]}" | tr ' ' '\n' | cut -d, -f1,2 | sort -u) )

# Get an array of resources
declare -a resources
resources=( $(echo "${objects[@]}" | tr ' ' '\n' | cut -d, -f1,9 | sort -u) )


###############################################
# Begin ${objects[@]} iterator
###############################################

# Iterate ${objects[@]}
for object in ${objects[@]}; do
  
  # Define the severity level as LOW by default
  severity="LOW"


  ###############################################
  # We need to break ${object} up to perform examination
  #  - clname: This is the cluster name
  #  - zname: This is the zone name associated/based on ${clname}
  #  - clrgname: The resource group name
  #  - clrsname: The resource name
  #  - clrgdependencies: The resource groups dependencies
  #  - clrgaffinities: The resource groups affinities
  #  - clrsdependencies: The resources dependencies
  ###############################################


  # Chop ${object}
  clname="$(echo "${object}" | cut -d, -f1)"
  zname="$(zlogin ${clname} 'uname -n')"
  clrgname="$(echo "${object}" | cut -d, -f3)"
  clrsname="$(echo "${object}" | cut -d, -f4)"
  clrgdependencies=( $(echo "${object}" | tr ' ' '\n' | cut -d, -f3 | tr '^' '\n' |
    grep "RG_dependencies" | cut -d: -f2 | sort -u) )
  clrgaffinities=( $(echo "${object}" | tr ' ' '\n' | cut -d, -f3 | tr '^' '\n' |
    grep "RG_affinities" | cut -d: -f2 | sort -u | sed "s|\+||g") )
  clrsdependencies=( $(echo "${object}" | tr ' ' '\n' | cut -d, -f5 | tr '^' '\n' |
    grep "Resource_dependencies" | cut -d: -f2 | sort -u) )


  ###############################################
  # Look for missing resource groups that might be defined as a dependency
  ###############################################

  # Does the ${clrgname} exist for ${clname} (searches the ${resource_groups[@]} array)
  if [ $(in_array "${clname},${clrgname}" "${resource_groups[@]}") -eq 0 ]; then

    # Set the test type name
    test_type="MissingRGDefinedAsDependency"

    # Since we have an issue determine severity
    [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
      severity="CRITICAL"

    # Add to the errors array
    errors+=("${severity},Application,${clname},${test_type},${clrgname},${clrsname},${clrgname}")
  fi


  ###############################################
  # Look for missing resource groups that might be defined as an affinity
  ###############################################

  # Does the ${clrgname} exist for ${clname} (searches the ${resource_groups[@]} array)
  if [ $(in_array "${clname},${clrgname}" "${resource_groups[@]}") -eq 0 ]; then

    # Set the test type name
    test_type="MissingRGDefinedAsAffinity"

    # Since we have an issue determine severity
    [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
      severity="CRITICAL"

    # Add to the errors array
    errors+=("${severity},Application,${clname},${test_type},${clrgname},${clrsname},${clrgname}")
  fi
  
  
  ###############################################
  # Look for missing resources that might be defined as an dependency
  ###############################################

  # Does the ${clrgname} exist for ${clname} (searches the ${resource_groups[@]} array)
  if [ $(in_array "${clname},${clrsname}" "${resources[@]}") -eq 0 ]; then

    # Set the test type name
    test_type="MissingRSDefinedAsDependency"

    # Since we have an issue determine severity
    [ $(echo "${monitor[@]}" | tr ' ' '\n' | grep -c "${clname}") -gt 0 ] &&
      severity="CRITICAL"

    # Add to the errors array
    errors+=("${severity},Application,${clname},${test_type},${clrgname},${clrsname},${clrgname}")
  fi
done


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
