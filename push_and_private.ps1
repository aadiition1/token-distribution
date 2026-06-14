# One-shot: commit, push, and optionally make repo private via gh (PowerShell)
# Copy-paste into PowerShell in your repo root and press Enter.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n== One-shot: add/commit/push & optional make-private ==" -ForegroundColor Cyan

# Show current status
git status --porcelain --branch
Write-Host ""

# Optionally set git identity
$setIdentity = Read-Host "Do you want to (re)configure git user.name/user.email? (yes/no) [no]"
if ($setIdentity -match '^(yes|y)$') {
  $name = Read-Host "Enter git user.name (e.g. ADEEL AHMAD)"
  $email = Read-Host "Enter git user.email (e.g. you@example.com)"
  if ($name) { git config --global user.name "$name"; Write-Host "git user.name set to $name" }
  if ($email) { git config --global user.email "$email"; Write-Host "git user.email set to $email" }
  Write-Host ""
}

# Detect changes
$status = git status --porcelain
if ([string]::IsNullOrWhiteSpace($status)) {
  Write-Host "Working tree clean (no staged/unstaged changes)." -ForegroundColor Green
} else {
  Write-Host "Uncommitted changes detected:" -ForegroundColor Yellow
  git status --short
  $doAdd = Read-Host "Stage all changes and commit them? (yes/no) [yes]"
  if ($doAdd -eq "" -or $doAdd -match '^(yes|y)$') {
    git add .
    $msg = Read-Host "Enter commit message [Add token distribution suite and wizards]"
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "Add token distribution suite and one-shot wizards" }
    git commit -m "$msg"
    Write-Host "Committed changes." -ForegroundColor Green
  } else {
    Write-Host "Skipping commit." -ForegroundColor Yellow
  }
}

# Push current branch
$branch = git rev-parse --abbrev-ref HEAD
Write-Host "`nPushing branch '$branch' to origin..." -ForegroundColor Cyan
try {
  git push origin $branch
  Write-Host "Push successful." -ForegroundColor Green
} catch {
  Write-Host "git push failed: $_" -ForegroundColor Red
  Write-Host "Attempting to pull/rebase and retry..." -ForegroundColor Yellow
  git pull --rebase origin $branch
  git push origin $branch
  Write-Host "Push after pull/rebase successful." -ForegroundColor Green
}

# Optionally make repo private using gh
$doPrivate = Read-Host "`nMake repository private now using GitHub CLI (gh)? (yes/no) [no]"
if ($doPrivate -match '^(yes|y)$') {
  # Check gh
  try {
    & gh --version > $null
  } catch {
    Write-Host "GitHub CLI (gh) not found. Install from https://cli.github.com/ and authenticate with 'gh auth login'." -ForegroundColor Red
    exit 1
  }

  # Ensure authenticated
  try {
    & gh auth status --show-token 2>$null
  } catch {
    Write-Host "You are not authenticated in gh. Running 'gh auth login' now..." -ForegroundColor Yellow
    gh auth login
  }

  # Make private
  $repo = git remote get-url origin 2>$null
  if (-not $repo) {
    Write-Host "Cannot determine remote 'origin' URL. Aborting make-private." -ForegroundColor Red
    exit 1
  }

  # Normalize owner/repo from remote URL
  function Get-OwnerRepo($remoteUrl) {
    if ($remoteUrl -match 'github\.com[:/](.+?)(\.git)?$') { return $matches[1] }
    return $null
  }
  $ownerRepo = Get-OwnerRepo $repo
  if (-not $ownerRepo) {
    Write-Host "Could not parse owner/repo from remote URL: $repo" -ForegroundColor Red
    exit 1
  }

  Write-Host "Setting repository '$ownerRepo' to private..." -ForegroundColor Cyan
  try {
    gh repo edit $ownerRepo --visibility private
    Write-Host "Repository visibility set to private." -ForegroundColor Green
  } catch {
    Write-Host "gh repo edit failed: $_" -ForegroundColor Red
    Write-Host "Ensure your gh user has admin access to the repository." -ForegroundColor Yellow
    exit 1
  }
}

Write-Host "`nAll done." -ForegroundColor Cyan