﻿function Register-RabbitMqEvent {
    <#
    .SYNOPSIS
        Register a PSJob that reads RabbitMq messages and runs a specified scriptblock

    .DESCRIPTION
        Register a PSJob that reads RabbitMq messages and runs a specified scriptblock

    .PARAMETER ComputerName
        RabbitMq host

        If SSL is specified, we use this as the SslOption server name as well.

    .PARAMETER Exchange
        RabbitMq Exchange

    .PARAMETER Key
        Routing Key to look for

        If you specify a QueueName and no Key, we use the QueueName as the key

    .PARAMETER QueueName
        If specified, bind to this queue.

        If not specified, create a temporal queue

    .PARAMETER Durable
        If queuename is specified, this needs to match whether it is durable

    .PARAMETER Exclusive
        If queuename is specified, this needs to match whether it is Exclusive

    .PARAMETER AutoDelete
        If queuename is specified, this needs to match whether it is AutoDelete

    .PARAMETER RequireAck
        If specified, require an ack for messages

        Note: Without this, dequeue seems to empty a whole queue?

    .PARAMETER Timeout
        Seconds. Timeout Wait-RabbitMqMessage after this expires. Defaults to 1 second

    .PARAMETER LoopInterval
        Seconds. Timeout for each interval we wait for a RabbitMq message. Defaults to 1 second.

    .PARAMETER Credential
        Optional PSCredential to connect to RabbitMq with

    .PARAMETER Ssl
        Optional Ssl version to connect to RabbitMq with

        If specified, we use ComputerName as the SslOption ServerName property.

    .EXAMPLE
        Register-RabbitMqEvent -ComputerName RabbitMq.Contoso.com -Exchange TestFanExc -Key 'wat' -Credential $Credential -Ssl Tls12 -QueueName TestQueue -Action {"HI! $_"}

        # Create a PowerShell job that...
            Connects to RabbitMq.consoto.com over tls 1.2, with credentials in $Credential
            Listens for messages on RabbitMq.consoto.com over the TestFanExc, with routing key 'wat' and queuename TestQueue.
            Runs a scriptblock that says "Hi! <message body>"

    #>
    [Cmdletbinding(DefaultParameterSetName = 'NoQueueName')]
    param(
        [string]$ComputerName = $Script:RabbitMqConfig.ComputerName,

        [parameter(Mandatory = $True)]
        [string]$Exchange,

        [parameter(ParameterSetName = 'NoQueueName',Mandatory = $true)]
        [parameter(ParameterSetName = 'QueueName',Mandatory = $false)]
        [string]$Key,

        [parameter(ParameterSetName = 'QueueName',
                   Mandatory = $True)]
        [string]$QueueName,

        [parameter(ParameterSetName = 'QueueName')]
        [bool]$Durable = $true,

        [parameter(ParameterSetName = 'QueueName')]
        [bool]$Exclusive = $False,

        [parameter(ParameterSetName = 'QueueName')]
        [bool]$AutoDelete = $False,

        [switch]$RequireAck,

        [int]$LoopInterval = 1,

        [ScriptBlock]$Action,

        [PSCredential]$Credential,

        [System.Security.Authentication.SslProtocols]$Ssl
    )

    $ArgList = $ComputerName, $Exchange, $Key, $Action, $Credential, $Ssl, $LoopInterval, $QueueName, $Durable, $Exclusive, $AutoDelete, $RequireAck
    Start-Job -Name "RabbitMq_${ComputerName}_${Exchange}_${Key}" -ArgumentList $Arglist -ScriptBlock {
        param(
            $ComputerName,
            $Exchange,
            $Key,
            $Action,
            $Credential,
            $Ssl,
            $LoopInterval,
            $QueueName,
            $Durable,
            $Exclusive,
            $AutoDelete,
            $RequireAck
        )

        $ActionSB = [System.Management.Automation.ScriptBlock]::Create($Action)
        try
        {
            Import-Module PSRabbitMq

            #Build the connection and channel params
            $ConnParams = @{ ComputerName = $ComputerName }
            $ChanParams = @{ Exchange = $Exchange }
            If($Ssl)       { $ConnParams.Add('Ssl',$Ssl) }
            If($Credential){ $ConnParams.Add('Credential',$Credential) }
            If($Key)       { $ChanParams.Add('Key',$Key)}
            If($QueueName)
            {
                $ChanParams.Add('QueueName',$QueueName)
                $ChanParams.Add('Durable' ,$Durable)
                $ChanParams.Add('Exclusive',$Exclusive)
                $ChanParams.Add('AutoDelete' ,$AutoDelete)
            }
            

            #Create the connection and channel
            $Connection = New-RabbitMqConnectionFactory @ConnParams
            $Channel = Connect-RabbitMqChannel @ChanParams -Connection $Connection

            #Create our consumer
            $Consumer = New-Object RabbitMQ.Client.QueueingBasicConsumer($Channel)
            $Channel.BasicConsume($QueueResult.QueueName, [bool](!$RequireAck), $Consumer) > $Null

            $Delivery = New-Object RabbitMQ.Client.Events.BasicDeliverEventArgs

            #Listen on an infinite loop but still use timeouts so Ctrl+C will work!
            $Timeout = New-TimeSpan -Seconds $LoopInterval
            $Message = $null
            while($True)
            {
                if($Consumer.Queue.Dequeue($Timeout.TotalMilliseconds, [ref]$Delivery))
                {
                    ConvertFrom-RabbitMqDelivery -Delivery $Delivery | ForEach-Object $ActionSB
                    if($RequireAck)
                    {
                        $Channel.BasicAck($Delivery.DeliveryTag, $false)
                    }
                }
            }
        }
        finally
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
}