$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$env:NODE_ENV = 'production'
$env:PORT = '3000'

node backend/server/index.js
