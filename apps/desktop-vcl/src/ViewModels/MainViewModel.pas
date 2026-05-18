unit MainViewModel;

interface

uses
  AppSettings,
  GatewayEventsClient,
  GatewayHttpClient,
  GatewayProcessService,
  GatewayProtocol;

type
  TGatewayConnectionStatus = (
    gcsNotConfigured,
    gcsChecking,
    gcsConnected,
    gcsUnauthorized,
    gcsDisconnected,
    gcsError
  );

  TChatChangedEvent = procedure(Sender: TObject) of object;

  TMainViewModel = class
  private
    FSettingsService: TAppSettingsService;
    FEventsClient: TGatewayEventsClient;
    FHttpClient: TGatewayHttpClient;
    FProcessService: TGatewayProcessService;
    FSettings: TGatewaySettings;
    FStatus: TGatewayConnectionStatus;
    FStatusText: string;
    FDetailsText: string;
    FHealth: TGatewayHealthResponse;
    FSession: TGatewaySessionResponse;
    FWorkspacePath: string;
    FTranscriptText: string;
    FRunning: Boolean;
    FOnChatChanged: TChatChangedEvent;
    procedure SetStatus(AStatus: TGatewayConnectionStatus; const AStatusText, ADetailsText: string);
    procedure NotifyChatChanged;
    procedure HandleGatewayEvent(const Event: TGatewayEvent);
    procedure HandleGatewayError(const ErrorMessage: string);
    procedure HandlePermissionRequest(const Event: TGatewayEvent);
    procedure HandleQuestionRequest(const Event: TGatewayEvent);
    procedure SubmitApproval(
      const RequestId: string;
      const Request: TGatewaySubmitApprovalRequest;
      const FailureTitle: string);
  public
    constructor Create(
      ASettingsService: TAppSettingsService;
      AEventsClient: TGatewayEventsClient;
      AHttpClient: TGatewayHttpClient;
      AProcessService: TGatewayProcessService);

    procedure LoadSettings;
    procedure CheckGatewayHealth;
    function SendPrompt(const WorkspacePath, Prompt: string): Boolean;
    function GatewayAddressText: string;
    function CanSendPrompt: Boolean;

    property Settings: TGatewaySettings read FSettings;
    property Status: TGatewayConnectionStatus read FStatus;
    property StatusText: string read FStatusText;
    property DetailsText: string read FDetailsText;
    property Health: TGatewayHealthResponse read FHealth;
    property Session: TGatewaySessionResponse read FSession;
    property WorkspacePath: string read FWorkspacePath;
    property TranscriptText: string read FTranscriptText;
    property Running: Boolean read FRunning;
    property OnChatChanged: TChatChangedEvent read FOnChatChanged write FOnChatChanged;
  end;

implementation

uses
  System.SysUtils,
  ApprovalDialog,
  QuestionDialog;

constructor TMainViewModel.Create(
  ASettingsService: TAppSettingsService;
  AEventsClient: TGatewayEventsClient;
  AHttpClient: TGatewayHttpClient;
  AProcessService: TGatewayProcessService);
begin
  inherited Create;
  FSettingsService := ASettingsService;
  FEventsClient := AEventsClient;
  FHttpClient := AHttpClient;
  FProcessService := AProcessService;
  FTranscriptText := '';
  FRunning := False;
  SetStatus(gcsNotConfigured, 'Not configured', 'Gateway settings have not been loaded.');
end;

procedure TMainViewModel.LoadSettings;
begin
  FSettings := FSettingsService.Load;
  FProcessService.UseExternalGateway(FSettings);

  if FSettings.IsConfigured then
    SetStatus(gcsDisconnected, 'Gateway not checked', 'Ready to check ' + FSettings.BaseUrl + '.')
  else
    SetStatus(
      gcsNotConfigured,
      'Gateway settings missing',
      Format('Set a gateway port in %s before connecting.', [FSettingsService.SettingsPath]));
end;

procedure TMainViewModel.CheckGatewayHealth;
var
  HealthResult: TGatewayHealthCheckResult;
begin
  if not FSettings.IsConfigured then
  begin
    SetStatus(
      gcsNotConfigured,
      'Gateway settings missing',
      Format('Set a gateway port in %s before connecting.', [FSettingsService.SettingsPath]));
    Exit;
  end;

  SetStatus(gcsChecking, 'Checking gateway', 'Calling ' + FSettings.BaseUrl + '/api/health.');

  HealthResult := FHttpClient.CheckHealth(FSettings);
  case HealthResult.Status of
    ghSuccess:
      begin
        FHealth := HealthResult.Health;
        SetStatus(
          gcsConnected,
          'Gateway connected',
          Format(
            'Gateway %s is healthy on %s:%d.',
            [FHealth.Version, FHealth.Config.Host, FHealth.Config.Port]));
      end;
    ghUnauthorized:
      begin
        FProcessService.MarkUnavailable(HealthResult.ErrorMessage);
        SetStatus(gcsUnauthorized, 'Gateway token rejected', HealthResult.ErrorMessage);
      end;
    ghConnectionFailed:
      begin
        FProcessService.MarkUnavailable(HealthResult.ErrorMessage);
        SetStatus(gcsDisconnected, 'Gateway unreachable', HealthResult.ErrorMessage);
      end;
    ghInvalidResponse:
      begin
        FProcessService.MarkUnavailable(HealthResult.ErrorMessage);
        SetStatus(gcsError, 'Gateway response invalid', HealthResult.ErrorMessage);
      end;
    ghHttpError:
      begin
        FProcessService.MarkUnavailable(HealthResult.ErrorMessage);
        SetStatus(gcsError, 'Gateway health check failed', HealthResult.ErrorMessage);
      end;
  end;
end;

function TMainViewModel.SendPrompt(const WorkspacePath, Prompt: string): Boolean;
var
  CreateRequest: TGatewayCreateSessionRequest;
  CreateResult: TGatewayCreateSessionResult;
  MessageRequest: TGatewaySendMessageRequest;
  MessageResult: TGatewaySendMessageResult;
  SessionCreated: Boolean;
begin
  Result := False;
  SessionCreated := False;

  if not FSettings.IsConfigured then
  begin
    SetStatus(gcsNotConfigured, 'Gateway settings missing', 'Configure and connect the gateway before sending a prompt.');
    NotifyChatChanged;
    Exit;
  end;

  if FRunning then
  begin
    SetStatus(gcsError, 'Chat is running', 'Wait for the current response to finish before sending another prompt.');
    NotifyChatChanged;
    Exit;
  end;

  FWorkspacePath := Trim(WorkspacePath);
  if FWorkspacePath = '' then
  begin
    SetStatus(gcsError, 'Workspace required', 'Choose a workspace before sending a prompt.');
    NotifyChatChanged;
    Exit;
  end;

  if Trim(Prompt) = '' then
  begin
    SetStatus(gcsError, 'Prompt required', 'Enter a prompt before sending.');
    NotifyChatChanged;
    Exit;
  end;

  if (FSession.Id = '') or not SameText(FSession.WorkspacePath, FWorkspacePath) then
  begin
    CreateRequest.WorkspacePath := FWorkspacePath;
    CreateRequest.PermissionPreset := 'default';
    CreateResult := FHttpClient.CreateSession(FSettings, CreateRequest);
    if CreateResult.Status <> gcSuccess then
    begin
      SetStatus(gcsError, 'Session creation failed', CreateResult.ErrorMessage);
      NotifyChatChanged;
      Exit;
    end;

    FSession := CreateResult.Session;
    FEventsClient.Connect(FSettings, FSession.Id, HandleGatewayEvent, HandleGatewayError);
    if not FEventsClient.WaitForConnected(2000) then
    begin
      SetStatus(gcsDisconnected, 'Gateway event stream unavailable', 'Could not connect the WebSocket event stream.');
      NotifyChatChanged;
      Exit;
    end;
    SessionCreated := True;
  end;

  if (not SessionCreated) and (not FEventsClient.Connected) then
  begin
    FEventsClient.Connect(FSettings, FSession.Id, HandleGatewayEvent, HandleGatewayError);
    if not FEventsClient.WaitForConnected(2000) then
    begin
      SetStatus(gcsDisconnected, 'Gateway event stream unavailable', 'Could not connect the WebSocket event stream.');
      NotifyChatChanged;
      Exit;
    end;
  end;

  FTranscriptText := FTranscriptText
    + 'User: ' + Prompt + sLineBreak + sLineBreak
    + 'Assistant: ';
  FRunning := True;
  SetStatus(gcsConnected, 'Chat running', 'Waiting for streamed response.');
  NotifyChatChanged;

  MessageRequest.Prompt := Prompt;
  MessageResult := FHttpClient.SendMessage(FSettings, FSession.Id, MessageRequest);
  if MessageResult.Status <> gcSuccess then
  begin
    FRunning := False;
    SetStatus(gcsError, 'Prompt send failed', MessageResult.ErrorMessage);
    NotifyChatChanged;
    Exit;
  end;

  Result := True;
end;

function TMainViewModel.GatewayAddressText: string;
begin
  if FSettings.IsConfigured then
    Result := FSettings.BaseUrl
  else
    Result := 'No gateway port configured';
end;

function TMainViewModel.CanSendPrompt: Boolean;
begin
  Result := FSettings.IsConfigured and not FRunning;
end;

procedure TMainViewModel.HandleGatewayEvent(const Event: TGatewayEvent);
begin
  if Event.EventType = 'text_delta' then
  begin
    FTranscriptText := FTranscriptText + Event.Text;
    NotifyChatChanged;
    Exit;
  end;

  if Event.EventType = 'result' then
  begin
    FRunning := False;
    if Event.SdkSessionId <> '' then
      FSession.SdkSessionId := Event.SdkSessionId;
    FTranscriptText := FTranscriptText + sLineBreak + sLineBreak;
    SetStatus(gcsConnected, 'Chat complete', 'Ready for the next prompt.');
    NotifyChatChanged;
    Exit;
  end;

  if Event.EventType = 'permission_request' then
  begin
    HandlePermissionRequest(Event);
    Exit;
  end;

  if Event.EventType = 'question_request' then
  begin
    HandleQuestionRequest(Event);
    Exit;
  end;

  if Event.EventType = 'error' then
  begin
    FRunning := False;
    FTranscriptText := FTranscriptText
      + sLineBreak
      + 'Error: ' + Event.ErrorMessage
      + sLineBreak
      + sLineBreak;
    SetStatus(gcsError, 'Chat failed', Event.ErrorMessage);
    NotifyChatChanged;
  end;
end;

procedure TMainViewModel.HandlePermissionRequest(const Event: TGatewayEvent);
var
  ApprovalRequest: TGatewaySubmitApprovalRequest;
  DenialReason: string;
begin
  FTranscriptText := FTranscriptText
    + sLineBreak
    + Format('[Permission requested: %s]', [Event.ToolName])
    + sLineBreak;
  SetStatus(gcsConnected, 'Waiting for approval', 'Review the requested tool action.');
  NotifyChatChanged;

  if TApprovalDialog.Execute(Event, DenialReason) = adAllow then
    ApprovalRequest.Action := 'allow'
  else
  begin
    ApprovalRequest.Action := 'deny';
    ApprovalRequest.Reason := DenialReason;
  end;

  SubmitApproval(Event.RequestId, ApprovalRequest, 'Approval submit failed');
end;

procedure TMainViewModel.HandleQuestionRequest(const Event: TGatewayEvent);
var
  ApprovalRequest: TGatewaySubmitApprovalRequest;
  Answers: TArray<TGatewayQuestionAnswer>;
begin
  FTranscriptText := FTranscriptText
    + sLineBreak
    + '[Question requested]'
    + sLineBreak;
  SetStatus(gcsConnected, 'Waiting for answer', 'Answer the question so Claude can continue.');
  NotifyChatChanged;

  if TQuestionDialog.Execute(Event, Answers) then
  begin
    ApprovalRequest.Action := 'answer_question';
    ApprovalRequest.Answers := Answers;
  end
  else
  begin
    ApprovalRequest.Action := 'deny';
    ApprovalRequest.Reason := 'User cancelled the question.';
  end;

  SubmitApproval(Event.RequestId, ApprovalRequest, 'Question submit failed');
end;

procedure TMainViewModel.SubmitApproval(
  const RequestId: string;
  const Request: TGatewaySubmitApprovalRequest;
  const FailureTitle: string);
var
  ApprovalResult: TGatewaySubmitApprovalResult;
begin
  ApprovalResult := FHttpClient.SubmitApproval(FSettings, FSession.Id, RequestId, Request);
  if ApprovalResult.Status <> gcSuccess then
  begin
    FRunning := False;
    SetStatus(gcsError, FailureTitle, ApprovalResult.ErrorMessage);
  end
  else
    SetStatus(gcsConnected, 'Chat running', 'Waiting for streamed response.');

  NotifyChatChanged;
end;

procedure TMainViewModel.HandleGatewayError(const ErrorMessage: string);
begin
  FRunning := False;
  SetStatus(gcsDisconnected, 'Gateway event stream closed', ErrorMessage);
  NotifyChatChanged;
end;

procedure TMainViewModel.NotifyChatChanged;
begin
  if Assigned(FOnChatChanged) then
    FOnChatChanged(Self);
end;

procedure TMainViewModel.SetStatus(
  AStatus: TGatewayConnectionStatus;
  const AStatusText, ADetailsText: string);
begin
  FStatus := AStatus;
  FStatusText := AStatusText;
  FDetailsText := ADetailsText;
end;

end.
