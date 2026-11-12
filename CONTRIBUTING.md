# Contributing to Team Scaler MCA Project

Welcome! This guide explains the Git and GitHub workflow that every team member must follow when contributing to this repository.

## Toolchain

- **HDL:** Verilog
- **Simulation:** Icarus Verilog (`iverilog` / `vvp`)
- **Waveform Viewer:** GTKWave

---

## 1. Before Starting an Issue

1. **Switch to `main` and pull the latest changes** from the remote repository so your work starts from an up-to-date baseline:

   ```bash
   git checkout main
   git pull origin main
   ```

2. **Read the selected issue carefully** on GitHub. Make sure you understand the requirements, interfaces, and acceptance criteria, and work **only** on that issue.
3. **Create a new branch for every issue** before making any edits. **Never make commits directly to `main`.**
4. **Use a descriptive branch name** that includes the issue number, for example:
   - `feature/issue-<number>-short-description`
   - `fix/issue-<number>-short-description`
   - `docs/issue-<number>-short-description`

   Example:

   ```bash
   git checkout -b feature/issue-2-program-counter
   ```

---

## 2. While Working

- **Follow the project specifications and existing folder structure** (`rtl/`, `testbench/`, `programs/`, `simulation/`, `reports/`, `docs/`).
- **Keep changes limited to the selected issue.** Do not include unrelated cleanups, refactors, or files from other issues.
- **Coordinate interface or dependency changes** (such as module ports, shared parameters, or pipeline register signals) with the relevant team members before modifying them.
- **Test your changes before submitting them** (for example, by compiling with Icarus Verilog, running the relevant testbench, and inspecting waveforms in GTKWave where applicable).
- **Use clear, meaningful commit messages** and include the issue number when practical:

  ```bash
  git status
  git add <files-for-this-issue>
  git commit -m "Implement PC module (#2)"
  ```

---

## 3. Submitting Work

1. **Push your issue-specific branch to GitHub:**

   ```bash
   git push -u origin <your-branch-name>
   ```

   Example:

   ```bash
   git push -u origin feature/issue-2-program-counter
   ```

2. **Open a Pull Request (PR) targeting `main`** on GitHub and fill out the Pull Request template completely.
3. **Link the related issue** using `Closes #<issue-number>` **only** when the PR fully completes that issue. (If a PR only partially addresses an issue, reference `#<issue-number>` without `Closes`.)
4. **Describe the changes clearly**, including affected modules/files and the tests or verification steps performed.
5. **Request review** from the team leader / repository owner, `WizardCarp85`.
6. **Address any requested changes** on the same branch, push your updates, and wait for approval.
7. **Do not merge your own PR.** Only the team leader / repository owner (`WizardCarp85`) merges approved PRs into `main`.

---

## 4. Keeping Your Branch Up to Date

If `main` receives new commits while you are working on your issue branch, bring the latest `main` changes into your branch before opening or updating your PR:

```bash
# 1. Fetch the latest changes from origin
git fetch origin

# 2. Make sure you are on your issue branch
git checkout <your-branch-name>

# 3. Merge the latest origin/main into your issue branch
git merge origin/main
```

### Resolving Merge Conflicts

If Git reports merge conflicts:

1. Run `git status` to see which files have conflicts.
2. Open each conflicted file and inspect the conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).
3. Carefully combine the changes so neither your work nor the updates from `main` are lost, and remove all conflict markers.
4. **Test your changes again** after resolving conflicts (re-compile and re-run relevant testbenches) before committing the merge resolution.
5. Stage and commit the resolved files, then push your updated branch:

   ```bash
   git add <resolved-files>
   git commit -m "Merge main into <your-branch-name> and resolve conflicts"
   git push
   ```
