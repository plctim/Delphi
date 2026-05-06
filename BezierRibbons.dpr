program BezierRibbons;

uses
  System.StartUpCopy,
  FMX.Forms,
  Main in 'Main.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
