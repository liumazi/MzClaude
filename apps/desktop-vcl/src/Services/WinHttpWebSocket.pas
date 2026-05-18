unit WinHttpWebSocket;

{
  WinHTTP WebSocket API declarations missing from Delphi's Winapi.WinHttp.
  Requires Windows 8+ (winhttp.dll WebSocket exports).
}

interface

uses
  Winapi.Windows, Winapi.WinHTTP;

const
  WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET = 114;
  WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE = 0;
  WINHTTP_WEB_SOCKET_UTF8_FRAGMENT_BUFFER_TYPE = 1;
  WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE = 2;
  WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE = 3;
  WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE = 4;
  WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS = 1000;

type
  WINHTTP_WEB_SOCKET_BUFFER_TYPE = Cardinal;

function WinHttpWebSocketCompleteUpgrade(hRequest: HINTERNET; pContext: ULONG_PTR): HINTERNET; stdcall;
  external 'winhttp.dll' name 'WinHttpWebSocketCompleteUpgrade';

function WinHttpWebSocketReceive(
  hWebSocket: HINTERNET;
  pvBuffer: Pointer;
  dwBufferLength: DWORD;
  var pdwBytesRead: DWORD;
  var peBufferType: WINHTTP_WEB_SOCKET_BUFFER_TYPE): DWORD; stdcall;
  external 'winhttp.dll' name 'WinHttpWebSocketReceive';

function WinHttpWebSocketClose(
  hWebSocket: HINTERNET;
  usStatus: USHORT;
  pvReason: Pointer;
  dwReasonLength: DWORD): DWORD; stdcall;
  external 'winhttp.dll' name 'WinHttpWebSocketClose';

implementation

end.
