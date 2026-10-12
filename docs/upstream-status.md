# Linux PCI/P2PDMA Upstream Status

Last checked: **2026-10-12**

## State

The Linux PCI maintainer reported on 2026-10-07 that the Broadwell-EP `8086:6f00` whitelist patch had been applied to the `pci/p2pdma` development tree for the Linux v7.4 merge window. This is **MAINTAINER_APPLIED**. It is not evidence that the change has reached Linus Torvalds' tree or a released kernel.

At the last check, kernel.org listed Linux `7.3-rc6` as the current mainline release candidate, and the current `torvalds/linux` `drivers/pci/p2pdma.c` did not contain `8086:6f00`. Therefore:

| Milestone | Status | Evidence |
| --- | --- | --- |
| Submitted | YES | [Linux PCI mailing-list thread](https://lkml.iu.edu/2610.0/13348.html), dated 2026-10-07 |
| Maintainer applied | YES | Bjorn Helgaas wrote “Applied to pci/p2pdma for v7.4, thanks!” in that thread |
| Merged to Linus | NO, not present at this check | [Current mainline source](https://github.com/torvalds/linux/blob/master/drivers/pci/p2pdma.c) lacks the `8086:6f00` entry |
| Released | NO, not present in a released Linux version at this check | [Kernel.org releases](https://www.kernel.org/) listed `7.3-rc6`, before the planned v7.4 merge window completed |

The mail subject is `[PATCH] PCI/P2PDMA: Add Intel 0x6f00 host bridge to whitelist`; the change adds Intel vendor/device `8086:6f00` with `REQ_SAME_HOST_BRIDGE`. The task brief supplied commit identifier `e7b44579a6b4495c03720da49f2eeaf13a94ba69`. The mailing-list application notice verifies the patch status and content; this repository has not independently resolved that identifier to a Git object, so treat it as a reported PCI-tree commit ID rather than a verified mainline SHA.

## Repository patch files

- [`patches/linux/validated/`](../patches/linux/validated/README.md) retains the original Ubuntu 6.8.0-139 validation patch. It is an older, locally validated kernel patch and is not replaced by the upstream submission.
- [`patches/linux/upstream/`](../patches/linux/upstream/README.md) contains the upstream patch artifact and current status pointer.
- `UPSTREAM_SUBMISSION_DRAFT.txt` and `UPSTREAM_PATCH_CHECKPATCH.txt` are retained as **historical preparation snapshots**. Their September 2026 pending-submission wording is stale and is superseded by this document and `patches/linux/upstream/README.md`.

Do not describe “applied to `pci/p2pdma`” as “merged”, “released”, or “available in v7.4”. Recheck the merge commit and release contents before changing those states.
