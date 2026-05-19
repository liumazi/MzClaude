unit MainForm;

interface

uses
  Winapi.Messages,
  Winapi.Windows,
  System.Classes,
  System.SysUtils,
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.FileCtrl,
  Vcl.Forms,
  Vcl.StdCtrls,
  AppBootstrap,
  MainViewModel;

type
  TMzClaudeMainForm = class(TForm)
    HeaderPanel: TPanel;
    TitleLabel: TLabel;
    GatewayLabel: TLabel;
    GatewayValueLabel: TLabel;
    StatusLabel: TLabel;
    StatusValueLabel: TLabel;
    RefreshButton: TButton;
    WorkspaceLabel: TLabel;
    WorkspaceEdit: TEdit;
    BrowseButton: TButton;
    PromptMemo: TMemo;
    SendButton: TButton;
    StopButton: TButton;
    SessionsPanel: TPanel;
    SessionsLabel: TLabel;
    SessionsListView: TListView;
    RestoreButton: TButton;
    RefreshSessionsButton: TButton;
    DetailsMemo: TMemo;
    StatusBar: TStatusBar;
    procedure BrowseButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure RefreshButtonClick(Sender: TObject);
    procedure RefreshSessionsButtonClick(Sender: TObject);
    procedure RestoreButtonClick(Sender: TObject);
    procedure SendButtonClick(Sender: TObject);
    procedure SessionsListViewSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure StopButtonClick(Sender: TObject);
  private
    FServices: TMzClaudeAppServices;
    FViewModel: TMainViewModel;
    procedure CheckGateway;
    procedure RefreshView;
    procedure RefreshSessionsList;
    procedure ViewModelChanged(Sender: TObject);
  end;

var
  MzClaudeMainForm: TMzClaudeMainForm;

implementation

uses
  GatewayProtocol;

{$R *.dfm}

procedure TMzClaudeMainForm.FormCreate(Sender: TObject);
begin
  FServices := TMzClaudeAppServices.Create;
  FViewModel := TMainViewModel.Create(
    FServices.SettingsService,
    FServices.EventsClient,
    FServices.HttpClient,
    FServices.ProcessService);
  FViewModel.OnChatChanged := ViewModelChanged;

  FViewModel.LoadSettings;
  RefreshView;

  if FViewModel.Settings.AutoConnect then
    CheckGateway;
end;

procedure TMzClaudeMainForm.FormDestroy(Sender: TObject);
begin
  FViewModel.OnChatChanged := nil;
  FServices.EventsClient.Disconnect;
  FViewModel.Free;
  FServices.Free;
end;

procedure TMzClaudeMainForm.RefreshButtonClick(Sender: TObject);
begin
  CheckGateway;
end;

procedure TMzClaudeMainForm.RefreshSessionsButtonClick(Sender: TObject);
begin
  FViewModel.LoadRecentSessions;
  RefreshView;
end;

procedure TMzClaudeMainForm.RestoreButtonClick(Sender: TObject);
begin
  if FViewModel.RestoreSelectedSession then
  begin
    WorkspaceEdit.Text := FViewModel.WorkspacePath;
    RefreshView;
  end;
end;

procedure TMzClaudeMainForm.StopButtonClick(Sender: TObject);
begin
  FViewModel.StopRunningTask;
  RefreshView;
end;

procedure TMzClaudeMainForm.BrowseButtonClick(Sender: TObject);
var
  Directory: string;
begin
  Directory := WorkspaceEdit.Text;
  if SelectDirectory('Choose workspace', '', Directory) then
  begin
    WorkspaceEdit.Text := Directory;
    RefreshView;
  end;
end;

procedure TMzClaudeMainForm.SendButtonClick(Sender: TObject);
begin
  if FViewModel.SendPrompt(WorkspaceEdit.Text, PromptMemo.Lines.Text) then
    PromptMemo.Clear;
  RefreshView;
end;

procedure TMzClaudeMainForm.SessionsListViewSelectItem(
  Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected and (Item <> nil) then
    FViewModel.SelectSession(Item.Index);
  RefreshView;
end;

procedure TMzClaudeMainForm.CheckGateway;
begin
  RefreshButton.Enabled := False;
  try
    FViewModel.CheckGatewayHealth;
    RefreshView;
  finally
    RefreshButton.Enabled := True;
  end;
end;

procedure TMzClaudeMainForm.RefreshSessionsList;
var
  I: Integer;
  Item: TListItem;
  Session: TGatewaySessionResponse;
begin
  SessionsListView.Items.BeginUpdate;
  try
    SessionsListView.Items.Clear;
    for I := 0 to High(FViewModel.RecentSessions) do
    begin
      Session := FViewModel.RecentSessions[I];
      Item := SessionsListView.Items.Add;
      Item.Caption := Session.WorkspacePath;
      Item.SubItems.Add(Session.Status);
      Item.SubItems.Add(Session.UpdatedAt);
      if Session.SdkSessionId <> '' then
        Item.SubItems.Add(Session.SdkSessionId)
      else
        Item.SubItems.Add('-');

      if I = FViewModel.SelectedSessionIndex then
        Item.Selected := True;
    end;
  finally
    SessionsListView.Items.EndUpdate;
  end;
end;

procedure TMzClaudeMainForm.RefreshView;
begin
  GatewayValueLabel.Caption := FViewModel.GatewayAddressText;
  StatusValueLabel.Caption := FViewModel.StatusText;
  if FViewModel.TranscriptText <> '' then
    DetailsMemo.Lines.Text := FViewModel.TranscriptText
  else
    DetailsMemo.Lines.Text := FViewModel.DetailsText;

  WorkspaceEdit.Text := FViewModel.WorkspacePath;
  RefreshSessionsList;

  StatusBar.Panels[0].Text := FViewModel.StatusText;
  StatusBar.Panels[1].Text := FViewModel.GatewayAddressText;
  SendButton.Enabled := FViewModel.CanSendPrompt;
  StopButton.Enabled := FViewModel.CanStop;
  RestoreButton.Enabled := FViewModel.CanRestore;
  RefreshSessionsButton.Enabled := FViewModel.Status = gcsConnected;
  PromptMemo.Enabled := not FViewModel.Running;
  BrowseButton.Enabled := not FViewModel.Running;
  WorkspaceEdit.Enabled := not FViewModel.Running;
end;

procedure TMzClaudeMainForm.ViewModelChanged(Sender: TObject);
begin
  RefreshView;
end;

end.
