# HAProxy Role

This Ansible role installs and configures HAProxy with support for multiple backends, SSL termination, and statistics.

## Requirements

- Ansible 2.9 or higher
- Target systems: Debian/Ubuntu or RHEL/CentOS

## Role Variables

See `defaults/main.yml` for all default variables.

### Main Configuration

```yaml
package_name: haproxy
config_dir: /etc/haproxy
config_file: /etc/haproxy/haproxy.cfg
service_name: haproxy
user: haproxy
group: haproxy
```

### Backend Configuration

Define your backends in group_vars or host_vars:

```yaml
backends:
  webservers:
    balance: roundrobin
    port: 80
    health_check: httpchk
    health_interval: 5s
    servers:
      - name: web1
        address: 192.168.1.101
        weight: 100
      - name: web2
        address: 192.168.1.102
        weight: 100
```

See `vars/sample_backends.yml` for more examples.

### SSL Configuration

```yaml
ssl_enabled: true
ssl_cert_path: /etc/ssl/certs
ssl_key_path: /etc/ssl/private
ssl_ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256"
ssl_min_version: "TLSv1.2"
```

### Statistics Configuration

```yaml
stats_enabled: true
stats_port: 8404
stats_uri: /stats
stats_user: admin
stats_password: "{{ vault_haproxy_stats_password }}"
```

## Dependencies

None.

## Example Playbook

```yaml
- hosts: loadbalancers
  roles:
    - role: profile_haproxy
      vars:
        ssl_enabled: true
        stats_enabled: true
```

## License

MIT

## Author Information

Created by Your Organization