###############################################################################
# 
# Developed with Kate
#
#  (c) 2018 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################

## Die folgenden Modelle sind identisch. Man kann sich das günstigste Modell auswählen.
##
## Name                	Preis      	Vertrieb über
## -----------------------------------------------
## Xavax Hama          	40 Euro    	Media Markt
## Sygonix HT100 BT    	20 Euro    	Conrad
## Comet Blue          	20 Euro    	Real / Bauhaus

        
        
        
        


package main;

use strict;
use warnings;
use POSIX;

use JSON;
use Blocking;


my $version = "0.1.11";




my %gatttChar = (
        CometBlue       => {'devicename' => '0x3', 'battery' => '0x41', 'payload' => '0x3f', 'firmware' => '0x18', 'pin' => '0x47'},
        SilverCrest     => {'devicename' => '0x3', 'battery' => '0x3f', 'payload' => '0x3d', 'firmware' => '0x18', 'pin' => '0x48'}
    );
    
my %winOpnSensitivity = ( 
        Sensitivity => {'12' => 'low' ,'8' => 'medium' ,'4' => 'high' ,'low' => '12' ,'medium' => '8' ,'high' => '4'}
    );

my %CallBatteryAge = (  '8h'    => 28800,
                                '16h'   => 57600,
                                '24h'   => 86400,
                                '32h'   => 115200,
                                '40h'   => 144000,
                                '48h'   => 172800
    );


# Declare functions
sub CometBlueBTLE_Initialize($);
sub CometBlueBTLE_Define($$);
sub CometBlueBTLE_Undef($$);
sub CometBlueBTLE_Attr(@);
sub CometBlueBTLE_stateRequest($);
sub CometBlueBTLE_stateRequestTimer($);
sub CometBlueBTLE_Set($$@);
sub CometBlueBTLE_Get($$@);
sub CometBlueBTLE_Notify($$);

sub CometBlueBTLE_CreateParamGatttool($@);

sub CometBlueBTLE_ExecGatttool_Run($);
sub CometBlueBTLE_ExecGatttool_Done($);
sub CometBlueBTLE_ExecGatttool_Aborted($);
sub CometBlueBTLE_ProcessingNotification($@);
sub CometBlueBTLE_WriteReadings($$);
sub CometBlueBTLE_ProcessingErrors($$);
sub CometBlueBTLE_encodeJSON($);

sub CometBlueBTLE_CallBattery_IsUpdateTimeAgeToOld($$);
sub CometBlueBTLE_CallBattery_Timestamp($);
sub CometBlueBTLE_CallBattery_UpdateTimeAge($);
sub CometBlueBTLE_CreateDevicenameHEX($);
sub CometBlueBTLE_CreatePayloadString($$$);
sub CometBlueBTLE_ConvertPinToHexLittleEndian($);

sub CometBlueBTLE_HandlePayload($$);
sub CometBlueBTLE_HandleBattery($$);
sub CometBlueBTLE_HandleFirmware($$);
sub CometBlueBTLE_HandleDevicename($$);





sub CometBlueBTLE_Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}      = "CometBlueBTLE_Set";
    $hash->{GetFn}      = "CometBlueBTLE_Get";
    $hash->{DefFn}      = "CometBlueBTLE_Define";
    $hash->{NotifyFn}   = "CometBlueBTLE_Notify";
    $hash->{UndefFn}    = "CometBlueBTLE_Undef";
    $hash->{AttrFn}     = "CometBlueBTLE_Attr";
    $hash->{AttrList}   = "interval ".
                            "disable:1 ".
                            "disabledForIntervals ".
                            "hciDevice:hci0,hci1,hci2 ".
                            "batteryFirmwareAge:8h,16h,24h,32h,40h,48h ".
                            "sshHost ".
                            "blockingCallLoglevel:2,3,4,5 ".
                            "pin ".
                            "model:CometBlue,SilverCrest ".         # XavaxHama,SygonixHT100BT,
                            $readingFnAttributes;



    foreach my $d(sort keys %{$modules{CometBlueBTLE}{defptr}}) {
        my $hash = $modules{CometBlueBTLE}{defptr}{$d};
        $hash->{VERSION} 	= $version;
    }
}

sub CometBlueBTLE_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    
    return "too few parameters: define <name> CometBlueBTLE <BTMAC>" if( @a != 3 );
    

    my $name                                = $a[0];
    my $mac                                 = $a[2];
    
    $hash->{BTMAC}                          = $mac;
    $hash->{VERSION}                        = $version;
    $hash->{INTERVAL}                       = 150;
    $hash->{helper}{writePin}               = 0;
    $hash->{helper}{CallBattery}            = 0;
    $hash->{helper}{paramGatttool}{mod};
    $hash->{helper}{paramGatttool}{handle};
    $hash->{helper}{paramGatttool}{value};
    $hash->{NOTIFYDEV}                      = "global,$name";
    $hash->{loglevel}                       = 4;
        
    
    readingsSingleUpdate($hash,"state","initialized", 0);
    $attr{$name}{room}                      = "CometBlueBTLE" if( AttrVal($name,'room','none') eq 'none' );
    
    Log3 $name, 3, "CometBlueBTLE ($name) - defined with BTMAC $hash->{BTMAC}";
    
    $modules{CometBlueBTLE}{defptr}{$hash->{BTMAC}} = $hash;
    return undef;
}

sub CometBlueBTLE_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $mac = $hash->{BTMAC};
    my $name = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);
    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
    
    delete($modules{CometBlueBTLE}{defptr}{$mac});
    Log3 $name, 3, "Sub CometBlueBTLE_Undef ($name) - delete device $name";
    return undef;
}

sub CometBlueBTLE_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash                                = $defs{$name};


    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);
            
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "CometBlueBTLE ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            Log3 $name, 3, "CometBlueBTLE ($name) - enabled";
        }
    }
    
    elsif( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
            unless($attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/);
            Log3 $name, 3, "CometBlueBTLE ($name) - disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
        }
	
        elsif( $cmd eq "del" ) {
            Log3 $name, 3, "CometBlueBTLE ($name) - enabled";
            readingsSingleUpdate ( $hash, "state", "active", 1 );
        }
    }
    
    elsif( $attrName eq "interval" ) {
        RemoveInternalTimer($hash);
        
        if( $cmd eq "set" ) {
            if( $attrVal < 30 ) {
                Log3 $name, 3, "CometBlueBTLE ($name) - interval too small, please use something >= 30 (sec), default is 150 (sec)";
                return "interval too small, please use something >= 30 (sec), default is 150 (sec)";
            } else {
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3, "CometBlueBTLE ($name) - set interval to $attrVal";
            }
        }

        elsif( $cmd eq "del" ) {
            $hash->{INTERVAL} = 300;
            Log3 $name, 3, "CometBlueBTLE ($name) - set interval to default";
        }
    }
    
    elsif( $attrName eq "blockingCallLoglevel" ) {
        if( $cmd eq "set" ) {
            $hash->{loglevel} = $attrVal;
            Log3 $name, 3, "CometBlueBTLE ($name) - set blockingCallLoglevel to $attrVal";
        }

        elsif( $cmd eq "del" ) {
            $hash->{loglevel} = 4;
            Log3 $name, 3, "CometBlueBTLE ($name) - set blockingCallLoglevel to default";
        }
    }
    
    return undef;
}

sub CometBlueBTLE_Notify($$) {

    my ($hash,$dev) = @_;
    my $name = $hash->{NAME};
    return if (IsDisabled($name));
    
    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events = deviceEvents($dev,1);
    return if (!$events);


    CometBlueBTLE_stateRequestTimer($hash) if( (grep /^DEFINED.$name$/,@{$events}
                                                    or grep /^INITIALIZED$/,@{$events}
                                                    or grep /^MODIFIED.$name$/,@{$events}
                                                    or grep /^DELETEATTR.$name.disable$/,@{$events}
                                                    or grep /^ATTR.$name.disable.0$/,@{$events}
                                                    or grep /^DELETEATTR.$name.interval$/,@{$events}
                                                    or grep /^DELETEATTR.$name.model$/,@{$events}
                                                    or grep /^ATTR.$name.model.+/,@{$events}
                                                    or grep /^ATTR.$name.interval.[0-9]+/,@{$events} ) and $init_done and $devname eq 'global' );

    return;
}

sub CometBlueBTLE_stateRequest($) {

    my ($hash)      = @_;
    my $name        = $hash->{NAME};
    my %readings;
    
    
    if( AttrVal($name,'model','none') eq 'none') {
        readingsSingleUpdate($hash,"state","set attribute model first",1);
        
    } elsif( !IsDisabled($name) ) {
        if( ReadingsVal($name,'firmware','none') ne 'none' ) {
        
            return CometBlueBTLE_CreateParamGatttool($hash,'read',$gatttChar{AttrVal($name,'model','')}{'battery'})
            if( CometBlueBTLE_CallBattery_IsUpdateTimeAgeToOld($hash,$CallBatteryAge{AttrVal($name,'BatteryFirmwareAge','24h')}) );

            CometBlueBTLE_CreateParamGatttool($hash,'read',$gatttChar{AttrVal($name,'model','')}{'payload'}) if( $hash->{helper}{writePin} == 0 );
            
        } else {

            CometBlueBTLE_CreateParamGatttool($hash,'read',$gatttChar{AttrVal($name,'model','')}{'firmware'});
        }

    } else {
        readingsSingleUpdate($hash,"state","disabled",1);
    }
}

sub CometBlueBTLE_stateRequestTimer($) {

    my ($hash)      = @_;
    
    my $name        = $hash->{NAME};

        
    CometBlueBTLE_stateRequest($hash) if( $init_done );
    
    InternalTimer( gettimeofday()+$hash->{INTERVAL}+int(rand(60)), "CometBlueBTLE_stateRequestTimer", $hash );
    
    Log3 $name, 4, "CometBlueBTLE ($name) - stateRequestTimer: Call Request Timer";
}

sub CometBlueBTLE_Set($$@) {
    
    my ($hash, $name, @aa)  = @_;
    my ($cmd, @args)        = @aa;
    

    my $mod                 = 'write';
    my $handle;
    my $value;
    
    if( $cmd eq 'desired-temp' ) {
        return 'CometBlueBTLE: desired-temp requires <temperature> in celsius degrees as additional parameter' if(@args < 1);
        return 'CometBlueBTLE: desired-temp supports temperatures from 6.0 - 28.0 degrees' if($args[0]<6.0 || $args[0]>28.0);
        
        $mod = 'write'; $handle = $gatttChar{AttrVal($name,'model','')}{'payload'};
        $value = join( " ", @args);
        
    } elsif( $cmd eq 'nert' ) {
    
        $mod = 'write'; $handle = $gatttChar{AttrVal($name,'model','')}{'noep'};
        $value = join( " ", @args);
    
    } else {
        my  $list = "desired-temp:on,off,6,6.5,7,7.5,8,8.5,9,9.5,10,10.5,11,11.5,12,12.5,13,13.5,14,14.5,15,15.5,16,16.5,17,17.5,18,18.5,19,19.5,20,20.5,21,21.5,22,22.5,23,23.5,24,24.5,25,25.5,26,26.5,27,27.5,28";
            $list .= "";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    return 'another process is running, try again later' if( $hash->{helper}{writePin} == 1 );

    CometBlueBTLE_CreateParamGatttool($hash,'write',$handle,CometBlueBTLE_CreatePayloadString($hash,$cmd,$value));
    
    return undef;
}

sub CometBlueBTLE_Get($$@) {
    
    my ($hash, $name, @aa)  = @_;
    my ($cmd, @args)        = @aa;

    my $handle;


    if( $cmd eq 'temperatures' ) {
        return 'usage: temperatures' if( @args != 0 );
        
        return 'another process is running, try again later' if( $hash->{helper}{writePin} == 1 );
        return CometBlueBTLE_stateRequest($hash);
        
    } elsif( $cmd eq 'firmware' ) {
        return 'usage: firmware' if( @args != 0 );

        $handle = $gatttChar{AttrVal($name,'model','')}{'firmware'};
        
    } elsif( $cmd eq 'devicename' ) {
        return 'usage: devicename' if( @args != 0 );

        $handle = $gatttChar{AttrVal($name,'model','')}{'devicename'};
        
    } else {
        my $list = "temperatures:noArg devicename:noArg firmware:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }

    return 'another process is running, try again later' if( $hash->{helper}{writePin} == 1 );

    CometBlueBTLE_CreateParamGatttool($hash,'read',$handle) if( $cmd ne 'temperatures' );

    return undef;
}

sub CometBlueBTLE_CreateParamGatttool($@) {

    my ($hash,$mod,$handle,$value)  = @_;
    my $name                        = $hash->{NAME};
    my $mac                         = $hash->{BTMAC};


    Log3 $name, 4, "CometBlueBTLE ($name) - Run CreateParamGatttool with mod: $mod";
    Log3 $name, 3, "CometBlueBTLE ($name) - Run CreateParamGatttool with mod: $mod : $handle : $value" if( defined($value) );
    
    if( $hash->{helper}{writePin} == 0 ) {
    
        $hash->{helper}{writePin} = 1;
        $hash->{helper}{paramGatttool}{mod}     = $mod;
        $hash->{helper}{paramGatttool}{handle}  = $handle;
        $hash->{helper}{paramGatttool}{value}   = $value if( $mod eq 'write' );
        
        $hash->{helper}{RUNNING_PID} = BlockingCall("CometBlueBTLE_ExecGatttool_Run", $name."|".$mac."|write|".$gatttChar{AttrVal($name,'model','')}{'pin'}."|".CometBlueBTLE_ConvertPinToHexLittleEndian(AttrVal($name,'pin','00000000')), "CometBlueBTLE_ExecGatttool_Done", 60, "CometBlueBTLE_ExecGatttool_Aborted", $hash) unless( exists($hash->{helper}{RUNNING_PID}) );
        
        readingsSingleUpdate($hash,"state","pairing thermostat with pin: " . CometBlueBTLE_ConvertPinToHexLittleEndian(AttrVal($name,'pin','00000000')),1);
    
        Log3 $name, 3, "CometBlueBTLE ($name) - Read CometBlueBTLE_ExecGatttool_Run $name|$mac|$mod|$handle";

    } elsif( $mod eq 'read' ) {
        $hash->{helper}{RUNNING_PID} = BlockingCall("CometBlueBTLE_ExecGatttool_Run", $name."|".$mac."|".$mod."|".$handle, "CometBlueBTLE_ExecGatttool_Done", 60, "CometBlueBTLE_ExecGatttool_Aborted", $hash) unless( exists($hash->{helper}{RUNNING_PID}) );
        
        readingsSingleUpdate($hash,"state","read sensor data",1);
    
        Log3 $name, 3, "CometBlueBTLE ($name) - Read CometBlueBTLE_ExecGatttool_Run $name|$mac|$mod|$handle";

    } elsif( $mod eq 'write' ) {
        $hash->{helper}{RUNNING_PID} = BlockingCall("CometBlueBTLE_ExecGatttool_Run", $name."|".$mac."|".$mod."|".$handle."|".$value, "CometBlueBTLE_ExecGatttool_Done", 60, "CometBlueBTLE_ExecGatttool_Aborted", $hash) unless( exists($hash->{helper}{RUNNING_PID}) );
        
        readingsSingleUpdate($hash,"state","write sensor data",1);
    
        Log3 $name, 3, "CometBlueBTLE ($name) - Write CometBlueBTLE_ExecGatttool_Run $name|$mac|$mod|$handle|$value";
    }
}

sub CometBlueBTLE_ExecGatttool_Run($) {

    my $string      = shift;
    
    my ($name,$mac,$gattCmd,$handle,$value) = split("\\|", $string);
    my $sshHost                             = AttrVal($name,"sshHost","none");
    my $gatttool;
    my $json_notification;


    $gatttool                               = qx(which gatttool) if($sshHost eq 'none');
    $gatttool                               = qx(ssh $sshHost 'which gatttool') if($sshHost ne 'none');
    chomp $gatttool;
    
    if(defined($gatttool) and ($gatttool)) {
    
        my $cmd;
        my $loop;
        my @gtResult;
        my $wait    = 1;
        my $sshHost = AttrVal($name,"sshHost","none");
        my $hci     = AttrVal($name,"hciDevice","hci0");
        
        while($wait) {
        
            my $grepGatttool;
            $grepGatttool = qx(ps ax| grep -E \'gatttool -i $hci -b $mac\' | grep -v grep) if($sshHost eq 'none');
            $grepGatttool = qx(ssh $sshHost 'ps ax| grep -E "gatttool -i $hci -b $mac" | grep -v grep') if($sshHost ne 'none');

            if(not $grepGatttool =~ /^\s*$/) {
                Log3 $name, 3, "CometBlueBTLE ($name) - ExecGatttool_Run: another gatttool process is running. waiting...";
                sleep(1);
            } else {
                $wait = 0;
            }
        }
        
        $cmd .= "ssh $sshHost '" if($sshHost ne 'none');
        $cmd .= "gatttool -i $hci -b $mac ";
        $cmd .= "--char-read -a $handle" if($gattCmd eq 'read');
        $cmd .= "--char-write-req -a $handle -n $value" if($gattCmd eq 'write');
        $cmd .= " 2>&1 /dev/null";
        $cmd .= "'" if($sshHost ne 'none');
        
        $loop = 0;
        do {
            
            Log3 $name, 3, "CometBlueBTLE ($name) - ExecGatttool_Run: call gatttool with command $cmd and loop $loop";
            @gtResult = split(": ",qx($cmd));
            Log3 $name, 3, "CometBlueBTLE ($name) - ExecGatttool_Run: gatttool loop result ".join(",", @gtResult);
            $loop++;
            
            $gtResult[0] = 'connect error'
            unless( defined($gtResult[0]) );
            
        } while( $loop < 5 and $gtResult[0] eq 'connect error' );
        
        Log3 $name, 3, "CometBlueBTLE ($name) - ExecGatttool_Run: gatttool result ".join(",", @gtResult);

        
        $gtResult[1] = 'no data response'
        unless( defined($gtResult[1]) );

        $gtResult[1] = 'wrong PIN'
        if( $gtResult[1] =~ /Attribute value length is invalid/ );

    
        $json_notification = CometBlueBTLE_encodeJSON($gtResult[1]);
        
        if($gtResult[1] =~ /^([0-9a-f]{2}(\s?))*$/) {
            return "$name|$mac|ok|$gattCmd|$handle|$json_notification";
        
        } elsif($handle eq $gatttChar{AttrVal($name,'model','')}{'pin'} and $gattCmd eq 'write') {
            if($gtResult[1] eq 'wrong PIN') {
                return "$name|$mac|error|$gattCmd|$handle|$json_notification";
            } else {
                return "$name|$mac|ok|$gattCmd|$handle|$json_notification";
            }
        
        } elsif($gtResult[1] eq 'no data response' and $gattCmd eq 'write') {
            return "$name|$mac|ok|$gattCmd|$handle|$json_notification";
        
        } else {
            return "$name|$mac|error|$gattCmd|$handle|$json_notification";
        }
        
    } else {
        $json_notification = CometBlueBTLE_encodeJSON('no gatttool binary found. Please check if bluez-package is properly installed');
        return "$name|$mac|error|$gattCmd|$handle|$json_notification";
    }
}

sub CometBlueBTLE_ExecGatttool_Done($) {

    my $string      = shift;
    my ($name,$mac,$respstate,$gattCmd,$handle,$json_notification) = split("\\|", $string);
    
    my $hash                = $defs{$name};
    
    
    delete($hash->{helper}{RUNNING_PID});
    
    Log3 $name, 3, "CometBlueBTLE ($name) - ExecGatttool_Done: Helper is disabled. Stop processing" if($hash->{helper}{DISABLED});
    return if($hash->{helper}{DISABLED});
    
    Log3 $name, 3, "CometBlueBTLE ($name) - ExecGatttool_Done: gatttool return string: $string";
    
    if( $respstate eq 'ok' and $gattCmd eq 'write' and $handle ne $gatttChar{AttrVal($name,'model','')}{'pin'} and $hash->{helper}{writePin} == 1 ) {
        readingsSingleUpdate($hash, "lastChangeBy", "FHEM", 1);
        return CometBlueBTLE_CreateParamGatttool($hash,'read',$hash->{helper}{paramGatttool}{handle})
    }
    
    if( $respstate eq 'ok' and $gattCmd eq 'write' and $handle eq $gatttChar{AttrVal($name,'model','')}{'pin'} and $hash->{helper}{writePin} == 1 ) {
        return CometBlueBTLE_CreateParamGatttool($hash,$hash->{helper}{paramGatttool}{mod},$hash->{helper}{paramGatttool}{handle})
        if($handle ne $gatttChar{AttrVal($name,'model','')}{'payload'} and $hash->{helper}{paramGatttool}{mod} eq 'read');
        
        return CometBlueBTLE_CreateParamGatttool($hash,$hash->{helper}{paramGatttool}{mod},$hash->{helper}{paramGatttool}{handle},$hash->{helper}{paramGatttool}{value})
        if($handle ne $gatttChar{AttrVal($name,'model','')}{'payload'} and $hash->{helper}{paramGatttool}{mod} eq 'write');
        
        return CometBlueBTLE_stateRequest($hash) if($handle eq $gatttChar{AttrVal($name,'model','')}{'payload'} and $hash->{helper}{paramGatttool}{mod} eq 'read');
    }


    $hash->{helper}{writePin} = 0;

    my $decode_json =   eval{decode_json($json_notification)};
    if($@){
        Log3 $name, 3, "CometBlueBTLE ($name) - ExecGatttool_Done: JSON error while request: $@";
    }

    
    if( $respstate eq 'ok' ) {
        CometBlueBTLE_ProcessingNotification($hash,$gattCmd,$handle,$decode_json->{gtResult});
        
    } else {
        CometBlueBTLE_ProcessingErrors($hash,$decode_json->{gtResult});
    }
}

sub CometBlueBTLE_ExecGatttool_Aborted($) {

    my ($hash)  = @_;
    my $name    = $hash->{NAME};
    my %readings;

    delete($hash->{helper}{RUNNING_PID});
    readingsSingleUpdate($hash,"state","unreachable", 1);
    
    $readings{'lastGattError'} = 'The BlockingCall Process terminated unexpectedly. Timedout';
    CometBlueBTLE_WriteReadings($hash,\%readings);

    Log3 $name, 3, "CometBlueBTLE ($name) - ExecGatttool_Aborted: The BlockingCall Process terminated unexpectedly. Timedout";
}

sub CometBlueBTLE_ProcessingNotification($@) {

    my ($hash,$gattCmd,$handle,$notification)   = @_;
    
    my $name                                    = $hash->{NAME};
    my $readings;
    
    
    Log3 $name, 3, "CometBlueBTLE ($name) - ProcessingNotification";

    if( $handle eq $gatttChar{AttrVal($name,'model','')}{'battery'} ) {
        ### Flower Sens - Read Firmware and Battery Data
        Log3 $name, 3, "CometBlueBTLE ($name) - ProcessingNotification: handle $gatttChar{AttrVal($name,'model','')}{'battery'}";
        
        $readings = CometBlueBTLE_HandleBattery($hash,$notification);
        
    } elsif( $handle eq $gatttChar{AttrVal($name,'model','')}{'payload'} ) {
        ### payload abrufen
        Log3 $name, 3, "CometBlueBTLE ($name) - ProcessingNotification: handle $gatttChar{AttrVal($name,'model','')}{'payload'}";
        
        $readings = CometBlueBTLE_HandlePayload($hash,$notification);
    
    } elsif( $handle eq $gatttChar{AttrVal($name,'model','')}{'firmware'} ) {
        ### firmware abrufen
        Log3 $name, 3, "CometBlueBTLE ($name) - ProcessingNotification: handle $gatttChar{AttrVal($name,'model','')}{'firmware'}";
        
        $readings = CometBlueBTLE_HandleFirmware($hash,$notification);
        
    } elsif( $handle eq $gatttChar{AttrVal($name,'model','')}{'devicename'} ) {
        ### firmware abrufen
        Log3 $name, 3, "CometBlueBTLE ($name) - ProcessingNotification: handle $gatttChar{AttrVal($name,'model','')}{'devicename'}";
        
        $readings = CometBlueBTLE_HandleDevicename($hash,$notification);
    }
    
    
    CometBlueBTLE_WriteReadings($hash,$readings);
}

sub CometBlueBTLE_HandleBattery($$) {
    ### Read Battery Data
    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    
    Log3 $name, 3, "CometBlueBTLE ($name) - handle $gatttChar{AttrVal($name,'model','')}{'battery'}";
    
    chomp($notification);

    $readings{'batteryLevel'}   = hex("0x".$notification);
    $readings{'battery'}        = (hex("0x".$notification) > 15?"ok":"low");

    $hash->{helper}{CallBattery} = 1;
    CometBlueBTLE_CallBattery_Timestamp($hash);
    return \%readings;
}

sub CometBlueBTLE_HandlePayload($$) {
    ### Read Payload Data
    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    
    Log3 $name, 5, "CometBlueBTLE ($name) - handle $gatttChar{AttrVal($name,'model','')}{'battery'}";
    
    my @payload  = split(" ",$notification);


#     char-read-hnd 0x003d
#     Characteristic value/descriptor: 2a 38 20 2a 00 04 0a
#     2a= Zimmertemperatur (42/2 = 21°C)
#     38= Manuelle Temperatur (56/2 = 28°C) Welche am Display mit Drehrad oder mit der App eingestellt wird.
#     20= Minimale Ziel-Temperatur (32/2 = 16°C)
#     2a= Maximale Ziel-Temperatur (42/2 = 21 °C)
#     00= Ausgleichstemperatur 
#     04 = Fenster offen Detektor
#     0a= Zeit Fenster offen in Minuten


    $readings{'measured-temp'}      = hex("0x".$payload[0])/2;
    $readings{'desired-temp'}       = hex("0x".$payload[1])/2;
    $readings{'tempEco'}            = hex("0x".$payload[2])/2;
    $readings{'tempComfort'}        = hex("0x".$payload[3])/2;
    $readings{'tempOffset'}         = hex("0x".$payload[4]);
    $readings{'winOpnSensitivity'}  = $winOpnSensitivity{'Sensitivity'}{hex("0x".$payload[5])};
    $readings{'winOpnPeriod'}       = hex("0x".$payload[6]);
        
    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub CometBlueBTLE_HandleFirmware($$) {
    ### Read Firmware Data
    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    $notification =~ s/\s+//g;
    
    
    Log3 $name, 3, "CometBlueBTLE ($name) - handle $gatttChar{AttrVal($name,'model','')}{'firmware'}";

    $readings{'firmware'}   = pack('H*',$notification);

    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub CometBlueBTLE_HandleDevicename($$) {
    ### Read Devicename Data
    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    $notification =~ s/\s+//g;
    
    
    Log3 $name, 3, "CometBlueBTLE ($name) - handle $gatttChar{AttrVal($name,'model','')}{'devicename'}";

    $readings{'devicename'}   = pack('H*',$notification);

    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub CometBlueBTLE_WriteReadings($$) {

    my ($hash,$readings)    = @_;
    
    my $name                = $hash->{NAME};


    readingsBeginUpdate($hash);
    while( my ($r,$v) = each %{$readings} ) {
        Log3 $name, 5, "CometBlueBTLE ($name) - WriteReadings: Reading $r, value $v altes value " . ReadingsVal($name, $r,"");
        readingsBulkUpdateIfChanged($hash, "lastChangeBy", "Thermostat") if( ReadingsVal($name, $r,"") ne $v and $r ne 'measured-temp' );
        readingsBulkUpdateIfChanged($hash,$r,$v) if( $r ne 'lastGattError' );
        readingsBulkUpdate($hash,$r,$v) if( $r eq 'lastGattError' );
    }

    readingsBulkUpdateIfChanged($hash, "state", ($readings->{'lastGattError'}?'error':'T: '. ReadingsVal($name,'measured-temp',-100) . ' desired: ' . ReadingsVal($name,'desired-temp',-100)));
    readingsEndUpdate($hash,1);


    CometBlueBTLE_stateRequest($hash) if( $hash->{helper}{CallBattery} == 1 );

    Log3 $name, 3, "CometBlueBTLE ($name) - WriteReadings: Readings were written";

}

sub CometBlueBTLE_ProcessingErrors($$) {

    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    Log3 $name, 3, "CometBlueBTLE ($name) - ProcessingErrors";
    $readings{'lastGattError'} = $notification;
    
    CometBlueBTLE_WriteReadings($hash,\%readings);
}

#### my little Helper
sub CometBlueBTLE_encodeJSON($) {

    my $gtResult    = shift;
    
    
    chomp($gtResult);
    
    my %response = (
        'gtResult'      => $gtResult
    );
    
    return encode_json \%response;
}

## Routinen damit Firmware und Batterie nur alle X male statt immer aufgerufen wird
sub CometBlueBTLE_CallBattery_Timestamp($) {

    my $hash    = shift;
    
    
    # get timestamp
    $hash->{helper}{updateTimeCallBattery}      = gettimeofday(); # in seconds since the epoch
    $hash->{helper}{updateTimestampCallBattery} = FmtDateTime(gettimeofday());
}

sub CometBlueBTLE_CallBattery_UpdateTimeAge($) {

    my $hash    = shift;

    
    $hash->{helper}{updateTimeCallBattery}  = 0 if( not defined($hash->{helper}{updateTimeCallBattery}) );
    my $UpdateTimeAge = gettimeofday() - $hash->{helper}{updateTimeCallBattery};
    
    return $UpdateTimeAge;
}

sub CometBlueBTLE_CallBattery_IsUpdateTimeAgeToOld($$) {

    my ($hash,$maxAge)    = @_;;
    
    
    return (CometBlueBTLE_CallBattery_UpdateTimeAge($hash)>$maxAge ? 1:0);
}

sub CometBlueBTLE_CreateDevicenameHEX($) {

    my $devicename      = shift;
    
    my $devicenameHex = unpack("H*", $devicename);
    

    return $devicenameHex;
}

sub CometBlueBTLE_ConvertPinToHexLittleEndian($) {

    my $pin     = shift;
    
    
    return '00000000' if( $pin =~ /^0/ );
    
    my $hex     = unpack( 'V', pack( 'N', $pin ) );
    $hex = sprintf('0x%2x',$hex);
    return $hex;
}

sub CometBlueBTLE_CreatePayloadString($$$) {

    my ($hash,$setCmd,$value)   = @_;
    my $name                    = $hash->{NAME};


    $value = 00 if($value eq 'off');
    $value = 28 if($value eq 'on');

    return '00' . sprintf('%.2x',$value*2) . sprintf('%.2x',ReadingsVal($name,'tempEco',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempComfort',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempOffset',0)) . sprintf('%.2x',$winOpnSensitivity{'Sensitivity'}{ReadingsVal($name,'winOpnSensitivity',0)}) . sprintf('%.2x',ReadingsVal($name,'winOpnPeriod',0)) if( $setCmd eq 'desired-temp' );
    
    return '00' . sprintf('%.2x',ReadingsVal($name,'desired-temp',0)*2) . sprintf('%.2x',$value*2) . sprintf('%.2x',ReadingsVal($name,'tempComfort',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempOffset',0)) . sprintf('%.2x',$winOpnSensitivity{'Sensitivity'}{ReadingsVal($name,'winOpnSensitivity',0)}) . sprintf('%.2x',ReadingsVal($name,'winOpnPeriod',0)) if( $setCmd eq 'tempEco' );
    
    return '00' . sprintf('%.2x',ReadingsVal($name,'desired-temp',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempEco',0)*2) . sprintf('%.2x',$value*2) . sprintf('%.2x',ReadingsVal($name,'tempOffset',0)) . sprintf('%.2x',$winOpnSensitivity{'Sensitivity'}{ReadingsVal($name,'winOpnSensitivity',0)}) . sprintf('%.2x',ReadingsVal($name,'winOpnPeriod',0)) if( $setCmd eq 'tempComfort' );
    
    return '00' . sprintf('%.2x',ReadingsVal($name,'desired-temp',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempEco',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempComfort',0)*2) . sprintf('%.2x',$value) . sprintf('%.2x',$winOpnSensitivity{'Sensitivity'}{ReadingsVal($name,'winOpnSensitivity',0)}) . sprintf('%.2x',ReadingsVal($name,'winOpnPeriod',0)) if( $setCmd eq 'tempOffset' );
    
    return '00' . sprintf('%.2x',ReadingsVal($name,'desired-temp',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempEco',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempComfort',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempOffset',0)) . sprintf('%.2x',$winOpnSensitivity{'Sensitivity'}{$value}) . sprintf('%.2x',ReadingsVal($name,'winOpnPeriod',0)) if( $setCmd eq 'winOpnSensitivity' );
    
    return '00' . sprintf('%.2x',ReadingsVal($name,'desired-temp',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempEco',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempComfort',0)*2) . sprintf('%.2x',ReadingsVal($name,'tempOffset',0)) . sprintf('%.2x',$winOpnSensitivity{'Sensitivity'}{ReadingsVal($name,'winOpnSensitivity',0)}) . sprintf('%.2x',$value) if( $setCmd eq 'winOpnPeriod' );

}








1;








=pod
=item device
=item summary       
=item summary_DE    

=begin html

<a name=""></a>
<h3></h3>


=end html

=begin html_DE

<a name=""></a>
<h3></h3>


=end html_DE

=cut
