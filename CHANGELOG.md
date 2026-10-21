# Changelog

All notable changes are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Repository foundation: Apache-2.0 license, contribution process, PR and issue templates, CODEOWNERS.
- CI quality gates: PSScriptAnalyzer with InjectionHunter, Pester on Ubuntu and Windows, markdown lint and link check.
- Security gates: gitleaks, Trivy, CodeQL, actionlint, zizmor, dependency review, PowerShell module audit, AI security review.
- Release pipeline with SBOM and build provenance attestation; deploy pipeline scaffold for Windows servers.
- Concept for identity and access as code (YAML desired state, providers with permission schemas, registry, plan and apply), person files, configurable approval chains, workspaces per site or line of business, notifier plugins, ADRs 0001–0008, sample configuration in `examples/`, and clickable mockups.
