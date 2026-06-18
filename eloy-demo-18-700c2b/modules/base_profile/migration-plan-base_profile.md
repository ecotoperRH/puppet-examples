---
source-path: site/profile/manifests/base
---

# Migration Plan: profile::base::base

**TLDR**: This module provides basic OS-level configuration for all nodes, including NTP time synchronization via chrony and system logging via rsyslog. It's a foundational module that's included in all roles.

## Service Type and Instances

**Service Type**: Base System Configuration

**Configured Instances**:
- **chrony**: NTP time synchronization
  - Location/Path: System service
  - Port/Socket: UDP 123 (standard NTP port)
  - Key Config: Uses NTP servers from Hiera data
- **rsyslog**: System logging
  - Location/Path: System service
  - Port/Socket: UDP/TCP 514 (standard syslog port)
  - Key Config: Configured with server and facility from Hiera data

## File Structure

```
site/profile/manifests/base/base.pp
data/common.yaml
data/environment/production.yaml
data/environment/staging.yaml
```

## Module Explanation

The module performs operations in this order:

1. **profile::base::base** (`site/profile/manifests/base/base.pp`):
   - Sets class parameters:
     - manage_ntp = true (default, can be overridden via Hiera)
     - manage_syslog = true (default, can be overridden via Hiera)
     - manage_utils = true (default, can be overridden via Hiera)
   - Conditional: if $manage_utils is true
     - Includes base_utils class (external class - not in the provided execution tree details)
   - Conditional: if $manage_ntp is true AND $facts['kernel'] == 'Linux'
     - Installs package: chrony (ensure: installed)
     - Manages service: chronyd (ensure: running, enable: true)
   - Conditional: if $manage_syslog is true AND $facts['kernel'] == 'Linux'
     - Installs package: rsyslog (ensure: installed)
     - Manages service: rsyslog (ensure: running, enable: true)
   - Resources: package (2), service (2)
   - Facts used: $facts['kernel'] (to check if running on Linux)

2. **role::redis_cluster** (`site/role/manifests/redis_cluster.pp`):
   - Conditional: if $facts['kernel'].downcase == 'linux'
     - Executes a command (details not provided in execution tree)
   - Includes profile::base::base class (described above)
   - Includes profile::cache::redis class
     - Includes profile_redis_cluster (external class)
   - Sets ordering: Class['::profile::base::base'] -> Class['::profile::cache::redis']
     - This ensures base configuration is applied before Redis configuration
   - Facts used: $facts['kernel'] (to check if running on Linux)

## Variables

**Variable Flow Summary**: 7 variables across 3 Hiera levels

### Variable Definitions

**common.yaml (defaults)** → Migration note: Base defaults for all nodes
- `ntp::servers`: `[0.pool.ntp.org, 1.pool.ntp.org]` (type: array)
- `ssh::client_alive_interval`: `300` (type: integer)
- `ssh::permit_root_login`: `false` (type: boolean)
- `syslog::server`: `127.0.0.1` (type: string)
- `syslog::facility`: `local0` (type: string)

**environment/production.yaml (environment overrides)** → Migration note: Production environment-specific variables
- `ntp::servers`: `[ntp1.prod.internal, ntp2.prod.internal]` (type: array)
- `syslog::server`: `syslog.prod.internal` (type: string)
- `syslog::facility`: `local1` (type: string)

**environment/staging.yaml (environment overrides)** → Migration note: Staging environment-specific variables
- `syslog::server`: `syslog.staging.internal` (type: string)

### Variable Migration Summary

- **Common defaults**: 5 variables from common.yaml (base configuration for all nodes)
- **Environment-specific variables**: 4 variables that vary by deployment environment (production, staging)
- **Host-specific variables**: 0 variables for individual host overrides
- **Encrypted variables**: 0 variables that are encrypted

### Cross-Level Overrides

Variables defined at multiple Hiera levels:
- **ntp::servers**: defined at common.yaml, production.yaml, merge strategy: first
- **syslog::server**: defined at common.yaml, production.yaml, staging.yaml, merge strategy: first
- **syslog::facility**: defined at common.yaml, production.yaml, merge strategy: first

### Merge Strategy Notes

- Variables using `first` (default) - First value found wins, no merging
- The profile::base::base class explicitly uses the 'first' merge strategy for its parameters

## Dependencies

**External module dependencies**: None explicitly shown for the base profile
**System package dependencies**: chrony, rsyslog
**Service dependencies**: None explicitly defined

## Puppet Facts Used

- `$facts['kernel']` - Operating system kernel (used to check if running on Linux)

## Checks for the Migration

**Files to verify**: 
- /etc/chrony.conf (standard chrony configuration file)
- /etc/rsyslog.conf (standard rsyslog configuration file)

**Service endpoints to check**: 
- chronyd service status
- rsyslog service status

## Pre-flight checks:
```bash
# Service status commands
systemctl status chronyd
systemctl status rsyslog

# Configuration validation commands
chronyc tracking
logger -t test "Test message" && grep test /var/log/messages
```