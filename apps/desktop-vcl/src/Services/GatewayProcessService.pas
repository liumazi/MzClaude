unit GatewayProcessService;

interface

uses
  AppSettings;

type
  TGatewayProcessState = (
    gpsExternal,
    gpsUnavailable,
    gpsExitedUnexpectedly
  );

  TGatewayProcessService = class
  private
    FState: TGatewayProcessState;
    FLastError: string;
  public
    constructor Create;
    procedure UseExternalGateway(const Settings: TGatewaySettings);
    procedure MarkUnavailable(const ErrorMessage: string);
    procedure MarkExitedUnexpectedly(const ErrorMessage: string);

    property State: TGatewayProcessState read FState;
    property LastError: string read FLastError;
  end;

implementation

constructor TGatewayProcessService.Create;
begin
  inherited Create;
  FState := gpsExternal;
  FLastError := '';
end;

procedure TGatewayProcessService.UseExternalGateway(const Settings: TGatewaySettings);
begin
  FState := gpsExternal;
  FLastError := '';
end;

procedure TGatewayProcessService.MarkUnavailable(const ErrorMessage: string);
begin
  FState := gpsUnavailable;
  FLastError := ErrorMessage;
end;

procedure TGatewayProcessService.MarkExitedUnexpectedly(const ErrorMessage: string);
begin
  FState := gpsExitedUnexpectedly;
  FLastError := ErrorMessage;
end;

end.
