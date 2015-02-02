Function Invoke-SQLBulkCopy{  
	[CmdletBinding(DefaultParameterSetName = "S1")]
	param(		
		[Parameter(Mandatory=$true, ParameterSetName = "S1")] [string] $connectionString,
		[Parameter(Mandatory=$true, ParameterSetName = "S2")] [System.Data.SqlClient.SqlConnection] $connection,
		[Parameter(ParameterSetName = "S2")] [System.Data.SqlClient.SqlTransaction] $transaction,		
		[Parameter(Mandatory=$true)] $data,
		[Parameter(Mandatory=$true)] [string] $tableName,
		[Parameter(Mandatory=$false)] [hashtable]$columnMappings = $null
	)
	
	try
	{	
		if ($PsCmdlet.ParameterSetName -eq "S1")
		{
			$connection = Get-DBConnection -connectionString $connectionString -providerName "System.Data.SqlClient"		
		}	    	    		
		
		$bulk = New-Object System.Data.SqlClient.SqlBulkCopy($connection, [System.Data.SqlClient.SqlBulkCopyOptions]::TableLock, $transaction)  				
		
		$bulk.DestinationTableName = $tableName		
		
		Write-Verbose "SQLBulkCopy started for '$($bulk.DestinationTableName)'"
		
		if ($data -is [System.Data.DataTable])
		{
			Write-Verbose "Writing $($data.Rows.Count) rows"					
			
			# by default mapps all the datatable columns
			
			if ($columnMappings -eq $null)
			{
				$data.Columns |%{
					$bulk.ColumnMappings.Add($_.ColumnName, $_.ColumnName) | Out-Null
				}
			}
			else
			{
				$columnMappings.GetEnumerator() |% {
					$bulk.ColumnMappings.Add($_.Key, $_.Value) | Out-Null
				}
			}
		}
		
#		$bulk.NotifyAfter = 1000
##		
#		$bulk.Add_SQlRowscopied({
#			Write-Verbose "$($args[1].RowsCopied) rows copied."
#			})
					
	    $bulk.WriteToServer($data)    	
		
		$bulk.Close()
		
		Write-Verbose "SQLBulkCopy finished for '$($bulk.DestinationTableName)'"
	}	
	finally
	{	
		if ($PsCmdlet.ParameterSetName -eq "S1" -and $connection -ne $null)
		{
			Write-Verbose ("Closing Connection to: '{0}'" -f $connection.ConnectionString)
			
			$connection.Close()
			$connection.Dispose()
			$connection = $null
		}
	}	   
}

function Get-DBConnection
{
	[CmdletBinding(DefaultParameterSetName = "S1")]
	param(				
		[Parameter(Mandatory=$true, ParameterSetName = "S1")] [string] $providerName = "System.Data.SqlClient",
		[Parameter(Mandatory=$true, ParameterSetName = "S2")] [System.Data.Common.DBProviderFactory] $providerFactory,
		[Parameter(Mandatory=$true)] [string] $connectionString,
		[switch] $open = $true
		)			
	
	if ($PsCmdlet.ParameterSetName -eq "S1")
	{
		$providerFactory = [System.Data.Common.DBProviderFactories]::GetFactory($providerName) 
	}
	
    $connection = $providerFactory.CreateConnection()
			
	$connection.ConnectionString = $connectionString
	
	if ($open)
	{
		Write-Verbose ("Opening Connection to: '{0}'" -f $connection.ConnectionString)
				
		$connection.Open()
	}
		
	Write-Output $connection
}

function Invoke-DBCommand{
	[CmdletBinding(DefaultParameterSetName = "S1")]
	param(						
		[Parameter(Mandatory=$false, ParameterSetName = "S1")] [string] $providerName = "System.Data.SqlClient",
		[Parameter(Mandatory=$true, ParameterSetName = "S1")] [string] $connectionString,
		[Parameter(Mandatory=$true, ParameterSetName = "S2")] [System.Data.Common.DbConnection] $connection,
		[ValidateSet("Query", "NonQuery", "Scalar", "Reader", "Schema")] [string] $executeType = "Query",
		[Parameter(Mandatory=$true)] [string] $commandText,		
		$parameters = $null,
		[int] $commandTimeout = 300
		)

	try
	{				 								
		if ($PsCmdlet.ParameterSetName -eq "S1")
		{									
			if ([string]::IsNullOrEmpty($providerName))
			{
				throw "ProviderName cannot be null";
			}
			
			$providerFactory = [System.Data.Common.DBProviderFactories]::GetFactory($providerName)
			
			$connection = Get-DBConnection -providerFactory $providerFactory -connectionString $connectionString
		}
		
		if ($executeType -eq "Schema") 
		{	  
			$dataTable = $connection.GetSchema($commandText)			

			Write-Output (,$dataTable)			
		}
		else
		{		
			$cmd = $connection.CreateCommand()
			
			$cmd.CommandText = $commandText
		
		   	$cmd.CommandTimeout = $commandTimeout			
			
			if ($parameters -ne $null)
			{			
				if ($parameters -is [hashtable])
				{
					$parameters.GetEnumerator() |% {
						$cmd.Parameters.AddWithValue($_.Name, $_.Value)	| Out-Null
					}
				}
				elseif ($parameters -is [array])
				{
					$parameters |% {
						$cmd.Parameters.Add($_) | Out-Null
					}
				}
				else
				{
					throw "Invalid type for '-parameters', must be an [hashtable] or [DbParameter[]]"
				}
			}				
			
			Write-Verbose ("Executing Command ($executeType): '{0}'" -f $cmd.CommandText)		
		
			if ($executeType -eq "NonQuery") 
			{			
				Write-Output $cmd.ExecuteNonQuery()
			}
			elseif ($executeType -eq "Scalar") 
			{
				Write-Output $cmd.ExecuteScalar()
			}
			elseif ($executeType -eq "Reader") 
			{
				$reader = $cmd.ExecuteReader()
				
				Write-Output (,$reader)
			}
			elseif ($executeType -eq "Query") 
			{
				# Já pode ter sido instanciado antes
				
				if ($providerFactory -eq $null)
				{
					$providerName = $connection.GetType().Namespace
					$providerFactory = [System.Data.Common.DBProviderFactories]::GetFactory($providerName)
				}
				
				try
				{
					$adapter = $providerFactory.CreateDataAdapter()
					
					$adapter.SelectCommand = $cmd
					
					$dataset = New-Object System.Data.DataSet
					
					$adapter.Fill($dataSet) | Out-Null

					Write-Output (,$dataset)	
				}
				finally
				{	
					if ($adapter -ne $null)
					{
						$adapter.Dispose()
					}
				}								
			} 
			else
			{
				throw "Invalid executionType $executeType"
			}
			
			$cmd.Dispose()
		}
	}
	finally
	{
		if ($PsCmdlet.ParameterSetName -eq "S1" -and $connection -ne $null)
		{
			Write-Verbose ("Closing Connection to: '{0}'" -f $connection.ConnectionString)
			
			$connection.Close()
			
			$connection.Dispose()
			
			$connection = $null
		}
	}	
}

function Invoke-SQLCreateTable{
    [CmdletBinding(DefaultParameterSetName = "S1")]
	param(						
		[Parameter(Mandatory=$true, ParameterSetName = "S1")] [string] $connectionString,
		[Parameter(Mandatory=$true, ParameterSetName = "S2")] [System.Data.SqlClient.SqlConnection] $connection,
		[Parameter(ParameterSetName = "S2")] [System.Data.SqlClient.SqlTransaction] $transaction,		   
		[Parameter(Mandatory=$true)] [System.Data.DataTable] $table,
		[Parameter(Mandatory=$true)] [string] $tableName,
		[Switch] $force
		)
			 										
    $strcolumns = "";

    #https://msdn.microsoft.com/en-us/library/cc716729%28v=vs.110%29.aspx
    foreach($obj in $table.Columns)
    {
        if ($obj.DataType.ToString() -eq "System.Double")
        {
            $strcolumns = $strcolumns +",[$obj] FLOAT" + [System.Environment]::NewLine
        }
        elseif ($obj.DataType.ToString() -eq "System.String")
        {
            $strcolumns = $strcolumns +",[$obj] nvarchar(MAX)" + [System.Environment]::NewLine
        }
		elseif ($obj.DataType.ToString() -eq "Int16")
        {
            $strcolumns = $strcolumns +",[$obj] smallint" + [System.Environment]::NewLine
        }
        elseif ($obj.DataType.ToString() -eq "System.Int32")
        {
            $strcolumns = $strcolumns +",[$obj] int" + [System.Environment]::NewLine
        }
		elseif ($obj.DataType.ToString() -eq "System.Int64")
        {
            $strcolumns = $strcolumns +",[$obj] bigint" + [System.Environment]::NewLine
        }
        elseif($obj.DataType.ToString() -eq "System.Decimal")
        {
            $strcolumns = $strcolumns +",[$obj] decimal(18,4)" + [System.Environment]::NewLine
        }
        elseif($obj.DataType.ToString() -eq "System.Boolean")
        {
            $strcolumns = $strcolumns +",[$obj] bit" + [System.Environment]::NewLine
        }
        elseif($obj.DataType.ToString() -eq "System.DateTime")
        {
            $strcolumns = $strcolumns +",[$obj] datetime" + [System.Environment]::NewLine
        }
		elseif($obj.DataType.ToString() -eq "System.Byte[]")
        {
            $strcolumns = $strcolumns +",[$obj] varbinary(max)" + [System.Environment]::NewLine
        }
		elseif($obj.DataType.ToString() -eq "System.Xml.XmlDocument]")
        {
            $strcolumns = $strcolumns +",[$obj] xml" + [System.Environment]::NewLine
        }		
		else
		{
			$strcolumns = $strcolumns +",[$obj] varchar(max)" + [System.Environment]::NewLine
		}			
    }

    $strcolumns = $strcolumns.TrimStart(",")

    $commandText = "
	IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'$tableName') AND type in (N'U'))
	BEGIN
		CREATE TABLE $tableName
        (
        $strcolumns
        );
	END					
	"
	
	if ($force)
	{
		$commandText = "
		IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'$tableName') AND type in (N'U'))
		BEGIN
			drop table $tableName
		END
		;		
		" + $commandText
	}
	
	if ($PsCmdlet.ParameterSetName -eq "S1")
	{
		Invoke-DBCommand -connectionString $connectionString -providerName "System.Data.SqlClient" -commandText $commandText -executeType "NonQuery" | Out-Null
	}
	else
	{
		Invoke-DBCommand -connection $connection -commandText $commandText -executeType "NonQuery" | Out-Null
	}				
}

Export-ModuleMember -Function @("Invoke-*", "Get-*")