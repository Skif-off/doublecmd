unit uMountedFileSource;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections,
  uFileSource, uFileSourceManager,
  uFileSystemFileSource, uFileSystemMoveOperation,
  uFileSourceOperation, uFileSourceOperationTypes,
  uDCUtils;

type
  { IMountedFileSource }

  IMountedFileSource = interface(IFileSource)
    ['{47A3B4E6-5C40-A86A-E325-E4ABDC069B42}']

    procedure mount( const path: String; const mountPoint: String );
    procedure mount( const path: String );
  end;

  { TMountPoint }

  TMountPoint = class
  strict private
    _path: String;
    _point: String;
  public
    constructor Create( const path: String; const point: String );
    property path: String read _path;
    property point: String read _point;
  end;

  TMountPoints = specialize TList<TMountPoint>;

  { TMountedFileSource }

  TMountedFileSource = class(TFileSystemFileSource, IMountedFileSource)
  private
    _mountPoints: TMountPoints;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure mount( const path: String; const point: String );
    procedure mount( const path: String );
    function getDefaultPointForPath( const path: String ): String; virtual;
    function getRealPath( const path: String ): String; virtual;
  protected
    function SetCurrentWorkingDirectory(NewDir: String): Boolean; override;
  public
    function GetProcessor: TFileSourceProcessor; override;
    function GetRootDir(sPath : String): String; override;
    function CreateListOperation(TargetPath: String): TFileSourceOperation; override;
  public
    property mountPoints: TMountPoints read _mountPoints;
  end;

implementation

uses
  uMountedListOperation;

type

  { TMountedFileSourceProcessor }

  TMountedFileSourceProcessor = class( TFileSystemFileSourceProcessor )
  private
    procedure resolveRealPath( var params: TFileSourceConsultParams );
  public
    procedure consultBeforeOperate( var params: TFileSourceConsultParams ); override;
  end;

var
  mountedFileSourceProcessor: TMountedFileSourceProcessor;

{ TMountPoint }

constructor TMountPoint.Create(const path: String; const point: String);
begin
  _path:= path;
  _point:= point;
end;

{ TMountedFileSource }

constructor TMountedFileSource.Create;
begin
  inherited Create;
  _mountPoints:= TMountPoints.Create;
  FOperationsClasses[fsoMove]:= TFileSystemMoveOperation.GetOperationClass;
end;

destructor TMountedFileSource.Destroy;
begin
  FreeAndNil( _mountPoints );
  inherited Destroy;
end;

procedure TMountedFileSource.mount(const path: String; const point: String );
var
  realPath: String;
  realPoint: String;
  mountPoint: TMountPoint;
begin
  realPath:= IncludeTrailingPathDelimiter( uDCUtils.ReplaceTilde(path) );
  realPoint:= IncludeTrailingPathDelimiter( point );
  mountPoint:= TMountPoint.Create( realPath, realPoint );
  _mountPoints.Add( mountPoint );
end;

procedure TMountedFileSource.mount( const path: String );
var
  realPath: String;
  realPoint: String;
begin
  realPath:= uDCUtils.ReplaceTilde( path );
  realPoint:= self.getDefaultPointForPath( realPath );
  if realPoint.IsEmpty then
    raise ENotImplemented.Create( 'getDefaultPointForPath() not Implemented in ' + self.ClassName );
  realPoint:= PathDelim + realPoint + PathDelim;
  self.mount( realPath, realPoint );
end;

function TMountedFileSource.getDefaultPointForPath(const path: String): String;
begin
  Result:= String.Empty;
end;

function TMountedFileSource.getRealPath( const path: String ): String;
var
  mountPoint: TMountPoint;
  logicPath: String;
begin
  logicPath:= Path.Substring( self.GetRootDir.Length - 1 );
  for mountPoint in _mountPoints do begin
    if logicPath.StartsWith(mountPoint.point) then begin
      Result:= mountPoint.path + logicPath.Substring(mountPoint.point.Length);
      Exit;
    end;
  end;
end;

function TMountedFileSource.SetCurrentWorkingDirectory(NewDir: String): Boolean;
begin
  Result:= True;
end;

function TMountedFileSource.GetProcessor: TFileSourceProcessor;
begin
  Result:= mountedFileSourceProcessor;
end;

function TMountedFileSource.GetRootDir(sPath: String): String;
begin
  Result:= PathDelim + PathDelim + PathDelim + 'mount' + PathDelim;
end;

function TMountedFileSource.CreateListOperation(TargetPath: String): TFileSourceOperation;
begin
  Result:= TMountedListOperation.Create( self, TargetPath );
end;

{ TMountedFileSourceProcessor }

procedure TMountedFileSourceProcessor.resolveRealPath( var params: TFileSourceConsultParams);
var
  mountedFS: TMountedFileSource;
begin
  if params.currentFS <> params.targetFS then
    Exit;

  mountedFS:= params.currentFS as TMountedFileSource;
  params.targetPath:= mountedFS.getRealPath(params.targetPath);
end;

procedure TMountedFileSourceProcessor.consultBeforeOperate( var params: TFileSourceConsultParams );
begin
  case params.operationType of
    fsoCopy, fsoMove:
      self.resolveRealPath( params );
  end;
  Inherited;
end;

initialization
  mountedFileSourceProcessor:= TMountedFileSourceProcessor.Create;

finalization
  FreeAndNil( mountedFileSourceProcessor );

end.

