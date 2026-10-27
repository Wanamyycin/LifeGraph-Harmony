param(
  [string]$StudioHome = 'F:/DevEco Studio',
  [ValidateSet('default', 'ohosTest')][string]$Target = 'default',
  [ValidateSet('debug', 'release')][string]$BuildMode = 'debug',
  [switch]$AppPack
)

$ErrorActionPreference = 'Stop'
if ($AppPack -and ($Target -ne 'default' -or $BuildMode -ne 'release')) {
  throw 'APP packaging requires -Target default -BuildMode release.'
}
$taskProject = Split-Path -Parent $PSScriptRoot
$taskNode = Join-Path $StudioHome 'tools/node/node.exe'
$taskHvigor = Join-Path $StudioHome 'tools/hvigor/hvigor/bin/hvigor.js'
$taskPlugin = Join-Path $StudioHome 'tools/hvigor/hvigor-ohos-plugin/package.json'
if (!(Test-Path -LiteralPath $taskNode) -or !(Test-Path -LiteralPath $taskHvigor)) {
  throw "DevEco tools were not found in $StudioHome. Pass -StudioHome with your installation directory."
}

# Reuse the dependency links already managed by DevEco; do not install packages
# or change the IDE installation. The wrapper otherwise tries to download pnpm.
$taskPluginVersion = (Get-Content -LiteralPath $taskPlugin -Raw | ConvertFrom-Json).version
$taskCacheRoot = Join-Path $env:USERPROFILE '.hvigor/project_caches'
$taskDependencyPath = $null
foreach ($taskCache in (Get-ChildItem -LiteralPath $taskCacheRoot -Directory -ErrorAction SilentlyContinue)) {
  $taskModules = Join-Path $taskCache.FullName 'workspace/node_modules'
  $taskCandidate = Join-Path $taskModules '@ohos/hvigor-ohos-plugin/package.json'
  if (Test-Path -LiteralPath $taskCandidate) {
    $taskCandidateVersion = (Get-Content -LiteralPath $taskCandidate -Raw | ConvertFrom-Json).version
    if ($taskCandidateVersion -eq $taskPluginVersion) {
      $taskDependencyPath = $taskModules
      break
    }
  }
}
if (!$taskDependencyPath) {
  throw 'No matching DevEco dependency cache was found. Open this project in DevEco and finish Sync first.'
}

$taskEnvNames = @('NODE_HOME', 'JAVA_HOME', 'DEVECO_SDK_HOME', 'NODE_PATH', 'HVIGOR_USER_HOME', 'PATH')
$taskPreviousEnv = @{}
foreach ($taskEnvName in $taskEnvNames) {
  $taskPreviousEnv[$taskEnvName] = [Environment]::GetEnvironmentVariable($taskEnvName, 'Process')
}
$taskExit = 1
Push-Location -LiteralPath $taskProject
try {
  $env:NODE_HOME = Join-Path $StudioHome 'tools/node'
  $env:JAVA_HOME = Join-Path $StudioHome 'jbr'
  $env:DEVECO_SDK_HOME = Join-Path $StudioHome 'sdk'
  $env:NODE_PATH = $taskDependencyPath
  $env:HVIGOR_USER_HOME = Join-Path $taskProject '.hvigor-direct'
  $env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:NODE_HOME + ';' + $env:PATH
  New-Item -ItemType Directory -Path (Join-Path $taskProject 'evidence') -Force | Out-Null
  $taskLogName = if ($AppPack) { 'build-release-app.log' } elseif ($BuildMode -eq 'release') { 'build-release-' + $Target + '.log' } else { 'build-' + $Target + '.log' }
  $taskLog = Join-Path $taskProject ('evidence/' + $taskLogName)
  $taskArguments = if ($AppPack) {
    @('--mode', 'project', '-p', 'product=default', '-p', 'buildMode=release', 'assembleApp', '--no-daemon', '--no-parallel')
  } else {
    @('--mode', 'module', '-p', 'product=default', '-p', "module=entry@$Target", '-p', "buildMode=$BuildMode", 'assembleHap', '--no-daemon', '--no-parallel')
  }
  & $taskNode $taskHvigor @taskArguments 2>&1 |
    Tee-Object -FilePath $taskLog
  $taskExit = $LASTEXITCODE
} finally {
  Pop-Location
  foreach ($taskEnvName in $taskEnvNames) {
    [Environment]::SetEnvironmentVariable($taskEnvName, $taskPreviousEnv[$taskEnvName], 'Process')
  }
}
exit $taskExit
