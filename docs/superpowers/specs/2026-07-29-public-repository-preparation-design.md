# Public Repository Preparation Design

**Date:** 2026-07-29

## Goal

Prepare SleepDaddy for public release under the MIT License while removing
machine-specific artifacts and avoiding unnecessary git-history rewriting.

## Repository Licensing

- Add the standard MIT License in a root-level `LICENSE` file, with Kevin
  Miller as the copyright holder and 2026 as the copyright year.
- Update the README license section to link to the MIT License.
- Apply the MIT License to the entire repository, including application artwork
  and other assets.

## Metadata Cleanup

- Remove the tracked `.superpowers` execution report that records local
  filesystem paths and image-generation working locations.
- Remove the local `.claude` directory from the working tree.
- Keep `.claude/settings.local.json` ignored so machine-specific permissions
  cannot be committed again.
- Do not rewrite git history. The historical Claude settings file contains no
  credentials, and the author name and email are accepted public metadata.

## Signing Configuration

- Remove the hard-coded Apple development team identifier from the shared base
  settings in `project.yml`.
- Store the developer's local `DEVELOPMENT_TEAM` assignment in an untracked
  `.env.local` file and add `.env.local` to `.gitignore`.
- Update `generate.sh` to load `.env.local` for local project generation while
  continuing to accept `DEVELOPMENT_TEAM` from the process environment in CI.
- Document `.env.local` as the local signing configuration file without
  publishing its value.
- Verify that project generation and unsigned simulator builds do not require
  the removed shared default.

## Security Documentation

- Add a concise root-level `SECURITY.md`.
- Direct vulnerability reports to GitHub private vulnerability reporting rather
  than public issues.
- State that supported-version information is maintained through the latest
  version on the default branch.

## Verification

- Confirm ignored local and credential file patterns remain effective.
- Confirm `.env.local` supplies the local development team without becoming a
  tracked file.
- Scan tracked content and git history again for common secret formats.
- Generate the Xcode project and run the existing test suite.
- Review the final diff to ensure unrelated and pre-existing untracked files
  were not changed.

## Out of Scope

- Rewriting commit history.
- Changing GitHub repository visibility or security settings.
- Rotating credentials, because the audit found no committed credential values.
- Changing application behavior or HealthKit access.
