#Skript som kör vid uppstart efter ett servicefönster som en schemalagd upppgift.
#När servrarna är omstartat så börjar skriptet kolla om det har stadigvarande kontakt
#Efter det så hämtar det in information och sedan är det lite logik för att se om alla tjänser är startade, alla servar omstartade, om de har fått alla uppdateringar.

#finns säkert mycket matnyttigt här som går att återanvända. Det är inte optimerat eller nåt men gör sin sak. 

#Skapar loggfil
$LoggPath = "C:\Users\XXXXX\Desktop\LOGS"
$FileName = (Get-Date).tostring("yyyy-MM-dd-hh-mm") 
  
if (!(Test-path $LoggPath)) {
         $LoggPath = New-Item -Path $Loggpath -ItemType Directory     
}
$logfile = New-Item -itemType File -Path $LoggPath -Name ($FileName + ".log")

#servrarna som ska övervakas
$Servers = @('')
$avsandare = <MAILADRESS>
$mottagare =  <MAILADDRESS>
$SMTP = <SmtpServer>
$Global:Tjanster = @(,'*SQL*','*tomcat*')  #Namnet på Serverspecifika tjänster
$Forsok = 0
$antal_forsok = 3


#Loggfil
Function Write-Log {
   Param (
      [Parameter(Mandatory, ValueFromPipeline)]
      [string[]]
      $logstring)

   Add-content $Logfile -value ( $(Get-Date).tostring("hh:mm:ss") + ":" + $logstring )
}


function Get-Status {
   #Skapar ett object med information om uppdateringstatus
   param (
      [Parameter(Mandatory = $true, ValueFromPipeline)] [string[]] $Server,
      [Parameter(Mandatory = $false)] [string[]] $tjanster,
      [parameter(Mandatory = $false)] [string] $user, #Ex. vih013sa
      [Parameter(Mandatory = $false)] [string] $domain # ex. extad.lul.se\
   )      
   
                                                            
   $pingtest = $false

   #Pingtest + informationhämtning 

   While ($pingtest -contains $false) {
      $pingtest = Test-connection $Server -count 1 -Quiet 

      switch ($pingtest) {
         $true {
            try { $session = New-PSSession -ComputerName $Server -ErrorAction Stop }  

            Catch { 
               Write-Log ("En dator tappade kontakten. Errormessage = " + $_.Exception); Continue; $pingtest = $false 
            }

            $lastupdate = Invoke-Command -Session $session -scriptBlock { 
               Get-wmiobject -class win32_quickfixengineering | sort-object "Installedon" | Select -last 1 }    #Senaste uppdatering

            $serverstatus = Invoke-Command -Session $session -scriptBlock { 
               Get-CimInstance -ClassName win32_operatingsystem | select lastbootuptime, Status }   #Omstart och Servestatus

            $services = Invoke-Command -Session $session -scriptBlock {
               Get-Service | Where-object { $_.StartType -eq "Automatic" } }   #Alla automatisk startade tjänster vid uppstart
         }
         $false {
            Write-Log "En Server håller på att uppdateras"
            Start-sleep -s 120
         }
      }
   }

   #Objectet skapas för en server 

   $StatusObject = [PScustomObject]@{

      Server              = $server
      Senaste_omstart     = $serverstatus.lastbootuptime
      Omstart_F           = $serverstatus.lastbootuptime.GetDateTimeFormats()[0]
      Server_Status       = $serverstatus.Status 
      Senaste_uppdatering = $lastupdate.InstalledOn
      SenasteUpp_F        = $lastupdate.InstalledOn.GetDateTimeFormats()[0]
      HotfixID            = $lastupdate.HotfixID
      Tjanster            = foreach($tjanst in $Global:Tjanster) { 
                            ( $services | Where-object {  $_.displayname -like $tjanst }   | Select-Object -ExpandProperty Displayname) }
      Status              = foreach($tjanst in $Global:Tjanster) { 
                            ( $services | Where-object {  $_.displayname -like $tjanst }   | Select-Object -ExpandProperty Status) }

   }

   #avsluta PS-session
   Remove-PSSession -Session $session

   #Reslutat funktion
   Return $StatusObject
} 

#Hämtar data för varje server och sparar det i arrayen $Statusarray

function Check-Status {
   #Kollar status på varje server och spottar ut det i ett object. Använder Get-Status
   Param
   (
      [Parameter(Mandatory = $true,
         ValueFromPipelineByPropertyName = $true,
         Position = 0)]
      [string[]]
      $Serverlista

   )
   [System.Collections.ArrayList]$Statusarray = @()

   $date = (Get-date).GetDateTimeFormats()[0]
   $Klara = @()
   $Uppdatering_utan_omstart = @()
   $Klart_tjansterstartar = @()
   $Omstart_utan_uppdatering_problem = @()
   $Server_status_ej_OK = @()
   $server_undantagen = @()
   
   ForEach ($servernamn in $Serverlista) {

      $Statusarray.Add((Get-status $servernamn)) | out-null
   }


   #Logik som sorterar beroende på olika statusar i uppdateringen
   switch ($Statusarray) { 

      { $_.Omstart_F -eq $date -and $_.SenasteUpp_F -eq $date -and $_.Status -like 'Running' -and $_.server_status -eq 'OK' } { $Klara += $_.server }

      { $_.Omstart_F -lt $date -and $_.SenasteUpp_F -eq $date -and $_.Status -like 'Running' -and $_.server_status -eq 'OK' } { $Uppdatering_utan_omstart += $_.server }

      { $_.Omstart_F -eq $date -and $_.SenasteUpp_F -eq $date -and $_.Status -like 'Stopped' -and $_.server_status -eq 'OK' } { $Klart_tjansterstartar += $_.server }

      { $_.Omstart_F -eq $date -and $_.SenasteUpp_F -lt $date -and $_.Status -like 'Stopped' -or $_.server_status -ne 'OK' } { $Omstart_utan_uppdatering_problem += $_.server }

      { $_.Omstart_F -ne $date -and $_.SenasteUpp_F -ne $date -and $_.Status -like 'Running' -and $_.server_status -eq 'OK' } { $server_undantagen += $_.server }
   
      Default { $Server_status_ej_OK += $_.server }
   }



   $Loggobject = [PScustomObject]@{

      Klara_servrar                    = $Klara
      Uppdatering_utan_omstart_klar    = $Uppdatering_utan_omstart
      Klart_tjansterstartar            = $Klart_tjansterstartar
      Omstart_utan_uppdatering_problem = $Omstart_utan_uppdatering_problem
      Server_status_ej_OK              = $Server_status_ej_OK
      server_undantagen                = $server_undantagen
      Omstart                          = $Statusarray.senaste_omstart
      Senaste_upp                      = $Statusarray.senaste_uppdatering 
   }
    
   Write-Log ("`r`n `r`n  --------------------Detaljer---------------------- `r`n $($statusarray | ConvertTo-json)") 


   Return $Loggobject

   
}


#Hämtar data max 3 - VARIABLEN $antal_forsok gånger eller det man väljer själv tills Status är klar innan E-post skickas 

:loop While ($Forsok -le $antal_forsok) {

   $checkobject = Check-status $servers

   Write-log ( "`r`n Försök: $($forsok+1)`r`n Resultat: `r`n Klara_servrar: $($checkobject.Klara_servrar) `r`n Uppdatering_utan_omstart_klar: $($checkobject.Uppdatering_utan_omstart_klar) `r`n Klart_tjansterstartar: $($checkobject.Klart_tjansterstartar) `r`n Servrar_undantagna:$($checkobject.server_undantagen)
        `r`n Omstart_utan_uppdatering_problem:$($checkobject.Omstart_utan_uppdatering_problem) `r`n Server_status_ej_OK: $($checkobject.Server_status_ej_OK) `r`n Senate omstart:$($checkobject.Omstart) `r`n Senaste_upp: $($checkobject.Senaste_upp) ")

:Om Switch ($checkobject) {

      #allt klart-MAIL
      { $_.Klara_servrar.count + $_.server_undantagen.count -eq $servers.Length } {  
    
    (Send-MailMessage -From $avsandare -Subject "Service klar för <SYSTEMNAMN>" -To $mottagare -Body ("Hej! `r`n Servern har 
fått alla patchar och alla tjänster har startats upp. $($Checkobject.server_undantagen). Se loggfilen för mer information. `r`n `r`n Hälsningar,`r`n Henrik Vikström`r`n Systemtekniker") -SmtpServer $SMTP -encoding utf8 -Attachments $logfile); Break loop 
      }

      #Fått uppdatering men har inte startat om-MAIL

      { $_.Uppdatering_utan_omstart_klar.count -ge 1 -and $forsok -eq 1 } { 

     (Send-MailMessage -From $avsandare -Subject "Service ej klar - <SYSTEMNAMN>" -To $mottagare -Body ("Hej! `r`n Servern $($Checkobject.Uppdatering_utan_omstart) har 
fått uppgraderingar men har ännu inte startats om, två kontroller till görs med 5 minuter mellanrum. Se loggfilen för information. `r`n `r`n Hälsningar,`r`n Henrik Vikström`r`n Systemtekniker") -SmtpServer $SMTP -encoding utf8 -Attachments $logfile)
        ; $forsok++ ; Break Om}   
    

      #Har fått alla upppgraderingar men alla tjänster har inte startats -MAIL

      { $_.Klart_tjansterstartar.count -ge 1 -and $_.Omstart_utan_uppdatering_problem.count + $_.Server_status_ej_OK.count -eq 0 -and $forsok -eq 2 } {

    (Send-MailMessage -From $avsandare -Subject "Service nästan klar för <SYSTEMNAMN>" -To $mottagare -Body ("Hej! `r`n Servern har fått alla patchar men alla tjänster på $($Checkobject.Server_status_ej_OK)
 som startas automatisk har inte gjort det ännu. Se kompletta loggen för vilken tjänst det gäller. En kontroll till görs med 10 minuters mellanrum. `r`n `r`n Hälsningar,`r`n Henrik Vikström`r`n Systemtekniker") -SmtpServer $SMTP -encoding utf8 -Attachments $logfile)
        ; $forsok++ ; Break Om
    } 

    # Har omstartats men inte fått uppgraderingar och alla tjänster har inte startats. - OVÄNTAD OMSTARt

      { $_.Omstart_utan_uppdatering_problem.count -ge 1 -and $forsok -eq 2 } {

    (Send-MailMessage -From $avsandare -Subject "Omväntad service på serverparken" -To $mottagare -Body ("Hej! `r`n Serverparken har omplanerat startats om, gäller dessa servrar: $($_.Omstart_utan_uppdatering_problem)
 Se loggen. `r`n `r`n Hälsningar,`r`n Henrik Vikström`r`n Systemtekniker") -SmtpServer $SMTP -encoding utf8 -Attachments $logfile)
        ; $forsok++ ; Break Om
    } 


      #Omstart utan uppgradering och något är fel. 
      { $_.Server_status_ej_OK.count -ge 1 -and $forsok -eq 2 } { 
    
 (Send-MailMessage -From $avsandare -Subject "Omstart utan uppgradering" -To $mottagare.se -Body ("Hej! `r`n Serverna: $($Loggobject.Server_status_ej_OK) har startas om utan att få patchar eller blivit uppgraderade.
 Tjänster har inte startats eller har dator felstatus. Se kompletta loggen. `r`n `r`n Hälsningar,`r`n Henrik Vikström`r`n Systemtekniker") -SmtpServer $SMTP -encoding utf8 -Attachments $logfile) 
     ; $forsok++ ; Break Om  }


    Default   { $forsok++ }

   }

   Start-sleep -s 600

}

