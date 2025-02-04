﻿function Send-RabbitMqMessage {
    <#
    .SYNOPSIS
        Send a RabbitMq message

    .DESCRIPTION
        Send a RabbitMq message

    .PARAMETER ComputerName
        RabbitMq host

        If SSL is specified, we use this as the SslOption server name as well.

    .PARAMETER Exchange
        RabbitMq Exchange to send message to

    .PARAMETER Key
        Routing Key to send message with

    .PARAMETER InputObject
        Object to serialize and include as the message body

        We use ContentType "application/clixml+xml"

    .PARAMETER Depth
        Depth of the InputObject to serialize. Defaults to 2.

    .PARAMETER Persistent
        If specified, send message with persitent delivery method.

        Defaults to non-persistent

    .PARAMETER Credential
        Optional PSCredential to connect to RabbitMq with

    .PARAMETER Ssl
        Optional Ssl version to connect to RabbitMq with

        If specified, we use ComputerName as the SslOption ServerName property.

    .EXAMPLE
        Send-RabbitMqMessage -ComputerName RabbitMq.Contoso.com -Exchange MyExchange -Key "wat" -InputObject $Object

        # Connects to RabbitMq.Contoso.com
        # Sends a message to the MyExchange exchange with the routing key 'wat', and the $Object object in the body

    .EXAMPLE
        Send-RabbitMqMessage -ComputerName RabbitMq.Contoso.com -Exchange MyExchange -Key "wat" -InputObject @{one=1} -Ssl Tls12 -Credential $Credential

        # Connects to RabbitMq.Contoso.com over tls 1.2 with credential in $Credential
        # Sends a message to the MyExchange exchange with the routing key 'wat', and a hash table in the message body
    #>
    param(
        [string]$ComputerName = $Script:RabbitMqConfig.ComputerName,

        [parameter(Mandatory = $True)]
        [string]$Exchange,

        [parameter(Mandatory = $True)]
        [string]$Key,

        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        $InputObject,

        [switch]$Persistent,

        [Int32]$Depth = 2,

        [PSCredential]$Credential,

        [System.Security.Authentication.SslProtocols]$Ssl
    )
    begin
    {
        #Build the connection. Filter bound parameters, splat them.
        $ConnParams = @{ ComputerName = $ComputerName }
        Switch($PSBoundParameters.Keys)
        {
            'Ssl'        { $ConnParams.Add('Ssl',$Ssl) }
            'Credential' { $ConnParams.Add('Credential',$Credential) }
        }
        Write-Verbose "Connection parameters: $($ConnParams | Out-String)"

        #Create the connection and channel
        $Connection = New-RabbitMqConnectionFactory @ConnParams

        $Channel = $Connection.CreateModel()
        $BodyProps = $Channel.CreateBasicProperties()
        if($Persistent)
        {
            $BodyProps.SetPersistent($true)
        }
        $BodyProps.ContentType = "application/clixml+xml"
    }
    process
    {
        try
        {
            $Serialized = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $Depth)
        }
        catch
        {
            #This is for V2 clients...
            $TempFile = [io.path]::GetTempFileName()
            try
            {
                Export-Clixml -Path $TempFile -InputObject $InputObject -Depth $Depth -Encoding Utf8
                $Serialized = [IO.File]::ReadAllLines($TempFile, [Text.Encoding]::UTF8)
            }
            finally
            {
                if( (Test-Path -Path $TempFile) )
                {
                    Remove-Item -Path $TempFile -Force
                }
            }
        }

        $Body = [System.Text.Encoding]::UTF8.GetBytes($Serialized)
        $Channel.BasicPublish($Exchange, $Key, $BodyProps, $Body)
    }
    end
    {
        if($Channel)
        {
            $Channel.Close()
        }
        if($Connection -and $Connection.IsOpen)
        {
            $Connection.Close()
        }
    }
}