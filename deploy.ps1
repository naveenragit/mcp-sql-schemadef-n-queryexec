# ============================================
# SQL MCP Server - Azure Container Apps Deployment
# Using Managed Identity Authentication
# ============================================
# 
# Prerequisites:
#   - Azure CLI installed (winget install Microsoft.AzureCLI)
#   - Logged in to Azure (az login)
#   - Dockerfile and dab-config.json in the current directory
#
# Usage:
#   1. Update the variables below
#   2. Run: .\deploy.ps1
#   3. After deployment, run grant-db-access.sql against your Northwind DB
# ============================================
 
param(
    [string]$TenantId = "",
    [string]$SubscriptionId = ""
)

# ============================================
# Variables - UPDATE THESE VALUES
# ============================================
$RESOURCE_GROUP       = "rg-sql-mcp-northwind"
$LOCATION             = "eastus"
$ACR_NAME             = "acrsqlmcpnw$(Get-Random -Minimum 1000 -Maximum 9999)"
$CONTAINERAPP_ENV     = "sql-mcp-northwind-env"
$CONTAINERAPP_NAME    = "sql-mcp-northwind"

# Your existing Azure SQL Server details
$SQL_SERVER           = "sql-demos"                    # Just the server name (without .database.windows.net)
$SQL_DATABASE         = "Northwind"

# Connection string for Managed Identity (no password needed)
$CONNECTION_STRING    = "Server=tcp:${SQL_SERVER}.database.windows.net,1433;Initial Catalog=${SQL_DATABASE};Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Managed Identity;"

# ============================================
# Sign in to Azure
# ============================================
if ($TenantId) {
    az login --tenant $TenantId
} else {
    Write-Host "Checking Azure login status..." -ForegroundColor Yellow
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        az login
    } else {
        Write-Host "Already logged in as: $($account.user.name)" -ForegroundColor Green
    }
}

if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
}

Write-Host ""
Write-Host "Current subscription:" -ForegroundColor Yellow
az account show --query "{Name:name, Id:id}" --output table

# ============================================
# Step 1: Create Resource Group
# ============================================
Write-Host ""
Write-Host "Step 1: Creating resource group '$RESOURCE_GROUP'..." -ForegroundColor Cyan

az group create `
    --name $RESOURCE_GROUP `
    --location $LOCATION `
    --output none

Write-Host "Resource group created." -ForegroundColor Green

# ============================================
# Step 2: Create Azure Container Registry
# ============================================
Write-Host ""
Write-Host "Step 2: Creating Azure Container Registry '$ACR_NAME'..." -ForegroundColor Cyan

az acr create `
    --resource-group $RESOURCE_GROUP `
    --name $ACR_NAME `
    --sku Basic `
    --admin-enabled true `
    --output none

Write-Host "Container Registry created." -ForegroundColor Green

# ============================================
# Step 3: Build and push Docker image
# ============================================
Write-Host ""
Write-Host "Step 3: Building and pushing Docker image..." -ForegroundColor Cyan

az acr build `
    --registry $ACR_NAME `
    --image sql-mcp-server:1 `
    .

Write-Host "Docker image built and pushed." -ForegroundColor Green

# ============================================
# Step 4: Create Container Apps Environment
# ============================================
Write-Host ""
Write-Host "Step 4: Creating Container Apps environment..." -ForegroundColor Cyan

az containerapp env create `
    --name $CONTAINERAPP_ENV `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION `
    --output none

Write-Host "Container Apps environment created." -ForegroundColor Green

# ============================================
# Step 5: Deploy Container App with Managed Identity
# ============================================
Write-Host ""
Write-Host "Step 5: Deploying Container App with Managed Identity..." -ForegroundColor Cyan

# Get ACR credentials for image pull
$ACR_LOGIN_SERVER = az acr show --name $ACR_NAME --query loginServer --output tsv
$ACR_USERNAME     = az acr credential show --name $ACR_NAME --query username --output tsv
$ACR_PASSWORD     = az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv

az containerapp create `
    --name $CONTAINERAPP_NAME `
    --resource-group $RESOURCE_GROUP `
    --environment $CONTAINERAPP_ENV `
    --image "$ACR_LOGIN_SERVER/sql-mcp-server:1" `
    --registry-server $ACR_LOGIN_SERVER `
    --registry-username $ACR_USERNAME `
    --registry-password $ACR_PASSWORD `
    --target-port 5000 `
    --ingress external `
    --min-replicas 1 `
    --max-replicas 3 `
    --secrets "mssql-connection-string=$CONNECTION_STRING" `
    --env-vars "MSSQL_CONNECTION_STRING=secretref:mssql-connection-string" `
    --cpu 0.5 `
    --memory 1.0Gi `
    --output none

Write-Host "Container App deployed." -ForegroundColor Green

# ============================================
# Step 6: Enable System-Assigned Managed Identity
# ============================================
Write-Host ""
Write-Host "Step 6: Enabling system-assigned managed identity..." -ForegroundColor Cyan

az containerapp identity assign `
    --name $CONTAINERAPP_NAME `
    --resource-group $RESOURCE_GROUP `
    --system-assigned `
    --output none

# Get the managed identity principal ID
$IDENTITY_PRINCIPAL_ID = az containerapp identity show `
    --name $CONTAINERAPP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "principalId" `
    --output tsv

$IDENTITY_NAME = az containerapp show `
    --name $CONTAINERAPP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "name" `
    --output tsv

Write-Host "Managed Identity enabled." -ForegroundColor Green
Write-Host "  Principal ID: $IDENTITY_PRINCIPAL_ID" -ForegroundColor Gray

# ============================================
# Step 7: Get MCP Endpoint URL
# ============================================
Write-Host ""
Write-Host "Step 7: Getting MCP endpoint URL..." -ForegroundColor Cyan

$MCP_URL = az containerapp show `
    --name $CONTAINERAPP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "properties.configuration.ingress.fqdn" `
    --output tsv

# ============================================
# Output Summary
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Deployment Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "MCP Server URL:  https://$MCP_URL/mcp" -ForegroundColor Cyan
Write-Host "Health Check:    https://$MCP_URL/health" -ForegroundColor Cyan
Write-Host ""
Write-Host "Container App:   $CONTAINERAPP_NAME" -ForegroundColor White
Write-Host "Resource Group:  $RESOURCE_GROUP" -ForegroundColor White
Write-Host "ACR Registry:    $ACR_NAME" -ForegroundColor White
Write-Host "Identity (Name): $IDENTITY_NAME" -ForegroundColor White
Write-Host "Identity (PID):  $IDENTITY_PRINCIPAL_ID" -ForegroundColor White
Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host " IMPORTANT: Grant Database Access" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "You must grant the managed identity access to your Northwind database." -ForegroundColor Yellow
Write-Host "Run the following SQL against your Northwind database:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  CREATE USER [$IDENTITY_NAME] FROM EXTERNAL PROVIDER;" -ForegroundColor White
Write-Host "  ALTER ROLE db_datareader ADD MEMBER [$IDENTITY_NAME];" -ForegroundColor White
Write-Host ""
Write-Host "Prerequisites for this SQL command:" -ForegroundColor Yellow
Write-Host "  1. An Azure AD admin must be set on sql-demos.database.windows.net" -ForegroundColor Gray
Write-Host "  2. Connect to the Northwind DB as the Azure AD admin" -ForegroundColor Gray
Write-Host "  3. Run the SQL commands above" -ForegroundColor Gray
Write-Host ""
Write-Host "To set an Azure AD admin via CLI:" -ForegroundColor Yellow
Write-Host "  az sql server ad-admin create \" -ForegroundColor White
Write-Host "    --resource-group <your-sql-resource-group> \" -ForegroundColor White
Write-Host "    --server-name $SQL_SERVER \" -ForegroundColor White
Write-Host "    --display-name <your-aad-admin-name> \" -ForegroundColor White
Write-Host "    --object-id <your-aad-admin-object-id>" -ForegroundColor White
Write-Host ""
Write-Host "See grant-db-access.sql for the complete script." -ForegroundColor Gray
Write-Host ""

# ============================================
# Test health endpoint
# ============================================
Write-Host "Testing health endpoint..." -ForegroundColor Cyan
Start-Sleep -Seconds 5
try {
    $health = Invoke-RestMethod -Uri "https://$MCP_URL/health" -Method Get -TimeoutSec 10
    Write-Host "Health check response: $health" -ForegroundColor Green
} catch {
    Write-Host "Health check not yet responding (container may still be starting)." -ForegroundColor Yellow
    Write-Host "Try manually: curl https://$MCP_URL/health" -ForegroundColor Gray
}

# ============================================
# Save deployment info
# ============================================
$deployInfo = @{
    mcpServerUrl   = "https://$MCP_URL/mcp"
    healthCheckUrl = "https://$MCP_URL/health"
    containerApp   = $CONTAINERAPP_NAME
    resourceGroup  = $RESOURCE_GROUP
    acrRegistry    = $ACR_NAME
    identityName   = $IDENTITY_NAME
    identityPrincipalId = $IDENTITY_PRINCIPAL_ID
    sqlServer      = "${SQL_SERVER}.database.windows.net"
    sqlDatabase    = $SQL_DATABASE
    deployedAt     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

$deployInfo | ConvertTo-Json -Depth 3 | Out-File -FilePath "deployment-info.json" -Encoding utf8
Write-Host "Deployment details saved to deployment-info.json" -ForegroundColor Gray
