object MzClaudeMainForm: TMzClaudeMainForm
  Left = 0
  Top = 0
  Caption = 'MzClaude'
  ClientHeight = 784
  ClientWidth = 760
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object HeaderPanel: TPanel
    Left = 0
    Top = 0
    Width = 760
    Height = 224
    Align = alTop
    BevelOuter = bvNone
    Padding.Left = 16
    Padding.Top = 12
    Padding.Right = 16
    Padding.Bottom = 12
    TabOrder = 0
    object TitleLabel: TLabel
      Left = 16
      Top = 12
      Width = 88
      Height = 25
      Caption = 'MzClaude'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -19
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object GatewayLabel: TLabel
      Left = 16
      Top = 56
      Width = 48
      Height = 15
      Caption = 'Gateway:'
    end
    object GatewayValueLabel: TLabel
      Left = 88
      Top = 56
      Width = 149
      Height = 15
      Caption = 'No gateway port configured'
    end
    object StatusLabel: TLabel
      Left = 16
      Top = 84
      Width = 35
      Height = 15
      Caption = 'Status:'
    end
    object StatusValueLabel: TLabel
      Left = 88
      Top = 84
      Width = 81
      Height = 15
      Caption = 'Not configured'
    end
    object WorkspaceLabel: TLabel
      Left = 16
      Top = 120
      Width = 61
      Height = 15
      Caption = 'Workspace:'
    end
    object RefreshButton: TButton
      Left = 616
      Top = 52
      Width = 112
      Height = 32
      Caption = 'Recheck'
      TabOrder = 0
      OnClick = RefreshButtonClick
    end
    object WorkspaceEdit: TEdit
      Left = 88
      Top = 116
      Width = 408
      Height = 23
      TabOrder = 1
      Text = 'C:\Users\liuliu.mz\Desktop\MzTest6'
    end
    object BrowseButton: TButton
      Left = 504
      Top = 115
      Width = 104
      Height = 25
      Caption = 'Browse...'
      TabOrder = 2
      OnClick = BrowseButtonClick
    end
    object PromptMemo: TMemo
      Left = 88
      Top = 152
      Width = 408
      Height = 56
      Lines.Strings = (
        '')
      TabOrder = 3
    end
    object SendButton: TButton
      Left = 504
      Top = 152
      Width = 104
      Height = 32
      Caption = 'Send'
      TabOrder = 4
      OnClick = SendButtonClick
    end
    object StopButton: TButton
      Left = 616
      Top = 152
      Width = 112
      Height = 32
      Caption = 'Stop'
      TabOrder = 5
      OnClick = StopButtonClick
    end
  end
  object SessionsPanel: TPanel
    Left = 0
    Top = 224
    Width = 760
    Height = 160
    Align = alTop
    BevelOuter = bvNone
    Padding.Left = 16
    Padding.Top = 8
    Padding.Right = 16
    Padding.Bottom = 8
    TabOrder = 1
    object SessionsLabel: TLabel
      Left = 22
      Top = -1
      Width = 82
      Height = 27
      Caption = 'Recent sessions'
    end
    object SessionsListView: TListView
      Left = 18
      Top = 16
      Width = 608
      Height = 138
      Columns = <
        item
          Caption = 'Workspace'
          Width = 200
        end
        item
          Caption = 'Title'
          Width = 160
        end
        item
          Caption = 'Status'
          Width = 80
        end
        item
          Caption = 'Updated'
          Width = 140
        end
        item
          Caption = 'SDK Session'
          Width = 140
        end>
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsReport
      OnSelectItem = SessionsListViewSelectItem
    end
    object RestoreButton: TButton
      Left = 632
      Top = 32
      Width = 96
      Height = 32
      Caption = 'Restore'
      TabOrder = 1
      OnClick = RestoreButtonClick
    end
    object RefreshSessionsButton: TButton
      Left = 632
      Top = 72
      Width = 96
      Height = 32
      Caption = 'Refresh'
      TabOrder = 2
      OnClick = RefreshSessionsButtonClick
    end
  end
  object DetailsMemo: TMemo
    Left = 0
    Top = 384
    Width = 760
    Height = 377
    Align = alClient
    BorderStyle = bsNone
    Color = clBtnFace
    Lines.Strings = (
      'Gateway status details will appear here.')
    ReadOnly = True
    TabOrder = 2
    ExplicitTop = 500
    ExplicitHeight = 545
  end
  object StatusBar: TStatusBar
    Left = 0
    Top = 761
    Width = 760
    Height = 23
    Panels = <
      item
        Text = 'Not configured'
        Width = 220
      end
      item
        Text = 'No gateway port configured'
        Width = 520
      end>
    ExplicitTop = 617
  end
end
