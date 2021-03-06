﻿cls

$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition –Parent)

Import-Module "$currentPath\..\SQLHelper.psm1" -Force

$sourceConnStr = "Integrated Security=SSPI;Persist Security Info=False;Initial Catalog=AdventureWorksDW2012;Data Source=.\sql2014"

$destinationConnStr = "Integrated Security=SSPI;Persist Security Info=False;Initial Catalog=DestinationDB;Data Source=.\sql2014"

$tables = @("[dbo].[DimProduct]", "[dbo].[FactInternetSales]")

$steps = $tables.Count
$i = 1;

$tables |% {
		
	$sourceTableName = $_
	$destinationTableName = $sourceTableName
	
	Write-Progress -activity "Tables Copy" -CurrentOperation "Executing source query over '$sourceTableName'" -PercentComplete (($i / $steps)  * 100) -Verbose
	
	# Query the datasource
	
	$sourceTable = Invoke-SQLCommand -executeType QueryAsTable -connectionString $sourceConnStr -commandText "select * from $sourceTableName" -Verbose
	
	Write-Progress -activity "Tables Copy" -CurrentOperation "Creating destination table '$destinationTableName'" -PercentComplete (($i / $steps)  * 100) -Verbose
	
	# Create the table if not exists
	
	if (-not (Test-SQLTableExists -connectionString $destinationConnStr -tableName $destinationTableName -verbose))
	{								
		New-SQLTable -connectionString $destinationConnStr -data $sourceTable -tableName $destinationTableName -force -Verbose
	}			
	
	Write-Progress -activity "Tables Copy" -CurrentOperation "Loading destination table '$destinationTableName'" -PercentComplete (($i / $steps)  * 100) -Verbose
	
	# Bulk copy into the destination table
	
	Invoke-SQLBulkCopy -connectionString $destinationConnStr -data $sourceTable -tableName $destinationTableName -Verbose
	
	$i++;
}

Write-Progress -activity "Tables Copy" -Completed
