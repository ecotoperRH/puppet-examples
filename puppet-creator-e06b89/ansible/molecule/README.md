# Running generated Molecule scenarios

Install Podman on the controller and Ansible/Molecule in the same Python environment.
No Molecule driver plugins are required. For a uv-managed environment:

```bash
uv pip install --python "$(command -v python)" ansible-core 'molecule>=25.9.0'
ANSIBLE_COLLECTIONS_PATH="$PWD/collections" \
  ansible-galaxy collection install -r molecule/requirements.yml
molecule test --scenario-name <module>
# Explicit cleanup after an interrupted run:
molecule destroy --scenario-name <module>
```

Run from the Ansible project root. The Ansible-native scenario uses standard
`inventory/hosts.yml` and the `containers.podman.podman` connection. Local lifecycle
playbooks create containers with `containers.podman.podman_container`, inspect
readiness with `containers.podman.podman_container_info`, and remove them on destroy.
There is no driver-managed inventory or external Molecule driver plugin.

Scenarios create privileged, disposable Linux containers; use a dedicated test
controller and never point them at production inventory. Names are scoped to the
project checkout and role. Do not run the same scenario concurrently in one checkout;
use separate generated projects. Destroy containers before moving/deleting a project.
Set `X2A_MOLECULE_IMAGE` to another Linux image with systemd at `/sbin/init` and a
supported `dnf` or `apt-get` package manager. Systemd mode is enabled. Python is
bootstrapped before connection checks and the actual project deployment playbook.
The test sequence destroys stale containers first and removes them after verification.

The converter generates and statically validates scenarios but does not execute
them; developer/CI results are the runtime acceptance signal. Windows hosts require
a separate future profile.

Reference: https://docs.ansible.com/projects/molecule/examples/podman/
