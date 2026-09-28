# Security Policy

## Reporting Security Issues
If you discover a potential security vulnerability in this project (e.g. secret leakage, memory corruption in diagnostic utilities, or privilege escalation risks), please do not report it publicly via GitHub Issues.

Instead, please send an encrypted or private email report to the project maintainers.

## Operational Safety Principles
- All diagnostic scripts in this repository default to **read-only** execution.
- No script will reboot the host, overwrite device firmware, reset PCIe buses, or reflash BIOS.
- Applying kernel or RCCL patches should only be done in testing or staging environments with proper recovery procedures in place.
