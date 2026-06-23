# profile_haproxy

An Ansible role to install and configure HAProxy load balancer.

## Requirements

- Ansible 2.9 or higher
- Supported operating systems:
  - Ubuntu 20.04 (Focal) and 22.04 (Jammy)
  - Debian 11 (Bullseye) and 12 (Bookworm)
  - RHEL/CentOS/Rocky 8 and 9

## Role Variables

### Main Configuration

```yaml
# Package installation settings
haproxy_package_name: haproxy
haproxy_package_state: present

# Service settings
haproxy_service_name: haproxy
haproxy_service_enabled: true
haproxy_service_state: started

# Configuration paths
haproxy_config_dir: /etc/haproxy
haproxy_config_file: "{{ haproxy_config_dir }}/haproxy.cfg"
haproxy_config_fragments_dir: "{{ haproxy_config_dir }}/conf.d"

# Log settings
haproxy_log_dir: /var/log/haproxy
haproxy_log_file: "{{ haproxy_log_dir }}/haproxy.log"
haproxy_log_level: info
haproxy_log_facility: local0

# Stick table settings
stick_table_size: 100k
stick_table_expire: 30m
```

### Backend Configuration

```yaml
backends:
  web:
    mode: http
    balance: roundrobin
    options:
      - httpchk GET /health
    servers:
      - name: web1
        address: 10.0.0.1
        port: 8080
        weight: 100
      - name: web2
        address: 10.0.0.2
        port: 8080
        weight: 100
```

## Dependencies

None.

## Example Playbook

```yaml
---
- hosts: loadbalancers
  roles:
    - role: profile_haproxy
      vars:
        backends:
          api:
            mode: http
            balance: roundrobin
            options:
              - httpchk GET /api/health
            servers:
              - name: api1
                address: 10.0.1.1
                port: 8000
                weight: 100
              - name: api2
                address: 10.0.1.2
                port: 8000
                weight: 100
```

## License

MIT

## Author Information

Ansible Migration Team