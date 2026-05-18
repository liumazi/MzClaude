unit AppBootstrap;

interface

uses
  AppSettings,
  GatewayEventsClient,
  GatewayHttpClient,
  GatewayProcessService;

type
  TMzClaudeAppServices = class
  private
    FSettingsService: TAppSettingsService;
    FEventsClient: TGatewayEventsClient;
    FHttpClient: TGatewayHttpClient;
    FProcessService: TGatewayProcessService;
  public
    constructor Create;
    destructor Destroy; override;

    property SettingsService: TAppSettingsService read FSettingsService;
    property EventsClient: TGatewayEventsClient read FEventsClient;
    property HttpClient: TGatewayHttpClient read FHttpClient;
    property ProcessService: TGatewayProcessService read FProcessService;
  end;

implementation

constructor TMzClaudeAppServices.Create;
begin
  inherited Create;
  FSettingsService := TAppSettingsService.Create;
  FEventsClient := TGatewayEventsClient.Create;
  FHttpClient := TGatewayHttpClient.Create;
  FProcessService := TGatewayProcessService.Create;
end;

destructor TMzClaudeAppServices.Destroy;
begin
  FProcessService.Free;
  FHttpClient.Free;
  FEventsClient.Free;
  FSettingsService.Free;
  inherited;
end;

end.
