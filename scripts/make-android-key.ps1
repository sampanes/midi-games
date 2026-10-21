# Makes the Android release signing key for Key Games, once, and the files
# that use it. Nothing it writes is committed (private/ and key.properties
# are ignored by Git):
#
#   private/keys/key-games.jks               the keystore
#   apps/key_games/android/key.properties    read by the Android release build
#   private/keys/github-secrets.txt          the values for the release workflow
#   private/keys/set-github-secrets.ps1      puts them in the repository's secrets
#
# BACK UP private/keys. A build signed with another key cannot install over
# one signed with this key, and a lost key cannot be made again.
#
#   .\scripts\make-android-key.ps1
#
# Refuses to replace an existing keystore unless -Force is given.

param(
  [string]$Alias = 'key-games',
  [switch]$Force
)
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$keys = Join-Path $root 'private\keys'
$jks = Join-Path $keys 'key-games.jks'
$props = Join-Path $root 'apps\key_games\android\key.properties'
$secrets = Join-Path $keys 'github-secrets.txt'
$setter = Join-Path $keys 'set-github-secrets.ps1'

if ((Test-Path $jks) -and -not $Force) {
  throw "$jks exists. Pass -Force to replace it; builds signed with the old key will then no longer update in place."
}

# keytool from the PATH, else the JDK bundled with Android Studio.
$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool) {
  $jbr = Join-Path $env:ProgramFiles 'Android\Android Studio\jbr\bin\keytool.exe'
  if (Test-Path $jbr) { $keytool = $jbr }
}
if (-not $keytool) { throw 'keytool not found: install a JDK or Android Studio.' }

New-Item -ItemType Directory -Force $keys | Out-Null

# One random password for the store and the key (a PKCS12 keystore keeps
# them the same anyway).
$bytes = New-Object byte[] 24
(New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
$password = ([Convert]::ToBase64String($bytes)) -replace '[+/=]', 'x'

# keytool talks on stderr even when all is well, so its output is left alone
# (a 2>&1 here would turn it into errors under Windows PowerShell).
& $keytool -genkeypair -keystore $jks -storetype PKCS12 -alias $Alias -keyalg RSA -keysize 2048 `
  -validity 10000 -storepass $password -keypass $password -dname 'CN=Key Games'
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $jks)) { throw 'keytool failed to make the keystore.' }

# Relative to apps/key_games/android/app, where the build resolves it.
@"
storeFile=../../../../private/keys/key-games.jks
storePassword=$password
keyAlias=$Alias
keyPassword=$password
"@ | Set-Content -Encoding ascii $props

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($jks))
@"
Repository secrets for .github/workflows/release.yml. Add them on GitHub under
Settings > Secrets and variables > Actions > New repository secret, or run
set-github-secrets.ps1 (next to this file) with the GitHub CLI logged in as
the repository owner.

ANDROID_KEYSTORE_BASE64
$b64

ANDROID_KEYSTORE_PASSWORD
$password

ANDROID_KEY_ALIAS
$Alias

ANDROID_KEY_PASSWORD
$password
"@ | Set-Content -Encoding ascii $secrets

@"
# Puts the Android signing key in the repository's Actions secrets, for
# .github/workflows/release.yml. Needs the GitHub CLI logged in as an owner
# of the repository (gh auth login). Made by scripts/make-android-key.ps1.
`$ErrorActionPreference = 'Stop'
Set-Location '$root'
`$repo = 'sampanes/midi-games'
`$who = gh api user --jq .login
if (`$LASTEXITCODE -ne 0) { throw 'gh is not logged in: run gh auth login first.' }
Write-Host "setting secrets on `$repo as `$who"
gh secret set ANDROID_KEYSTORE_BASE64 --repo `$repo --body '$b64'
gh secret set ANDROID_KEYSTORE_PASSWORD --repo `$repo --body '$password'
gh secret set ANDROID_KEY_ALIAS --repo `$repo --body '$Alias'
gh secret set ANDROID_KEY_PASSWORD --repo `$repo --body '$password'
gh secret list --repo `$repo
"@ | Set-Content -Encoding ascii $setter

Write-Host "keystore:   $jks"
Write-Host "properties: $props"
Write-Host "secrets:    $secrets"
Write-Host "setter:     $setter"
Write-Host 'Back up private\keys now.'
