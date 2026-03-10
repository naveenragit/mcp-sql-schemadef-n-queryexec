# ============================================
# Test SQL MCP Server Container Locally
# ============================================
#
# Prerequisites:
#   - Docker Desktop running
#   - Access to the sql-demos Azure SQL Server
#
# NOTE: Managed Identity does NOT work from a local container.
#       This script uses SQL Authentication for local testing only.
#       You'll need a SQL login with read access to the Northwind DB.
# ============================================

param(
    [Parameter(Mandatory=$true)]
    [string]$SqlUser,

    [Parameter(Mandatory=$true)]
    [SecureString]$SqlPassword
)

$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlPassword)
$PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

$CONNECTION_STRING = "Server=tcp:sql-demos.database.windows.net,1433;Initial Catalog=Northwind;User ID=$SqlUser;Password=$PlainPassword;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Building SQL MCP Server container"     -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

docker build -t sql-mcp-server:local .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker build failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Starting container on port 5000"       -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Stop any existing instance
docker rm -f sql-mcp-local 2>$null

docker run -d `
    --name sql-mcp-local `
    -p 5000:5000 `
    -e "MSSQL_CONNECTION_STRING=$CONNECTION_STRING" `
    sql-mcp-server:local

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start container." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Container started. Waiting for it to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 8

# Health check with retries
$healthy = $false
for ($i = 1; $i -le 5; $i++) {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:5000/health" -Method Get -TimeoutSec 5
        Write-Host "Health check passed!" -ForegroundColor Green
        $healthy = $true
        break
    } catch {
        Write-Host "  Attempt $i/5 - not ready yet, retrying in 5s..." -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
}

Write-Host ""
if ($healthy) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " Container is running!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "Container may still be starting. Check logs:" -ForegroundColor Yellow
    Write-Host "  docker logs sql-mcp-local" -ForegroundColor White
}

Write-Host ""
Write-Host "Endpoints:" -ForegroundColor Cyan
Write-Host "  Health:  http://localhost:5000/health" -ForegroundColor White
Write-Host "  MCP:     http://localhost:5000/mcp" -ForegroundColor White
Write-Host ""
Write-Host "VS Code MCP config (add to .vscode/mcp.json):" -ForegroundColor Cyan
Write-Host '  {' -ForegroundColor White
Write-Host '    "servers": {' -ForegroundColor White
Write-Host '      "northwind-local": {' -ForegroundColor White
Write-Host '        "type": "http",' -ForegroundColor White
Write-Host '        "url": "http://localhost:5000/mcp"' -ForegroundColor White
Write-Host '      }' -ForegroundColor White
Write-Host '    }' -ForegroundColor White
Write-Host '  }' -ForegroundColor White
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Cyan
Write-Host "  docker logs sql-mcp-local          # View logs" -ForegroundColor White
Write-Host "  docker logs -f sql-mcp-local       # Follow logs" -ForegroundColor White
Write-Host "  docker stop sql-mcp-local          # Stop container" -ForegroundColor White
Write-Host "  docker rm -f sql-mcp-local         # Remove container" -ForegroundColor White
Write-Host ""
