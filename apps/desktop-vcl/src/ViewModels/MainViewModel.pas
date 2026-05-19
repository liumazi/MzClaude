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
    FRecentSessions: TArray<TGatewaySessionResponse>;
    FSelectedSessionIndex: Integer;
    FWorkspacePath: string;
    FTranscriptText: string;
    FRunning: Boolean;
    FResumeSdkSessionId: string;
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
    procedure DisconnectEvents;
    procedure ClearActiveSession;
    function EnsureSessionConnected(const WorkspacePath: string): Boolean;
    function ConnectEventsForSession(const SessionId: string): Boolean;
  public
    constructor Create(
      ASettingsService: TAppSettingsService;
      AEventsClient: TGatewayEventsClient;
      AHttpClient: TGatewayHttpClient;
      AProcessService: TGatewayProcessService);

    procedure LoadSettings;
    procedure CheckGatewayHealth;
    procedure LoadRecentSessions;
    procedure SelectSession(Index: Integer);
    function RestoreSelectedSession: Boolean;
    function StopRunningTask: Boolean;
    function SendPrompt(const WorkspacePath, Prompt: string): Boolean;
    function GatewayAddressText: string;
    function CanSendPrompt: Boolean;
    function CanStop: Boolean;
    function CanRestore: Boolean;

    property Settings: TGatewaySettings read FSettings;
    property Status: TGatewayConnectionStatus read FStatus;
    property StatusText: string read FStatusText;
    property DetailsText: string read FDetailsText;
    property Health: TGatewayHealthResponse read FHealth;
    property Session: TGatewaySessionResponse read FSession;
    property RecentSessions: TArray<TGatewaySessionResponse> read FRecentSessions;
    property SelectedSessionIndex: Integer read FSelectedSessionIndex;
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
  FSelectedSessionIndex := -1;
  FResumeSdkSessionId := '';
  SetLength(FRecentSessions, 0);
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
        DisconnectEvents;
        ClearActiveSession;
        SetStatus(
          gcsConnected,
          'Gateway connected',
          Format(
            'Gateway %s is healthy on %s:%d.',
            [FHealth.Version, FHealth.Config.Host, FHealth.Config.Port]));
        LoadRecentSessions;
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
  NotifyChatChanged;
end;

procedure TMainViewModel.LoadRecentSessions;
var
  ListResult: TGatewayListSessionsResult;
begin
  SetLength(FRecentSessions, 0);
  FSelectedSessionIndex := -1;

  if FStatus <> gcsConnected then
  begin
    NotifyChatChanged;
    Exit;
  end;

  ListResult := FHttpClient.ListSessions(FSettings);
  if ListResult.Status = gcSuccess then
    FRecentSessions := ListResult.Sessions.Sessions
  else
    SetStatus(gcsError, 'Session list failed', ListResult.ErrorMessage);

  NotifyChatChanged;
end;

procedure TMainViewModel.SelectSession(Index: Integer);
begin
  if (Index < 0) or (Index >= Length(FRecentSessions)) then
  begin
    FSelectedSessionIndex := -1;
    NotifyChatChanged;
    Exit;
  end;

  FSelectedSessionIndex := Index;
  FWorkspacePath := FRecentSessions[Index].WorkspacePath;
  NotifyChatChanged;
end;

function TMainViewModel.RestoreSelectedSession: Boolean;
var
  Selected: TGatewaySessionResponse;
begin
  Result := False;

  if not CanRestore then
    Exit;

  Selected := FRecentSessions[FSelectedSessionIndex];
  DisconnectEvents;
  FSession := Selected;
  FWorkspacePath := Selected.WorkspacePath;
  FResumeSdkSessionId := Selected.SdkSessionId;
  FTranscriptText := Format(
    'Restored session %s' + sLineBreak
    + 'Workspace: %s' + sLineBreak
    + 'SDK session: %s' + sLineBreak + sLineBreak,
    [Selected.Id, Selected.WorkspacePath, Selected.SdkSessionId]);
  SetStatus(gcsConnected, 'Session restored', 'Ready to continue this conversation.');
  Result := ConnectEventsForSession(FSession.Id);
  NotifyChatChanged;
end;

function TMainViewModel.StopRunningTask: Boolean;
var
  StopResult: TGatewayStopSessionResult;
begin
  Result := False;

  if not CanStop then
    Exit;

  StopResult := FHttpClient.StopSession(FSettings, FSession.Id);
  if StopResult.Status <> gcSuccess then
  begin
    SetStatus(gcsError, 'Stop failed', StopResult.ErrorMessage);
    NotifyChatChanged;
    Exit;
  end;

  Result := True;
end;

function TMainViewModel.SendPrompt(const WorkspacePath, Prompt: string): Boolean;
var
  MessageRequest: TGatewaySendMessageRequest;
  MessageResult: TGatewaySendMessageResult;
begin
  Result := False;

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

  if not EnsureSessionConnected(FWorkspacePath) then
  begin
    NotifyChatChanged;
    Exit;
  end;

  FTranscriptText := FTranscriptText
    + 'User: ' + Prompt + sLineBreak + sLineBreak
    + 'Assistant: ';
  FRunning := True;
  SetStatus(gcsConnected, 'Chat running', 'Waiting for streamed response.');
  NotifyChatChanged;

  MessageRequest.Prompt := Prompt;
  MessageResult := FHttpClient.SendMessage(FSettings, FSession.Id, MessageRequest);
  if (MessageResult.Status <> gcSuccess) and (MessageResult.StatusCode = 404) then
  begin
    DisconnectEvents;
    ClearActiveSession;
    if EnsureSessionConnected(FWorkspacePath) then
      MessageResult := FHttpClient.SendMessage(FSettings, FSession.Id, MessageRequest);
  end;

  if MessageResult.Status <> gcSuccess then
  begin
    FRunning := False;
    SetStatus(gcsError, 'Prompt send failed', MessageResult.ErrorMessage);
    NotifyChatChanged;
    Exit;
  end;

  Result := True;
end;

procedure TMainViewModel.DisconnectEvents;
begin
  FEventsClient.Disconnect;
end;

procedure TMainViewModel.ClearActiveSession;
begin
  FSession.Id := '';
  FSession.SdkSessionId := '';
  FSession.WorkspacePath := '';
  FSession.Status := '';
  FResumeSdkSessionId := '';
end;

function TMainViewModel.ConnectEventsForSession(const SessionId: string): Boolean;
begin
  Result := False;
  if SessionId = '' then
    Exit;

  FEventsClient.Connect(FSettings, SessionId, HandleGatewayEvent, HandleGatewayError);
  if FEventsClient.WaitForConnected(2000) then
    Exit(True);

  SetStatus(gcsDisconnected, 'Gateway event stream unavailable', 'Could not connect the WebSocket event stream.');
end;

function TMainViewModel.EnsureSessionConnected(const WorkspacePath: string): Boolean;
var
  CreateRequest: TGatewayCreateSessionRequest;
  CreateResult: TGatewayCreateSessionResult;
begin
  Result := False;

  if (FSession.Id <> '') and SameText(FSession.WorkspacePath, WorkspacePath) then
  begin
    if FEventsClient.Connected then
      Exit(True);

    Result := ConnectEventsForSession(FSession.Id);
    Exit;
  end;

  CreateRequest.WorkspacePath := WorkspacePath;
  CreateRequest.PermissionPreset := 'default';
  if FResumeSdkSessionId <> '' then
    CreateRequest.ResumeSessionId := FResumeSdkSessionId;
  CreateResult := FHttpClient.CreateSession(FSettings, CreateRequest);
  if CreateResult.Status <> gcSuccess then
  begin
    SetStatus(gcsError, 'Session creation failed', CreateResult.ErrorMessage);
    Exit;
  end;

  FSession := CreateResult.Session;
  FResumeSdkSessionId := '';
  Result := ConnectEventsForSession(FSession.Id);
  if Result then
    LoadRecentSessions;
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

function TMainViewModel.CanStop: Boolean;
begin
  Result := FRunning and (FSession.Id <> '');
end;

function TMainViewModel.CanRestore: Boolean;
begin
  Result := (not FRunning)
    and (FSelectedSessionIndex >= 0)
    and (FSelectedSessionIndex < Length(FRecentSessions))
    and (FStatus = gcsConnected);
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
    if Event.Text <> '' then
      FTranscriptText := FTranscriptText + Event.Text;
    FTranscriptText := FTranscriptText + sLineBreak + sLineBreak;
    SetStatus(gcsConnected, 'Chat complete', 'Ready for the next prompt.');
    LoadRecentSessions;
    NotifyChatChanged;
    Exit;
  end;

  if Event.EventType = 'run_stopped' then
  begin
    FRunning := False;
    if Event.ErrorMessage <> '' then
      FTranscriptText := FTranscriptText + sLineBreak + Event.ErrorMessage + sLineBreak
    else
      FTranscriptText := FTranscriptText + sLineBreak + '[Task stopped]' + sLineBreak;
    FTranscriptText := FTranscriptText + sLineBreak;
    SetStatus(gcsConnected, 'Chat stopped', 'Task was cancelled. Ready for the next prompt.');
    LoadRecentSessions;
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
    LoadRecentSessions;
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
