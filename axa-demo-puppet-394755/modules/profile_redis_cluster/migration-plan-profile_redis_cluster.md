---
source-path: modules/profile_redis_cluster
---

# Migration Plan: profile_redis_cluster

**TLDR**: The profile_redis_cluster module is a Puppet profile that sets up a Redis server with basic configuration. It uses PuppetDB to query for other Redis nodes in the cluster. The module depends on the puppet-redis module for the actual Redis installation and configuration. The migration to Ansible will require creating roles and tasks that install Redis, configure it with the appropriate settings, and implement a mechanism to discover other Redis nodes.

## Service Type and Instances

**Service Type**: Redis (in-memory data structure store)

**Configured Instances**:
- **Redis Server**: Primary Redis instance
  - Location/Path: /etc/redis/redis.conf
  - Port/Socket: 6379 (default)
  - Key Config: Authentication password, memory limits, persistence settings

## File Structure

```
modules/profile_redis_cluster/
├── manifests/
│   ├── init.pp           # Main class with parameters and PuppetDB query
│   └── install.pp        # Redis installation class
├── templates/
│   └── redis.conf.erb    # Redis configuration template
├── lib/
│   └── facter/
│       └── redis_role.rb # Custom fact to determine Redis role
└── metadata.json         # Module metadata and dependencies
```

## Module Explanation

The module performs operations in this order:

1. **profile_redis_cluster** (`manifests/init.pp`):
   - Defines main parameters: redis_port, redis_password, maxmemory_mb, maxmemory_policy
   - Queries PuppetDB for other nodes with the same class
   - Includes the profile_redis_cluster::install class

2. **profile_redis_cluster::install** (`manifests/install.pp`):
   - Configures the Redis server using the puppet-redis module
   - Sets bind address to 0.0.0.0
   - Configures port, password, memory limits from parent class
   - Enables appendonly persistence with everysec sync
   - Manages the Redis package

## Variables

**Variable Flow Summary**: 4 variables defined in the main class, passed to the install class

### Variable Definitions

**class parameters (defaults)** → Migration note: Define in Ansible defaults/main.yml
- `profile_redis_cluster::redis_port`: `6379` (type: Integer)
- `profile_redis_cluster::redis_password`: `'CHANGEME'` (type: String)
- `profile_redis_cluster::maxmemory_mb`: `2048` (type: Integer)
- `profile_redis_cluster::maxmemory_policy`: `'allkeys-lru'` (type: String)

**PuppetDB query results** → Migration note: Replace with Ansible inventory or dynamic inventory
- `profile_redis_cluster::redis_nodes`: Array of nodes with profile_redis_cluster class (type: Array)

### Variable Migration Summary

- **Common defaults**: 4 variables defined in the main class with defaults
- **Encrypted variables**: 1 variable (redis_password) that should be stored in Ansible Vault

## Custom Types and Providers

The module includes a custom fact:

- **redis_role**: Determines if the Redis instance is a primary or replica by checking for the presence of 'replicaof' in the replica.conf file

## Dependencies

**External module dependencies**:
- puppetlabs-stdlib: Standard library for Puppet functions
- puppet-redis: Main Redis module that handles installation and configuration

**System package dependencies**:
- redis-server

**Service dependencies**:
- redis-server service

## Puppet Facts Used

- **networking.fqdn**: Used in the Redis configuration template
- **environment**: Used in Hiera data lookup
- **kernel**: Used in the redis_role custom fact to ensure it only runs on Linux

## Template Conversion Notes

### redis.conf.erb
The Redis configuration template needs to be converted to a Jinja2 template for Ansible:
- Replace ERB tags (<%= %>) with Jinja2 syntax ({{ }})
- Replace @facts references with Ansible facts
- Example conversion:
  ```
  # Redis configuration — Managed by Puppet
  # Node: <%= @facts['networking']['fqdn'] %>
  ```
  becomes:
  ```
  # Redis configuration — Managed by Ansible
  # Node: {{ ansible_fqdn }}
  ```

## PuppetDB Dependencies

**Exported Resources**: None found in this module

**Resource Collectors**: None found in this module

**PuppetDB Queries**:
- Query: `resources[certname] { type = 'Class' and title = 'Profile_redis_cluster' }`
- Returned data: List of nodes with the Profile_redis_cluster class
- Migration notes: Replace with Ansible inventory groups or dynamic inventory for Redis nodes

## Checks for the Migration

**Files to verify**:
- /etc/redis/redis.conf
- /etc/systemd/system/redis.service

**Service endpoints to check**:
- Redis server on port 6379 (or custom port if configured)

**Templates rendered**:
- redis.conf.erb (1 instance per node)

## Pre-flight checks:
```bash
# Service status command
systemctl status redis-server

# Configuration validation
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD ping

# Memory configuration check
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD CONFIG GET maxmemory
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD CONFIG GET maxmemory-policy

# Persistence configuration check
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD CONFIG GET appendonly
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD CONFIG GET appendfsync

# Role verification
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD INFO replication
```