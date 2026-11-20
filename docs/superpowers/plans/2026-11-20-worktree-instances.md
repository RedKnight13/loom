# Worktree instance implementation

1. Add an idempotent worktree setup script and bind the instance before
   routing, calibration and direct legacy operations.
2. Namespace worker destinations at dispatch and preserve the selected names
   for subsequent operations.
3. Update bootstrap and session entry to select the consumer worktree.
4. Exercise setup twice, two linked worktrees using one ticket and one worker
   pool, explicit overrides, and selection from a subdirectory.
