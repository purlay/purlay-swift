# The stable entry point. scripts/verify holds the lanes (and `scripts/verify <lane>` runs one); this file only names them.
.PHONY: setup verify verify-security verify-all

# What a pull request needs: every lane that checks the code, without the secret scan (its own target, its own CI job).
verify:
	scripts/verify rules
	scripts/verify generated
	scripts/verify test
	scripts/verify ios

# The history holds no secret.
verify-security:
	scripts/verify security

# Every lane, as a release runs them.
verify-all:
	scripts/verify

# The pinned contract bundle and the pinned scanner. Network.
setup:
	scripts/prepare-contract
	scripts/install-gitleaks
