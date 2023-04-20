# pselastic
Get stats for indices from elasticsearch.

# Use
```powershell
Import-Module -Name .\pselastic

# Fetch stats for all indices
Get-ElasticIndexStats -Server "127.0.0.1" -Port 9200

# Get stats and group by indexname (e.g. 'index-2022.01.01' and 'index-2022.01.02' is grouped as 'index')
Get-ElasticIndexStats -Server "127.0.0.1" -Port 9200 -GroupIndexPatterns 
´´´