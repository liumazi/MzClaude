unit GatewayHttpClient;

interface

uses
  AppSettings,
  GatewayProtocol;

type
  TGatewayHealthCheckStatus = (
    ghSuccess,
    ghUnauthorized,
    ghConnectionFailed,
    ghInvalidResponse,
    ghHttpError
  );

  TGatewayHealthCheckResult = record
    Status: TGatewayHealthCheckStatus;
    StatusCode: Integer;
    Health: TGatewayHealthResponse;
    ErrorMessage: string;
  end;

  TGatewayCommandStatus = (
    gcSuccess,
    gcUnauthorized,
    gcConnectionFailed,
    gcInvalidResponse,
    gcHttpError
  );

  TGatewayCreateSessionResult = record
    Status: TGatewayCommandStatus;
    StatusCode: Integer;
    Session: TGatewaySessionResponse;
    ErrorMessage: string;
  end;

  TGatewaySendMessageResult = record
    Status: TGatewayCommandStatus;
    StatusCode: Integer;
    Message: TGatewaySendMessageResponse;
    ErrorMessage: string;
  end;

  TGatewaySubmitApprovalResult = record
    Status: TGatewayCommandStatus;
    StatusCode: Integer;
    Approval: TGatewaySubmitApprovalResponse;
    ErrorMessage: string;
  end;

  TGatewayListSessionsResult = record
    Status: TGatewayCommandStatus;
    StatusCode: Integer;
    Sessions: TGatewaySessionListResponse;
    ErrorMessage: string;
  end;

  TGatewayStopSessionResult = record
    Status: TGatewayCommandStatus;
    StatusCode: Integer;
    StopResponse: TGatewayStopSessionResponse;
    ErrorMessage: string;
  end;

  TGatewayHttpClient = class
  public
    function CheckHealth(const Settings: TGatewaySettings): TGatewayHealthCheckResult;
    function ListSessions(const Settings: TGatewaySettings): TGatewayListSessionsResult;
    function CreateSession(
      const Settings: TGatewaySettings;
      const Request: TGatewayCreateSessionRequest): TGatewayCreateSessionResult;
    function SendMessage(
      const Settings: TGatewaySettings;
      const SessionId: string;
      const Request: TGatewaySendMessageRequest): TGatewaySendMessageResult;
    function StopSession(
      const Settings: TGatewaySettings;
      const SessionId: string): TGatewayStopSessionResult;
    function SubmitApproval(
      const Settings: TGatewaySettings;
      const SessionId: string;
      const RequestId: string;
      const Request: TGatewaySubmitApprovalRequest): TGatewaySubmitApprovalResult;
  end;

implementation

uses
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.SysUtils;

function BuildJsonHeaders(const Settings: TGatewaySettings): TNetHeaders;
var
  HeaderCount: Integer;
begin
  HeaderCount := 2;
  if Settings.AuthToken <> '' then
    Inc(HeaderCount);

  SetLength(Result, HeaderCount);
  Result[0].Name := 'Accept';
  Result[0].Value := 'application/json';
  Result[1].Name := 'Content-Type';
  Result[1].Value := 'application/json; charset=utf-8';
  if Settings.AuthToken <> '' then
  begin
    Result[2].Name := 'Authorization';
    Result[2].Value := 'Bearer ' + Settings.AuthToken;
  end;
end;

function BuildGetHeaders(const Settings: TGatewaySettings): TNetHeaders;
var
  HeaderCount: Integer;
begin
  HeaderCount := 1;
  if Settings.AuthToken <> '' then
    Inc(HeaderCount);

  SetLength(Result, HeaderCount);
  Result[0].Name := 'Accept';
  Result[0].Value := 'application/json';
  if Settings.AuthToken <> '' then
  begin
    Result[1].Name := 'Authorization';
    Result[1].Value := 'Bearer ' + Settings.AuthToken;
  end;
end;

function TGatewayHttpClient.CheckHealth(const Settings: TGatewaySettings): TGatewayHealthCheckResult;
var
  Client: THTTPClient;
  Headers: TNetHeaders;
  Response: IHTTPResponse;
  Body: string;
begin
  Result.Status := ghConnectionFailed;
  Result.StatusCode := 0;
  Result.ErrorMessage := '';

  Headers := BuildGetHeaders(Settings);

  Client := THTTPClient.Create;
  try
    try
      Response := Client.Get(Settings.BaseUrl + '/api/health', nil, Headers);
      Result.StatusCode := Response.StatusCode;
      Body := Response.ContentAsString(TEncoding.UTF8);

      if Response.StatusCode = 200 then
      begin
        try
          Result.Health := TGatewayHealthResponse.FromJson(Body);
          Result.Status := ghSuccess;
        except
          on E: Exception do
          begin
            Result.Status := ghInvalidResponse;
            Result.ErrorMessage := E.Message;
          end;
        end;
        Exit;
      end;

      if Response.StatusCode = 401 then
      begin
        Result.Status := ghUnauthorized;
        try
          Result.ErrorMessage := TGatewayErrorResponse.FromJson(Body).Message;
        except
          Result.ErrorMessage := 'Gateway rejected the configured launch token.';
        end;
        Exit;
      end;

      Result.Status := ghHttpError;
      Result.ErrorMessage := Format('Gateway returned HTTP %d.', [Response.StatusCode]);
    except
      on E: Exception do
      begin
        Result.Status := ghConnectionFailed;
        Result.ErrorMessage := E.Message;
      end;
    end;
  finally
    Client.Free;
  end;
end;

function TGatewayHttpClient.ListSessions(const Settings: TGatewaySettings): TGatewayListSessionsResult;
var
  Client: THTTPClient;
  Headers: TNetHeaders;
  Response: IHTTPResponse;
  Body: string;
begin
  Result.Status := gcConnectionFailed;
  Result.StatusCode := 0;
  Result.ErrorMessage := '';

  Headers := BuildGetHeaders(Settings);
  Client := THTTPClient.Create;
  try
    try
      Response := Client.Get(Settings.BaseUrl + '/api/sessions', nil, Headers);
      Result.StatusCode := Response.StatusCode;
      Body := Response.ContentAsString(TEncoding.UTF8);

      if Response.StatusCode = 200 then
      begin
        try
          Result.Sessions := TGatewaySessionListResponse.FromJson(Body);
          Result.Status := gcSuccess;
        except
          on E: Exception do
          begin
            Result.Status := gcInvalidResponse;
            Result.ErrorMessage := E.Message;
          end;
        end;
        Exit;
      end;

      if Response.StatusCode = 401 then
      begin
        Result.Status := gcUnauthorized;
        try
          Result.ErrorMessage := TGatewayErrorResponse.FromJson(Body).Message;
        except
          Result.ErrorMessage := 'Gateway rejected the configured launch token.';
        end;
        Exit;
      end;

      Result.Status := gcHttpError;
      try
        Result.ErrorMessage := TGatewayErrorResponse.FromJson(Body).Message;
      except
        Result.ErrorMessage := Format('Gateway returned HTTP %d.', [Response.StatusCode]);
      end;
    except
      on E: Exception do
      begin
        Result.Status := gcConnectionFailed;
        Result.ErrorMessage := E.Message;
      end;
    end;
  finally
    Client.Free;
  end;
end;

function TGatewayHttpClient.CreateSession(
  const Settings: TGatewaySettings;
  const Request: TGatewayCreateSessionRequest): TGatewayCreateSessionResult;
var
  Client: THTTPClient;
  Headers: TNetHeaders;
  Response: IHTTPResponse;
  Body: string;
  RequestBody: TStringStream;
begin
  Result.Status := gcConnectionFailed;
  Result.StatusCode := 0;
  Result.ErrorMessage := '';

  Headers := BuildJsonHeaders(Settings);
  RequestBody := TStringStream.Create(Request.ToJson, TEncoding.UTF8);
  Client := THTTPClient.Create;
  try
    try
      Response := Client.Post(Settings.BaseUrl + '/api/sessions', RequestBody, nil, Headers);
      Result.StatusCode := Response.StatusCode;
      Body := Response.ContentAsString(TEncoding.UTF8);

      if Response.StatusCode = 201 then
      begin
        try
          Result.Session := TGatewaySessionResponse.FromJson(Body);
          Result.Status := gcSuccess;
        except
          on E: Exception do
          begin
            Result.Status := gcInvalidResponse;
            Result.ErrorMessage := E.Message;
          end;
        end;
        Exit;
      end;

      if Response.StatusCode = 401 then
      begin
        Result.Status := gcUnauthorized;
        try
          Result.ErrorMessage := TGatewayErrorResponse.FromJson(Body).Message;
        except
          Result.ErrorMessage := 'Gateway rejected the configured launch token.';
        end;
        Exit;
      end;

      Result.Status := gcHttpError;
      try
        Result.ErrorMessage := TGatewayErrorResponse.FromJson(Body).Message;
      except
        Result.ErrorMessage := Format('Gateway returned HTTP %d.', [Response.StatusCode]);
      end;
    except
      on E: Exception do
      begin
        Result.Status := gcConnectionFailed;
        Result.ErrorMessage := E.Message;
      end;
    end;
  finally
    Client.Free;
    RequestBody.Free;
  end;
end;

function TGatewayHttpClient.SendMessage(
  const Settings: TGatewaySettings;
  const SessionId: string;
  const Request: TGatewaySendMessageRequest): TGatewaySendMessageResult;
var
  Client: THTTPClient;
  Headers: TNetHeaders;
  Response: IHTTPResponse;
  Body: string;
  RequestBody: TStringStream;
begin
  Result.Status := gcConnectionFailed;
  Result.StatusCode := 0;
  Result.ErrorMessage := '';

  Headers := BuildJsonHeaders(Settings);
  RequestBody := TStringStream.Create(Request.ToJson, TEncoding.UTF8);
  Client := THTTPClient.Create;
  try
    try
      Response := Client.Post(
        Format('%s/api/sessions/%s/messages', [Settings.BaseUrl, SessionId]),
        RequestBody,
        nil,
        Headers);
      Result.StatusCode := Response.StatusCode;
      Body := Response.ContentAsString(TEncoding.UTF8);

      if Response.StatusCode = 202 then
      begin
        try
          Result.Message := TGatewaySendMessageResponse.FromJson(Body);
          Result.Status := gcSuccess;
        except
          on E: Exception do
          begin
            Result.Status := gcInvalidResponse;
            Result.ErrorMessage := E.Message;
          end;
        end;
        Exit;
      end;

      if Response.StatusCode = 401 then
      begin
        Result.Status := gcUnauthorized;
        try
          Result.ErrorMessage := TGatewayErrorResponse.FromJson(Body).Message;
        except
          Result.ErrorMessage := 'Gateway rejected the configured launch token.';
        end;
        Exit;
      end;

      Result.Status := gcHttpError;
      try
        Result.ErrorMessage := TGatewayErrorResponse.FromJson(Body).Message;
      except
        Result.ErrorMessage := Format('Gateway returned HTTP %d.', [Response.StatusCode]);
      end;
    except
      on E: Exception do
      begin
        Result.Status := gcConnectionFailed;
        Result.ErrorMessage := E.Message;
      end;
    end;
  finally
    Client.Free;
    RequestBody.Free;
  end;
end;

function TGatewayHttpClient.StopSession(
  const Settings: TGatewaySettings;
  const SessionId: string): TGatewayStopSessionResult;
var
  Client: THTTPClient;
  Headers: TNetHeaders;
  Response: IHTTPResponse;
  Body: string;
  RequestBody: TStringStream;
begin
  Result.Status := gcConnectionFailed;
  Result.StatusCode := 0;
  Result.ErrorMessage := '';

  Headers := BuildJsonHeaders(Settings);
  RequestBody := TStringStream.Create('{}', TEncoding.UTF8);
  Client := THTTPClient.Create;
  try
    try
      Response := Client.Post(
        Format('%s/api/sessions/%s/stop', [Settings.BaseUrl, SessionId]),
        RequestBody,
        nil,
        Headers);
      Result.StatusCode := Response.StatusCode;
      Body := Response.ContentAsString(TEncoding.UTF8);

      if Response.StatusCode = 200 then
      begin
        try
          Result.StopResponse := TGatewayStopSessionResponse.FromJson(Body);
          Result.Status := gcSuccess;
        except
          on E: Exception do
          begin
            Result.Status := gcInvalidResponse;
            Result.ErrorMessage := E.Message;
          end;
        end;
        Exit;
      end;

      if Response.StatusCode = 401 then
      begin
        Result.Status := gcUnauthorized;
        try
          Result.ErrorMessage := TGatewayErrorResponse.FromJson(Body).Message;
        except
          Result.ErrorMessage := 'Gateway rejected the configured launch token.';
        end;
        Exit;
      end;

      Result.Status := gcHttpError;
      try
        Result.ErrorMessage := TGatewayErrorResponse.FromJson(Body).Message;
      except
        Result.ErrorMessage := Format('Gateway returned HTTP %d.', [Response.StatusCode]);
      end;
    except
      on E: Exception do
      begin
        Result.Status := gcConnectionFailed;
        Result.ErrorMessage := E.Message;
      end;
    end;
  finally
    Client.Free;
    RequestBody.Free;
  end;
end;

function TGatewayHttpClient.SubmitApproval(
  const Settings: TGatewaySettings;
  const SessionId: string;
  const RequestId: string;
  const Request: TGatewaySubmitApprovalRequest): TGatewaySubmitApprovalResult;
var
  Client: THTTPClient;
  Headers: TNetHeaders;
  Response: IHTTPResponse;
  Body: string;
  RequestBody: TStringStream;
begin
  Result.Status := gcConnectionFailed;
  Result.StatusCode := 0;
  Result.ErrorMessage := '';

  Headers := BuildJsonHeaders(Settings);
  RequestBody := TStringStream.Create(Request.ToJson, TEncoding.UTF8);
  Client := THTTPClient.Create;
  try
    try
      Response := Client.Post(
        Format('%s/api/sessions/%s/approvals/%s', [Settings.BaseUrl, SessionId, RequestId]),
        RequestBody,
        nil,
        Headers);
      Result.StatusCode := Response.StatusCode;
      Body := Response.ContentAsString(TEncoding.UTF8);

      if Response.StatusCode = 200 then
      begin
        try
          Result.Approval := TGatewaySubmitApprovalResponse.FromJson(Body);
          Result.Status := gcSuccess;
        except
          on E: Exception do
          begin
            Result.Status := gcInvalidResponse;
            Result.ErrorMessage := E.Message;
          end;
        end;
        Exit;
      end;

      if Response.StatusCode = 401 then
      begin
        Result.Status := gcUnauthorized;
        try
          Result.ErrorMessage := TGatewayErrorResponse.FromJson(Body).Message;
        except
          Result.ErrorMessage := 'Gateway rejected the configured launch token.';
        end;
        Exit;
      end;

      Result.Status := gcHttpError;
      try
        Result.ErrorMessage := TGatewayErrorResponse.FromJson(Body).Message;
      except
        Result.ErrorMessage := Format('Gateway returned HTTP %d.', [Response.StatusCode]);
      end;
    except
      on E: Exception do
      begin
        Result.Status := gcConnectionFailed;
        Result.ErrorMessage := E.Message;
      end;
    end;
  finally
    Client.Free;
    RequestBody.Free;
  end;
end;

end.
