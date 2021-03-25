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
* Acquires necessary configuration data and generates a cached copy in .reports
* Validates network configurations for all applicable resources
  * IPMI groups, aggregate links and underlying physical interfaces
  * DNS forward & reverse lookups for all defined IP and/or hostname resources
  * Local nsswitch lookups for all defined IP and/or hostname resources
  * ICMP test for all defined IP and/or hostname resources
  * Socket open test for all defined IP and/or hostname resources
* Validates disk configurations for all applicable resources
  * Zpool configuration in zone cluster configuration
  * NFS remote share validation
  * NFS local mount point validation
