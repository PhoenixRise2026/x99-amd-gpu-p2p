# Security Policy

## Reporting Security Issues
If you discover a potential security vulnerability in this project (e.g. secret leakage, memory corruption in diagnostic utilities, or privilege escalation risks), please do not report it publicly via GitHub Issues.

Please report sensitive vulnerabilities using GitHub's Private Vulnerability Reporting mechanism once enabled on this repository.
Do not post credentials, secrets, or sensitive memory dumps in public GitHub issues.

## Operational Safety Principles
- All diagnostic scripts in this repository default to **read-only** execution.
- No script will reboot the host, overwrite device firmware, reset PCIe buses, or reflash BIOS.
- Applying kernel or RCCL patches should only be done in testing or staging environments with proper recovery procedures in place.
