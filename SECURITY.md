# Security reporting

Report suspected vulnerabilities through [GitHub private vulnerability reporting](https://github.com/RedKnight13/loom/security/advisories/new). Do not open a public issue containing exploit details or credentials.

Include the affected commit or version, environment, impact and a minimal reproduction with secrets removed. If credentials were exposed, revoke them through their provider.

Loom is under active development. Reports against current main are preferred; older releases do not have a separate maintenance commitment. There is no guaranteed response or remediation timeline.

Loom workspaces and process groups are not a security sandbox. Agent permissions, execution hosts and repository access must be configured for the trust level of the work. See the [supported workflows and known gaps](https://redknight13.github.io/loom/support.html).
