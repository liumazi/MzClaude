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
    FSocket: HINTERNET;
    FConnected: Boolean;
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
      BytesRead: DWORD;
      BufferType: WINHTTP_WEB_SOCKET_BUFFER_TYPE;
      Text: string;
      Event: TGatewayEvent;
    begin
      SessionHandle := nil;
      ConnectHandle := nil;
      RequestHandle := nil;
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
          [SessionId, TNetEncoding.URL.Encode(Token)]);
        RequestHandle := WinHttpOpenRequest(
          ConnectHandle,
          'GET',
          PWideChar(RequestPath),
          nil,
          WINHTTP_NO_REFERER,
          WINHTTP_DEFAULT_ACCEPT_TYPES,
          0);
        if RequestHandle = nil then
          raise EInvalidOperation.Create('Unable to open gateway WebSocket request.');

        if not WinHttpSetOption(
          RequestHandle,
          WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET,
          nil,
          0) then
          raise EInvalidOperation.Create('Unable to request WebSocket upgrade.');

        if not WinHttpSendRequest(
          RequestHandle,
          WINHTTP_NO_ADDITIONAL_HEADERS,
          0,
          WINHTTP_NO_REQUEST_DATA,
          0,
          0,
          0) then
          raise EInvalidOperation.Create('Unable to send WebSocket upgrade request.');

        if not WinHttpReceiveResponse(RequestHandle, nil) then
          raise EInvalidOperation.Create('Gateway did not complete WebSocket upgrade.');

        FSocket := WinHttpWebSocketCompleteUpgrade(RequestHandle, 0);
        RequestHandle := nil;
        if FSocket = nil then
          raise EInvalidOperation.Create('Unable to complete WebSocket upgrade.');

        FConnected := True;
        SetLength(Buffer, RECEIVE_BUFFER_BYTES);
        while not TThread.CurrentThread.CheckTerminated do
        begin
          BytesRead := 0;
          BufferType := WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE;
          if WinHttpWebSocketReceive(
            FSocket,
            @Buffer[0],
            Length(Buffer),
            BytesRead,
            BufferType) <> NO_ERROR then
            raise EInvalidOperation.Create('Gateway WebSocket receive failed.');

          if BufferType = WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE then
            Break;

          if (BufferType = WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE) and (BytesRead > 0) then
          begin
            Text := TEncoding.UTF8.GetString(Buffer, 0, BytesRead);
            try
              Event := TGatewayEvent.FromJson(Text);
              QueueEvent(OnEvent, Event);
            except
              on E: Exception do
                QueueError(OnError, E.Message);
            end;
          end;
        end;
      except
        on E: Exception do
          QueueError(OnError, E.Message);
      end;

      FConnected := False;
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
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    if FSocket <> nil then
      WinHttpWebSocketClose(FSocket, WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS, nil, 0);
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
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
