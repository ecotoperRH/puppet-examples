## GitHub Actions CI Integration

All migrated Ansible projects must include a GitHub Actions workflow that runs `ansible-lint` on every pull request. No code reaches `main` without passing lint.

Include this workflow in `.github/workflows/ansible-ci.yml`:

```yaml
name: Ansible CI
on:
  pull_request:
    branches: [main]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install ansible-lint
      - run: ansible-lint roles/ --strict
```