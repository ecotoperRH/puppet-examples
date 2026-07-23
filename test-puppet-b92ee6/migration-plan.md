# MIGRATION FROM PUPPET TO ANSIBLE

## Executive Summary

This repository contains a Puppet control repository with three main profile modules that need to be migrated to Ansible. The infrastructure appears to be designed for a multi-tier application stack with HAProxy load balancing, Python application servers with PostgreSQL databases, and Redis clusters. The migration complexity is moderate, with clear module boundaries and well-defined dependencies. Estimated timeline: 3-4 weeks for a complete migration with testing.

## Module Migration Plan

This repository contains Puppet modules that need individual migration planning:

### MODULE INVENTORY

- **profile_app_stack**:
    - Description: Python application stack with PostgreSQL database, systemd service management, and monitoring
    - Path: modules/profile_app_stack
    - Technology: Puppet
    - Key Features: Python virtual environment, PostgreSQL database configuration, application deployment from Git, systemd service management

- **profile_haproxy**:
    - Description: HAProxy load balancer with multi-backend support, SSL termination, and statistics interface
    - Path: modules/profile_haproxy
    - Technology: Puppet
    - Key Features: Backend configuration, SSL termination, statistics interface, firewall rules

- **profile_redis_cluster**:
    - Description: Redis cluster configuration with PuppetDB node discovery
    - Path: modules/profile_redis_cluster
    - Technology: Puppet
    - Key Features: Redis server configuration, memory management, cluster setup

- **puppetdb_query_stub**:
    - Description: Stub function for PuppetDB queries when no PuppetDB is available
    - Path: modules/puppetdb_query_stub
    - Technology: Puppet
    - Key Features: Ruby function that returns empty arrays for PuppetDB queries

- **profile::app::stack**:
    - Description: Thin wrapper around profile_app_stack module
    - Path: site/profile/manifests/app/stack.pp
    - Technology: Puppet
    - Key Features: Environment-aware application stack configuration

- **role::app_stack**:
    - Description: Role class for application stack nodes
    - Path: site/role/manifests/app_stack.pp
    - Technology: Puppet
    - Key Features: Combines base profile with application stack profile

### Infrastructure Files

- `Puppetfile`: Defines external module dependencies (puppetlabs-stdlib, puppetlabs-concat, puppetlabs-firewall, puppetlabs-vcsrepo, puppet-redis, puppetlabs-apt)
- `environment.conf`: Defines the module path for Puppet environments
- `hiera.yaml`: Hierarchical data configuration with node-specific, environment-specific, and common data
- `data/common.yaml`: Common configuration values for all environments
- `data/environment/*.yaml`: Environment-specific configuration values
- `Vagrantfile`: Development environment configuration using Ubuntu 24.04
- `vagrant-provision.sh`: Provisioning script for Vagrant that installs Puppet and required modules
- `test/site.pp`: Test manifest that sets up a Git repository and includes the main profiles

### Target Details

Based on the source repository analysis:

- **Operating System**: Ubuntu 24.04 (Noble Numbat) as specified in the Vagrantfile
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises deployment

## Migration Approach

### Key Dependencies to Address

- **puppetlabs-stdlib (9.7.0)**: Replace with Ansible built-in filters and modules
- **puppetlabs-concat (9.0.2)**: Replace with Ansible's template module and blockinfile/lineinfile modules
- **puppetlabs-firewall (8.1.3)**: Replace with Ansible's firewalld or iptables modules
- **puppetlabs-vcsrepo (6.1.0)**: Replace with Ansible's git module
- **puppet-redis (11.0.0)**: Replace with Ansible Redis role from Ansible Galaxy
- **puppetlabs-apt (9.4.0)**: Replace with Ansible's apt module

### Security Considerations

- **Hiera eyaml encryption**: The repository uses encrypted Hiera data for node-specific secrets. Migration should use Ansible Vault for secret management.
- **Database credentials**: The profile_app_stack module contains database credentials that should be migrated to Ansible Vault.
- **HAProxy statistics credentials**: The profile_haproxy module contains statistics interface credentials that should be migrated to Ansible Vault.
- **Redis password**: The profile_redis_cluster module contains a Redis password that should be migrated to Ansible Vault.
- **SSL certificates**: The profile_haproxy module references SSL certificate and key paths that will need to be managed securely in Ansible.
- **Vault/secrets management**: For each module, credential patterns identified:
  - profile_app_stack: 2 credentials (db_password, secret_key)
  - profile_haproxy: 2 credentials (stats_password, SSL certificates)
  - profile_redis_cluster: 1 credential (redis_password)

### Technical Challenges

- **PuppetDB queries**: The profile_redis_cluster module uses PuppetDB queries to discover Redis nodes. This will need to be replaced with Ansible's inventory or dynamic inventory plugins.
- **Strict dependency ordering**: The profile_app_stack module uses strict dependency ordering between classes. This will need to be carefully mapped to Ansible's task execution order.
- **Custom functions**: The profile_app_stack module uses a custom function to build the database URL. This will need to be replaced with Ansible filters or custom plugins.
- **Hiera data hierarchy**: The repository uses a complex Hiera data hierarchy with environment-specific and node-specific data. This will need to be mapped to Ansible's variable precedence and group_vars/host_vars structure.

### Migration Order

1. **puppetdb_query_stub** (low risk, simple functionality)
2. **profile_redis_cluster** (moderate complexity, depends on Redis Galaxy role)
3. **profile_haproxy** (moderate complexity, depends on firewall modules)
4. **profile_app_stack** (high complexity, depends on multiple modules and has strict dependency ordering)
5. **site/profile/manifests/app/stack.pp** (low risk, thin wrapper)
6. **site/role/manifests/app_stack.pp** (low risk, role class)

### Assumptions

1. The target environment will continue to be Ubuntu 24.04.
2. The application being deployed is a Python application with PostgreSQL database.
3. The current Vagrant development environment will be preserved or migrated to a similar setup.
4. The current directory structure with separate modules will be preserved in the Ansible roles structure.
5. The current Hiera data hierarchy will be mapped to Ansible's variable precedence.
6. The current PuppetDB queries will be replaced with Ansible's inventory or dynamic inventory plugins.
7. The current custom functions will be replaced with Ansible filters or custom plugins.
8. The current strict dependency ordering will be preserved in Ansible's task execution order.
9. The current secret management will be migrated to Ansible Vault.
10. The test fixtures will be migrated to Ansible's testing framework.