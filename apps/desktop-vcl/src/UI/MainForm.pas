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
    DetailsMemo: TMemo;
    StatusBar: TStatusBar;
    procedure BrowseButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure RefreshButtonClick(Sender: TObject);
    procedure SendButtonClick(Sender: TObject);
  private
    FServices: TMzClaudeAppServices;
    FViewModel: TMainViewModel;
    procedure CheckGateway;
    procedure RefreshView;
    procedure ViewModelChanged(Sender: TObject);
  end;

var
  MzClaudeMainForm: TMzClaudeMainForm;

implementation

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

procedure TMzClaudeMainForm.RefreshView;
begin
  GatewayValueLabel.Caption := FViewModel.GatewayAddressText;
  StatusValueLabel.Caption := FViewModel.StatusText;
  if FViewModel.TranscriptText <> '' then
    DetailsMemo.Lines.Text := FViewModel.TranscriptText
  else
    DetailsMemo.Lines.Text := FViewModel.DetailsText;

  StatusBar.Panels[0].Text := FViewModel.StatusText;
  StatusBar.Panels[1].Text := FViewModel.GatewayAddressText;
  SendButton.Enabled := FViewModel.CanSendPrompt;
  PromptMemo.Enabled := not FViewModel.Running;
  BrowseButton.Enabled := not FViewModel.Running;
  WorkspaceEdit.Enabled := not FViewModel.Running;
end;

procedure TMzClaudeMainForm.ViewModelChanged(Sender: TObject);
begin
  RefreshView;
end;

end.
