# 0004: Sign-in with Entra ID and Active Directory

- Status: Accepted
- Date: 2026-10-21

## Context

Some organizations are cloud-first with Entra ID, others are on-premises AD only, and many are both. IAMasC is a privileged tool, so who can do what must come from groups the organization already manages.

## Decision

Support both methods, each switchable in config:

- Entra ID through OpenID Connect (Pode's Azure AD scheme), roles from the `groups` claim.
- Active Directory through Pode's Windows AD form authentication (LDAP bind), roles from group membership.

Roles map from configurable groups: Admin, HR, ITOperator, Auditor (read only). Sessions are server-side with secure, HTTP-only cookies and CSRF protection on every form.

## Consequences

- Entra sign-in brings MFA and conditional access for free. AD form sign-in doesn't, so the docs recommend Entra wherever it exists.
- AD form sign-in works from Linux too, so it survives the container move.
- Kerberos single sign-on is left for later.

## Alternatives considered

- Local accounts in the database: another password store to protect, and no MFA.
- Windows integrated (Negotiate) only: Windows-hosted and domain-joined clients only.
