###############################################################################
#
# Developed with Kate
#
#  (c) 2018 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to:
#       - mokeo for many bugfix code
#
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

## Info https://www.torsten-traenkner.de/wissen/smarthome/heizung.php
## Die folgenden Modelle sind identisch. Man kann sich das günstigste Modell auswählen.
##
## Name                	Preis      	Vertrieb über
## -----------------------------------------------
## Xavax Hama           40 Euro     Media Markt
## Sygonix HT100 BT     20 Euro     Conrad
## Comet Blue           20 Euro     Real / Bauhaus
## SilverCrest          15 Euro     Lidl
## THERMy blue                      Aldi

package main;

use strict;
use warnings;

my $version = "0.2.1";

sub CometBlueBTLE_Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}    = "CometBlueBTLE::Set";
    $hash->{GetFn}    = "CometBlueBTLE::Get";
    $hash->{DefFn}    = "CometBlueBTLE::Define";
    $hash->{NotifyFn} = "CometBlueBTLE::Notify";
    $hash->{UndefFn}  = "CometBlueBTLE::Undef";
    $hash->{AttrFn}   = "CometBlueBTLE::Attr";
    $hash->{AttrList} =
        "interval "
      . "disable:1 "
      . "disabledForIntervals "
      . "hciDevice:hci0,hci1,hci2 "
      . "batteryFirmwareAge:8h,16h,24h,32h,40h,48h "
      . "sshHost "
      . "blockingCallLoglevel:2,3,4,5 " . "pin "
      . "model:CometBlue,SilverCrest,Sygonix,THERMyBlue "
      . $readingFnAttributes;

    foreach my $d ( sort keys %{ $modules{CometBlueBTLE}{defptr} } ) {
        my $hash = $modules{CometBlueBTLE}{defptr}{$d};
        $hash->{VERSION} = $version;
    }
}

package CometBlueBTLE;

my $missingModul = "";

use strict;
use warnings;
use POSIX;

use GPUtils qw(GP_Import)
  ;    # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt

eval "use JSON;1"     or $missingModul .= "JSON ";
eval "use Blocking;1" or $missingModul .= "Blocking ";

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsEndUpdate
          defs
          modules
          Log3
          CommandAttr
          AttrVal
          ReadingsVal
          ReadingsAge
          IsDisabled
          deviceEvents
          init_done
          gettimeofday
          InternalTimer
          RemoveInternalTimer
          BlockingKill
          BlockingCall
          FmtDateTime)
    );
}

my %gatttChar = (
    CometBlue => {
        'devicename' => '0x3',
        'battery'    => '0x41',
        'payload'    => '0x3f',
        'firmware'   => '0x18',
        'pin'        => '0x47',
        'date'       => '0x1d',
        'tempLists'  => '0x29,0x2b,0x1f,0x21,0x23,0x25,0x27,end'
    },
    Sygonix => {
        'devicename' => '0x3',
        'battery'    => '0x41',
        'payload'    => '0x3f',
        'firmware'   => '0x18',
        'pin'        => '0x47',
        'date'       => '0x1d',
        'tempLists'  => '0x29,0x2b,0x1f,0x21,0x23,0x25,0x27,end'
    },
    SilverCrest => {
        'devicename' => '0x3',
        'battery'    => '0x3f',
        'payload'    => '0x3d',
        'firmware'   => '0x18',
        'pin'        => '0x48'
    },
    THERMyBlue => {
        'devicename' => '0x3',
        'battery'    => '0x3f',
        'payload'    => '0x3d',
        'firmware'   => '0x18',
        'pin'        => '0x48',
        'date'       => '0x1b',
        'tempLists'  => '0x27,0x29,0x1d,0x1f,0x21,0x23,0x25,end'
    }
);

my %winOpnSensitivity = (
    Sensitivity => {
        '12'     => 'low',
        '8'      => 'medium',
        '4'      => 'high',
        'low'    => '12',
        'medium' => '8',
        'high'   => '4'
    }
);

my %CallBatteryAge = (
    '8h'  => 28800,
    '16h' => 57600,
    '24h' => 86400,
    '32h' => 115200,
    '40h' => 144000,
    '48h' => 172800
);

# declare prototype
sub ExecGatttool_Run($);

sub Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return "too few parameters: define <name> CometBlueBTLE <BTMAC>"
      if ( @a != 3 );
    return
"Cannot define CometBlueBTLE device. Perl modul ${missingModul}is missing."
      if ($missingModul);

    my $name = $a[0];
    my $mac  = $a[2];

    $hash->{BTMAC}                = $mac;
    $hash->{VERSION}              = $version;
    $hash->{INTERVAL}             = 150;
    $hash->{helper}{writePin}     = 0;
    $hash->{helper}{CallBattery}  = 0;
    $hash->{NOTIFYDEV}            = "global,$name";
    $hash->{loglevel}             = 4;
    $hash->{tempListsHandleQueue} = [];

    readingsSingleUpdate( $hash, "state", "initialized", 0 );
    CommandAttr( undef, $name . ' room CometBlueBTLE' )
      if ( AttrVal( $name, 'room', 'none' ) eq 'none' );

    Log3 $name, 3, "CometBlueBTLE ($name) - defined with BTMAC $hash->{BTMAC}";

    $modules{CometBlueBTLE}{defptr}{ $hash->{BTMAC} } = $hash;
    return undef;
}

sub Undef($$) {

    my ( $hash, $arg ) = @_;

    my $mac  = $hash->{BTMAC};
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    BlockingKill( $hash->{helper}{RUNNING_PID} )
      if ( defined( $hash->{helper}{RUNNING_PID} ) );

    delete( $modules{CometBlueBTLE}{defptr}{$mac} );
    Log3 $name, 3, "Sub CometBlueBTLE_Undef ($name) - delete device $name";
    return undef;
}

sub Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq "disable" ) {
        if ( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);

            readingsSingleUpdate( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "CometBlueBTLE ($name) - disabled";
        }

        elsif ( $cmd eq "del" ) {
            Log3 $name, 3, "CometBlueBTLE ($name) - enabled";
        }
    }

    elsif ( $attrName eq "disabledForIntervals" ) {
        if ( $cmd eq "set" ) {
            return
"check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
              unless ( $attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/ );
            Log3 $name, 3, "CometBlueBTLE ($name) - disabledForIntervals";
            readingsSingleUpdate( $hash, "state", "disabled", 1 );
        }
        elsif ( $cmd eq "del" ) {
            Log3 $name, 3, "CometBlueBTLE ($name) - enabled";
            readingsSingleUpdate( $hash, "state", "active", 1 );
        }
    }

    elsif ( $attrName eq "pin" ) {
        if ( $cmd eq "set" ) {
            return "the pin string may not begin with 0"
              unless ( $attrVal =~ /^[1-9]/ );
        }
    }

    elsif ( $attrName eq "interval" ) {
        RemoveInternalTimer($hash);

        if ( $cmd eq "set" ) {
            if ( $attrVal < 30 ) {
                Log3 $name, 3,
"CometBlueBTLE ($name) - interval too small, please use something >= 30 (sec), default is 150 (sec)";
                return
"interval too small, please use something >= 30 (sec), default is 150 (sec)";
            }
            else {
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3,
                  "CometBlueBTLE ($name) - set interval to $attrVal";
            }
        }

        elsif ( $cmd eq "del" ) {
            $hash->{INTERVAL} = 300;
            Log3 $name, 3, "CometBlueBTLE ($name) - set interval to default";
        }
    }

    elsif ( $attrName eq "blockingCallLoglevel" ) {
        if ( $cmd eq "set" ) {
            $hash->{loglevel} = $attrVal;
            Log3 $name, 3,
              "CometBlueBTLE ($name) - set blockingCallLoglevel to $attrVal";
        }

        elsif ( $cmd eq "del" ) {
            $hash->{loglevel} = 4;
            Log3 $name, 3,
              "CometBlueBTLE ($name) - set blockingCallLoglevel to default";
        }
    }

    return undef;
}

sub Notify($$) {

    my ( $hash, $dev ) = @_;
    my $name = $hash->{NAME};
    return if ( IsDisabled($name) );

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = deviceEvents( $dev, 1 );
    return if ( !$events );

    StateRequestTimer($hash)
      if (
        (
            (
                (
                    grep /^DEFINED.$name$/,
                    @{$events}
                    or grep /^INITIALIZED$/,
                    @{$events}
                    or grep /^MODIFIED.$name$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.disable$/,
                    @{$events}
                    or grep /^ATTR.$name.disable.0$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.interval$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.model$/,
                    @{$events}
                    or grep /^ATTR.$name.model.+/,
                    @{$events}
                    or grep /^ATTR.$name.interval.[0-9]+/,
                    @{$events}
                )
                and $devname eq 'global'
            )
            or grep /^resetBatteryTimestamp$/,
            @{$events}
        )
        and $init_done
      );

    return;
}

sub StateRequest($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    my %readings;

    if ( AttrVal( $name, 'model', 'none' ) eq 'none' ) {
        readingsSingleUpdate( $hash, "state", "set attribute model first", 1 );

    }
    elsif ( !IsDisabled($name) ) {
        if ( ReadingsVal( $name, 'firmware', 'none' ) ne 'none' ) {

            return CreateParamGatttool( $hash, 'read',
                $gatttChar{ AttrVal( $name, 'model', '' ) }{'battery'} )
              if (
                CallBattery_IsUpdateTimeAgeTooOld(
                    $hash,
                    $CallBatteryAge{ AttrVal( $name, 'BatteryFirmwareAge',
                            '24h' ) }
                )
              );

            CreateParamGatttool( $hash, 'read',
                $gatttChar{ AttrVal( $name, 'model', '' ) }{'payload'} )
              if ( $hash->{helper}{writePin} == 0 );

        }
        else {

            CreateParamGatttool( $hash, 'read',
                $gatttChar{ AttrVal( $name, 'model', '' ) }{'firmware'} );
        }

    }
    else {
        readingsSingleUpdate( $hash, "state", "disabled", 1 );
    }
}

sub StateRequestTimer($) {

    my ($hash) = @_;

    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    StateRequest($hash) if ($init_done);
    InternalTimer( gettimeofday() + $hash->{INTERVAL} + int( rand(60) ),
        "CometBlueBTLE::StateRequestTimer", $hash );

    Log3 $name, 4,
      "CometBlueBTLE ($name) - stateRequestTimer: Call Request Timer";
}

sub Set($$@) {

    my ( $hash, $name, @aa ) = @_;
    my ( $cmd, @args ) = @aa;

    my $handle;
    my $value;

    if ( $cmd eq 'desired-temp' or $cmd eq 'controlManu' ) {
        return
'CometBlueBTLE: desired-temp requires <temperature> in degrees celsius as additional parameter'
          if ( @args < 1 );

#return 'CometBlueBTLE: desired-temp supports temperatures from 6.0 - 28.0 degrees' if($args[0]<8.0 or $args[0]>28.0 or $args[0] ne 'on' or $args[0] ne 'off');

        $handle = $gatttChar{ AttrVal( $name, 'model', '' ) }{'payload'};
        $value = join( " ", @args );

    }
    elsif ( $cmd eq 'tempEco' ) {
        return
'CometBlueBTLE: tempEco requires <temperature> in degrees celsius as additional parameter'
          if ( @args < 1 );
        return
'CometBlueBTLE: tempEco supports temperatures from 6.0 to 28.0 degrees'
          if ( $args[0] < 12.0 or $args[0] > 23.0 );

        $handle = $gatttChar{ AttrVal( $name, 'model', '' ) }{'payload'};
        $value = join( " ", @args );

    }
    elsif ( $cmd eq 'tempComfort' ) {
        return
'CometBlueBTLE: tempComfort requires <temperature> in degrees celsius as additional parameter'
          if ( @args < 1 );
        return
'CometBlueBTLE: tempComfort supports temperatures from 6.0 to 28.0 degrees'
          if ( $args[0] < 12.0 or $args[0] > 23.0 );

        $handle = $gatttChar{ AttrVal( $name, 'model', '' ) }{'payload'};
        $value = join( " ", @args );

    }
    elsif ( $cmd eq 'tempOffset' ) {
        return 'CometBlueBTLE: tempOffset requires an additional parameter'
          if ( @args < 1 );
        return 'CometBlueBTLE: tempOffset supports values from -5.0 to 5.0'
          if ( $args[0] < -5.0 or $args[0] > 5.0 );

        $handle = $gatttChar{ AttrVal( $name, 'model', '' ) }{'payload'};
        $value = join( " ", @args );

    }
    elsif ( $cmd eq 'winOpnSensitivity' ) {
        return
'CometBlueBTLE: winOpnSensitivity requires an additional parameter high, medium or low'
          if ( @args < 1
            or $args[0] ne 'high'
            or $args[0] ne 'medium'
            or $args[0] ne 'low' );

        $handle = $gatttChar{ AttrVal( $name, 'model', '' ) }{'payload'};
        $value = join( " ", @args );

    }
    elsif ( $cmd eq 'winOpnPeriod' ) {
        return
'CometBlueBTLE: winOpnSensitivity requires an additional parameter in minutes'
          if ( @args < 1 );

        $handle = $gatttChar{ AttrVal( $name, 'model', '' ) }{'payload'};
        $value = join( " ", @args );

    }
    elsif ( $cmd eq 'resetBatteryTimestamp' ) {
        return "usage: resetBatteryTimestamp" if ( @args != 0 );

        $hash->{helper}{updateTimeCallBattery} = 0;
        return;

    }
    else {
        my $list =
"desired-temp:on,off,Eco,Comfort,8.0,8.5,9.0,9.5,10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0,23.5,24.0,24.5,25.0,25.5,26.0,26.5,27.0,27.5,28.0";
        $list .=
" controlManu:on,off,8.0,8.5,9.0,9.5,10.0,10.5,11.0,11.5,12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0,23.5,24.0,24.5,25.0,25.5,26.0,26.5,27.0,27.5,28.0";
        $list .=
" tempEco:12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0";
        $list .=
" tempComfort:12.0,12.5,13.0,13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0";
        $list .=
" tempOffset:-5,-4.5,-4,-3.5,-3,-2.5,-2,-1.5,-1,-0.5,0,0.5,1,1.5,2,2.5,3,3.5,4,4.5,5 winOpnSensitivity:high,medium,low winOpnPeriod:slider,5,5,30";

        return "Unknown argument $cmd, choose one of $list";
    }

    return 'another process is running, try again later'
      if ( $hash->{helper}{writePin} == 1 );

    CreateParamGatttool( $hash, 'write', $handle,
        CreatePayloadString( $hash, $cmd, $value ) );

    return undef;
}

sub Get($$@) {

    my ( $hash, $name, @aa ) = @_;
    my ( $cmd, @args ) = @aa;

    my $handle;

    if ( $cmd eq 'temperatures' ) {
        return 'usage: temperatures' if ( @args != 0 );

        return 'another process is running, try again later'
          if ( $hash->{helper}{writePin} == 1 );
        return StateRequest($hash);

    }
    elsif ( $cmd eq 'firmware' ) {
        return 'usage: firmware' if ( @args != 0 );

        $handle = $gatttChar{ AttrVal( $name, 'model', '' ) }{'firmware'};

    }
    elsif ( $cmd eq 'devicename' ) {
        return 'usage: devicename' if ( @args != 0 );

        $handle = $gatttChar{ AttrVal( $name, 'model', '' ) }{'devicename'};

    }
    elsif ( $cmd eq 'tempLists' ) {
        return 'usage: tempLists' if ( @args != 0 );

        if ( defined( $hash->{tempListsHandleQueue} )
            and scalar( @{ $hash->{tempListsHandleQueue} } ) == 0 )
        {
            foreach (
                split(
                    ',',
                    $gatttChar{ AttrVal( $name, 'model', '' ) }{'tempLists'}
                )
              )
            {
                unshift( @{ $hash->{tempListsHandleQueue} }, $_ );
            }
        }

        $handle = pop( @{ $hash->{tempListsHandleQueue} } );

    }
    else {
        my $list =
          "temperatures:noArg devicename:noArg firmware:noArg tempLists:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }

    return 'another process is running, try again later'
      if ( $hash->{helper}{writePin} == 1 );

    CreateParamGatttool( $hash, 'read', $handle ) if ( $cmd ne 'temperatures' );

    return undef;
}

sub CreateParamGatttool($@) {

    my ( $hash, $mod, $handle, $value ) = @_;
    my $name = $hash->{NAME};
    my $mac  = $hash->{BTMAC};

    Log3 $name, 4,
      "CometBlueBTLE ($name) - Run CreateParamGatttool with mod: $mod";
    Log3 $name, 4,
"CometBlueBTLE ($name) - Run CreateParamGatttool with mod: $mod : $handle : $value"
      if ( defined($value) );
    Log3 $name, 5, "CometBlueBTLE ($name) - Noch in Queue nach pop: "
      . scalar( @{ $hash->{tempListsHandleQueue} } );

    if ( $hash->{helper}{writePin} == 0 ) {
        Log3 $name, 4, "CometBlueBTLE ($name) - CreateParamGatttool erstes if";
        $hash->{helper}{writePin}              = 1;
        $hash->{helper}{paramGatttool}{mod}    = $mod;
        $hash->{helper}{paramGatttool}{handle} = $handle;
        $hash->{helper}{paramGatttool}{value} = $value if ( $mod eq 'write' );

        $hash->{helper}{RUNNING_PID} = BlockingCall(
            "CometBlueBTLE::ExecGatttool_Run",
            $name . "|"
              . $mac
              . "|write|"
              . $gatttChar{ AttrVal( $name, 'model', '' ) }{'pin'} . "|"
              . ConvertPinToHexLittleEndian(
                AttrVal( $name, 'pin', '00000000' )
              ),
            "CometBlueBTLE::ExecGatttool_Done",
            60,
            "CometBlueBTLE::ExecGatttool_Aborted",
            $hash
        ) unless ( exists( $hash->{helper}{RUNNING_PID} ) );

        readingsSingleUpdate(
            $hash, "state",
            "pairing thermostat with pin: "
              . ConvertPinToHexLittleEndian(
                AttrVal( $name, 'pin', '00000000' )
              ),
            1
        );

        Log3 $name, 4,
"CometBlueBTLE ($name) - Read CometBlueBTLE_ExecGatttool_Run $name|$mac|$mod|$handle";

    }
    elsif ( $mod eq 'read' ) {
        Log3 $name, 4, "CometBlueBTLE ($name) - CreateParamGatttool zweites if";
        $hash->{helper}{RUNNING_PID} = BlockingCall(
            "CometBlueBTLE::ExecGatttool_Run",
            $name . "|" . $mac . "|" . $mod . "|" . $handle,
            "CometBlueBTLE::ExecGatttool_Done",
            60,
            "CometBlueBTLE::ExecGatttool_Aborted",
            $hash
        ) unless ( exists( $hash->{helper}{RUNNING_PID} ) );

        readingsSingleUpdate( $hash, "state", "read sensor data", 1 );

        Log3 $name, 4,
"CometBlueBTLE ($name) - Read CometBlueBTLE_ExecGatttool_Run $name|$mac|$mod|$handle";

    }
    elsif ( $mod eq 'write' ) {
        Log3 $name, 4, "CometBlueBTLE ($name) - CreateParamGatttool drittes if";
        $hash->{helper}{RUNNING_PID} = BlockingCall(
            "CometBlueBTLE::ExecGatttool_Run",
            $name . "|" . $mac . "|" . $mod . "|" . $handle . "|" . $value,
            "CometBlueBTLE::ExecGatttool_Done",
            60,
            "CometBlueBTLE::ExecGatttool_Aborted",
            $hash
        ) unless ( exists( $hash->{helper}{RUNNING_PID} ) );

        readingsSingleUpdate( $hash, "state", "write sensor data", 1 );

        Log3 $name, 4,
"CometBlueBTLE ($name) - Write CometBlueBTLE_ExecGatttool_Run $name|$mac|$mod|$handle|$value";
    }
}

sub ExecGatttool_Run($) {

    my $string = shift;

    my ( $name, $mac, $gattCmd, $handle, $value ) = split( "\\|", $string );
    my $sshHost = AttrVal( $name, "sshHost", "none" );
    my $gatttool;
    my $json_notification;

    $gatttool = qx(which gatttool) if ( $sshHost eq 'none' );
    $gatttool = qx(ssh $sshHost 'which gatttool') if ( $sshHost ne 'none' );
    chomp $gatttool;

    if ( defined($gatttool) and ($gatttool) ) {

        my $cmd;
        my $loop;
        my @gtResult;
        my $wait    = 1;
        my $sshHost = AttrVal( $name, "sshHost", "none" );
        my $hci     = AttrVal( $name, "hciDevice", "hci0" );

        while ($wait) {

            my $grepGatttool;
            my $gatttoolCmdlineStaticEscaped =
              CmdlinePreventGrepFalsePositive("gatttool -i $hci -b $mac");

            $grepGatttool = qx(ps ax| grep -E \'$gatttoolCmdlineStaticEscaped\')
              if ( $sshHost eq 'none' );
            $grepGatttool =
              qx(ssh $sshHost 'ps ax| grep -E "$gatttoolCmdlineStaticEscaped"')
              if ( $sshHost ne 'none' );

            if ( not $grepGatttool =~ /^\s*$/ ) {
                Log3 $name, 4,
"CometBlueBTLE ($name) - ExecGatttool_Run: another gatttool process is running. waiting...";
                sleep(1);
            }
            else {
                $wait = 0;
            }
        }

        $cmd .= "ssh $sshHost '"         if ( $sshHost ne 'none' );
        $cmd .= "gatttool -i $hci -b $mac ";
        $cmd .= "--char-read -a $handle" if ( $gattCmd eq 'read' );
        $cmd .= "--char-write-req -a $handle -n $value"
          if ( $gattCmd eq 'write' );
        $cmd .= " 2>&1 /dev/null";
        $cmd .= "'" if ( $sshHost ne 'none' );

        $loop = 0;
        do {

            Log3 $name, 4,
"CometBlueBTLE ($name) - ExecGatttool_Run: call gatttool with command $cmd and loop $loop";
            @gtResult = split( ": ", qx($cmd) );
            Log3 $name, 5,
              "CometBlueBTLE ($name) - ExecGatttool_Run: gatttool loop result "
              . join( ",", @gtResult );
            $loop++;

            $gtResult[0] = 'connect error'
              unless ( defined( $gtResult[0] ) );

        } while ( $loop < 5 and $gtResult[0] eq 'connect error' );

        Log3 $name, 4,
          "CometBlueBTLE ($name) - ExecGatttool_Run: gatttool result "
          . join( ",", @gtResult );

        $gtResult[1] = 'no data response'
          unless ( defined( $gtResult[1] ) );

        $gtResult[1] = 'wrong PIN'
          if ( $gtResult[1] =~ /Attribute value length is invalid/ );

        $json_notification = EncodeJSON( $gtResult[1] );

        if ( $gtResult[0] =~ /^connect error$/ ) {
            return "$name|$mac|error|$gattCmd|$handle|$json_notification";

        }
        elsif ( $gtResult[1] =~ /^([0-9a-f]{2}(\s?))*$/ ) {
            return "$name|$mac|ok|$gattCmd|$handle|$json_notification";

        }
        elsif ( $handle eq $gatttChar{ AttrVal( $name, 'model', '' ) }{'pin'}
            and $gattCmd eq 'write' )
        {
            if ( $gtResult[1] eq 'wrong PIN' ) {
                return "$name|$mac|error|$gattCmd|$handle|$json_notification";
            }
            else {
                return "$name|$mac|ok|$gattCmd|$handle|$json_notification";
            }

        }
        elsif ( $gtResult[1] eq 'no data response' and $gattCmd eq 'write' ) {
            return "$name|$mac|ok|$gattCmd|$handle|$json_notification";

        }
        else {
            return "$name|$mac|error|$gattCmd|$handle|$json_notification";
        }

    }
    else {
        $json_notification = EncodeJSON(
'no gatttool binary found. Please check if bluez-package is properly installed'
        );
        return "$name|$mac|error|$gattCmd|$handle|$json_notification";
    }
}

sub ExecGatttool_Done($) {

    my $string = shift;
    my ( $name, $mac, $respstate, $gattCmd, $handle, $json_notification ) =
      split( "\\|", $string );

    my $hash = $defs{$name};

    delete( $hash->{helper}{RUNNING_PID} );

    Log3 $name, 3,
"CometBlueBTLE ($name) - ExecGatttool_Done: Helper is disabled. Stop processing"
      if ( $hash->{helper}{DISABLED} );
    return if ( $hash->{helper}{DISABLED} );

    Log3 $name, 4,
"CometBlueBTLE ($name) - ExecGatttool_Done: gatttool return string: $string";

    if (
        $respstate eq 'ok'
        and (
            $gattCmd eq 'write'
            or ( defined( $hash->{tempListsHandleQueue} )
                and scalar( @{ $hash->{tempListsHandleQueue} } ) > 0 )
        )
        and $handle ne $gatttChar{ AttrVal( $name, 'model', '' ) }{'pin'}
        and $hash->{helper}{writePin} == 1
      )
    {

        if ( $gattCmd eq 'write' ) {
            readingsBeginUpdate($hash);
            readingsBulkUpdateIfChanged( $hash, "lastChangeBy", "FHEM" );
            readingsEndUpdate( $hash, 1 );
        }

        return CreateParamGatttool( $hash, 'read',
            $hash->{helper}{paramGatttool}{handle} )
          if ( defined( $hash->{tempListsHandleQueue} )
            and scalar( @{ $hash->{tempListsHandleQueue} } ) == 0 );
    }

    elsif ( $respstate eq 'ok'
        and $gattCmd eq 'write'
        and $handle eq $gatttChar{ AttrVal( $name, 'model', '' ) }{'pin'}
        and $hash->{helper}{writePin} == 1 )
    {

        return CreateParamGatttool(
            $hash,
            $hash->{helper}{paramGatttool}{mod},
            $hash->{helper}{paramGatttool}{handle}
          )
          if ( $handle ne $gatttChar{ AttrVal( $name, 'model', '' ) }{'payload'}
            and $hash->{helper}{paramGatttool}{mod} eq 'read' );

        return CreateParamGatttool(
            $hash,
            $hash->{helper}{paramGatttool}{mod},
            $hash->{helper}{paramGatttool}{handle},
            $hash->{helper}{paramGatttool}{value}
          )
          if ( $handle ne $gatttChar{ AttrVal( $name, 'model', '' ) }{'payload'}
            and $hash->{helper}{paramGatttool}{mod} eq 'write' );

        return StateRequest($hash)
          if ( $handle eq $gatttChar{ AttrVal( $name, 'model', '' ) }{'payload'}
            and $hash->{helper}{paramGatttool}{mod} eq 'read' );
    }

    my $decode_json = eval { decode_json($json_notification) };
    if ($@) {
        Log3 $name, 3,
"CometBlueBTLE ($name) - ExecGatttool_Done: JSON error while request: $@";
    }

    if ( $respstate eq 'ok' ) {
        ProcessingNotification( $hash, $gattCmd, $handle,
            $decode_json->{gtResult} );

    }
    else {
        ProcessingErrors( $hash, $decode_json->{gtResult} );
    }

    $hash->{helper}{writePin} = 0
      if ( defined( $hash->{tempListsHandleQueue} )
        and scalar( @{ $hash->{tempListsHandleQueue} } ) == 0 );
}

sub ExecGatttool_Aborted($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    my %readings;

    delete( $hash->{helper}{RUNNING_PID} );
    readingsSingleUpdate( $hash, "state", "unreachable", 1 );

    $readings{'lastGattError'} =
      'The BlockingCall Process terminated unexpectedly. Timedout';
    WriteReadings( $hash, \%readings );

    $hash->{helper}{writePin} = 0;

    Log3 $name, 3,
"CometBlueBTLE ($name) - ExecGatttool_Aborted: The BlockingCall Process terminated unexpectedly. Timedout";
}

sub ProcessingNotification($@) {

    my ( $hash, $gattCmd, $handle, $notification ) = @_;

    my $name = $hash->{NAME};
    my $readings;

    Log3 $name, 4, "CometBlueBTLE ($name) - ProcessingNotification";
    Log3 $name, 4,
        "CometBlueBTLE ($name) - ProcessingNotification: handle "
      . $handle
      . " - Noch in Queue: "
      . scalar( @{ $hash->{tempListsHandleQueue} } );

    if ( $handle eq $gatttChar{ AttrVal( $name, 'model', '' ) }{'battery'} ) {
        ### Read Firmware and Battery Data
        Log3 $name, 5,
"CometBlueBTLE ($name) - ProcessingNotification: handle $gatttChar{AttrVal($name,'model','')}{'battery'}";

        $readings = HandleBattery( $hash, $notification );

    }
    elsif ( $handle eq $gatttChar{ AttrVal( $name, 'model', '' ) }{'payload'} )
    {
        ### payload abrufen
        Log3 $name, 5,
"CometBlueBTLE ($name) - ProcessingNotification: handle $gatttChar{AttrVal($name,'model','')}{'payload'}";

        $readings = HandlePayload( $hash, $notification );

    }
    elsif ( $handle eq $gatttChar{ AttrVal( $name, 'model', '' ) }{'firmware'} )
    {
        ### firmware abrufen
        Log3 $name, 5,
"CometBlueBTLE ($name) - ProcessingNotification: handle $gatttChar{AttrVal($name,'model','')}{'firmware'}";

        $readings = HandleFirmware( $hash, $notification );

    }
    elsif (
        $handle eq $gatttChar{ AttrVal( $name, 'model', '' ) }{'devicename'} )
    {
        ### devicename abrufen
        Log3 $name, 5,
"CometBlueBTLE ($name) - ProcessingNotification: handle $gatttChar{AttrVal($name,'model','')}{'devicename'}";

        $readings = HandleDevicename( $hash, $notification );

    }
    elsif ( defined( $hash->{tempListsHandleQueue} )
        and scalar( @{ $hash->{tempListsHandleQueue} } ) > 0 )
    {
        Log3 $name, 4,
"CometBlueBTLE ($name) - ProcessingNotification: $notification - Noch in Queue: "
          . scalar( @{ $hash->{tempListsHandleQueue} } );
        ### templisten abrufen
        my $i = 0;
        foreach (
            split(
                ',', $gatttChar{ AttrVal( $name, 'model', '' ) }{'tempLists'}
            )
          )
        {
            if ( $handle eq $_ ) {
                Log3 $name, 4,
"CometBlueBTLE ($name) - ProcessingNotification in der Schleife: handle "
                  . $_
                  . " und dayOfWeek: "
                  . $i;
                $readings = HandleTempLists( $hash, $_, $i, $notification );
            }

            $i++;
        }

        $hash->{helper}{paramGatttool}{handle} =
          pop( @{ $hash->{tempListsHandleQueue} } )
          if ( defined( $hash->{tempListsHandleQueue} )
            and scalar( @{ $hash->{tempListsHandleQueue} } ) > 0 );

        CreateParamGatttool( $hash, 'read',
            $hash->{helper}{paramGatttool}{handle} )
          if ( $hash->{helper}{paramGatttool}{handle} ne 'end' );
    }

    WriteReadings( $hash, $readings );
}

sub HandleBattery($$) {
    ### Read Battery Data
    my ( $hash, $notification ) = @_;

    my $name = $hash->{NAME};
    my %readings;

    Log3 $name, 5,
"CometBlueBTLE ($name) - handle $gatttChar{AttrVal($name,'model','')}{'battery'}";

    #chomp($notification);
    $notification =~ s/\s+//g;

    $readings{'batteryPercent'} = hex( "0x" . $notification );
    $readings{'batteryState'} =
      ( hex( "0x" . $notification ) > 15 ? "ok" : "low" );

    $hash->{helper}{CallBattery} = 1;
    CallBattery_Timestamp($hash);
    return \%readings;
}

sub HandlePayload($$) {
    ### Read Payload Data
    my ( $hash, $notification ) = @_;

    my $name = $hash->{NAME};
    my %readings;

    Log3 $name, 5,
"CometBlueBTLE ($name) - handle $gatttChar{AttrVal($name,'model','')}{'battery'}";

    my @payload = split( " ", $notification );

#     char-read-hnd 0x003d
#     Characteristic value/descriptor: 2a 38 20 2a 00 04 0a
#     2a= Zimmertemperatur (42/2 = 21°C)
#     38= Manuelle Temperatur (56/2 = 28°C) Welche am Display mit Drehrad oder mit der App eingestellt wird.
#     20= Minimale Ziel-Temperatur (32/2 = 16°C)
#     2a= Maximale Ziel-Temperatur (42/2 = 21 °C)
#     00= Ausgleichstemperatur
#     04 = Fenster offen Detektor
#     0a= Zeit Fenster offen in Minuten

    $readings{'measured-temp'} = hex( "0x" . $payload[0] ) / 2;

    if ( hex( "0x" . $payload[1] ) / 2 == 7.5 ) {
        $readings{'desired-temp'} = 'off';
    }
    elsif ( hex( "0x" . $payload[1] ) / 2 == 28.5 ) {
        $readings{'desired-temp'} = 'on';
    }
    else {
        $readings{'desired-temp'} = hex( "0x" . $payload[1] ) / 2;
    }

    $readings{'tempEco'}     = hex( "0x" . $payload[2] ) / 2;
    $readings{'tempComfort'} = hex( "0x" . $payload[3] ) / 2;

    if ( $payload[4] =~ /^f/ ) {
        $readings{'tempOffset'} = ( hex( "0x" . $payload[4] ) / 2 ) - 128;
    }
    else {
        $readings{'tempOffset'} = hex( "0x" . $payload[4] ) / 2;
    }

    $readings{'winOpnSensitivity'} =
      $winOpnSensitivity{'Sensitivity'}{ hex( "0x" . $payload[5] ) };
    $readings{'winOpnPeriod'} = hex( "0x" . $payload[6] );

    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub HandleFirmware($$) {
    ### Read Firmware Data
    my ( $hash, $notification ) = @_;

    my $name = $hash->{NAME};
    my %readings;
    $notification =~ s/\s+//g;

    Log3 $name, 3,
"CometBlueBTLE ($name) - handle $gatttChar{AttrVal($name,'model','')}{'firmware'}";

    $readings{'firmware'} = pack( 'H*', $notification );

    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub HandleDevicename($$) {
    ### Read Devicename Data
    my ( $hash, $notification ) = @_;

    my $name = $hash->{NAME};
    my %readings;
    $notification =~ s/\s+//g;

    Log3 $name, 5,
"CometBlueBTLE ($name) - handle $gatttChar{AttrVal($name,'model','')}{'devicename'}";

    $readings{'devicename'} = pack( 'H*', $notification );

    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub HandleTempLists($@) {
    ### Read tempList Data
    my ( $hash, $handle, $dayOfWeek, $notification ) = @_;

    my $name = $hash->{NAME};
    my %readings;
    my %days = (
        0 => 'Sat',
        1 => 'Sun',
        2 => 'Mon',
        3 => 'Tue',
        4 => 'Wed',
        5 => 'Thu',
        6 => 'Fri'
    );

    Log3 $name, 3,
"CometBlueBTLE ($name) - handle $handle - dayOfWeek: $dayOfWeek - Notification: $notification - Noch in Queue: "
      . scalar( @{ $hash->{tempListsHandleQueue} } );

    my @tempList = split( " ", $notification );
    my $i = 0;
    my $hour;
    my $min;

    foreach (@tempList) {

#         ### Berechnung Stunden
#         if( hex("0x".$tempList[$i])*10/6 < 100 ) {
#             $hour = '0'.substr(hex("0x".$tempList[$i])*10/6,0,1);
#         } elsif( hex("0x".$tempList[$i])*10/6 > 99 ) {
#             $hour = substr(hex("0x".$tempList[$i])*10/6,0,2);
#         }
#
#         ### Berechnung Minuten
#         if( hex("0x".$tempList[$i])*10/6 == 0 or (hex("0x".$tempList[$i])*10/6) =~ /^[1-9]0$/ ) {
#             $min = '00';
#         } elsif( int(hex("0x".$tempList[$i])*10/6) == hex("0x".$tempList[$i])*10/6 and hex("0x".$tempList[$i])*10/6 > 0 and hex("0x".$tempList[$i])*10/6 < 100 ) {
#             $min = int(substr(hex("0x".$tempList[$i])*10/6,1)/10*60+0.5);
#         } elsif( int(hex("0x".$tempList[$i])*10/6) == hex("0x".$tempList[$i])*10/6 ) {
#             $min = int(substr(hex("0x".$tempList[$i])*10/6,2)/10*60+0.5).'0';
#         } elsif( int(hex("0x".$tempList[$i])*10/6) != hex("0x".$tempList[$i])*10/6 and hex("0x".$tempList[$i])*10/6 > 99 ) {
#             $min = int(substr(hex("0x".$tempList[$i])*10/6,2)/10*60+0.5);
#         } elsif( int(hex("0x".$tempList[$i])*10/6) != hex("0x".$tempList[$i])*10/6 and hex("0x".$tempList[$i])*10/6 < 100 ) {
#             $min = int(substr(hex("0x".$tempList[$i])*10/6,1)/10*60+0.5);
#         }

        ### Berechnung Stunden, Minuten
        ### es kommt vor dass leere Felder mit FF gefuellt sind, als 00 interpretieren
        if ( hex( "0x" . $tempList[$i] ) == 255 ) {
            $hour = '00';
            $min  = '00';
        }
        else {
            $hour = sprintf( "%02s", int( hex( "0x" . $tempList[$i] ) / 6 ) );
            $min  = sprintf( "%02s", hex( "0x" . $tempList[$i] ) % 6 * 10 );
        }

        $readings{ $dayOfWeek . '_tempList' . $days{$dayOfWeek} } =
          $hour . ':' . $min
          if ( $i == 0 );
        $readings{ $dayOfWeek . '_tempList' . $days{$dayOfWeek} } =
            $readings{ $dayOfWeek . '_tempList' . $days{$dayOfWeek} } . ' '
          . $hour . ':'
          . $min
          if ( $i > 0 );

        $i++;
    }

    $hash->{helper}{CallBattery} = 0;

    return \%readings;
}

sub WriteReadings($$) {

    my ( $hash, $readings ) = @_;

    my $name = $hash->{NAME};

    readingsBeginUpdate($hash);
    while ( my ( $r, $v ) = each %{$readings} ) {
        Log3 $name, 5,
"CometBlueBTLE ($name) - WriteReadings: Reading $r, value $v altes value "
          . ReadingsVal( $name, $r, "" );
        readingsBulkUpdateIfChanged( $hash, "lastChangeBy", "Thermostat" )
          if (  ReadingsVal( $name, $r, "" ) ne $v
            and $r ne 'measured-temp'
            and ReadingsAge( $name, 'lastChangeBy', 300 ) > 30 );
        readingsBulkUpdateIfChanged( $hash, $r, $v )
          if ( $r ne 'lastGattError' );
        readingsBulkUpdate( $hash, $r, $v ) if ( $r eq 'lastGattError' );
    }

    readingsBulkUpdateIfChanged(
        $hash, "state",
        (
            $readings->{'lastGattError'}
            ? 'error'
            : 'T: '
              . ReadingsVal( $name, 'measured-temp', -100 )
              . ' desired: '
              . ReadingsVal( $name, 'desired-temp', -100 )
        )
    );
    readingsEndUpdate( $hash, 1 );

    StateRequest($hash) if ( $hash->{helper}{CallBattery} == 1 );

    Log3 $name, 4,
      "CometBlueBTLE ($name) - WriteReadings: Readings were written";

}

sub ProcessingErrors($$) {

    my ( $hash, $notification ) = @_;

    my $name = $hash->{NAME};
    my %readings;

    Log3 $name, 4, "CometBlueBTLE ($name) - ProcessingErrors";
    $readings{'lastGattError'} = $notification;

    WriteReadings( $hash, \%readings );
    $hash->{helper}{writePin} = 0
      if ( defined( $hash->{tempListsHandleQueue} )
        and scalar( @{ $hash->{tempListsHandleQueue} } ) > 0 );
}

#### my little Helper
sub EncodeJSON($) {
    my $gtResult = shift;

    chomp($gtResult);

    my %response = ( 'gtResult' => $gtResult );

    return encode_json( \%response );
}

## Routinen damit Firmware und Batterie nur alle X male statt immer aufgerufen wird
sub CallBattery_Timestamp($) {

    my $hash = shift;

    # get timestamp
    $hash->{helper}{updateTimeCallBattery} =
      gettimeofday();    # in seconds since the epoch
    $hash->{helper}{updateTimestampCallBattery} = FmtDateTime( gettimeofday() );
}

sub CallBattery_UpdateTimeAge($) {

    my $hash = shift;

    $hash->{helper}{updateTimeCallBattery} = 0
      if ( not defined( $hash->{helper}{updateTimeCallBattery} ) );
    my $UpdateTimeAge = gettimeofday() - $hash->{helper}{updateTimeCallBattery};

    return $UpdateTimeAge;
}

sub CallBattery_IsUpdateTimeAgeTooOld($$) {

    my ( $hash, $maxAge ) = @_;

    return ( CallBattery_UpdateTimeAge($hash) > $maxAge ? 1 : 0 );
}

sub CreateDevicenameHEX($) {

    my $devicename = shift;

    my $devicenameHex = unpack( "H*", $devicename );

    return $devicenameHex;
}

sub ConvertPinToHexLittleEndian($) {

    my $pin = shift;

    #     return '00000000' if( $pin =~ /^0/ );

    my $hex = unpack( 'V', pack( 'N', $pin ) );

    #     $hex = sprintf('0x%2x',$hex);
    $hex = sprintf( '%08x', $hex );
    return $hex;
}

sub CreatePayloadString($$$) {

    my ( $hash, $setCmd, $value ) = @_;
    my $name = $hash->{NAME};

    $value = 7.5  if ( $value eq 'off' );
    $value = 28.5 if ( $value eq 'on' );
    $value = ReadingsVal( $name, 'tempComfort', 0 ) if ( $value eq 'Comfort' );
    $value = ReadingsVal( $name, 'tempEco',     0 ) if ( $value eq 'Eco' );

    return
        sprintf( '%.2x', ReadingsVal( $name, 'measured-temp', 0 ) * 2 )
      . sprintf( '%.2x', $value * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'tempEco', 0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'tempComfort', 0 ) * 2 )
      . sprintf( '%.2x',
        ReadingsVal( $name, 'tempOffset', 0 ) * 2 +
          ( ReadingsVal( $name, 'tempOffset', 0 ) < 0 ? 256 : 0 ) )
      . sprintf( '%.2x',
        $winOpnSensitivity{'Sensitivity'}
          { ReadingsVal( $name, 'winOpnSensitivity', 0 ) } )
      . sprintf( '%.2x', ReadingsVal( $name, 'winOpnPeriod', 0 ) )
      if ( $setCmd eq 'desired-temp' );

    return
        sprintf( '%.2x', ReadingsVal( $name, 'measured-temp', 0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'desired-temp', 0 ) * 2 )
      . sprintf( '%.2x', $value * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'tempComfort',  0 ) * 2 )
      . sprintf( '%.2x',
        ReadingsVal( $name, 'tempOffset', 0 ) * 2 +
          ( ReadingsVal( $name, 'tempOffset', 0 ) < 0 ? 256 : 0 ) )
      . sprintf( '%.2x',
        $winOpnSensitivity{'Sensitivity'}
          { ReadingsVal( $name, 'winOpnSensitivity', 0 ) } )
      . sprintf( '%.2x', ReadingsVal( $name, 'winOpnPeriod', 0 ) )
      if ( $setCmd eq 'tempEco' );

    return
        sprintf( '%.2x', ReadingsVal( $name, 'measured-temp', 0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'desired-temp', 0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'tempEco',      0 ) * 2 )
      . sprintf( '%.2x', $value * 2 )
      . sprintf( '%.2x',
        ReadingsVal( $name, 'tempOffset', 0 ) * 2 +
          ( ReadingsVal( $name, 'tempOffset', 0 ) < 0 ? 256 : 0 ) )
      . sprintf( '%.2x',
        $winOpnSensitivity{'Sensitivity'}
          { ReadingsVal( $name, 'winOpnSensitivity', 0 ) } )
      . sprintf( '%.2x', ReadingsVal( $name, 'winOpnPeriod', 0 ) )
      if ( $setCmd eq 'tempComfort' );

    return
        sprintf( '%.2x', ReadingsVal( $name, 'measured-temp', 0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'desired-temp', 0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'tempEco',      0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'tempComfort',  0 ) * 2 )
      . sprintf( '%.2x', $value * 2 + ( $value < 0 ? 256 : 0 ) )
      . sprintf( '%.2x',
        $winOpnSensitivity{'Sensitivity'}
          { ReadingsVal( $name, 'winOpnSensitivity', 0 ) } )
      . sprintf( '%.2x', ReadingsVal( $name, 'winOpnPeriod', 0 ) )
      if ( $setCmd eq 'tempOffset' );

    return
        sprintf( '%.2x', ReadingsVal( $name, 'measured-temp', 0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'desired-temp', 0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'tempEco',      0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'tempComfort',  0 ) * 2 )
      . sprintf( '%.2x',
        ReadingsVal( $name, 'tempOffset', 0 ) * 2 +
          ( ReadingsVal( $name, 'tempOffset', 0 ) < 0 ? 256 : 0 ) )
      . sprintf( '%.2x', $winOpnSensitivity{'Sensitivity'}{$value} )
      . sprintf( '%.2x', ReadingsVal( $name, 'winOpnPeriod', 0 ) )
      if ( $setCmd eq 'winOpnSensitivity' );

    return
        sprintf( '%.2x', ReadingsVal( $name, 'measured-temp', 0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'desired-temp', 0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'tempEco',      0 ) * 2 )
      . sprintf( '%.2x', ReadingsVal( $name, 'tempComfort',  0 ) * 2 )
      . sprintf( '%.2x',
        ReadingsVal( $name, 'tempOffset', 0 ) * 2 +
          ( ReadingsVal( $name, 'tempOffset', 0 ) < 0 ? 256 : 0 ) )
      . sprintf( '%.2x',
        $winOpnSensitivity{'Sensitivity'}
          { ReadingsVal( $name, 'winOpnSensitivity', 0 ) } )
      . sprintf( '%.2x', $value )
      if ( $setCmd eq 'winOpnPeriod' );

}

sub CmdlinePreventGrepFalsePositive($) {

# https://stackoverflow.com/questions/9375711/more-elegant-ps-aux-grep-v-grep
# Given abysmal (since external-command-based) performance in the first place, we'd better
# avoid an *additional* grep process plus pipe...

    my $cmdline = shift;

    $cmdline =~ s/(.)(.*)/[$1]$2/;
    return $cmdline;
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
