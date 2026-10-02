# Isolation tests

The reference state is `hello-working-fixed`. Each test starts with a host
rollback to that snapshot and changes exactly one candidate. Never run the two
test scripts successively on the same guest state.

## Test A

Run `X:\tests\test-signedchain-on.cmd`. It sets
`RequireMicrosoftSignedBootChain=1`, `SystemGuard=0`, VBS=0 and keeps the
hypervisor launch type off. A successful boot makes SignedBootChain compatible;
a failure confirms it is incompatible or contributes to the failure.

## Test B

Run `X:\tests\test-systemguard-on.cmd`. It sets `SystemGuard=1`,
`RequireMicrosoftSignedBootChain=0`, VBS=0 and keeps the hypervisor launch type
off. A successful boot makes SystemGuard alone compatible; a failure confirms
it is incompatible or contributes to the failure.

Neither script reboots automatically. On failure, power off and roll back to
`hello-working-fixed` before any other action.
