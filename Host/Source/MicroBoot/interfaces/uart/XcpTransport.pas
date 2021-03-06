unit XcpTransport;
//***************************************************************************************
//  Description: XCP transport layer for SCI.
//    File Name: XcpTransport.pas
//
//---------------------------------------------------------------------------------------
//                          C O P Y R I G H T
//---------------------------------------------------------------------------------------
//   Copyright (c) 2011 by Feaser    http://www.feaser.com    All rights reserved
//
//   This software has been carefully tested, but is not guaranteed for any particular
// purpose. The author does not offer any warranties and does not guarantee the accuracy,
//   adequacy, or completeness of the software and is not responsible for any errors or
//              omissions or the results obtained from use of the software.
//
//---------------------------------------------------------------------------------------
//                            L I C E N S E
//---------------------------------------------------------------------------------------
// This file is part of OpenBLT. OpenBLT is free software: you can redistribute it and/or
// modify it under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// OpenBLT is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
// PURPOSE. See the GNU General Public License for more details.
//
// You have received a copy of the GNU General Public License along with OpenBLT. It 
// should be located in ".\Doc\license.html". If not, contact Feaser to obtain a copy.
//
//***************************************************************************************
interface


//***************************************************************************************
// Includes
//***************************************************************************************
uses
  Windows, Messages, SysUtils, Classes, Forms, CPort, IniFiles;


//***************************************************************************************
// Global Constants
//***************************************************************************************
const kMaxPacketSize = 256;


//***************************************************************************************
// Type Definitions
//***************************************************************************************
type
  TXcpTransport = class(TObject)
  private
  public
    packetData   : array[0..kMaxPacketSize-1] of Byte;
    packetLen    : Word;
    sciDriver    : TComPort;
    constructor Create;
    procedure   Configure(iniFile : string);
    function    Connect : Boolean;
    function    SendPacket(timeOutms: LongWord): Boolean;
    function    IsComError: Boolean;
    procedure   Disconnect;
    destructor  Destroy; override;
  end;


implementation

//***************************************************************************************
// NAME:           Create
// PARAMETER:      none
// RETURN VALUE:   none
// DESCRIPTION:    Class constructore
//
//***************************************************************************************
constructor TXcpTransport.Create;
begin
  // call inherited constructor
  inherited Create;

  // reset packet length
  packetLen := 0;

  // create a sci driver instance
  sciDriver := TComPort.Create(nil);

  // init sci settings
  try
    sciDriver.DataBits := dbEight;
    sciDriver.StopBits := sbOneStopBit;
    sciDriver.Parity.Bits := prNone;
    sciDriver.FlowControl.XonXoffOut := false;
    sciDriver.FlowControl.XonXoffIn := false;
    sciDriver.FlowControl.ControlRTS := rtsDisable;
    sciDriver.FlowControl.ControlDTR := dtrEnable;
  except
    Exit;
  end;
end; //*** end of Create ***


//***************************************************************************************
// NAME:           Destroy
// PARAMETER:      none
// RETURN VALUE:   none
// DESCRIPTION:    Class destructor
//
//***************************************************************************************
destructor TXcpTransport.Destroy;
begin
  // release sci driver instance
  sciDriver.Free;
  // call inherited destructor
  inherited;
end; //*** end of Destroy ***


//***************************************************************************************
// NAME:           Configure
// PARAMETER:      filename of the INI
// RETURN VALUE:   none
// DESCRIPTION:    Configures both this class from the settings in the INI.
//
//***************************************************************************************
procedure TXcpTransport.Configure(iniFile : string);
var
  settingsIni : TIniFile;
  configIndex : integer;
  baudrateValue: TBaudRate;
begin
	// read XCP configuration from INI
  if FileExists(iniFile) then
  begin
    // create ini file object
    settingsIni := TIniFile.Create(iniFile);

    // read baudrate
    configIndex := settingsIni.ReadInteger('sci', 'baudrate', 6);
    // init to default baudrate value
    baudrateValue := br38400;
    case configIndex of
      0 : baudrateValue := br1200;
      1 : baudrateValue := br2400;
      2 : baudrateValue := br4800;
      3 : baudrateValue := br9600;
      4 : baudrateValue := br14400;
      5 : baudrateValue := br19200;
      6 : baudrateValue := br38400;
      7 : baudrateValue := br56000;
      8 : baudrateValue := br57600;
      9 : baudrateValue := br115200;
      10: baudrateValue := br128000;
      11: baudrateValue := br256000;
    end;

    // read port
    configIndex := settingsIni.ReadInteger('sci', 'port', 0);

    // release ini file object
    settingsIni.Free;

    // set the port and the baudrate
    try
      sciDriver.Port := Format( 'COM%d', [ord(configIndex + 1)] );
      sciDriver.BaudRate := baudrateValue;
    except
      Exit;
    end;
  end;
end; //*** end of Configure ***


//***************************************************************************************
// NAME:           Connect
// PARAMETER:      none
// RETURN VALUE:   True is successful, False otherwise.
// DESCRIPTION:    Connects the transport layer device.
//
//***************************************************************************************
function TXcpTransport.Connect : Boolean;
begin
  try
    sciDriver.Open;
    result := sciDriver.Connected;
  except
    result := False;
  end;
end; //*** end of Connect ***


//***************************************************************************************
// NAME:           IsComError
// PARAMETER:      none
// RETURN VALUE:   True if in error state, False otherwise.
// DESCRIPTION:    Determines if the communication interface is in an error state.
//
//***************************************************************************************
function TXcpTransport.IsComError: Boolean;
begin
  result := false;
end; //*** end of IsComError ***


//***************************************************************************************
// NAME:           SendPacket
// PARAMETER:      the time[ms] allowed for the reponse from the slave to come in.
// RETURN VALUE:   True if response received from slave, False otherwise
// DESCRIPTION:    Sends the XCP packet using the data in 'packetData' and length in
//                 'packetLen' and waits for the response to come in.
//
//***************************************************************************************
function TXcpTransport.SendPacket(timeOutms: LongWord): Boolean;
var
  msgData   : array of Byte;
  resLen    : byte;
  cnt       : byte;
  rxCnt     : byte;
  dwEnd     : DWord;
  bytesRead : integer;
begin
  // init the return value
  result := false;

  // during high burst I/O the USB/RS232 emulated COM-ports sometimes have problems
  // processing all the data. therefore, add a small delay time between packet I/O.
  // exclude the CONNECT command because of the default small backdoor time of the
  // bootloader
  if packetData[0] <> $FF then
  begin
    Application.ProcessMessages;
    Sleep(5);
  end;

  // prepare the packet. length goes in the first byte followed by the packet data
  SetLength(msgData, packetLen+1);
  msgData[0] := packetLen;
  for cnt := 0 to packetLen-1 do
  begin
    msgData[cnt+1] := packetData[cnt];
  end;

  // configure transmit timeout. timeout = (MULTIPLIER) * number_of_bytes + CONSTANT
  try
    sciDriver.Timeouts.WriteTotalConstant := 0;
    sciDriver.Timeouts.WriteTotalMultiplier := timeOutms div (packetLen+1);
  except
    Exit;
  end;

  // submit the packet transmission request
  if sciDriver.Write(msgData[0], packetLen+1) <> (packetLen+1) then
  begin
    // unable to submit tx request
    Exit;
  end;

  // give application the opportunity to process the messages
  Application.ProcessMessages;

  // confgure the reception timeout. timeout = (MULTIPLIER) * number_of_bytes + CONSTANT
  try
    sciDriver.Timeouts.ReadTotalConstant := timeOutms;
    sciDriver.Timeouts.ReadTotalMultiplier := 0;
  except
    Exit;
  end;

  // compute timeout time for receiving the response
  dwEnd := GetTickCount + timeOutms;

  // receive the first byte which should hold the packet length
  try
    bytesRead := sciDriver.Read(resLen, 1);
  except
    Exit;
  end;

  if bytesRead = 1 then
  begin
    // init the number of received bytes to 0
    rxCnt := 0;
    packetLen := 0;

    // only attempt to receive the remainder of the packet if its length is valid
    if resLen > 0 then
    begin
      // re-confgure the reception timeout now that the total packet length is known.
      // timeout = (MULTIPLIER) * number_of_bytes + CONSTANT
      try
        sciDriver.Timeouts.ReadTotalConstant := 0;
        sciDriver.Timeouts.ReadTotalMultiplier := timeOutms div resLen;
      except
        Exit;
      end;

      // attempt to receive the bytes of the response packet one by one
      while (rxCnt < resLen) and (GetTickCount < dwEnd) do
      begin
        // receive the next byte
        try
          bytesRead := sciDriver.Read(packetData[rxCnt], 1);
        except
          Exit;
        end;

        if bytesRead  = 1 then
        begin
          // increment counter
          rxCnt := rxCnt + 1;
        end;
      end;

      // check to see if all bytes were received. if not, then a timeout must have
      // happened.
      if rxCnt = resLen then
      begin
        packetLen := resLen;
        result := true;
      end;
    end;
  end;
end; //*** end of SendPacket ***


//***************************************************************************************
// NAME:           Disconnect
// PARAMETER:      none
// RETURN VALUE:   none
// DESCRIPTION:    Disconnects the transport layer device.
//
//***************************************************************************************
procedure TXcpTransport.Disconnect;
begin
  try
    sciDriver.Close;
  except
    Exit;
  end;
end; //*** end of Disconnect ***


end.
//******************************** end of XcpTransport.pas ******************************

