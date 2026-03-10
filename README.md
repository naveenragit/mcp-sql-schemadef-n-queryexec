# SQL MCP Server for Northwind Database

Deploys a [Data API Builder](https://learn.microsoft.com/en-us/azure/data-api-builder/) SQL MCP Server to **Azure Container Apps** with **Managed Identity** authentication, exposing your Northwind database views as MCP tools.

## Architecture

```
MCP Client (VS Code, Foundry, etc.)
        │
        ▼  HTTPS (Streamable HTTP)
┌─────────────────────────┐
│  Azure Container Apps   │
│  (sql-mcp-northwind)    │
│  ┌───────────────────┐  │
│  │ Data API Builder   │  │
│  │ SQL MCP Server     │  │
│  └───────────────────┘  │
└─────────┬───────────────┘
          │ Managed Identity
          ▼
┌─────────────────────────┐
│  Azure SQL Database     │
│  sql-demos.database.    │
│  windows.net/Northwind  │
└─────────────────────────┘
```

## Exposed Entities (16 Northwind Views)

| Entity Name | SQL View | Description |
|---|---|---|
| CustomerAndSuppliersByCity | Customer and Suppliers by City | Customers and suppliers by city |
| AlphabeticalListOfProducts | Alphabetical list of products | Active products with categories |
| CurrentProductList | Current Product List | Active product IDs and names |
| OrdersQry | Orders Qry | Orders with customer details |
| ProductsAboveAveragePrice | Products Above Average Price | Premium-priced products |
| ProductsByCategory | Products by Category | Products grouped by category |
| QuarterlyOrders | Quarterly Orders | Customers with 1997 orders |
| Invoices | Invoices | Full invoice details |
| OrderDetailsExtended | Order Details Extended | Line items with extended prices |
| OrderSubtotals | Order Subtotals | Order subtotal amounts |
| ProductSalesFor1997 | Product Sales for 1997 | 1997 sales by product |
| CategorySalesFor1997 | Category Sales for 1997 | 1997 sales by category |
| SalesByCategory | Sales by Category | Sales totals by category |
| SalesTotalsByAmount | Sales Totals by Amount | High-value orders (>$2,500) |
| SummaryOfSalesByQuarter | Summary of Sales by Quarter | Quarterly sales summary |
| SummaryOfSalesByYear | Summary of Sales by Year | Yearly sales summary |

## Prerequisites

- **Azure CLI** — `winget install Microsoft.AzureCLI`
- **Azure subscription** with access to your Azure SQL Server
- **Azure AD admin** configured on your SQL Server (required for managed identity)
- **Docker Desktop** (only needed for local testing)

## Quick Start

```powershell
# 1. Clone and navigate to the project
cd "SQL Server MCP"

# 2. Create a Northwind database in Azure SQL and populate it with schema and data
#    (create the database first via the Azure Portal or Azure CLI, then run the script)
sqlcmd -S sql-demos.database.windows.net -d Northwind -G -i Northwind.sql

# 3. Deploy to Azure Container Apps
.\deploy.ps1

# 4. Grant database access (connect as Azure AD admin)
sqlcmd -S sql-demos.database.windows.net -d Northwind -G -i grant-db-access.sql

# 5. Verify it's running
curl https://<your-app-url>/health
```

## Deployment Guide

### Set Up the Northwind Database

Before deploying the MCP server, you need a Northwind database in Azure SQL. The included `Northwind.sql` script creates all the tables, views, stored procedures, and sample data — but it does **not** create the database itself.

#### 1. Create an Azure SQL Database

If you don't already have a Northwind database, create one via the Azure Portal or Azure CLI:

```powershell
az sql db create `
    --resource-group <your-sql-resource-group> `
    --server sql-demos `
    --name Northwind `
    --service-objective S0
```

#### 2. Run the Northwind Setup Script

Connect to the database and run `Northwind.sql` to create the schema and populate it with data:

```powershell
sqlcmd -S sql-demos.database.windows.net -d Northwind -G -i Northwind.sql
```

This creates:
- **8 tables** — Employees, Categories, Customers, Shippers, Suppliers, Orders, Products, Order Details (plus supporting tables for territories and demographics)
- **16 views** — the views exposed by the MCP server (e.g., Invoices, Order Subtotals, Product Sales for 1997)
- **7 stored procedures** — CustOrderHist, CustOrdersDetail, SalesByCategory, etc.
- **Sample data** — customers, orders, products, and related records

> **Note:** The script drops and recreates objects if they already exist, so it is safe to re-run.

---

### Option A: Deploy to Azure Container Apps (Production)

#### Step 1 — Configure Deployment Variables

Open `deploy.ps1` and update the variables at the top to match your environment:

```powershell
$RESOURCE_GROUP       = "rg-sql-mcp-northwind"          # Resource group name
$LOCATION             = "eastus"                         # Azure region
$CONTAINERAPP_NAME    = "sql-mcp-northwind"              # Container App name
$SQL_SERVER           = "sql-demos"                      # Your SQL Server name (without .database.windows.net)
$SQL_DATABASE         = "Northwind"                      # Your database name
```

#### Step 2 — Run the Deployment Script

```powershell
.\deploy.ps1
```

You can optionally pass a tenant and subscription:

```powershell
.\deploy.ps1 -TenantId "<your-tenant-id>" -SubscriptionId "<your-subscription-id>"
```

The script performs the following steps automatically:

1. Signs in to Azure (or reuses an existing session)
2. Creates a resource group (`rg-sql-mcp-northwind`)
3. Creates an Azure Container Registry and builds the Docker image remotely
4. Creates a Container Apps environment
5. Deploys the container with external ingress on port 5000
6. Enables a **system-assigned managed identity** on the Container App
7. Outputs the MCP endpoint URL and health check URL

> **Note:** The connection string is stored as a Container Apps **secret** — it is never exposed as a plain environment variable.

#### Step 3 — Grant Database Access to the Managed Identity

The Container App's managed identity needs read access to your database. You must run this as an **Azure AD admin** on the SQL Server.

**Option A: Using SSMS or Azure Data Studio**

1. Connect to `sql-demos.database.windows.net` → `Northwind` as an Azure AD admin
2. Run [grant-db-access.sql](grant-db-access.sql)

**Option B: Using sqlcmd**

```powershell
sqlcmd -S sql-demos.database.windows.net -d Northwind -G -i grant-db-access.sql
```

> **Important:** If you changed `$CONTAINERAPP_NAME` in `deploy.ps1`, update the user name in `grant-db-access.sql` to match. The managed identity user name must exactly match the Container App name.

**Setting an Azure AD Admin (if not already configured):**

```powershell
az sql server ad-admin create `
    --resource-group <your-sql-resource-group> `
    --server-name sql-demos `
    --display-name "<your-aad-admin-display-name>" `
    --object-id <your-aad-admin-object-id>
```

#### Step 4 — Verify the Deployment

```powershell
# Health check
curl https://<your-app-url>/health

# The MCP endpoint is available at:
# https://<your-app-url>/mcp
```

---

### Option B: Run Locally with Docker (Testing)

For local development and testing, use the provided `test-local.ps1` script. This uses SQL Authentication instead of managed identity.

> **Note:** Managed Identity does **not** work from a local container. You'll need a SQL login with read access to the database.

#### Prerequisites

- Docker Desktop running
- A SQL login with access to the Northwind database

#### Run Locally

```powershell
.\test-local.ps1 -SqlUser "<your-sql-user>" -SqlPassword (Read-Host -AsSecureString "Password")
```

The script will:
1. Build the Docker image locally
2. Start the container on port 5000
3. Run health checks until the server is ready

#### Local Endpoints

| Endpoint | URL |
|---|---|
| Health check | `http://localhost:5000/health` |
| MCP server | `http://localhost:5000/mcp` |

#### Useful Docker Commands

```powershell
docker logs sql-mcp-local           # View logs
docker logs -f sql-mcp-local        # Follow logs
docker stop sql-mcp-local           # Stop container
docker rm -f sql-mcp-local          # Remove container
```

---

## Connecting MCP Clients

### VS Code

Add to your VS Code `settings.json` or `.vscode/mcp.json`:

```json
{
  "mcp": {
    "servers": {
      "northwind-sql-mcp": {
        "type": "http",
        "url": "https://<your-app-url>/mcp"
      }
    }
  }
}
```

For a local container, use:

```json
{
  "mcp": {
    "servers": {
      "northwind-local": {
        "type": "http",
        "url": "http://localhost:5000/mcp"
      }
    }
  }
}
```

### Other MCP Clients

Use the MCP endpoint URL: `https://<your-app-url>/mcp`

The server uses **Streamable HTTP** transport (not SSE or stdio).

## Customizing for Your Own Database

To point this at a different SQL Server or database:

1. **Update `deploy.ps1`** — Change the `$SQL_SERVER` and `$SQL_DATABASE` variables
2. **Update `dab-config.json`** — Replace the entity definitions with your own tables/views. Each entity needs:
   - `source` — the SQL object name
   - `key-fields` — primary key column(s)
   - `description` — exposed to MCP clients to describe the data
3. **Update `grant-db-access.sql`** — Adjust the user name and permissions as needed
4. **Update `Dockerfile`** — Change the DAB base image version if needed (currently `1.7.83-rc`)

## Files

| File | Purpose |
|---|---|
| `dab-config.json` | Data API Builder config — defines all 16 Northwind view entities |
| `Dockerfile` | Container image based on DAB 1.7.83-rc |
| `deploy.ps1` | PowerShell deployment script for Azure Container Apps |
| `test-local.ps1` | PowerShell script to build and run the server locally in Docker |
| `grant-db-access.sql` | SQL script to grant managed identity database access |
| `Northwind.sql` | Creates all Northwind tables, views, procedures, and sample data (run against an existing database) |
| `deployment-info.json` | Auto-generated deployment metadata (git-ignored) |

## Monitoring

```powershell
# View container logs
az containerapp logs show --name sql-mcp-northwind --resource-group rg-sql-mcp-northwind --follow

# Check health
curl https://<your-app-url>/health

# View container app details
az containerapp show --name sql-mcp-northwind --resource-group rg-sql-mcp-northwind
```

## Troubleshooting

| Problem | Solution |
|---|---|
| Health check returns errors | Check container logs: `az containerapp logs show --name sql-mcp-northwind --resource-group rg-sql-mcp-northwind` |
| `Login failed for user '<token-identified principal>'` | Run `grant-db-access.sql` as an Azure AD admin — the managed identity hasn't been granted access |
| Container starts but MCP endpoint fails | Verify the connection string and ensure the SQL Server firewall allows Azure services |
| Local container can't reach SQL Server | Ensure your SQL Server firewall allows your client IP, and that you're using SQL Authentication (not managed identity) |
| `CREATE USER ... FROM EXTERNAL PROVIDER` fails | You must be connected as an Azure AD admin, and the Container App must already be deployed |

## Clean Up

```powershell
# Delete all Azure resources
az group delete --name rg-sql-mcp-northwind --yes --no-wait
```

## Reference

- [Quickstart: SQL MCP Server with Azure Container Apps](https://learn.microsoft.com/en-us/azure/data-api-builder/mcp/quickstart-azure-container-apps)
- [Data API Builder documentation](https://learn.microsoft.com/en-us/azure/data-api-builder/)
- [SQL MCP Server overview](https://learn.microsoft.com/en-us/azure/data-api-builder/mcp/overview)
