# CI/CD Workflows

This directory contains GitHub Actions workflows for automated testing and quality assurance.

## Workflows

### 🚀 CI (Minimal) - `ci.yml`

**Runs on**: Every push and pull request to `main`

**Purpose**: Fast feedback loop for development

**What it does**:
- ✅ Syntax check all shell scripts (~5 seconds)
- ✅ Run core library tests (cmd.sh) (~10 seconds)
- ✅ Shellcheck for critical errors only

**Duration**: ~30 seconds

**Use case**: Quick validation during development

---

### 🔬 Comprehensive Tests - `comprehensive.yml`

**Runs on**:
- Manual trigger (workflow_dispatch)
- Weekly schedule (Sundays at 2 AM UTC)

**Purpose**: Thorough validation and reporting

**What it does**:
- ✅ Run **all 102 tests** on Linux
- ✅ Run **all 102 tests** on macOS (including launchd tests)
- ✅ Comprehensive shellcheck (all severity levels)
- ✅ Test coverage analysis
- ✅ Integration checks
- ✅ Documentation consistency verification

**Duration**: ~5-10 minutes

**Artifacts generated**:
- Test reports (Linux & macOS)
- Shellcheck report
- Coverage analysis
- Retained for 90 days

**Use case**: Pre-release validation, quality audits

---

## Running Workflows Manually

### Trigger Comprehensive Tests

```bash
# Via GitHub CLI
gh workflow run comprehensive.yml

# Via GitHub web UI
# Actions → Comprehensive Tests → Run workflow
```

### View Workflow Status

```bash
gh run list --workflow=ci.yml
gh run list --workflow=comprehensive.yml
```

### Download Artifacts

```bash
gh run download <run-id>
```

---

## CI Strategy

### Fast Feedback (ci.yml)
- **Goal**: Catch obvious errors quickly
- **Scope**: Essential validations only
- **Frequency**: Every commit
- **Trade-off**: Speed over thoroughness

### Deep Validation (comprehensive.yml)
- **Goal**: Comprehensive quality assurance
- **Scope**: All tests, all platforms, all checks
- **Frequency**: On-demand and weekly
- **Trade-off**: Thoroughness over speed

---

## Test Coverage

Current test coverage:
- **102 tests** across 5 libraries
- **100% library coverage**
- **Multi-platform**: Linux + macOS
- **Platform-aware**: macOS-specific tests skip on Linux

### Test Breakdown

| Library | Tests | Platform |
|---------|-------|----------|
| cmd.sh | 20 | All |
| dryrun.sh | 19 | All |
| json.sh | 25 | All |
| pkg.sh | 18 | All |
| launchd.sh | 20 | macOS only |

---

## Quality Gates

### Minimal CI (ci.yml)
- ✅ All scripts must have valid syntax
- ✅ Core tests must pass
- ✅ No critical shellcheck errors

### Comprehensive (comprehensive.yml)
- ✅ All 102 tests must pass on Linux
- ✅ All 102 tests must pass on macOS
- ✅ No shellcheck issues (style level)
- ✅ Documentation up to date
- ✅ Library dependencies correct

---

## Debugging Failed Workflows

### Syntax Errors
```bash
# Reproduce locally
bash -n scripts/problematic-script.sh
```

### Test Failures
```bash
# Run specific test locally
bats tests/lib/failing-test.bats

# Run all tests
bats tests/lib/*.bats
```

### Shellcheck Issues
```bash
# Check locally
shellcheck scripts/*.sh scripts/lib/*.sh

# Check with same severity as CI
shellcheck -S error scripts/*.sh  # Minimal CI
shellcheck -S style scripts/*.sh  # Comprehensive
```

---

## Adding New Tests

When adding new tests:
1. Add test file: `tests/lib/newlib.bats`
2. CI automatically picks it up
3. Minimal CI runs fast core tests
4. Comprehensive CI runs all tests including new ones

No workflow changes needed! 🎉

---

## Workflow Files

- `ci.yml` - Minimal fast CI for every commit
- `comprehensive.yml` - Thorough testing on-demand and weekly

---

## Best Practices

1. **Let minimal CI run** on every PR before merging
2. **Run comprehensive tests** before releases
3. **Check artifacts** for detailed reports
4. **Fix shellcheck warnings** proactively
5. **Keep tests fast** - minimal CI should complete in <1 minute

---

## Maintenance

### Update Dependencies
- Workflows use pinned action versions (v4)
- Review and update quarterly
- Test locally before updating

### Adjust Test Scope
- Minimal CI: Only essential tests for speed
- Comprehensive: All tests for completeness
- Balance based on your needs
