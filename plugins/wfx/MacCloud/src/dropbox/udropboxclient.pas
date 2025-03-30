{
   Notes:
   1. the most basic DropBox Client
   2. no dependencies on other libraries
}

unit uDropBoxClient;

{$mode ObjFPC}{$H+}
{$modeswitch objectivec2}

interface

uses
  Classes, SysUtils, Generics.Collections, DateUtils,
  CocoaAll, uMiniCocoa,
  uMiniHttpClient, uMiniUtil;

type

  { TDropBoxResult }

  TDropBoxResult = class
  public
    httpResult: TMiniHttpResult;
    resultMessage: String;
  end;

  { EDropBoxException }

  EDropBoxException = class( Exception );
  EDropBoxTokenException = class( EDropBoxException );
  EDropBoxConflictException = class( EDropBoxException );
  EDropBoxPermissionException = class( EDropBoxException );
  EDropBoxRateLimitException = class( EDropBoxException );

  { TDropBoxFile }

  TDropBoxFile = class
  private
    _dotTag: String;
    _name: String;
    _size: QWord;
    _clientModified: TDateTime;
    _serverModified: TDateTime;
  public
    function isFolder: Boolean;
  public
    property dotTag: String read _dotTag write _dotTag;
    property name: String read _name write _name;
    property size: QWord read _size write _size;
    property clientModified: TDateTime read _clientModified write _clientModified;
    property serverModified: TDateTime read _serverModified write _serverModified;
  end;

  TDropBoxFiles = specialize TList<TDropBoxFile>;

  IDropBoxProgressCallback = IMiniHttpDataCallback;

  { TDropBoxConfig }

  TDropBoxConfig = class
  private
    _clientID: String;
    _listenURI: String;
  public
    constructor Create( const clientID: String; const listenURI: String );
    property clientID: String read _clientID;
    property listenURI: String read _listenURI;
  end;

  { TDropBoxToken }

  TDropBoxToken = class
  private
    _access: String;
    _refresh: String;
    _accessExpirationTime: NSTimeInterval;
  private
    function isValidAccessToken: Boolean;
    function isValidFreshToken: Boolean;
  public
    procedure setExpiration( const seconds: Integer );
    procedure invalid;
    property access: String read _access write _access;
    property refresh: String read _refresh write _refresh;
  end;

  { TDropBoxAuthPKCESession }

  TDropBoxAuthPKCESession = class
  private
    _config: TDropBoxConfig;
    _codeVerifier: String;
    _state: String;
    _code: String;
    _token: TDropBoxToken;
    _accountID: String;
    _alert: NSAlert;
  private
    procedure requestAuthorization;
    procedure waitAuthorizationAndPrompt;
    procedure closePrompt;
    procedure requestToken;
    procedure refreshToken;
    procedure onRedirect( const url: NSURL );
    function getAccessToken: String;
  public
    constructor Create( const config: TDropBoxConfig );
    destructor Destroy; override;
  public
    function authorize: Boolean;
    procedure setAuthHeader( http: TMiniHttpClient );
  end;

  { TDropBoxListFolderSession }

  TDropBoxListFolderSession = class
  private
    _authSession: TDropBoxAuthPKCESession;
    _path: String;
    _files: TDropBoxFiles;
    _cursor: String;
    _hasMore: Boolean;
  private
    procedure listFolderFirst;
    procedure listFolderContinue;
    procedure analyseListResult( const jsonString: String );
  public
    constructor Create( const authSession: TDropBoxAuthPKCESession; const path: String );
    destructor Destroy; override;
    function getNextFile: TDropBoxFile;
  end;

  { TDropBoxDownloadSession }

  TDropBoxDownloadSession = class
  private
    _authSession: TDropBoxAuthPKCESession;
    _serverPath: String;
    _localPath: String;
    _callback: IDropBoxProgressCallback;
  public
    constructor Create(
      const authSession: TDropBoxAuthPKCESession;
      const serverPath: String;
      const localPath: String;
      const callback: IDropBoxProgressCallback );
    procedure download;
  end;

  { TDropBoxUploadSession }

  TDropBoxUploadSession = class
  private
    _authSession: TDropBoxAuthPKCESession;
    _serverPath: String;
    _localPath: String;
    _callback: IDropBoxProgressCallback;
  public
    constructor Create(
      const authSession: TDropBoxAuthPKCESession;
      const serverPath: String;
      const localPath: String;
      const callback: IDropBoxProgressCallback );
    procedure upload;
  end;

  { TDropBoxCreateFolderSession }

  TDropBoxCreateFolderSession = class
  private
    _authSession: TDropBoxAuthPKCESession;
    _path: String;
  public
    constructor Create( const authSession: TDropBoxAuthPKCESession; const path: String );
    procedure createFolder;
  end;

  { TDropBoxDeleteSession }

  TDropBoxDeleteSession = class
  private
    _authSession: TDropBoxAuthPKCESession;
    _path: String;
  public
    constructor Create( const authSession: TDropBoxAuthPKCESession; const path: String );
    procedure delete;
  end;

  { TDropBoxCopyMoveSession }

  TDropBoxCopyMoveSession = class
  private
    _authSession: TDropBoxAuthPKCESession;
    _fromPath: String;
    _toPath: String;
  public
    constructor Create( const authSession: TDropBoxAuthPKCESession;
      const fromPath: String; const toPath: String );
    procedure copyOrMove( const needToMove: Boolean );
    procedure copy;
    procedure move;
  end;

  { TDropBoxClient }

  TDropBoxClient = class
  private
    _config: TDropBoxConfig;
    _authSession: TDropBoxAuthPKCESession;
    _listFolderSession: TDropBoxListFolderSession;
  public
    constructor Create( const config: TDropBoxConfig );
    destructor Destroy; override;
  public
    function authorize: Boolean;
  public
    procedure listFolderBegin( const path: String );
    function  listFolderGetNextFile: TDropBoxFile;
    procedure listFolderEnd;
  public
    procedure download(
      const serverPath: String;
      const localPath: String;
      const callback: IDropBoxProgressCallback );
    procedure upload(
      const serverPath: String;
      const localPath: String;
      const callback: IDropBoxProgressCallback );
  public
    procedure createFolder( const path: String );
    procedure delete(  const path: String );
    procedure copyOrMove( const fromPath: String; const toPath: String; const needToMove: Boolean );
  end;

implementation

type
  TDropBoxConstURI = record
    OAUTH2: String;
    TOKEN: String;
    LIST_FOLDER: String;
    LIST_FOLDER_CONTINUE: String;
    DOWNLOAD: String;
    UPLOAD_SMALL: String;
    CREATE_FOLDER: String;
    DELETE: String;
    COPY: String;
    MOVE: String;
  end;

  TDropBoxConstHeader = record
    AUTH: String;
    ARG: String;
    RESULT: String;
  end;

  TDropBoxConst = record
    URI: TDropBoxConstURI;
    HEADER: TDropBoxConstHeader;
  end;

const
  DropBoxConst: TDropBoxConst = (
    URI: (
      OAUTH2: 'https://www.dropbox.com/oauth2/authorize';
      TOKEN: 'https://api.dropbox.com/oauth2/token';
      LIST_FOLDER:  'https://api.dropboxapi.com/2/files/list_folder';
      LIST_FOLDER_CONTINUE: 'https://api.dropboxapi.com/2/files/list_folder/continue';
      DOWNLOAD: 'https://content.dropboxapi.com/2/files/download';
      UPLOAD_SMALL: 'https://content.dropboxapi.com/2/files/upload';
      CREATE_FOLDER: 'https://api.dropboxapi.com/2/files/create_folder_v2';
      DELETE: 'https://api.dropboxapi.com/2/files/delete_v2';
      COPY: 'https://api.dropboxapi.com/2/files/copy_v2';
      MOVE: 'https://api.dropboxapi.com/2/files/move_v2';
    );
    HEADER: (
      AUTH: 'Authorization';
      ARG: 'Dropbox-API-Arg';
      RESULT: 'Dropbox-API-Result';
    );
  );

// raise the corresponding exception if there are errors
procedure DropBoxClientProcessResult( const dropBoxResult: TDropBoxResult );
var
  httpResult: TMiniHttpResult;
  httpError: NSError;
  httpErrorDescription: String;
  dropBoxMessage: String;

  procedure processHttpError;
  begin
    httpResult:= dropBoxResult.httpResult;
    httpError:= httpResult.error;

    if Assigned(httpError) then begin
      httpErrorDescription:= httpError.localizedDescription.UTF8String;
      case httpError.code of
        2: raise EFileNotFoundException.Create( httpErrorDescription );
        -1001: raise EInOutError.Create( httpErrorDescription );
      end;
    end;
  end;

  procedure processDropBox401Error;
  begin
    if dropBoxMessage.IndexOf('access_token') >= 0 then
      raise EDropBoxTokenException.Create( dropBoxMessage );
    raise EDropBoxException.Create( dropBoxMessage );
  end;

  procedure processDropBox409Error;
  begin
    if dropBoxMessage.IndexOf('not_found') >= 0 then
      raise EFileNotFoundException.Create( dropBoxMessage );
    if dropBoxMessage.IndexOf('conflict') >= 0 then
      raise EDropBoxConflictException.Create( dropBoxMessage );
    raise EDropBoxPermissionException.Create( dropBoxMessage );
  end;

  procedure processDropBoxError;
  begin
    dropBoxMessage:= dropBoxResult.resultMessage;

    if (httpResult.resultCode>=200) and (httpResult.resultCode<=299) then
      Exit;
    case httpResult.resultCode of
      401: processDropBox401Error;
      409: processDropBox409Error;
      403: raise EDropBoxPermissionException.Create( dropBoxMessage );
      429: raise EDropBoxRateLimitException.Create( dropBoxMessage );
      else raise EDropBoxException.Create( dropBoxMessage );
    end;
  end;

  procedure logException( const e: Exception );
  var
    message: String;
  begin
    message:= 'DropBox Error';
    if e.Message <> EmptyStr then
      message:= message + ': ' + e.Message;
    TLogUtil.log( 6, message );
  end;

begin
  try
    processHttpError;
    processDropBoxError;
  except
    on e: Exception do begin
      logException( e );
      raise;
    end;
  end;
end;

{ TDropBoxFile }

function TDropBoxFile.isFolder: Boolean;
begin
  Result:= _dotTag = 'folder';
end;

{ TDropBoxConfig }

constructor TDropBoxConfig.Create( const clientID: String; const listenURI: String );
begin
  _clientID:= clientID;
  _listenURI:= listenURI;
end;

{ TDropBoxToken }

function TDropBoxToken.isValidAccessToken: Boolean;
var
  now: NSDate;
begin
  Result:= False;
  if _access = EmptyStr then
    Exit;
  now:= NSDate.new;
  if now.timeIntervalSince1970 < _accessExpirationTime then
    Result:= True;
  now.release;
end;

function TDropBoxToken.isValidFreshToken: Boolean;
begin
  Result:= _refresh <> EmptyStr;
end;

procedure TDropBoxToken.setExpiration(const seconds: Integer);
var
  now: NSDate;
  expirationDate: NSDate;
begin
  now:= NSDate.new;
  expirationDate:= now.dateByAddingTimeInterval( seconds - 300 );
  _accessExpirationTime:= expirationDate.timeIntervalSince1970;
  now.release;
end;

procedure TDropBoxToken.invalid;
begin
  _access:= EmptyStr;
  _refresh:= EmptyStr;
end;

{ TDropBoxAuthPKCESession }

procedure TDropBoxAuthPKCESession.requestAuthorization;
var
  queryItems: TQueryItemsDictonary;
  codeChallenge: String;
begin
  _codeVerifier:= TStringUtil.generateRandomString( 43 );
  _state:= TStringUtil.generateRandomString( 10 );
  codeChallenge:= THashUtil.sha256AndBase64( _codeVerifier ) ;

  queryItems:= TQueryItemsDictonary.Create;
  queryItems.Add( 'client_id', _config.clientID );
  queryItems.Add( 'redirect_uri', _config.listenURI );
  queryItems.Add( 'code_challenge', codeChallenge );
  queryItems.Add( 'code_challenge_method', 'S256' );
  queryItems.Add( 'response_type', 'code' );
  queryItems.Add( 'token_access_type', 'offline' );
  queryItems.Add( 'state', _state );
  THttpClientUtil.openInSafari( DropBoxConst.URI.OAUTH2, queryItems );
end;

procedure TDropBoxAuthPKCESession.waitAuthorizationAndPrompt;
begin
  NSApplication(NSAPP).setOpenURLObserver( @self.onRedirect );
  _alert:= NSAlert.new;
  _alert.setMessageText( StringToNSString('Waiting for DropBox authorization') );
  _alert.setInformativeText( StringToNSString('Please login your DropBox account in Safari and authorize Double Commander to access. '#13'The authorization is completed on the DropBox official website, Double Command will not get your password.') );
  _alert.addButtonWithTitle( NSSTR('Cancel') );
  _alert.runModal;
  NSApplication(NSAPP).setOpenURLObserver( nil );
  _alert.release;
  _alert:= nil;
end;

procedure TDropBoxAuthPKCESession.closePrompt;
var
  button: NSButton;
begin
  if _alert = nil then
    Exit;

  button:= NSButton( _alert.buttons.objectAtIndex(0) );
  button.performClick( nil );
end;

procedure TDropBoxAuthPKCESession.requestToken;
var
  http: TMiniHttpClient;
  dropBoxResult: TDropBoxResult;

  procedure doRequest;
  var
    queryItems: TQueryItemsDictonary;
  begin
    queryItems:= TQueryItemsDictonary.Create;
    queryItems.Add( 'client_id', _config.clientID );
    queryItems.Add( 'redirect_uri', _config.listenURI );
    queryItems.Add( 'code', _code );
    queryItems.Add( 'code_verifier', _codeVerifier );
    queryItems.Add( 'grant_type', 'authorization_code' );
    dropBoxResult:= TDropBoxResult.Create;
    dropBoxResult.httpResult:= http.post( DropBoxConst.URI.TOKEN, queryItems );
    dropBoxResult.resultMessage:= dropBoxResult.httpResult.body;

    DropBoxClientProcessResult( dropBoxResult );
  end;

  procedure analyseResult;
  var
    json: NSDictionary;
  begin
    json:= TJsonUtil.parse( dropBoxResult.httpResult.body );
    _token.access:= TJsonUtil.getString( json, 'access_token' );
    _token.refresh:= TJsonUtil.getString( json, 'refresh_token' );
    _token.setExpiration( TJsonUtil.getInteger( json, 'expires_in' ) );
    _accountID:= TJsonUtil.getString( json, 'account_id' );
  end;

begin
  if _code = EmptyStr then
    Exit;

  try
    http:= TMiniHttpClient.Create;
    doRequest;

    if dropBoxResult.httpResult.resultCode <> 200 then
      Exit;
    analyseResult;
  finally
    FreeAndNil( dropBoxResult );
    FreeAndNil( http );
  end;
end;

procedure TDropBoxAuthPKCESession.refreshToken;
var
  http: TMiniHttpClient;
  dropBoxResult: TDropBoxResult;

  procedure doRequest;
  var
    queryItems: TQueryItemsDictonary;
  begin
    queryItems:= TQueryItemsDictonary.Create;
    queryItems.Add( 'client_id', _config.clientID );
    queryItems.Add( 'grant_type', 'refresh_token' );
    queryItems.Add( 'refresh_token', _token.refresh );
    dropBoxResult:= TDropBoxResult.Create;
    dropBoxResult.httpResult:= http.post( DropBoxConst.URI.TOKEN, queryItems );
    dropBoxResult.resultMessage:= dropBoxResult.httpResult.body;

    DropBoxClientProcessResult( dropBoxResult );
  end;

  procedure analyseResult;
  var
    json: NSDictionary;
  begin
    json:= TJsonUtil.parse( dropBoxResult.httpResult.body );
    _token.access:= TJsonUtil.getString( json, 'access_token' );
    _token.setExpiration( TJsonUtil.getInteger( json, 'expires_in' ) );
  end;

begin
  try
    http:= TMiniHttpClient.Create;
    doRequest;

    if dropBoxResult.httpResult.resultCode <> 200 then
      Exit;
    analyseResult;
  finally
    FreeAndNil( dropBoxResult );
    FreeAndNil( http );
  end;
end;

procedure TDropBoxAuthPKCESession.onRedirect(const url: NSURL);
var
  components: NSURLComponents;
  state: String;
begin
  components:= NSURLComponents.componentsWithURL_resolvingAgainstBaseURL( url, False );
  state:= THttpClientUtil.queryValue( components, 'state' );
  if state <> _state then
    Exit;
  _code:= THttpClientUtil.queryValue( components, 'code' );
  closePrompt;
end;

function TDropBoxAuthPKCESession.getAccessToken: String;
begin
  try
    if NOT _token.isValidAccessToken then begin
      if _token.isValidFreshToken then begin
        self.refreshToken;
      end else begin
        self.authorize;
      end;
    end;
  except
    on e: EDropBoxTokenException do begin
      TLogUtil.log( 6, 'Token Error: ' + e.ClassName + ': ' + e.Message );
      _token.invalid;
      self.authorize;
    end;
  end;
  Result:= _token.access;
end;

constructor TDropBoxAuthPKCESession.Create(const config: TDropBoxConfig);
begin
  _config:= config;
  _token:= TDropBoxToken.Create;
end;

destructor TDropBoxAuthPKCESession.Destroy;
begin
  FreeAndNil( _token );
end;

function TDropBoxAuthPKCESession.authorize: Boolean;
begin
  requestAuthorization;
  TThread.Synchronize( TThread.CurrentThread, @waitAuthorizationAndPrompt );
  requestToken;
  Result:= (_token.access <> EmptyStr);
end;

procedure TDropBoxAuthPKCESession.setAuthHeader(http: TMiniHttpClient);
var
  access: String;
begin
  access:= self.getAccessToken;
  http.addHeader( DropBoxConst.HEADER.AUTH, 'Bearer ' + access );
end;

{ TDropBoxListFolderSession }

procedure TDropBoxListFolderSession.listFolderFirst;
var
  http: TMiniHttpClient;
  httpResult: TMiniHttpResult;
  dropBoxResult: TDropBoxResult;
  body: String;
begin
  try
    body:= TJsonUtil.dumps( ['path', _path] );
    http:= TMiniHttpClient.Create;
    _authSession.setAuthHeader( http );
    http.setContentType( HttpConst.ContentType.JSON );
    http.setBody( body );

    dropBoxResult:= TDropBoxResult.Create;
    httpResult:= http.post( DropBoxConst.URI.LIST_FOLDER, nil );
    dropBoxResult.httpResult:= httpResult;
    dropBoxResult.resultMessage:= httpResult.body;

    if Assigned(_files) then
      _files.Free;
    _files:= TDropBoxFiles.Create;
    if httpResult.resultCode = 200 then
      analyseListResult( httpResult.body );

    DropBoxClientProcessResult( dropBoxResult );
  finally
    FreeAndNil( dropBoxResult );
    FreeAndNil( http );
  end;
end;

procedure TDropBoxListFolderSession.listFolderContinue;
var
  http: TMiniHttpClient;
  httpResult: TMiniHttpResult;
  dropBoxResult: TDropBoxResult;
  body: String;
begin
  try
    body:= TJsonUtil.dumps( ['cursor', _cursor] );
    http:= TMiniHttpClient.Create;
    _authSession.setAuthHeader( http );
    http.setContentType( HttpConst.ContentType.JSON );
    http.setBody( body );

    dropBoxResult:= TDropBoxResult.Create;
    httpResult:= http.post( DropBoxConst.URI.LIST_FOLDER_CONTINUE, nil );
    dropBoxResult.httpResult:= httpResult;
    dropBoxResult.resultMessage:= httpResult.body;

    if httpResult.resultCode = 200 then
      analyseListResult( httpResult.body );

    DropBoxClientProcessResult( dropBoxResult );
  finally
    FreeAndNil( dropBoxResult );
    FreeAndNil( http );
  end;
end;

procedure TDropBoxListFolderSession.analyseListResult(const jsonString: String);
var
  json: NSDictionary;
  jsonEntries: NSArray;
  jsonItem: NSDictionary;
  dbFile: TDropBoxFile;

  function toDateTime( const key: String ): TDateTime;
  var
    str: String;
  begin
    str:= TJsonUtil.getString( json, key );
    if str = EmptyStr then
      Result:= 0
    else
      Result:= ISO8601ToDate( str );
  end;

begin
  json:= TJsonUtil.parse( jsonString );
  _cursor:= TJsonUtil.getString( json, 'cursor' );
  _hasMore:= TJsonUtil.getBoolean( json, 'has_more' );
  jsonEntries:= TJsonUtil.getArray( json, 'entries' );
  if jsonEntries = nil then
    Exit;
  for jsonItem in jsonEntries do begin
    dbFile:= TDropBoxFile.Create;
    dbFile.dotTag:= TJsonUtil.getString( jsonItem, '.tag' );
    dbFile.name:= TJsonUtil.getString( jsonItem, 'name' );
    dbFile.size:= TJsonUtil.getInteger( jsonItem, 'size' );
    dbFile.clientModified:= toDateTime( 'client_modified' );
    dbFile.serverModified:= toDateTime( 'server_modified' );
    _files.Add( dbFile );
  end;
end;

constructor TDropBoxListFolderSession.Create( const authSession: TDropBoxAuthPKCESession; const path: String );
begin
  _authSession:= authSession;
  if path <> '/' then
    _path:= path;
end;

destructor TDropBoxListFolderSession.Destroy;
begin
  FreeAndNil( _files );
end;

function TDropBoxListFolderSession.getNextFile: TDropBoxFile;
  function popFirst: TDropBoxFile;
  begin
    if _files.Count > 0 then begin
      Result:= _files.First;
      _files.Delete( 0 );
    end else begin
      Result:= nil;
    end;
  end;

begin
  Result:= popFirst;
  if (Result=nil) and _hasMore then begin
    listFolderContinue;
    Result:= popFirst;
  end;
end;

{ TDropBoxDownloadSession }

constructor TDropBoxDownloadSession.Create(
  const authSession: TDropBoxAuthPKCESession;
  const serverPath: String;
  const localPath: String;
  const callback: IDropBoxProgressCallback );
begin
  _authSession:= authSession;
  _serverPath:= serverPath;
  _localPath:= localPath;
  _callback:= callback;
end;

procedure TDropBoxDownloadSession.download;
var
  http: TMiniHttpClient;
  argJsonString: String;
  dropBoxResult: TDropBoxResult;
begin
  try
    argJsonString:= TJsonUtil.dumps( ['path', _serverPath], True );
    http:= TMiniHttpClient.Create;
    _authSession.setAuthHeader( http );
    http.addHeader( DropBoxConst.HEADER.ARG, argJsonString );

    dropBoxResult:= TDropBoxResult.Create;
    dropBoxResult.httpResult:= http.download( DropBoxConst.URI.DOWNLOAD, _localPath, _callback );
    dropBoxResult.resultMessage:= dropBoxResult.httpResult.getHeader( DropBoxConst.HEADER.RESULT );

    DropBoxClientProcessResult( dropBoxResult );
  finally
    FreeAndNil( dropBoxResult );
    FreeAndNil( http );
  end;
end;

{ TDropBoxUploadSession }

constructor TDropBoxUploadSession.Create(
  const authSession: TDropBoxAuthPKCESession; const serverPath: String;
  const localPath: String; const callback: IDropBoxProgressCallback);
begin
  _authSession:= authSession;
  _serverPath:= serverPath;
  _localPath:= localPath;
  _callback:= callback;
end;

procedure TDropBoxUploadSession.upload;
var
  http: TMiniHttpClient;
  argJsonString: String;
  dropBoxResult: TDropBoxResult;
begin
  try
    argJsonString:= TJsonUtil.dumps( ['path', _serverPath], True );
    http:= TMiniHttpClient.Create;
    _authSession.setAuthHeader( http );
    http.addHeader( DropBoxConst.HEADER.ARG, argJsonString );

    dropBoxResult:= TDropBoxResult.Create;
    dropBoxResult.httpResult:= http.upload( DropBoxConst.URI.UPLOAD_SMALL, _localPath, _callback );
    dropBoxResult.resultMessage:= dropBoxResult.httpResult.getHeader( DropBoxConst.HEADER.RESULT );

    DropBoxClientProcessResult( dropBoxResult );
  finally
    FreeAndNil( dropBoxResult );
    FreeAndNil( http );
  end;
end;

{ TDropBoxCreateFolderSession }

constructor TDropBoxCreateFolderSession.Create(
  const authSession: TDropBoxAuthPKCESession; const path: String );
begin
  _authSession:= authSession;
  _path:= path;
end;

procedure TDropBoxCreateFolderSession.createFolder;
var
  http: TMiniHttpClient;
  dropBoxResult: TDropBoxResult;
  body: String;
begin
  try
    body:= TJsonUtil.dumps( ['path', _path] );
    http:= TMiniHttpClient.Create;
    http.setContentType( HttpConst.ContentType.JSON );
    _authSession.setAuthHeader( http );
    http.setBody( body );

    dropBoxResult:= TDropBoxResult.Create;
    dropBoxResult.httpResult:= http.post( DropBoxConst.URI.CREATE_FOLDER, nil );
    dropBoxResult.resultMessage:= dropBoxResult.httpResult.body;

    DropBoxClientProcessResult( dropBoxResult );
  finally
    FreeAndNil( dropBoxResult );
    FreeAndNil( http );
  end;
end;

{ TDropBoxDeleteSession }

constructor TDropBoxDeleteSession.Create(
  const authSession: TDropBoxAuthPKCESession; const path: String);
begin
  _authSession:= authSession;
  _path:= path;
end;

procedure TDropBoxDeleteSession.delete;
var
  http: TMiniHttpClient;
  body: String;
  dropBoxResult: TDropBoxResult;
begin
  try
    body:= TJsonUtil.dumps( ['path', _path] );
    http:= TMiniHttpClient.Create;
    http.setContentType( HttpConst.ContentType.JSON );
    _authSession.setAuthHeader( http );
    http.setBody( body );

    dropBoxResult:= TDropBoxResult.Create;
    dropBoxResult.httpResult:= http.post( DropBoxConst.URI.DELETE, nil );
    dropBoxResult.resultMessage:= dropBoxResult.httpResult.body;

    DropBoxClientProcessResult( dropBoxResult );
  finally
    FreeAndNil( dropBoxResult );
    FreeAndNil( http );
  end;
end;

{ TDropBoxCopyMoveSession }

constructor TDropBoxCopyMoveSession.Create( const authSession: TDropBoxAuthPKCESession;
  const fromPath: String; const toPath: String );
begin
  _authSession:= authSession;
  _fromPath:= fromPath;
  _toPath:= toPath;
end;

procedure TDropBoxCopyMoveSession.copyOrMove( const needToMove: Boolean );
var
  uri: String;
  http: TMiniHttpClient;
  dropBoxResult: TDropBoxResult;
  body: String;
begin
  try
    http:= TMiniHttpClient.Create;
    http.setContentType( HttpConst.ContentType.JSON );
    _authSession.setAuthHeader( http );

    body:= TJsonUtil.dumps( ['from_path', _fromPath, 'to_path', _toPath] );
    http.setBody( body );

    if needToMove then
      uri:= DropBoxConst.URI.MOVE
    else
      uri:= DropBoxConst.URI.COPY;

    dropBoxResult:= TDropBoxResult.Create;
    dropBoxResult.httpResult:= http.post( uri, nil );
    dropBoxResult.resultMessage:= dropBoxResult.httpResult.body;

    DropBoxClientProcessResult( dropBoxResult );
  finally
    FreeAndNil( dropBoxResult );
    FreeAndNil( http );
  end;
end;

procedure TDropBoxCopyMoveSession.copy;
begin
  copyOrMove( False );
end;

procedure TDropBoxCopyMoveSession.move;
begin
  copyOrMove( True );
end;

{ TDropBoxClient }

constructor TDropBoxClient.Create(const config: TDropBoxConfig);
begin
  _config:= config;
  _authSession:= TDropBoxAuthPKCESession.Create( _config );
end;

destructor TDropBoxClient.Destroy;
begin
  FreeAndNil( _config );
  FreeAndNil( _authSession );
  FreeAndNil( _listFolderSession );
end;

function TDropBoxClient.authorize: Boolean;
begin
  Result:= _authSession.authorize;
end;

procedure TDropBoxClient.listFolderBegin(const path: String);
begin
  if Assigned(_listFolderSession) then
    _listFolderSession.Free;
  _listFolderSession:= TDropBoxListFolderSession.Create( _authSession, path );
  _listFolderSession.listFolderFirst;
end;

function TDropBoxClient.listFolderGetNextFile: TDropBoxFile;
begin
  Result:= _listFolderSession.getNextFile;
end;

procedure TDropBoxClient.listFolderEnd;
begin
  FreeAndNil( _listFolderSession );
end;

procedure TDropBoxClient.download(
  const serverPath: String;
  const localPath: String;
  const callback: IDropBoxProgressCallback );
var
  session: TDropBoxDownloadSession;
begin
  try
    session:= TDropBoxDownloadSession.Create( _authSession, serverPath, localPath, callback );
    session.download;
  finally
    FreeAndNil( session );
  end;
end;

procedure TDropBoxClient.upload(
  const serverPath: String;
  const localPath: String;
  const callback: IDropBoxProgressCallback);
var
  session: TDropBoxUploadSession;
begin
  try
    session:= TDropBoxUploadSession.Create( _authSession, serverPath, localPath, callback );
    session.upload;
  finally
    FreeAndNil( session );
  end;
end;

procedure TDropBoxClient.createFolder(const path: String);
var
  session: TDropBoxCreateFolderSession;
begin
  try
    session:= TDropBoxCreateFolderSession.Create( _authSession, path );
    session.createFolder;
  finally
    FreeAndNil( session );
  end;
end;

procedure TDropBoxClient.delete(const path: String);
var
  session: TDropBoxDeleteSession;
begin
  try
    session:= TDropBoxDeleteSession.Create( _authSession, path );
    session.delete;
  finally
    FreeAndNil( session );
  end;
end;

procedure TDropBoxClient.copyOrMove(const fromPath: String; const toPath: String;
  const needToMove: Boolean );
var
  session: TDropBoxCopyMoveSession;
begin
  try
    session:= TDropBoxCopyMoveSession.Create( _authSession, fromPath, toPath );
    session.copyOrMove( needToMove );
  finally
    FreeAndNil( session );
  end;
end;

end.

