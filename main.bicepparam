// ===========================================================================
// main.bicepparam  -  YOUR values go here.
// Secrets (adminPassword, safeModePassword) are read from environment
// variables at deploy time via readEnvironmentVariable() - the deploy
// workflow sets those env vars from GitHub secrets immediately before this
// runs. Nothing secret is ever hardcoded here or committed.
// ===========================================================================

using './main.bicep'

param adminPassword = readEnvironmentVariable('LAB_ADMIN_PASSWORD')
param safeModePassword = readEnvironmentVariable('LAB_SAFEMODE_PASSWORD')

param location = 'westeurope'
param vnetAddressPrefix = '10.20.0.0/16'
param subnetPrefix = '10.20.1.0/24'
param dcPrivateIp = '10.20.1.4'
param autoShutdownTime = '1900'
param timeZoneId = 'GMT Standard Time'

param domainName = 'eph.internal'
param netbiosName = 'EPH'

// Not 'admin' or 'administrator' - Azure rejects those.
param adminUsername = 'labadmin'

param scriptBaseUri = 'https://raw.githubusercontent.com/remlap-m/secops-lab/main/scripts/windows'

param clientCount = 4
