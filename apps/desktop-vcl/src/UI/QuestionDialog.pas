unit QuestionDialog;

interface

uses
  GatewayProtocol;

type
  TQuestionDialog = class
  public
    class function Execute(const Event: TGatewayEvent; out Answers: TArray<TGatewayQuestionAnswer>): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.Forms,
  Vcl.StdCtrls;

function PromptForQuestion(const Question: TGatewayQuestion; out Answer: string): Boolean; forward;

class function TQuestionDialog.Execute(
  const Event: TGatewayEvent;
  out Answers: TArray<TGatewayQuestionAnswer>): Boolean;
var
  I: Integer;
  SelectedAnswer: string;
begin
  Result := False;
  SetLength(Answers, Length(Event.Questions));

  for I := 0 to High(Event.Questions) do
  begin
    if not PromptForQuestion(Event.Questions[I], SelectedAnswer) then
      Exit(False);

    Answers[I].Question := Event.Questions[I].Question;
    Answers[I].Answer := SelectedAnswer;
  end;

  Result := True;
end;

function PromptForQuestion(const Question: TGatewayQuestion; out Answer: string): Boolean;
var
  Form: TForm;
  QuestionLabel: TLabel;
  OptionsList: TListBox;
  PreviewMemo: TMemo;
  OkButton: TButton;
  CancelButton: TButton;
  I: Integer;
  Values: TStringList;
begin
  Result := False;
  Answer := '';

  Form := TForm.CreateNew(nil);
  try
    Form.Caption := Question.Header;
    Form.Position := poScreenCenter;
    Form.BorderStyle := bsDialog;
    Form.ClientWidth := 520;
    Form.ClientHeight := 360;

    QuestionLabel := TLabel.Create(Form);
    QuestionLabel.Parent := Form;
    QuestionLabel.Left := 16;
    QuestionLabel.Top := 16;
    QuestionLabel.Width := 488;
    QuestionLabel.AutoSize := False;
    QuestionLabel.WordWrap := True;
    QuestionLabel.Caption := Question.Question;

    OptionsList := TListBox.Create(Form);
    OptionsList.Parent := Form;
    OptionsList.Left := 16;
    OptionsList.Top := 64;
    OptionsList.Width := 220;
    OptionsList.Height := 224;
    OptionsList.MultiSelect := Question.MultiSelect;
    for I := 0 to High(Question.Options) do
      OptionsList.Items.Add(Question.Options[I].LabelText);
    if OptionsList.Items.Count > 0 then
      OptionsList.ItemIndex := 0;

    PreviewMemo := TMemo.Create(Form);
    PreviewMemo.Parent := Form;
    PreviewMemo.Left := 248;
    PreviewMemo.Top := 64;
    PreviewMemo.Width := 256;
    PreviewMemo.Height := 224;
    PreviewMemo.ReadOnly := True;
    PreviewMemo.ScrollBars := ssVertical;
    for I := 0 to High(Question.Options) do
    begin
      PreviewMemo.Lines.Add(Question.Options[I].LabelText + ': ' + Question.Options[I].Description);
      if Question.Options[I].Preview <> '' then
        PreviewMemo.Lines.Add(Question.Options[I].Preview);
      PreviewMemo.Lines.Add('');
    end;

    OkButton := TButton.Create(Form);
    OkButton.Parent := Form;
    OkButton.Left := 328;
    OkButton.Top := 312;
    OkButton.Width := 80;
    OkButton.Caption := 'OK';
    OkButton.ModalResult := mrOk;
    OkButton.Default := True;

    CancelButton := TButton.Create(Form);
    CancelButton.Parent := Form;
    CancelButton.Left := 424;
    CancelButton.Top := 312;
    CancelButton.Width := 80;
    CancelButton.Caption := 'Cancel';
    CancelButton.ModalResult := mrCancel;
    CancelButton.Cancel := True;

    while Form.ShowModal = mrOk do
    begin
      Values := TStringList.Create;
      try
        for I := 0 to OptionsList.Items.Count - 1 do
          if (Question.MultiSelect and OptionsList.Selected[I])
            or ((not Question.MultiSelect) and (I = OptionsList.ItemIndex)) then
            Values.Add(OptionsList.Items[I]);

        if Values.Count = 0 then
        begin
          MessageDlg('Choose at least one option.', mtWarning, [mbOK], 0);
          Continue;
        end;

        Answer := Values.CommaText;
        Exit(True);
      finally
        Values.Free;
      end;
    end;
  finally
    Form.Free;
  end;
end;

end.
