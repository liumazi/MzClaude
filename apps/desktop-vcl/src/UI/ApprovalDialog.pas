unit ApprovalDialog;

interface

uses
  GatewayProtocol;

type
  TApprovalDialogDecision = (adAllow, adDeny);

  TApprovalDialog = class
  public
    class function Execute(const Event: TGatewayEvent; out Reason: string): TApprovalDialogDecision; static;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls;

class function TApprovalDialog.Execute(
  const Event: TGatewayEvent;
  out Reason: string): TApprovalDialogDecision;
var
  Form: TForm;
  TitleLabel: TLabel;
  DetailsMemo: TMemo;
  ReasonEdit: TEdit;
  AllowButton: TButton;
  DenyButton: TButton;
  PromptText: string;
begin
  Reason := 'User denied the tool request.';
  Result := adDeny;

  Form := TForm.CreateNew(nil);
  try
    Form.Caption := 'Tool approval required';
    Form.Position := poScreenCenter;
    Form.BorderStyle := bsDialog;
    Form.ClientWidth := 520;
    Form.ClientHeight := 360;

    TitleLabel := TLabel.Create(Form);
    TitleLabel.Parent := Form;
    TitleLabel.Left := 16;
    TitleLabel.Top := 16;
    TitleLabel.Width := 488;
    TitleLabel.AutoSize := False;
    TitleLabel.WordWrap := True;
    if Event.Title <> '' then
      PromptText := Event.Title
    else if Event.DisplayName <> '' then
      PromptText := Event.DisplayName
    else
      PromptText := Format('Claude wants to use %s.', [Event.ToolName]);
    TitleLabel.Caption := PromptText;

    DetailsMemo := TMemo.Create(Form);
    DetailsMemo.Parent := Form;
    DetailsMemo.Left := 16;
    DetailsMemo.Top := 56;
    DetailsMemo.Width := 488;
    DetailsMemo.Height := 216;
    DetailsMemo.ReadOnly := True;
    DetailsMemo.ScrollBars := ssVertical;
    DetailsMemo.Lines.Add('Tool: ' + Event.ToolName);
    if Event.Description <> '' then
      DetailsMemo.Lines.Add('Description: ' + Event.Description);
    if Event.ToolInputJson <> '' then
    begin
      DetailsMemo.Lines.Add('');
      DetailsMemo.Lines.Add('Input:');
      DetailsMemo.Lines.Add(Event.ToolInputJson);
    end;

    ReasonEdit := TEdit.Create(Form);
    ReasonEdit.Parent := Form;
    ReasonEdit.Left := 16;
    ReasonEdit.Top := 288;
    ReasonEdit.Width := 488;
    ReasonEdit.Text := Reason;

    AllowButton := TButton.Create(Form);
    AllowButton.Parent := Form;
    AllowButton.Left := 328;
    AllowButton.Top := 320;
    AllowButton.Width := 80;
    AllowButton.Caption := 'Allow';
    AllowButton.ModalResult := mrOk;
    AllowButton.Default := True;

    DenyButton := TButton.Create(Form);
    DenyButton.Parent := Form;
    DenyButton.Left := 424;
    DenyButton.Top := 320;
    DenyButton.Width := 80;
    DenyButton.Caption := 'Deny';
    DenyButton.ModalResult := mrNo;
    DenyButton.Cancel := True;

    if Form.ShowModal = mrOk then
      Result := adAllow
    else
    begin
      Reason := Trim(ReasonEdit.Text);
      if Reason = '' then
        Reason := 'User denied the tool request.';
      Result := adDeny;
    end;
  finally
    Form.Free;
  end;
end;

end.
