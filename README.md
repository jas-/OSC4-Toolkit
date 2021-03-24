# OSC4 (Oracle Super Cluster) Toolkit
A collection of shell scripts to provide status and inspect configured resources for potential issues

# Status
```sh
$ for f in status*.sh; do /bin/bash ${f}; echo; done
```

# Inspect for issues
```sh
$ for f in clval*.sh; do /bin/bash ${f} verbose; echo; done
```

The inspection(s) performs the following:
1. Acquires necessary configuration data and generates a cached copy in .reports
2. Validates network configurations for all applicable resources
  a. IPMI groups, aggregate links and underlying physical interfaces
  b. DNS forward & reverse lookups for all defined IP and/or hostname resources
  c. Local nsswitch lookups for all defined IP and/or hostname resources
  d. ICMP test for all defined IP and/or hostname resources
  e. Socket open test for all defined IP and/or hostname resources
4. Validates disk configurations for all applicable resources
  a. Zpool configuration in zone cluster configuration
  b. NFS remote share validation
  c. NFS local mount point validation
