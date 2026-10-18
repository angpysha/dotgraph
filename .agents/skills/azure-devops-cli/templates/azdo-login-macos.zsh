# macOS Keychain login helper for Azure DevOps CLI
#
# One-time setup:
#   security add-generic-password -a "$USER" -s AZDO_PAT -w "YOUR_PAT" -U
#
# Add to ~/.zshrc:
#   export AZDO_ORG=petrovskyitools
#   source /path/to/repo/.cursor/skills/azure-devops-cli/templates/azdo-login-macos.zsh
#
# Usage:
#   azdo-login
#   pwsh .cursor/skills/azure-devops-cli/scripts/ensure-azure-devops.ps1

azdo-login() {
  local org="${AZDO_ORG:-petrovskyitools}"
  export AZURE_DEVOPS_EXT_PAT="$(security find-generic-password -s AZDO_PAT -w)"
  az devops login --organization "https://dev.azure.com/${org}"
}
