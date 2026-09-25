# setup-ssh-key.ps1 - one-time passwordless SSH from this PC to PI_GPS.
# Run in a normal PowerShell window (NOT PowerShell ISE): step 2 asks "yes/no"
# and for the Pi's password, and ISE cannot show those prompts.

$Pi  = 'pigps@pigps.local'
$Key = "$env:USERPROFILE\.ssh\id_ed25519"

# 1. Create a key if there isn't one (default location, no passphrase)
if (-not (Test-Path $Key)) {
    New-Item -ItemType Directory -Force (Split-Path $Key) | Out-Null
    ssh-keygen -t ed25519 -f $Key -N '""'
}

# 2. Copy the public key to the Pi (asks for the Pi password one last time)
Get-Content "$Key.pub" | ssh $Pi "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"

# 3. Test: should print "pigps" with no password prompt
ssh -o BatchMode=yes $Pi whoami
