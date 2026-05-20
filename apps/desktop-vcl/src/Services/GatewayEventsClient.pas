unit GatewayEventsClient;

interface

uses
  System.Classes, System.NetEncoding, System.SysUtils,
  Winapi.WinHTTP, Winapi.Windows,
  WinHttpWebSocket, AppSettings, GatewayProtocol;

type
  TGatewayEventHandler = procedure(const Event: TGatewayEvent) of object;
  TGatewayEventErrorHandler = procedure(const ErrorMessage: string) of object;

  TGatewayEventsClient = class
  private
    FThread: TThread;
    FRequestHandle: HINTERNET;
    FSocket: HINTERNET;
    FConnected: Boolean;
    function WinHttpErrorText(const Operation: string): string;
    procedure QueueError(const Handler: TGatewayEventErrorHandler; const ErrorMessage: string);
    procedure QueueEvent(const Handler: TGatewayEventHandler; const Event: TGatewayEvent);
  public
    destructor Destroy; override;
    procedure Connect(
      const Settings: TGatewaySettings;
      const SessionId: string;
      const OnEvent: TGatewayEventHandler;
      const OnError: TGatewayEventErrorHandler);
    procedure Disconnect;
    function WaitForConnected(TimeoutMs: Cardinal): Boolean;
    property Connected: Boolean read FConnected;
  end;

implementation

const
  RECEIVE_BUFFER_BYTES = 8192;
  ERROR_WINHTTP_OPERATION_CANCELLED = 12017;

function IsExpectedDisconnectError(ErrorCode: DWORD): Boolean;
begin
  Result := (ErrorCode = ERROR_WINHTTP_OPERATION_CANCELLED)
    or TThread.CurrentThread.CheckTerminated;
end;

procedure AppendReceiveBytes(var MessageBuffer: TBytes; const Buffer: TBytes; Count: Integer);
var
  OldLen: Integer;
begin
  if Count <= 0 then
    Exit;

  OldLen := Length(MessageBuffer);
  SetLength(MessageBuffer, OldLen + Count);
  Move(Buffer[0], MessageBuffer[OldLen], Count);
end;

function TGatewayEventsClient.WinHttpErrorText(const Operation: string): string;
var
  ErrorCode: DWORD;
begin
  ErrorCode := GetLastError;
  if ErrorCode = 0 then
    Result := Operation
  else
    Result := Format('%s (WinHTTP error %d).', [Operation, ErrorCode]);
end;

destructor TGatewayEventsClient.Destroy;
begin
  Disconnect;
  inherited;
end;

procedure TGatewayEventsClient.Connect(
  const Settings: TGatewaySettings;
  const SessionId: string;
  const OnEvent: TGatewayEventHandler;
  const OnError: TGatewayEventErrorHandler);
var
  Host: string;
  Port: Integer;
  Token: string;
begin
  Disconnect;

  Host := Settings.Host;
  Port := Settings.Port;
  Token := Settings.AuthToken;

  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      SessionHandle: HINTERNET;
      ConnectHandle: HINTERNET;
      RequestHandle: HINTERNET;
      RequestPath: string;
      Buffer: TBytes;
      MessageBuffer: TBytes;
      BytesRead: DWORD;
      BufferType: WINHTTP_WEB_SOCKET_BUFFER_TYPE;
      ReceiveResult: DWORD;
      Text: string;
      Event: TGatewayEvent;

      procedure DispatchCompleteMessage;
      begin
        if Length(MessageBuffer) = 0 then
          Exit;

        Text := TEncoding.UTF8.GetString(MessageBuffer);
        SetLength(MessageBuffer, 0);
        try
          Event := TGatewayEvent.FromJson(Text);
          QueueEvent(OnEvent, Event);
        except
          on E: Exception do
            QueueError(OnError, E.Message);
        end;
      end;
    begin
      SessionHandle := nil;
      ConnectHandle := nil;
      RequestHandle := nil;
      FRequestHandle := nil;
      FSocket := nil;
      try
        SessionHandle := WinHttpOpen(
          'MzClaude/0.1',
          WINHTTP_ACCESS_TYPE_NO_PROXY,
          WINHTTP_NO_PROXY_NAME,
          WINHTTP_NO_PROXY_BYPASS,
          0);
        if SessionHandle = nil then
          raise EInvalidOperation.Create('Unable to open WinHTTP session.');

        ConnectHandle := WinHttpConnect(SessionHandle, PWideChar(Host), Port, 0);
        if ConnectHandle = nil then
          raise EInvalidOperation.Create('Unable to connect to gateway WebSocket endpoint.');
        RequestPath := Format(
          '/api/sessions/%s/events?token=%s',
          [TNetEncoding.URL.Encode(SessionId), TNetEncoding.URL.Encode(Token)]);
        RequestHandle := WinHttpOpenRequest(
          ConnectHandle,
          'GET',
          PWideChar(RequestPath),
          nil,
          WINHTTP_NO_REFERER,
          WINHTTP_DEFAULT_ACCEPT_TYPES,
          0);
        if RequestHandle = nil then
          raise EInvalidOperation.Create(WinHttpErrorText('Unable to open gateway WebSocket request'));

        if Token <> '' then
        begin
          if WinHttpAddRequestHeaders(
            RequestHandle,
            PWideChar('Authorization: Bearer ' + Token),
            Cardinal(-1),
            WINHTTP_ADDREQ_FLAG_ADD) = False then
            raise EInvalidOperation.Create(WinHttpErrorText('Unable to add WebSocket authorization header'));
        end;

        if not WinHttpSetOption(
          RequestHandle,
          WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET,
          nil,
          0) then
          raise EInvalidOperation.Create(WinHttpErrorText('Unable to request WebSocket upgrade'));

        FRequestHandle := RequestHandle;
        if not WinHttpSendRequest(
          RequestHandle,
          WINHTTP_NO_ADDITIONAL_HEADERS,
          0,
          WINHTTP_NO_REQUEST_DATA,
          0,
          0,
          0) then
          raise EInvalidOperation.Create(WinHttpErrorText('Unable to send WebSocket upgrade request'));

        if not WinHttpReceiveResponse(RequestHandle, nil) then
          raise EInvalidOperation.Create(WinHttpErrorText('Gateway did not complete WebSocket upgrade'));

        FSocket := WinHttpWebSocketCompleteUpgrade(RequestHandle, 0);
        FRequestHandle := nil;
        RequestHandle := nil;
        if FSocket = nil then
          raise EInvalidOperation.Create('Unable to complete WebSocket upgrade.');

        FConnected := True;
        SetLength(Buffer, RECEIVE_BUFFER_BYTES);
        SetLength(MessageBuffer, 0);
        while not TThread.CurrentThread.CheckTerminated do
        begin
          BytesRead := 0;
          BufferType := WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE;
          ReceiveResult := WinHttpWebSocketReceive(
            FSocket,
            @Buffer[0],
            Length(Buffer),
            BytesRead,
            BufferType);
          if ReceiveResult <> NO_ERROR then
          begin
            if IsExpectedDisconnectError(ReceiveResult) then
              Break;
            raise EInvalidOperation.CreateFmt(
              'Gateway WebSocket receive failed (error %d).',
              [ReceiveResult]);
          end;

          if BufferType = WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE then
            Break;

          if BufferType in [
            WINHTTP_WEB_SOCKET_UTF8_FRAGMENT_BUFFER_TYPE,
            WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE] then
          begin
            AppendReceiveBytes(MessageBuffer, Buffer, BytesRead);
            if BufferType = WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE then
              DispatchCompleteMessage;
          end;
        end;
      except
        on E: Exception do
          if not TThread.CurrentThread.CheckTerminated then
            QueueError(OnError, E.Message);
      end;

      FConnected := False;
      FRequestHandle := nil;
      if FSocket <> nil then
      begin
        WinHttpCloseHandle(FSocket);
        FSocket := nil;
      end;
      if RequestHandle <> nil then
        WinHttpCloseHandle(RequestHandle);
      if ConnectHandle <> nil then
        WinHttpCloseHandle(ConnectHandle);
      if SessionHandle <> nil then
        WinHttpCloseHandle(SessionHandle);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TGatewayEventsClient.Disconnect;
var
  Thread: TThread;
  Socket: HINTERNET;
  Request: HINTERNET;
begin
  Thread := FThread;
  if Thread = nil then
    Exit;

  FThread := nil;
  Thread.Terminate;

  Socket := FSocket;
  if Socket <> nil then
  begin
    FSocket := nil;
    WinHttpWebSocketClose(Socket, WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS, nil, 0);
    WinHttpCloseHandle(Socket);
  end;

  Request := FRequestHandle;
  if Request <> nil then
  begin
    FRequestHandle := nil;
    WinHttpCloseHandle(Request);
  end;

  Thread.WaitFor;
  Thread.Free;
  FConnected := False;
end;

function TGatewayEventsClient.WaitForConnected(TimeoutMs: Cardinal): Boolean;
var
  StartedAt: Cardinal;
begin
  StartedAt := GetTickCount;
  while (not FConnected) and (GetTickCount - StartedAt < TimeoutMs) do
    Sleep(25);

  Result := FConnected;
end;

procedure TGatewayEventsClient.QueueError(
  const Handler: TGatewayEventErrorHandler;
  const ErrorMessage: string);
var
  ErrorCopy: string;
begin
  if Assigned(Handler) then
  begin
    ErrorCopy := ErrorMessage;
    TThread.Queue(nil,
      procedure
      begin
        Handler(ErrorCopy);
      end);
  end;
end;

procedure TGatewayEventsClient.QueueEvent(
  const Handler: TGatewayEventHandler;
  const Event: TGatewayEvent);
var
  EventCopy: TGatewayEvent;
begin
  if Assigned(Handler) then
  begin
    EventCopy := Event;
    TThread.Queue(nil,
      procedure
      begin
        Handler(EventCopy);
      end);
  end;
end;

end.
