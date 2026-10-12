# Linux Upstream Patch Status

Last checked: **2026-10-12**. See [the full upstream status record](../../../docs/upstream-status.md).

The `8086:6f00` P2PDMA whitelist patch was submitted and the PCI maintainer reported it applied to the `pci/p2pdma` tree for the Linux v7.4 merge window on 2026-10-07. At this check it was **not yet in Linus' mainline tree or a released kernel**. “Maintainer applied” does not mean merged or released.

Files in this directory:

- `0001-broadwell-6f00-p2pdma-candidate.diff`: retained patch artifact. Its filename reflects its original role; it is the patch reported applied by the maintainer.
- `UPSTREAM_COMMIT_MESSAGE.txt`, `UPSTREAM_GET_MAINTAINER.txt`: retained submission materials.
- `UPSTREAM_SUBMISSION_DRAFT.txt`, `UPSTREAM_PATCH_CHECKPATCH.txt`: historical snapshots from 2026-09-28. Their pending-submission conclusion is superseded by the current status above.

The task brief supplied PCI-tree commit ID `e7b44579a6b4495c03720da49f2eeaf13a94ba69`; this checkout did not independently resolve it as a Git object. Use the mailing-list record as the status evidence until the corresponding tree commit can be verified directly.
