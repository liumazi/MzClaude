unit GatewayProtocol;

interface

type
  TGatewayHealthConfig = record
    Host: string;
    Port: Integer;
    AuthRequired: Boolean;
    DataDirConfigured: Boolean;
  end;

  TGatewayHealthResponse = record
    ProtocolVersion: Integer;
    Status: string;
    Version: string;
    Config: TGatewayHealthConfig;
    class function FromJson(const JsonText: string): TGatewayHealthResponse; static;
  end;

  TGatewayErrorResponse = record
    Code: string;
    Message: string;
    class function FromJson(const JsonText: string): TGatewayErrorResponse; static;
  end;

  TGatewayCreateSessionRequest = record
    WorkspacePath: string;
    PermissionPreset: string;
    ResumeSessionId: string;
    function ToJson: string;
  end;

  TGatewaySessionResponse = record
    ProtocolVersion: Integer;
    Id: string;
    SdkSessionId: string;
    WorkspacePath: string;
    Title: string;
    Status: string;
    CreatedAt: string;
    UpdatedAt: string;
    class function FromJson(const JsonText: string): TGatewaySessionResponse; static;
  end;

  TGatewaySendMessageRequest = record
    Prompt: string;
    function ToJson: string;
  end;

  TGatewaySendMessageResponse = record
    ProtocolVersion: Integer;
    SessionId: string;
    RunId: string;
    Status: string;
    class function FromJson(const JsonText: string): TGatewaySendMessageResponse; static;
  end;

  TGatewayStopSessionResponse = record
    ProtocolVersion: Integer;
    SessionId: string;
    RunId: string;
    Status: string;
    class function FromJson(const JsonText: string): TGatewayStopSessionResponse; static;
  end;

  TGatewaySessionListResponse = record
    ProtocolVersion: Integer;
    Sessions: TArray<TGatewaySessionResponse>;
    class function FromJson(const JsonText: string): TGatewaySessionListResponse; static;
  end;

  TGatewaySessionHistoryMessage = record
    Role: string;
    Uuid: string;
    SessionId: string;
    Text: string;
  end;

  TGatewaySessionHistoryResponse = record
    ProtocolVersion: Integer;
    SessionId: string;
    WorkspacePath: string;
    Messages: TArray<TGatewaySessionHistoryMessage>;
    class function FromJson(const JsonText: string): TGatewaySessionHistoryResponse; static;
  end;

  TGatewayQuestionOption = record
    LabelText: string;
    Description: string;
    Preview: string;
  end;

  TGatewayQuestion = record
    Question: string;
    Header: string;
    MultiSelect: Boolean;
    Options: TArray<TGatewayQuestionOption>;
  end;

  TGatewayQuestionAnswer = record
    Question: string;
    Answer: string;
  end;

  TGatewaySubmitApprovalRequest = record
    Action: string;
    Reason: string;
    UpdatedInputJson: string;
    Answers: TArray<TGatewayQuestionAnswer>;
    function ToJson: string;
  end;

  TGatewaySubmitApprovalResponse = record
    ProtocolVersion: Integer;
    SessionId: string;
    RequestId: string;
    Status: string;
    class function FromJson(const JsonText: string): TGatewaySubmitApprovalResponse; static;
  end;

  TGatewayEvent = record
    ProtocolVersion: Integer;
    SessionId: string;
    RunId: string;
    EventType: string;
    Timestamp: string;
    Text: string;
    Status: string;
    SdkSessionId: string;
    ErrorCode: string;
    ErrorMessage: string;
    RequestId: string;
    ToolName: string;
    ToolInputJson: string;
    Title: string;
    DisplayName: string;
    Description: string;
    Questions: TArray<TGatewayQuestion>;
    class function FromJson(const JsonText: string): TGatewayEvent; static;
  end;

implementation

uses
  System.Classes,
  System.JSON,
  System.SysUtils;

function ReadRequiredString(const Json: TJSONObject; const Name: string): string;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if Value = nil then
    raise EInvalidOperation.CreateFmt('Missing JSON string property: %s', [Name]);

  Result := Value.Value;
end;

function ReadRequiredInteger(const Json: TJSONObject; const Name: string): Integer;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if (Value = nil) or not TryStrToInt(Value.Value, Result) then
    raise EInvalidOperation.CreateFmt('Missing or invalid JSON integer property: %s', [Name]);
end;

function ReadRequiredBoolean(const Json: TJSONObject; const Name: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if Value = nil then
    raise EInvalidOperation.CreateFmt('Missing JSON boolean property: %s', [Name]);

  if SameText(Value.Value, 'true') then
    Exit(True);
  if SameText(Value.Value, 'false') then
    Exit(False);

  raise EInvalidOperation.CreateFmt('Invalid JSON boolean property: %s', [Name]);
end;

function ReadRequiredObject(const Json: TJSONObject; const Name: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if not (Value is TJSONObject) then
    raise EInvalidOperation.CreateFmt('Missing JSON object property: %s', [Name]);

  Result := TJSONObject(Value);
end;

function ReadOptionalString(const Json: TJSONObject; const Name: string): string;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if Value = nil then
    Exit('');

  Result := Value.Value;
end;

function ReadOptionalBoolean(const Json: TJSONObject; const Name: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if Value = nil then
    Exit(False);

  if SameText(Value.Value, 'true') then
    Exit(True);
  if SameText(Value.Value, 'false') then
    Exit(False);

  raise EInvalidOperation.CreateFmt('Invalid JSON boolean property: %s', [Name]);
end;

function ReadOptionalObjectJson(const Json: TJSONObject; const Name: string): string;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if Value = nil then
    Exit('');

  Result := Value.ToJSON;
end;

function WriteJsonString(const Value: string): string;
var
  JsonString: TJSONString;
begin
  JsonString := TJSONString.Create(Value);
  try
    Result := JsonString.ToJSON;
  finally
    JsonString.Free;
  end;
end;

function ParseQuestionOptions(const Json: TJSONObject): TArray<TGatewayQuestionOption>;
var
  OptionsValue: TJSONValue;
  OptionsArray: TJSONArray;
  I: Integer;
  OptionObject: TJSONObject;
begin
  SetLength(Result, 0);
  OptionsValue := Json.GetValue('options');
  if not (OptionsValue is TJSONArray) then
    Exit;

  OptionsArray := TJSONArray(OptionsValue);
  SetLength(Result, OptionsArray.Count);
  for I := 0 to OptionsArray.Count - 1 do
  begin
    if not (OptionsArray.Items[I] is TJSONObject) then
      Continue;

    OptionObject := TJSONObject(OptionsArray.Items[I]);
    Result[I].LabelText := ReadOptionalString(OptionObject, 'label');
    Result[I].Description := ReadOptionalString(OptionObject, 'description');
    Result[I].Preview := ReadOptionalString(OptionObject, 'preview');
  end;
end;

function ParseQuestions(const Json: TJSONObject): TArray<TGatewayQuestion>;
var
  QuestionsValue: TJSONValue;
  QuestionsArray: TJSONArray;
  I: Integer;
  QuestionObject: TJSONObject;
begin
  SetLength(Result, 0);
  QuestionsValue := Json.GetValue('questions');
  if not (QuestionsValue is TJSONArray) then
    Exit;

  QuestionsArray := TJSONArray(QuestionsValue);
  SetLength(Result, QuestionsArray.Count);
  for I := 0 to QuestionsArray.Count - 1 do
  begin
    if not (QuestionsArray.Items[I] is TJSONObject) then
      Continue;

    QuestionObject := TJSONObject(QuestionsArray.Items[I]);
    Result[I].Question := ReadOptionalString(QuestionObject, 'question');
    Result[I].Header := ReadOptionalString(QuestionObject, 'header');
    Result[I].MultiSelect := ReadOptionalBoolean(QuestionObject, 'multiSelect');
    Result[I].Options := ParseQuestionOptions(QuestionObject);
  end;
end;

class function TGatewayHealthResponse.FromJson(const JsonText: string): TGatewayHealthResponse;
var
  RootValue: TJSONValue;
  Root: TJSONObject;
  ConfigObject: TJSONObject;
begin
  RootValue := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (RootValue is TJSONObject) then
      raise EInvalidOperation.Create('Health response is not a JSON object.');

    Root := TJSONObject(RootValue);
    ConfigObject := ReadRequiredObject(Root, 'config');

    Result.ProtocolVersion := ReadRequiredInteger(Root, 'protocolVersion');
    Result.Status := ReadRequiredString(Root, 'status');
    Result.Version := ReadRequiredString(Root, 'version');
    Result.Config.Host := ReadRequiredString(ConfigObject, 'host');
    Result.Config.Port := ReadRequiredInteger(ConfigObject, 'port');
    Result.Config.AuthRequired := ReadRequiredBoolean(ConfigObject, 'authRequired');
    Result.Config.DataDirConfigured := ReadRequiredBoolean(ConfigObject, 'dataDirConfigured');
  finally
    RootValue.Free;
  end;
end;

class function TGatewayErrorResponse.FromJson(const JsonText: string): TGatewayErrorResponse;
var
  RootValue: TJSONValue;
  Root: TJSONObject;
  ErrorObject: TJSONObject;
begin
  RootValue := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (RootValue is TJSONObject) then
      raise EInvalidOperation.Create('Error response is not a JSON object.');

    Root := TJSONObject(RootValue);
    ErrorObject := ReadRequiredObject(Root, 'error');

    Result.Code := ReadRequiredString(ErrorObject, 'code');
    Result.Message := ReadRequiredString(ErrorObject, 'message');
  finally
    RootValue.Free;
  end;
end;

function TGatewayCreateSessionRequest.ToJson: string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('workspacePath', WorkspacePath);
    if PermissionPreset <> '' then
      Root.AddPair('permissionPreset', PermissionPreset);
    if ResumeSessionId <> '' then
      Root.AddPair('resumeSessionId', ResumeSessionId);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TGatewaySessionResponse.FromJson(const JsonText: string): TGatewaySessionResponse;
var
  RootValue: TJSONValue;
  Root: TJSONObject;
begin
  RootValue := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (RootValue is TJSONObject) then
      raise EInvalidOperation.Create('Session response is not a JSON object.');

    Root := TJSONObject(RootValue);
    Result.ProtocolVersion := ReadRequiredInteger(Root, 'protocolVersion');
    Result.Id := ReadRequiredString(Root, 'id');
    Result.SdkSessionId := ReadOptionalString(Root, 'sdkSessionId');
    Result.WorkspacePath := ReadRequiredString(Root, 'workspacePath');
    Result.Title := ReadOptionalString(Root, 'title');
    Result.Status := ReadRequiredString(Root, 'status');
    Result.CreatedAt := ReadRequiredString(Root, 'createdAt');
    Result.UpdatedAt := ReadRequiredString(Root, 'updatedAt');
  finally
    RootValue.Free;
  end;
end;

function TGatewaySendMessageRequest.ToJson: string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('prompt', Prompt);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TGatewayStopSessionResponse.FromJson(const JsonText: string): TGatewayStopSessionResponse;
var
  RootValue: TJSONValue;
  Root: TJSONObject;
begin
  RootValue := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (RootValue is TJSONObject) then
      raise EInvalidOperation.Create('Stop session response is not a JSON object.');

    Root := TJSONObject(RootValue);
    Result.ProtocolVersion := ReadRequiredInteger(Root, 'protocolVersion');
    Result.SessionId := ReadRequiredString(Root, 'sessionId');
    Result.RunId := ReadOptionalString(Root, 'runId');
    Result.Status := ReadRequiredString(Root, 'status');
  finally
    RootValue.Free;
  end;
end;

class function TGatewaySessionHistoryResponse.FromJson(const JsonText: string): TGatewaySessionHistoryResponse;
var
  RootValue: TJSONValue;
  Root: TJSONObject;
  MessagesValue: TJSONValue;
  MessagesArray: TJSONArray;
  MessageObject: TJSONObject;
  I: Integer;
begin
  SetLength(Result.Messages, 0);
  RootValue := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (RootValue is TJSONObject) then
      raise EInvalidOperation.Create('Session history response is not a JSON object.');

    Root := TJSONObject(RootValue);
    Result.ProtocolVersion := ReadRequiredInteger(Root, 'protocolVersion');
    Result.SessionId := ReadRequiredString(Root, 'sessionId');
    Result.WorkspacePath := ReadOptionalString(Root, 'workspacePath');
    MessagesValue := Root.GetValue('messages');
    if not (MessagesValue is TJSONArray) then
      Exit;

    MessagesArray := TJSONArray(MessagesValue);
    SetLength(Result.Messages, MessagesArray.Count);
    for I := 0 to MessagesArray.Count - 1 do
    begin
      if MessagesArray.Items[I] is TJSONObject then
      begin
        MessageObject := TJSONObject(MessagesArray.Items[I]);
        Result.Messages[I].Role := ReadRequiredString(MessageObject, 'role');
        Result.Messages[I].Uuid := ReadRequiredString(MessageObject, 'uuid');
        Result.Messages[I].SessionId := ReadRequiredString(MessageObject, 'sessionId');
        Result.Messages[I].Text := ReadOptionalString(MessageObject, 'text');
      end;
    end;
  finally
    RootValue.Free;
  end;
end;

class function TGatewaySessionListResponse.FromJson(const JsonText: string): TGatewaySessionListResponse;
var
  RootValue: TJSONValue;
  Root: TJSONObject;
  SessionsValue: TJSONValue;
  SessionsArray: TJSONArray;
  I: Integer;
  SessionObject: TJSONObject;
begin
  SetLength(Result.Sessions, 0);
  RootValue := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (RootValue is TJSONObject) then
      raise EInvalidOperation.Create('Session list response is not a JSON object.');

    Root := TJSONObject(RootValue);
    Result.ProtocolVersion := ReadRequiredInteger(Root, 'protocolVersion');
    SessionsValue := Root.GetValue('sessions');
    if not (SessionsValue is TJSONArray) then
      Exit;

    SessionsArray := TJSONArray(SessionsValue);
    SetLength(Result.Sessions, SessionsArray.Count);
    for I := 0 to SessionsArray.Count - 1 do
    begin
      if SessionsArray.Items[I] is TJSONObject then
      begin
        SessionObject := TJSONObject(SessionsArray.Items[I]);
        Result.Sessions[I] := TGatewaySessionResponse.FromJson(SessionObject.ToJSON);
      end;
    end;
  finally
    RootValue.Free;
  end;
end;

class function TGatewaySendMessageResponse.FromJson(const JsonText: string): TGatewaySendMessageResponse;
var
  RootValue: TJSONValue;
  Root: TJSONObject;
begin
  RootValue := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (RootValue is TJSONObject) then
      raise EInvalidOperation.Create('Message response is not a JSON object.');

    Root := TJSONObject(RootValue);
    Result.ProtocolVersion := ReadRequiredInteger(Root, 'protocolVersion');
    Result.SessionId := ReadRequiredString(Root, 'sessionId');
    Result.RunId := ReadRequiredString(Root, 'runId');
    Result.Status := ReadRequiredString(Root, 'status');
  finally
    RootValue.Free;
  end;
end;

function TGatewaySubmitApprovalRequest.ToJson: string;
var
  Root: TJSONObject;
  AnswersObject: TJSONObject;
  I: Integer;
  InputValue: TJSONValue;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('action', Action);
    if Reason <> '' then
      Root.AddPair('reason', Reason);

    if UpdatedInputJson <> '' then
    begin
      InputValue := TJSONObject.ParseJSONValue(UpdatedInputJson);
      if InputValue = nil then
        raise EInvalidOperation.Create('UpdatedInputJson is not valid JSON.');
      Root.AddPair('updatedInput', InputValue);
    end;

    if Length(Answers) > 0 then
    begin
      AnswersObject := TJSONObject.Create;
      Root.AddPair('answers', AnswersObject);
      for I := 0 to High(Answers) do
        AnswersObject.AddPair(Answers[I].Question, Answers[I].Answer);
    end;

    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TGatewaySubmitApprovalResponse.FromJson(const JsonText: string): TGatewaySubmitApprovalResponse;
var
  RootValue: TJSONValue;
  Root: TJSONObject;
begin
  RootValue := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (RootValue is TJSONObject) then
      raise EInvalidOperation.Create('Approval response is not a JSON object.');

    Root := TJSONObject(RootValue);
    Result.ProtocolVersion := ReadRequiredInteger(Root, 'protocolVersion');
    Result.SessionId := ReadRequiredString(Root, 'sessionId');
    Result.RequestId := ReadRequiredString(Root, 'requestId');
    Result.Status := ReadRequiredString(Root, 'status');
  finally
    RootValue.Free;
  end;
end;

class function TGatewayEvent.FromJson(const JsonText: string): TGatewayEvent;
var
  RootValue: TJSONValue;
  Root: TJSONObject;
  Payload: TJSONObject;
begin
  RootValue := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (RootValue is TJSONObject) then
      raise EInvalidOperation.Create('Gateway event is not a JSON object.');

    Root := TJSONObject(RootValue);
    Result.ProtocolVersion := ReadRequiredInteger(Root, 'protocolVersion');
    Result.SessionId := ReadRequiredString(Root, 'sessionId');
    Result.RunId := ReadOptionalString(Root, 'runId');
    Result.EventType := ReadRequiredString(Root, 'type');
    Result.Timestamp := ReadRequiredString(Root, 'timestamp');

    Payload := ReadRequiredObject(Root, 'payload');
    Result.Text := ReadOptionalString(Payload, 'text');
    Result.Status := ReadOptionalString(Payload, 'status');
    Result.SdkSessionId := ReadOptionalString(Payload, 'sdkSessionId');
    Result.ErrorCode := ReadOptionalString(Payload, 'code');
    Result.ErrorMessage := ReadOptionalString(Payload, 'message');
    Result.RequestId := ReadOptionalString(Payload, 'requestId');
    Result.ToolName := ReadOptionalString(Payload, 'toolName');
    Result.ToolInputJson := ReadOptionalObjectJson(Payload, 'input');
    Result.Title := ReadOptionalString(Payload, 'title');
    Result.DisplayName := ReadOptionalString(Payload, 'displayName');
    Result.Description := ReadOptionalString(Payload, 'description');
    Result.Questions := ParseQuestions(Payload);
  finally
    RootValue.Free;
  end;
end;

end.
