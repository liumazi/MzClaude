unit AppSettings;

interface

type
  TGatewaySettings = record
    Host: string;
    Port: Integer;
    AuthToken: string;
    AutoConnect: Boolean;
    function BaseUrl: string;
    function IsConfigured: Boolean;
  end;

  TAppSettingsService = class
  private
    FSettingsPath: string;
    class function DefaultSettingsPath: string; static;
  public
    constructor Create;
    function Load: TGatewaySettings;

    property SettingsPath: string read FSettingsPath;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.SysUtils;

function TGatewaySettings.BaseUrl: string;
begin
  Result := Format('http://%s:%d', [Host, Port]);
end;

function TGatewaySettings.IsConfigured: Boolean;
begin
  Result := (Host <> '') and (Port > 0) and (Port <= 65535);
end;

constructor TAppSettingsService.Create;
begin
  inherited Create;
  FSettingsPath := DefaultSettingsPath;
end;

class function TAppSettingsService.DefaultSettingsPath: string;
var
  BasePath: string;
begin
  BasePath := GetEnvironmentVariable('APPDATA');
  if BasePath = '' then
    BasePath := TPath.GetHomePath;

  Result := TPath.Combine(TPath.Combine(BasePath, 'MzClaude'), 'settings.json');
end;

function TAppSettingsService.Load: TGatewaySettings;
var
  JsonText: string;
  RootValue: TJSONValue;
  Root: TJSONObject;

  function ReadString(const Json: TJSONObject; const Name, DefaultValue: string): string;
  var
    Value: TJSONValue;
  begin
    Value := Json.GetValue(Name);
    if Value = nil then
      Exit(DefaultValue);

    Result := Value.Value;
  end;

  function ReadInteger(const Json: TJSONObject; const Name: string; DefaultValue: Integer): Integer;
  var
    Value: TJSONValue;
  begin
    Value := Json.GetValue(Name);
    if (Value = nil) or not TryStrToInt(Value.Value, Result) then
      Result := DefaultValue;
  end;

  function ReadBoolean(const Json: TJSONObject; const Name: string; DefaultValue: Boolean): Boolean;
  var
    Value: TJSONValue;
  begin
    Value := Json.GetValue(Name);
    if Value = nil then
      Exit(DefaultValue);

    if SameText(Value.Value, 'true') then
      Exit(True);
    if SameText(Value.Value, 'false') then
      Exit(False);

    Result := DefaultValue;
  end;

begin
  Result.Host := '127.0.0.1';
  Result.Port := 0;
  Result.AuthToken := '';
  Result.AutoConnect := True;

  if not TFile.Exists(FSettingsPath) then
    Exit;

  JsonText := TFile.ReadAllText(FSettingsPath, TEncoding.UTF8);
  RootValue := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (RootValue is TJSONObject) then
      raise EInvalidOperation.CreateFmt('Settings file is not a JSON object: %s', [FSettingsPath]);

    Root := TJSONObject(RootValue);
    Result.Host := ReadString(Root, 'host', Result.Host);
    Result.Port := ReadInteger(Root, 'port', Result.Port);
    Result.AuthToken := ReadString(Root, 'authToken', Result.AuthToken);
    Result.AutoConnect := ReadBoolean(Root, 'autoConnect', Result.AutoConnect);
  finally
    RootValue.Free;
  end;
end;

end.
