-- ============================================
-- Grant Managed Identity Access to Northwind Database
-- ============================================
--
-- PREREQUISITES:
--   1. An Azure AD admin must be configured on your SQL Server (sql-demos)
--   2. You must connect to the Northwind database AS the Azure AD admin
--   3. The Container App must already be deployed (run deploy.ps1 first)
--
-- TO SET AN AZURE AD ADMIN (if not already set):
--   az sql server ad-admin create \
--     --resource-group <your-sql-resource-group> \
--     --server-name sql-demos \
--     --display-name "<your-aad-admin-display-name>" \
--     --object-id <your-aad-admin-object-id>
--
-- CONNECT using Azure AD authentication, then run this script.
-- Replace [sql-mcp-northwind] below with your Container App name
-- if you changed it in deploy.ps1.
-- ============================================

-- Create a contained database user for the Container App's managed identity
-- The name must match the Container App name exactly
CREATE USER [sql-mcp-northwind] FROM EXTERNAL PROVIDER;
GO

-- Grant read-only access (since our DAB config only exposes read permissions on views)
ALTER ROLE db_datareader ADD MEMBER [sql-mcp-northwind];
GO

-- Verify the user was created
SELECT name, type_desc, authentication_type_desc
FROM sys.database_principals
WHERE name = 'sql-mcp-northwind';
GO
