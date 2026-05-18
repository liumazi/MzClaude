program MzClaude;

uses
  Vcl.Forms,
  AppBootstrap in 'src\App\AppBootstrap.pas',
  MainForm in 'src\UI\MainForm.pas' {MzClaudeMainForm},
  GatewayProtocol in 'src\Protocol\GatewayProtocol.pas',
  AppSettings in 'src\Services\AppSettings.pas',
  WinHttpWebSocket in 'src\Services\WinHttpWebSocket.pas',
  GatewayEventsClient in 'src\Services\GatewayEventsClient.pas',
  GatewayHttpClient in 'src\Services\GatewayHttpClient.pas',
  GatewayProcessService in 'src\Services\GatewayProcessService.pas',
  ApprovalDialog in 'src\UI\ApprovalDialog.pas',
  QuestionDialog in 'src\UI\QuestionDialog.pas',
  MainViewModel in 'src\ViewModels\MainViewModel.pas';

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'MzClaude';
  Application.CreateForm(TMzClaudeMainForm, MzClaudeMainForm);
  Application.Run;
end.
