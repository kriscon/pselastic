function Get-ElasticIndexStats
{
    <#
	.DESCRIPTION
		Get statistics for elasticsearch indices, converts index size to GB
		Groups dayily, monthly and yearly index patterns
	.SYNOPSIS
		Get statistics for elasticsearch indices
	.EXAMPLE
		Get-ElasticIndexStats -Server elasticsearch.local
			Gets index stats from elasticsearch.local
	.PARAMETER Server
		Specify one or more elasticsearch servers
	.PARAMETER Protocol
		Specify http or https, http is defaul
	.PARAMETER Port
		Specify port, 9200 is default
	.PARAMETER GroupIndexPatterns
		Group all index patterns (e.q. 'index-2019.01.01' and 'index-2019.01.02' is grouped as 'index') and display as one index
	#>
	
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[string[]]$Server,
		
		[Parameter(Mandatory = $false, Position = 1)]
		[Alias("Group")]
		[switch]$GroupIndexPatterns,
		
		[Parameter(Mandatory = $false, Position = 2)]
		[ValidateSet('http', 'https')]
		[string]$Protocol = "http",
		
		[Parameter(Mandatory = $false)]
		[int]$Port = 9200
	)
	
	begin
	{		
		Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
		
		Write-Verbose -Message "Function called: $($MyInvocation.MyCommand)"
		
	} # begin
	
	process
	{
		# Process each elasticsearch server specified
		foreach ($ElasticNode in $Server)
		{
			Write-Verbose -Message "Processing $ElasticNode"
			[string]$Uri = $Protocol + "://" + $ElasticNode + ":" + $Port
			
			# Verify connectivity to elasticsearch port
			try
			{
				Write-Verbose -Message "Testing API on $Uri"
				$APITest = Invoke-RestMethod -Uri $Uri -Method Get -UseBasicParsing -ErrorAction Stop
				if ($APITest.cluster_name -match '\S+')
				{
					Write-Verbose -Message " API Test successful"
				} # if APITest.cluster_name
				else
				{
					Write-Warning -Message " API Test failed"
					Write-Warning -Message " Unable to identify $Uri as an elasticsearch node"
					break
				} # else APITest.cluster_name
			} # try
			
			catch
			{
				Write-Warning -Message " API Test failed"
				Write-Warning -Message " $($_.Exception.Message)"
				break
			} # catch
			
			# List all indices from elasticsearch node
			try
			{
				$indicesUri = "$Uri/_cat/indices?format=json"
				Write-Verbose -Message "Getting indices from $indicesUri"
				$Indices = Invoke-RestMethod -Uri $indicesUri -Method Get -UseBasicParsing -ErrorAction Stop
				Write-Verbose -Message " Successfully got indicies from $indicesUri"
			}
			catch
			{
				Write-Warning -Message " Failed to list indices from $indicesUri"
			}
			
			if ($Indices)
			{
				# Convert all sizes to GB from MB,KB
				foreach ($elastic in $Indices)
				{
					switch -Wildcard ($elastic."pri.store.size")
					{
						'*kb' { $elastic."pri.store.size" = [double]($elastic."pri.store.size" -replace "kb", "") * 0.00001 }
						'*mb' { $elastic."pri.store.size" = [double]($elastic."pri.store.size" -replace "mb", "") * 0.001 }
						'*gb' { $elastic."pri.store.size" = [double]($elastic."pri.store.size" -replace "gb", "") }
						Default { $elastic."pri.store.size" = [double]($elastic."pri.store.size" -replace "b", "") * 0.0000001 }
					}
					switch -Wildcard ($elastic."store.size")
					{
						'*kb' { $elastic."store.size" = [double]($elastic."store.size" -replace "kb", "") * 0.00001 }
						'*mb' { $elastic."store.size" = [double]($elastic."store.size" -replace "mb", "") * 0.001 }
						'*gb' { $elastic."store.size" = [double]($elastic."store.size" -replace "gb", "") }
						Default { $elastic."store.size" = [double]($elastic."store.size" -replace "b", "") * 0.0000001 }
					}
				}
				
				if ($GroupIndexPatterns -eq $true)
				{
					# RegEx to trim index suffix (e.g trim '-2019.01.30' from indexname-2019.01.30)
					[regex]$RegEx = "(-\d+.+)"
					
					# Create Object with the unique indices
					$CustomIndices = $Indices.index | ForEach-Object { ($_ -replace $RegEx, '') } | Select-Object -Unique
					
					# Create dynamic variables for each unique index
					foreach ($Index in $CustomIndices)
					{
						$varname = "customarray$Index"
						if (-not (Get-Variable -Name $varname -ErrorAction SilentlyContinue))
						{
							New-Variable -Name $varname -Value @()
						}
						Set-Variable -Name $varname -Value ($Indices | Where-Object { $_.Index -like "*$Index*" })
						
						Clear-Variable -Name varname -ErrorAction SilentlyContinue
					}
					
					# Create an array with all the unique indices
					$Combinedarrays = New-Object -TypeName System.Collections.ArrayList
					foreach ($Item in (Get-Variable | Where-Object { $_.Name -like "customarray*" }).Name)
					{
						$UniqueItem = Get-Variable -Name $Item -ValueOnly
						[void]$Combinedarrays.Add($UniqueItem)
					}
					
					# Measure document count and size for unique indices
					$ResultArray = New-Object -TypeName System.Collections.ArrayList
					$Customvariables = Get-Variable | Where-Object { $_.Name -like "customarray*" } | Select-Object Name
					foreach ($Item in $Customvariables)
					{
						$Var = (Get-Variable -Name $Item.Name -ValueOnly)
						$Object = New-Object psobject -Property @{
							"index" = ($Item.Name).Replace('customarray', '')
							"store.size" = [math]::Round(($Var."store.size" | Measure-Object -Sum).Sum, 2)
							"pri.store.size" = [math]::Round(($Var."pri.store.size" | Measure-Object -Sum).Sum, 2)
							[int]"docs.count" = ($Var."docs.count" | Measure-Object -Sum).Sum
							"servername" = $ElasticNode
						}
						
						[void]$ResultArray.Add($Object)
						Clear-Variable -Name Var, Object, Count -ErrorAction SilentlyContinue
						
					} # foreach Item in Customvariables
					
				} # if ($GroupIndexPatterns -eq $true)
				
				else
				{
					foreach ($Index in $Indices) {
						$Index."docs.count" = [int]$Index."docs.count"
					}
					$ResultArray = $Indices
					
				} # else ($GroupIndexPatterns -eq $true)
				
			} # if Indices
			
			Write-Output -InputObject $ResultArray
			
			Clear-Variable -Name ResultArray, Customvariables, CustomIndices, Combinedarrays -ErrorAction SilentlyContinue
			Remove-Variable -Name customarray* -ErrorAction SilentlyContinue
			
		} # foreach ElasticNode
		
	} # process
	
	end
	{
		Write-Verbose -Message "Function complete: $($MyInvocation.MyCommand)"
	} # end
	
} # Function