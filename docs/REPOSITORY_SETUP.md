# Remote And Branch Protection Setup

## 1. Create Remote Repository

Create an empty repository in GitHub/GitLab/Bitbucket, then connect it:

```bash
git remote add origin <your-repo-url>
git push -u origin main --tags
```

## 2. Enable Branch Protection On `main`

Configure branch protection for `main` with these minimum rules:

- Require pull request before merging
- Require at least 1 approval (recommended even for solo development)
- Restrict direct pushes to `main`
- Require linear history (recommended)
- Require status checks before merge (if CI is added)

## 3. Daily Development Flow

```bash
git checkout -b feature/<short-description>
# work, commit, push, open PR
git checkout main
git pull
```

## 4. Hotfix Flow

```bash
git checkout -b hotfix/<short-description> main
# fix, test, commit, push, open PR
```
