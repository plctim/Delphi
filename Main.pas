unit Main;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  System.Math.Vectors, System.Generics.Collections, System.StrUtils,
  FMX.Types, FMX.Controls, FMX.Controls.Presentation, FMX.Forms, FMX.Graphics,
  FMX.Objects, FMX.StdCtrls, FMX.Layouts;

const
  PALETTE: array[0..14] of string = (
    '#ff6b9d','#45d4fa','#a78bfa','#34d399','#fbbf24',
    '#f97316','#38bdf8','#c084fc','#4ade80','#fb923c',
    '#e879f9','#2dd4bf','#facc15','#f87171','#60a5fa'
  );
  HALF_W   = 18.0;
  DEPTH_X  =  0.20;
  DEPTH_Y  = -0.13;
  TRAIL_LEN = 160;
  PT_SPACE  = 5.0;
  TSTEP     = 0.004;
  SPF       = 7;     // steps per frame

type
  // ── Value types ─────────────────────────────────────────────────────────────
  TVec2     = record X, Y: Single; end;
  TTrailPt  = record X, Y, Twist: Single; end;
  TParticle = record
    X, Y, VX, VY: Single;
    R, G, B:      Byte;
    Alpha, Grav, Drag, Sz: Single;
  end;

  // ── Ribbon worm ─────────────────────────────────────────────────────────────
  TWorm = class
  private
    FR, FG, FB, FHR, FHG, FHB: Byte;
    FTrail:  TList<TTrailPt>;
    FPath:   TPathData;         // reused every frame
    FT, FTwist, FTwRate, FWAngle: Single;
    FP0, FP1, FP2, FP3: TVec2;
    FSW, FSH: Single;
    function  BPt(T: Single): TVec2;
    procedure Extend;
    function  Perp(I: Integer): TVec2;
    function  RandPt: TVec2;
    procedure Step;
  public
    constructor Create(R, G, B: Byte; SW, SH: Single);
    destructor  Destroy; override;
    procedure Update;
    procedure Draw(C: TCanvas);
    property ColorR: Byte read FR;
    property ColorG: Byte read FG;
    property ColorB: Byte read FB;
    property Trail: TList<TTrailPt> read FTrail;
  end;

  // ── Firework ─────────────────────────────────────────────────────────────────
  TFWKind = (fwBurst, fwRing, fwWillow, fwStar);

  TFirework = class
  private
    FX, FY:  Single;
    FR, FG, FB: Byte;
    FKind:   TFWKind;
    FParts:  TArray<TParticle>;
    procedure Spawn;
    procedure AddP(PVX, PVY: Single; PR, PG, PB: Byte; PSz, PGrav, PDrag: Single);
  public
    constructor Create(X, Y: Single; R, G, B: Byte);
    procedure Update;
    procedure Draw(C: TCanvas);
    function  Dead: Boolean;
  end;

  // ── Sprites ──────────────────────────────────────────────────────────────────
  TSprite = class
  private
    FSprIdx: Integer;
    FX, FY, FVX, FVY: Single;
    FRadius, FMass, FScl, FT: Single;
    FAngle, FPulseT, FMorphAlpha: Single;
    FHopTimer, FMorphTimer, FMorphTarget: Integer;
    FSW, FSH: Single;
    procedure DrawAt(C: TCanvas; SprIdx: Integer; Alpha: Single);
  public
    constructor Create(SW, SH: Single; Scatter: Boolean = False);
    procedure Update;
    procedure Draw(C: TCanvas);
    function  Offscreen: Boolean;
    property X:      Single read FX write FX;
    property Y:      Single read FY write FY;
    property VX:     Single read FVX write FVX;
    property VY:     Single read FVY write FVY;
    property Radius: Single read FRadius;
    property Mass:   Single read FMass;
  end;

  // ── Main form ────────────────────────────────────────────────────────────────
  TMainForm = class(TForm)
  private
    FTimer:   TTimer;
    FPBox:    TPaintBox;
    FAddBtn, FRemBtn, FAddSprBtn, FRemSprBtn: TButton;
    FCountLbl: TLabel;
    FBtnLayout: TLayout;
    FWorms:   TObjectList<TWorm>;
    FFW:      TObjectList<TFirework>;
    FSprites: TObjectList<TSprite>;
    FFrame, FNextFW, FCursor: Integer;
    procedure OnTick(Sender: TObject);
    procedure OnPaint(Sender: TObject; Canvas: TCanvas);
    procedure AddWorm;
    procedure RemoveWorm;
    procedure AddSprite;
    procedure RemoveSprite;
    procedure UpdateCount;
    procedure BtnAddClick(Sender: TObject);
    procedure BtnRemClick(Sender: TObject);
    procedure BtnAddSprClick(Sender: TObject);
    procedure BtnRemSprClick(Sender: TObject);
    procedure ResolveCollision(A, B: TSprite);
    procedure ApplyShockwave(X, Y: Single);
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
  end;

var
  MainForm: TMainForm;

// ── Color helpers ─────────────────────────────────────────────────────────────
function  RGB(R, G, B: Byte): TAlphaColor;
procedure ParseHex(const S: string; out R, G, B: Byte);

implementation

{$R *.fmx}

const
  // Indices 0-99: emoji sprites; 100=rainbow star, 101=smiley face, 102=ghost
  SPR_EMOJI: array[0..102] of string = (
    '🐱','🐸','🐶','🐭','🐹','🐰','🐻','🐼','🐨','🐯',
    '🦊','🐮','🐷','🐙','🦋','🐝','🐞','🦄','🐬','🐠',
    '🐡','🦀','🐢','🦔','🦦','🦥','🦘','🦙','🦒','🦓',
    '🐇','🦝','🦭','🐿','🦫','🦚','🦜','🦢','🦩','🦆',
    '🦉','🐛','🐌','🪲','🦎','🦕','🦖','🐳','🦑','🦞',
    '🍦','🍩','🍪','🍰','🧁','🍫','🍬','🍭','🍡','🎂',
    '🎈','🎀','🎁','🪀','🎮','🌸','🌺','🌻','🌹','🌷',
    '🌈','⭐','🌟','💫','✨','🌙','🍄','🌵','🎄','🚀',
    '🛸','🎠','🎨','🔮','🧸','🪆','🪄','💎','🌀','🎆',
    '🎇','🧨','🏆','🧊','🪸','🫧','🪼','🐧','🦤','🎪',
    '', '', ''  // 100-102: custom drawn
  );
  // 0=float 1=hop 2=drift
  SPR_BEHAV: array[0..102] of Byte = (
    0,1,0,1,1, 1,2,0,0,2,
    0,2,1,0,0, 0,0,0,0,0,
    0,1,2,2,0, 2,1,2,2,2,
    1,0,0,1,2, 0,0,0,0,0,
    0,2,2,1,2, 2,2,0,0,1,
    1,1,1,1,0, 2,0,0,1,1,
    0,0,1,1,2, 0,0,0,0,0,
    0,0,0,0,0, 0,1,2,2,0,
    0,0,0,0,1, 1,0,0,0,0,
    0,1,1,2,2, 0,0,0,2,2,
    2,0,0  // star=drift, face=float, ghost=float
  );
  // mass × 10
  SPR_MASS10: array[0..102] of Byte = (
    10,12,11, 8, 8,  9,18,16,14,15,
    11,16,14,13, 6,  7, 7,13,15, 8,
     9,11,12, 9,10, 15,16,14,17,16,
     8,10,15, 7,12, 12, 9,11,10,10,
    11, 6, 5, 7, 9, 20,20,20,12,11,
     7, 8, 8, 9, 7,  8, 6, 7, 7,10,
     5, 6,10, 7,10,  5, 6, 7, 6, 5,
     8, 6, 6, 5, 5,  7, 8,12,10, 9,
    11,12, 8,10,12,  9, 7,12, 8, 7,
     7, 8,11,13,10,  4, 8,10,13,12,
     9, 8, 6  // star, face, ghost
  );

function RGB(R, G, B: Byte): TAlphaColor;
begin
  Result := TAlphaColor(
    (Cardinal($FF) shl 24) or
    (Cardinal(R)   shl 16) or
    (Cardinal(G)   shl  8) or
     Cardinal(B));
end;

procedure ParseHex(const S: string; out R, G, B: Byte);
begin
  R := StrToInt('$' + Copy(S, 2, 2));
  G := StrToInt('$' + Copy(S, 4, 2));
  B := StrToInt('$' + Copy(S, 6, 2));
end;

// ════════════════════════════════════════════════════════════════════════════
//  Sprite animation helpers
// ════════════════════════════════════════════════════════════════════════════

function HueColor(H: Single): TAlphaColor;
var
  I: Integer;
  F, R, G, B: Single;
begin
  H := Frac(H) * 6; I := Trunc(H); F := H - I;
  case I of
    0: begin R:=1;   G:=F;   B:=0;   end;
    1: begin R:=1-F; G:=1;   B:=0;   end;
    2: begin R:=0;   G:=1;   B:=F;   end;
    3: begin R:=0;   G:=1-F; B:=1;   end;
    4: begin R:=F;   G:=0;   B:=1;   end;
    else begin R:=1; G:=0;   B:=1-F; end;
  end;
  Result := RGB(Round(R*255), Round(G*255), Round(B*255));
end;

function SpinRate(Idx: Integer): Single;
begin
  case Idx of
    71,72,73,74: Result := 0.025; // ⭐🌟💫✨
    88:          Result := 0.040; // 🌀
    89,90:       Result := 0.018; // 🎆🎇
    80,81:       Result := 0.015; // 🛸🎠
    100:         Result := 0.050; // rainbow star
    101:         Result := 0.008; // face wobble
    else         Result := 0;
  end;
end;

function HasPulse(Idx: Integer): Boolean;
begin
  case Idx of
    60,65,66,67,68,69,83,87,95,96,102: Result := True;
    else Result := False;
  end;
end;

procedure DrawAnimStar(C: TCanvas; X, Y, R, Angle, T, Alpha: Single);
var
  I: Integer;
  A, Ri, R2, Ri2: Single;
  Pts, GPts: array[0..9] of TPointF;
  Path: TPathData;
  Clr: TAlphaColor;
begin
  R  := R * (1.0 + 0.20 * Sin(T * 0.07));
  Ri := R * 0.42; R2 := R * 1.35; Ri2 := Ri * 1.35;
  Clr := HueColor(Frac(T / 240));
  for I := 0 to 4 do
  begin
    A := Angle + I * (2*Pi/5) - Pi/2;
    Pts[I*2]   := TPointF.Create(X + Cos(A)*R,   Y + Sin(A)*R);
    GPts[I*2]  := TPointF.Create(X + Cos(A)*R2,  Y + Sin(A)*R2);
    A := A + Pi/5;
    Pts[I*2+1]  := TPointF.Create(X + Cos(A)*Ri,  Y + Sin(A)*Ri);
    GPts[I*2+1] := TPointF.Create(X + Cos(A)*Ri2, Y + Sin(A)*Ri2);
  end;
  C.Fill.Kind := TBrushKind.Solid; C.Stroke.Kind := TBrushKind.Solid;
  // Glow
  Path := TPathData.Create;
  try
    Path.MoveTo(GPts[0]);
    for I := 1 to 9 do Path.LineTo(GPts[I]);
    Path.ClosePath;
    C.Fill.Color := Clr;
    C.FillPath(Path, Alpha * 0.28);
  finally Path.Free; end;
  // Star body
  Path := TPathData.Create;
  try
    Path.MoveTo(Pts[0]);
    for I := 1 to 9 do Path.LineTo(Pts[I]);
    Path.ClosePath;
    C.Fill.Color := Clr;
    C.FillPath(Path, Alpha);
    C.Stroke.Color := TAlphaColors.White; C.Stroke.Thickness := 1.5;
    C.DrawPath(Path, Alpha * 0.55);
  finally Path.Free; end;
end;

procedure DrawAnimFace(C: TCanvas; X, Y, R, T, Alpha: Single);
var
  Path:   TPathData;
  EyeSz, MouthR: Single;
  BlinkL, BlinkR: Boolean;
  Expr: Integer;
begin
  Expr   := Trunc(T / 200) mod 3;
  BlinkL := (Expr = 1) or (Frac(T / 80.0) > 0.93);
  BlinkR := Frac(T / 67.0) > 0.94;
  EyeSz  := R * 0.15;
  C.Fill.Kind := TBrushKind.Solid; C.Stroke.Kind := TBrushKind.Solid;
  // Head
  C.Fill.Color := RGB(255, 218, 36);
  C.FillEllipse(TRectF.Create(X-R, Y-R, X+R, Y+R), Alpha);
  C.Stroke.Color := RGB(200, 155, 0); C.Stroke.Thickness := 1.5;
  C.DrawEllipse(TRectF.Create(X-R, Y-R, X+R, Y+R), Alpha);
  // Eyes
  C.Fill.Color := RGB(30, 20, 10);
  C.Stroke.Color := RGB(30, 20, 10); C.Stroke.Thickness := 2.5;
  if BlinkL then
    C.DrawLine(TPointF.Create(X-R*0.42, Y-R*0.22), TPointF.Create(X-R*0.13, Y-R*0.22), Alpha)
  else
    C.FillEllipse(TRectF.Create(X-R*0.42-EyeSz, Y-R*0.22-EyeSz, X-R*0.42+EyeSz, Y-R*0.22+EyeSz), Alpha);
  if BlinkR then
    C.DrawLine(TPointF.Create(X+R*0.13, Y-R*0.22), TPointF.Create(X+R*0.42, Y-R*0.22), Alpha)
  else
    C.FillEllipse(TRectF.Create(X+R*0.42-EyeSz, Y-R*0.22-EyeSz, X+R*0.42+EyeSz, Y-R*0.22+EyeSz), Alpha);
  // Mouth
  if Expr = 2 then
  begin
    MouthR := R * 0.2;
    C.Fill.Color := RGB(200, 65, 65);
    C.FillEllipse(TRectF.Create(X-MouthR, Y+R*0.22-MouthR, X+MouthR, Y+R*0.22+MouthR), Alpha);
  end else
  begin
    Path := TPathData.Create;
    try
      Path.MoveTo(TPointF.Create(X-R*0.38, Y+R*0.18));
      Path.CurveTo(
        TPointF.Create(X-R*0.28, Y+R*0.52),
        TPointF.Create(X+R*0.28, Y+R*0.52),
        TPointF.Create(X+R*0.38, Y+R*0.18));
      C.Stroke.Color := RGB(200, 65, 65); C.Stroke.Thickness := 2.5;
      C.DrawPath(Path, Alpha);
    finally Path.Free; end;
  end;
end;

procedure DrawAnimGhost(C: TCanvas; X, Y, R, T, Alpha: Single);
const NBumps = 4;
var
  I: Integer;
  BodyBot, BumpW, BX1, BX2, BumpH, BMidY, ER: Single;
  Path: TPathData;
  Blink: Boolean;
begin
  Blink   := Frac(T / 55.0) > 0.90;
  BodyBot := Y + R * 0.32;
  BumpW   := (2 * R) / NBumps;
  Path := TPathData.Create;
  try
    Path.MoveTo(TPointF.Create(X-R, BodyBot));
    Path.LineTo(TPointF.Create(X-R, Y-R*0.2));
    Path.CurveTo(
      TPointF.Create(X-R, Y-R*1.45),
      TPointF.Create(X+R, Y-R*1.45),
      TPointF.Create(X+R, Y-R*0.2));
    Path.LineTo(TPointF.Create(X+R, BodyBot));
    for I := 0 to NBumps-1 do
    begin
      BX1   := X+R - I*BumpW;
      BX2   := BX1 - BumpW;
      BumpH := R*0.38 + Sin(T*0.055 + I*1.4)*R*0.13;
      BMidY := BodyBot + BumpH;
      Path.CurveTo(
        TPointF.Create(BX1-BumpW*0.22, BMidY),
        TPointF.Create(BX2+BumpW*0.22, BMidY),
        TPointF.Create(BX2, BodyBot));
    end;
    Path.ClosePath;
    C.Fill.Kind := TBrushKind.Solid;
    C.Fill.Color := RGB(225, 230, 255);
    C.FillPath(Path, Alpha * 0.93);
    C.Stroke.Kind := TBrushKind.Solid;
    C.Stroke.Color := RGB(165, 170, 220); C.Stroke.Thickness := 1.5;
    C.DrawPath(Path, Alpha * 0.6);
  finally Path.Free; end;
  ER := R * 0.13;
  C.Fill.Kind := TBrushKind.Solid; C.Stroke.Kind := TBrushKind.Solid;
  if Blink then
  begin
    C.Stroke.Color := RGB(50, 30, 100); C.Stroke.Thickness := 2.5;
    C.DrawLine(TPointF.Create(X-R*0.40, Y-R*0.58), TPointF.Create(X-R*0.15, Y-R*0.58), Alpha);
    C.DrawLine(TPointF.Create(X+R*0.15, Y-R*0.58), TPointF.Create(X+R*0.40, Y-R*0.58), Alpha);
  end else
  begin
    C.Fill.Color := RGB(50, 30, 100);
    C.FillEllipse(TRectF.Create(X-R*0.35-ER, Y-R*0.63-ER, X-R*0.35+ER, Y-R*0.63+ER), Alpha);
    C.FillEllipse(TRectF.Create(X+R*0.35-ER, Y-R*0.63-ER, X+R*0.35+ER, Y-R*0.63+ER), Alpha);
    ER := ER * 0.42;
    C.Fill.Color := TAlphaColors.White;
    C.FillEllipse(TRectF.Create(X-R*0.29-ER, Y-R*0.69-ER, X-R*0.29+ER, Y-R*0.69+ER), Alpha);
    C.FillEllipse(TRectF.Create(X+R*0.41-ER, Y-R*0.69-ER, X+R*0.41+ER, Y-R*0.69+ER), Alpha);
  end;
end;

// ════════════════════════════════════════════════════════════════════════════
//  TWorm
// ════════════════════════════════════════════════════════════════════════════

constructor TWorm.Create(R, G, B: Byte; SW, SH: Single);
begin
  inherited Create;
  FR := R; FG := G; FB := B;
  FHR := Min(255, R + 90);
  FHG := Min(255, G + 90);
  FHB := Min(255, B + 90);
  FSW := SW; FSH := SH;
  FTrail  := TList<TTrailPt>.Create;
  FPath   := TPathData.Create;
  FTwist  := Random * 2 * Pi;
  FTwRate := 0.042 + Random * 0.028;
  FWAngle := Random * 2 * Pi;
  FP0 := RandPt; FP1 := RandPt; FP2 := RandPt; FP3 := RandPt;
  FT := 0;
end;

destructor TWorm.Destroy;
begin
  FTrail.Free;
  FPath.Free;
  inherited;
end;

function TWorm.RandPt: TVec2;
begin
  Result.X := 100 + Random * (FSW - 200);
  Result.Y := 100 + Random * (FSH - 200);
end;

function TWorm.BPt(T: Single): TVec2;
var U: Single;
begin
  U := 1 - T;
  Result.X := U*U*U*FP0.X + 3*U*U*T*FP1.X + 3*U*T*T*FP2.X + T*T*T*FP3.X;
  Result.Y := U*U*U*FP0.Y + 3*U*U*T*FP1.Y + 3*U*T*T*FP2.Y + T*T*T*FP3.Y;
end;

procedure TWorm.Extend;
var
  N0, N1, N2, N3: TVec2;
  D, BX, BY, Strength, TargetAngle, AngleDiff: Single;
begin
  N0 := FP3;
  N1.X := 2*FP3.X - FP2.X; N1.Y := 2*FP3.Y - FP2.Y;
  FWAngle := FWAngle + (Random - 0.5) * 1.3;

  // Steer away from edges
  BX := 0; BY := 0;
  if N0.X < 200 then BX := BX + (1.0 - N0.X / 200);
  if N0.X > FSW - 200 then BX := BX - (1.0 - (FSW - N0.X) / 200);
  if N0.Y < 200 then BY := BY + (1.0 - N0.Y / 200);
  if N0.Y > FSH - 200 then BY := BY - (1.0 - (FSH - N0.Y) / 200);
  Strength := Sqrt(BX * BX + BY * BY);
  if Strength > 0.01 then
  begin
    TargetAngle := ArcTan2(BY, BX);
    AngleDiff := TargetAngle - FWAngle;
    while AngleDiff >  Pi do AngleDiff := AngleDiff - 2 * Pi;
    while AngleDiff < -Pi do AngleDiff := AngleDiff + 2 * Pi;
    FWAngle := FWAngle + AngleDiff * Min(Strength * 2.0, 1.0);
  end;

  D := 130 + Random * 230;
  N3.X := EnsureRange(N0.X + Cos(FWAngle)*D, 100, FSW - 100);
  N3.Y := EnsureRange(N0.Y + Sin(FWAngle)*D, 100, FSH - 100);
  N2.X := (N1.X + N3.X) / 2 + (Random - 0.5) * 150;
  N2.Y := (N1.Y + N3.Y) / 2 + (Random - 0.5) * 150;
  FP0 := N0; FP1 := N1; FP2 := N2; FP3 := N3;
  FT := 0;
end;

function TWorm.Perp(I: Integer): TVec2;
var
  Prev, Next: TTrailPt;
  DX, DY, L: Single;
begin
  Prev := FTrail[Max(0, I - 1)];
  Next := FTrail[Min(FTrail.Count - 1, I + 1)];
  DX := Next.X - Prev.X; DY := Next.Y - Prev.Y;
  L := Sqrt(DX*DX + DY*DY);
  if L = 0 then L := 1;
  Result.X := -DY / L; Result.Y := DX / L;
end;

procedure TWorm.Step;
var
  V, Last: TTrailPt;
  Pt: TVec2;
  DX, DY: Single;
begin
  if FT >= 1 then Extend;
  Pt := BPt(FT);
  V.X := Pt.X; V.Y := Pt.Y; V.Twist := FTwist;
  if FTrail.Count = 0 then
    FTrail.Add(V)
  else
  begin
    Last := FTrail[FTrail.Count - 1];
    DX := V.X - Last.X; DY := V.Y - Last.Y;
    if Sqrt(DX*DX + DY*DY) >= PT_SPACE then
    begin
      FTrail.Add(V);
      FTwist := FTwist + FTwRate;
      if FTrail.Count > TRAIL_LEN then FTrail.Delete(0);
    end;
  end;
  FT := FT + TSTEP;
end;

procedure TWorm.Update;
var I: Integer;
begin
  for I := 0 to SPF - 1 do Step;
end;

procedure TWorm.Draw(C: TCanvas);
var
  I, Len, Side: Integer;
  PA, PB, P: TTrailPt;
  PA2, PB2, PP: TVec2;
  SA, CA, SB, CB: Single;
  ACX, ACY, BCX, BCY, WA, WB: Single;
  X0,Y0,X1,Y1,X2,Y2,X3,Y3: Single;
  Shade, Alpha: Single;
  EX, EY, S, Cs: Single;
  RI, GI, BI: Integer;
begin
  Len := FTrail.Count;
  if Len < 2 then Exit;

  // ── Ribbon quad strip ──────────────────────────────────────────────────────
  C.Fill.Kind := TBrushKind.Solid;
  for I := 0 to Len - 2 do
  begin
    PA := FTrail[I]; PB := FTrail[I + 1];
    PA2 := Perp(I);  PB2 := Perp(I + 1);
    SA := Sin(PA.Twist); CA := Cos(PA.Twist);
    SB := Sin(PB.Twist); CB := Cos(PB.Twist);

    ACX := PA.X + SA*HALF_W*DEPTH_X; ACY := PA.Y + SA*HALF_W*DEPTH_Y;
    BCX := PB.X + SB*HALF_W*DEPTH_X; BCY := PB.Y + SB*HALF_W*DEPTH_Y;
    WA  := CA * HALF_W; WB := CB * HALF_W;

    X0 := ACX + PA2.X*WA; Y0 := ACY + PA2.Y*WA;
    X1 := ACX - PA2.X*WA; Y1 := ACY - PA2.Y*WA;
    X2 := BCX - PB2.X*WB; Y2 := BCY - PB2.Y*WB;
    X3 := BCX + PB2.X*WB; Y3 := BCY + PB2.Y*WB;

    Shade := 0.15 + 0.85 * (CA * 0.5 + 0.5);
    Alpha := Power((I + 1) / Len, 1.3);
    RI := Min(255, Round(FR * Shade));
    GI := Min(255, Round(FG * Shade));
    BI := Min(255, Round(FB * Shade));

    C.Fill.Color := RGB(RI, GI, BI);
    FPath.Clear;
    FPath.MoveTo(PointF(X0,Y0)); FPath.LineTo(PointF(X1,Y1));
    FPath.LineTo(PointF(X2,Y2)); FPath.LineTo(PointF(X3,Y3));
    FPath.ClosePath;
    C.FillPath(FPath, Alpha);
  end;

  // ── Edge highlight lines ───────────────────────────────────────────────────
  C.Stroke.Kind      := TBrushKind.Solid;
  C.Stroke.Color     := RGB(FHR, FHG, FHB);
  C.Stroke.Thickness := 1.5;
  for Side := -1 to 1 do
  begin
    if Side = 0 then Continue;
    FPath.Clear;
    for I := 0 to Len - 1 do
    begin
      P  := FTrail[I];
      PP := Perp(I);
      S  := Sin(P.Twist); Cs := Cos(P.Twist);
      EX := P.X + S*HALF_W*DEPTH_X + PP.X*Cs*HALF_W*Side;
      EY := P.Y + S*HALF_W*DEPTH_Y + PP.Y*Cs*HALF_W*Side;
      if I = 0 then FPath.MoveTo(PointF(EX, EY))
      else           FPath.LineTo(PointF(EX, EY));
    end;
    C.DrawPath(FPath, 0.45);
  end;
end;

// ════════════════════════════════════════════════════════════════════════════
//  TFirework
// ════════════════════════════════════════════════════════════════════════════

constructor TFirework.Create(X, Y: Single; R, G, B: Byte);
begin
  inherited Create;
  FX := X; FY := Y; FR := R; FG := G; FB := B;
  FKind := TFWKind(Random(4));
  Spawn;
end;

procedure TFirework.AddP(PVX, PVY: Single; PR, PG, PB: Byte; PSz, PGrav, PDrag: Single);
var N: Integer;
begin
  N := Length(FParts);
  SetLength(FParts, N + 1);
  FParts[N].X    := FX;    FParts[N].Y    := FY;
  FParts[N].VX   := PVX;   FParts[N].VY   := PVY;
  FParts[N].R    := PR;    FParts[N].G    := PG;    FParts[N].B := PB;
  FParts[N].Alpha := 1;
  FParts[N].Grav := PGrav; FParts[N].Drag := PDrag; FParts[N].Sz := PSz;
end;

procedure TFirework.Spawn;
var
  I, Arm, J: Integer;
  A, S:      Single;
  White:     Boolean;
begin
  case FKind of
    fwBurst:
      for I := 0 to 39 do
      begin
        A := Random * 2 * Pi; S := 1.2 + Random * 4;
        White := Random < 0.25;
        if White then AddP(Cos(A)*S, Sin(A)*S, 255, 245, 200, 1.5+Random*1.5, 0.07, 0.97)
        else           AddP(Cos(A)*S, Sin(A)*S, FR,  FG,  FB,  1.5+Random*1.5, 0.07, 0.97);
      end;

    fwRing:
      for I := 0 to 31 do
      begin
        A := (I / 32) * 2 * Pi; S := 3.5 + Random * 0.8;
        AddP(Cos(A)*S, Sin(A)*S, FR, FG, FB, 2.5, 0.025, 0.985);
      end;

    fwWillow:
      for I := 0 to 34 do
      begin
        A := -Pi/2 + (Random - 0.5)*Pi*0.9; S := 1.5 + Random * 2.5;
        AddP(Cos(A)*S, Sin(A)*S,
          Min(255, FR+80), Min(255, FG+40), Max(0, FB-60),
          1.5, 0.15, 0.95);
      end;

    fwStar:
      for Arm := 0 to 5 do
        for J := 0 to 5 do
        begin
          A := (Arm / 6) * 2 * Pi; S := 0.7 + J * 0.65;
          if J < 2 then AddP(Cos(A)*S, Sin(A)*S, 255, 250, 220, 3.0, 0.03, 0.99)
          else          AddP(Cos(A)*S, Sin(A)*S, FR,  FG,  FB,  2.0, 0.03, 0.99);
        end;
  end;
end;

procedure TFirework.Update;
var I: Integer;
begin
  for I := 0 to High(FParts) do
    with FParts[I] do
    begin
      X     := X  + VX;
      Y     := Y  + VY;
      VY    := VY + Grav;
      VX    := VX * Drag;
      VY    := VY * Drag;
      Alpha := Alpha - 0.017;
    end;
end;

procedure TFirework.Draw(C: TCanvas);
var
  I:  Integer;
  P:  TParticle;
  R:  TRectF;
begin
  C.Fill.Kind := TBrushKind.Solid;
  for I := 0 to High(FParts) do
  begin
    P := FParts[I];
    if P.Alpha <= 0 then Continue;
    C.Fill.Color := RGB(P.R, P.G, P.B);
    R := TRectF.Create(P.X - P.Sz, P.Y - P.Sz, P.X + P.Sz, P.Y + P.Sz);
    C.FillEllipse(R, P.Alpha);
  end;
end;

function TFirework.Dead: Boolean;
var I: Integer;
begin
  for I := 0 to High(FParts) do
    if FParts[I].Alpha > 0 then Exit(False);
  Result := True;
end;

// ════════════════════════════════════════════════════════════════════════════
//  TSprite
// ════════════════════════════════════════════════════════════════════════════

constructor TSprite.Create(SW, SH: Single; Scatter: Boolean);
var
  Spd, Ang: Single;
  GoRight: Boolean;
begin
  inherited Create;
  FSW      := SW; FSH := SH;
  FSprIdx  := Random(103);
  FScl     := 0.8 + Random * 0.6;
  FMass    := SPR_MASS10[FSprIdx] / 10.0;
  FRadius  := 20 * FScl;
  FT       := Random * 300;
  FAngle      := Random * 2 * Pi;
  FPulseT     := Random * 200;
  FMorphAlpha := -1;
  FMorphTimer := 1800 + Random(1800); // 30-60 s at 60 fps
  FMorphTarget := 0;
  FHopTimer := 0;
  Spd := 0.75 + Random * 1.0;
  if Scatter then
  begin
    FX := FRadius + Random * (SW - FRadius * 2);
    FY := FRadius + Random * (SH - FRadius * 2);
    Ang := Random * 2 * Pi;
    FVX := Cos(Ang) * Spd;
    FVY := Sin(Ang) * Spd;
  end else
  begin
    GoRight := Random < 0.5;
    FX  := IfThen(GoRight, -80, SW + 80);
    FY  := 80 + Random * (SH - 160);
    FVX := IfThen(GoRight, Spd, -Spd);
    FVY := (Random - 0.5) * 0.75;
  end;
end;

procedure TSprite.Update;
var
  Spd: Single;
begin
  // Visual animation
  FAngle  := FAngle + SpinRate(FSprIdx);
  FPulseT := FPulseT + 1;
  // Morph countdown
  if FMorphAlpha < 0 then
  begin
    Dec(FMorphTimer);
    if FMorphTimer <= 0 then
    begin
      repeat FMorphTarget := Random(103) until FMorphTarget <> FSprIdx;
      FMorphAlpha := 0;
    end;
  end else
  begin
    FMorphAlpha := FMorphAlpha + 1/60.0;
    if FMorphAlpha >= 1.0 then
    begin
      FSprIdx     := FMorphTarget;
      FMass       := SPR_MASS10[FSprIdx] / 10.0;
      FMorphAlpha := -1;
      FMorphTimer := 1800 + Random(1800);
    end;
  end;
  // Physics
  case SPR_BEHAV[FSprIdx] of
    1:
    begin
      FVY := FVY + 0.03;
      Inc(FHopTimer);
      if FHopTimer > 65 + Random(40) then
      begin
        FVY := FVY - (2 + Random * 1);
        FHopTimer := 0;
      end;
    end;
    0:
      FVY := FVY + Sin(FT * 0.05) * 0.03;
  end;
  Spd := Sqrt(FVX * FVX + FVY * FVY);
  if Spd > 3.5 then begin FVX := FVX / Spd * 3.5; FVY := FVY / Spd * 3.5; end;
  FX := FX + FVX;
  FY := FY + FVY;
  FT := FT + 1;
  if FX < FRadius then begin FX := FRadius; FVX := Abs(FVX); end;
  if FX > FSW - FRadius then begin FX := FSW - FRadius; FVX := -Abs(FVX); end;
  if FY < FRadius then begin FY := FRadius; FVY := Abs(FVY) * 0.85; end;
  if FY > FSH - FRadius then begin FY := FSH - FRadius; FVY := -Abs(FVY) * 0.85; end;
end;

procedure TSprite.Draw(C: TCanvas);
begin
  if FMorphAlpha < 0 then
    DrawAt(C, FSprIdx, 1.0)
  else
  begin
    DrawAt(C, FSprIdx,      1.0 - FMorphAlpha);
    DrawAt(C, FMorphTarget, FMorphAlpha);
  end;
end;

procedure TSprite.DrawAt(C: TCanvas; SprIdx: Integer; Alpha: Single);
var
  Sz, Scale: Single;
  M, SaveM: TMatrix;
begin
  if Alpha < 0.01 then Exit;
  Scale := 1.0;
  if HasPulse(SprIdx) then
    Scale := 1.0 + 0.15 * Sin(FPulseT * 0.07);
  // Custom drawn sprites
  if SprIdx >= 100 then
  begin
    Sz := FScl * 28 * Scale;
    case SprIdx of
      100: DrawAnimStar(C, FX, FY, Sz,        FAngle, FT, Alpha);
      101: DrawAnimFace(C, FX, FY, Sz * 0.88, FT,         Alpha);
      102: DrawAnimGhost(C, FX, FY, Sz,        FT,         Alpha);
    end;
    Exit;
  end;
  // Emoji sprite
  Sz := Round(36 * FScl * Scale);
  C.Font.Size := Sz;
  {$IFDEF MSWINDOWS}
  C.Font.Family := 'Segoe UI Emoji';
  {$ELSE}
  C.Font.Family := 'Apple Color Emoji';
  {$ENDIF}
  C.Fill.Kind  := TBrushKind.Solid;
  C.Fill.Color := TAlphaColors.White;
  if SpinRate(SprIdx) > 0 then
  begin
    SaveM := C.Matrix;
    M.m11 :=  Cos(FAngle); M.m12 := Sin(FAngle); M.m13 := 0;
    M.m21 := -Sin(FAngle); M.m22 := Cos(FAngle); M.m23 := 0;
    M.m31 := FX;           M.m32 := FY;           M.m33 := 1;
    C.SetMatrix(M * SaveM);
    C.FillText(TRectF.Create(-Sz, -Sz, Sz, Sz),
      SPR_EMOJI[SprIdx], False, Alpha, [], TTextAlign.Center, TTextAlign.Center);
    C.SetMatrix(SaveM);
  end else
    C.FillText(TRectF.Create(FX-Sz, FY-Sz, FX+Sz, FY+Sz),
      SPR_EMOJI[SprIdx], False, Alpha, [], TTextAlign.Center, TTextAlign.Center);
end;

function TSprite.Offscreen: Boolean;
begin
  Result := (FX < -120) or (FX > FSW + 120);
end;

// ════════════════════════════════════════════════════════════════════════════
//  TMainForm
// ════════════════════════════════════════════════════════════════════════════

constructor TMainForm.Create(AOwner: TComponent);
var
  I: Integer;
  R, G, B: Byte;
begin
  inherited;

  Caption      := 'Wandering Bezier Ribbons';
  FullScreen   := True;
  BorderStyle  := TFmxFormBorderStyle.None;

  // ── Paint box (covers whole form) ─────────────────────────────────────────
  FPBox        := TPaintBox.Create(Self);
  FPBox.Parent := Self;
  FPBox.Align  := TAlignLayout.Client;
  FPBox.OnPaint := OnPaint;

  // ── Button bar at bottom ──────────────────────────────────────────────────
  FBtnLayout          := TLayout.Create(Self);
  FBtnLayout.Parent   := Self;
  FBtnLayout.Align    := TAlignLayout.Bottom;
  FBtnLayout.Height   := 60;

  FRemBtn             := TButton.Create(Self);
  FRemBtn.Parent      := FBtnLayout;
  FRemBtn.Text        := '− Ribbon';
  FRemBtn.Width       := 110;
  FRemBtn.Height      := 40;
  FRemBtn.Position.X  := Screen.WorkAreaWidth / 2 - 240;
  FRemBtn.Position.Y  := 10;
  FRemBtn.OnClick     := BtnRemClick;

  FAddBtn             := TButton.Create(Self);
  FAddBtn.Parent      := FBtnLayout;
  FAddBtn.Text        := '+ Ribbon';
  FAddBtn.Width       := 110;
  FAddBtn.Height      := 40;
  FAddBtn.Position.X  := Screen.WorkAreaWidth / 2 - 120;
  FAddBtn.Position.Y  := 10;
  FAddBtn.OnClick     := BtnAddClick;

  FRemSprBtn             := TButton.Create(Self);
  FRemSprBtn.Parent      := FBtnLayout;
  FRemSprBtn.Text        := '− Sprite';
  FRemSprBtn.Width       := 110;
  FRemSprBtn.Height      := 40;
  FRemSprBtn.Position.X  := Screen.WorkAreaWidth / 2 + 10;
  FRemSprBtn.Position.Y  := 10;
  FRemSprBtn.OnClick     := BtnRemSprClick;

  FAddSprBtn             := TButton.Create(Self);
  FAddSprBtn.Parent      := FBtnLayout;
  FAddSprBtn.Text        := '+ Sprite';
  FAddSprBtn.Width       := 110;
  FAddSprBtn.Height      := 40;
  FAddSprBtn.Position.X  := Screen.WorkAreaWidth / 2 + 130;
  FAddSprBtn.Position.Y  := 10;
  FAddSprBtn.OnClick     := BtnAddSprClick;

  FCountLbl               := TLabel.Create(Self);
  FCountLbl.Parent        := Self;
  FCountLbl.Position.Y    := 20;
  FCountLbl.Align         := TAlignLayout.Right;
  FCountLbl.Width         := 120;
  FCountLbl.TextSettings.FontColor := TAlphaColors.Gray;
  FCountLbl.TextSettings.HorzAlign := TTextAlign.Trailing;

  // ── Game state ────────────────────────────────────────────────────────────
  Randomize;
  FCursor := 0; FFrame := 0; FNextFW := 40;
  FWorms   := TObjectList<TWorm>.Create(True);
  FFW      := TObjectList<TFirework>.Create(True);
  FSprites := TObjectList<TSprite>.Create(True);

  for I := 0 to 4 do AddWorm;

  // Pre-scatter sprites across the screen
  for I := 0 to 8 do
    FSprites.Add(TSprite.Create(Screen.WorkAreaWidth, Screen.WorkAreaHeight, True));

  // ── Timer ─────────────────────────────────────────────────────────────────
  FTimer          := TTimer.Create(Self);
  FTimer.Interval := 16;
  FTimer.OnTimer  := OnTick;
  FTimer.Enabled  := True;

  UpdateCount;
end;

destructor TMainForm.Destroy;
begin
  FTimer.Enabled := False;
  FWorms.Free; FFW.Free; FSprites.Free;
  inherited;
end;

procedure TMainForm.AddWorm;
var R, G, B: Byte;
begin
  ParseHex(PALETTE[FCursor mod 15], R, G, B);
  Inc(FCursor);
  FWorms.Add(TWorm.Create(R, G, B, Screen.WorkAreaWidth, Screen.WorkAreaHeight));
  UpdateCount;
end;

procedure TMainForm.RemoveWorm;
begin
  if FWorms.Count > 1 then
  begin
    FWorms.Delete(FWorms.Count - 1);
    UpdateCount;
  end;
end;

procedure TMainForm.AddSprite;
begin
  FSprites.Add(TSprite.Create(Screen.WorkAreaWidth, Screen.WorkAreaHeight, True));
  UpdateCount;
end;

procedure TMainForm.RemoveSprite;
begin
  if FSprites.Count > 0 then
  begin
    FSprites.Delete(FSprites.Count - 1);
    UpdateCount;
  end;
end;

procedure TMainForm.UpdateCount;
begin
  FCountLbl.Text := Format('%d ribbon%s · %d sprite%s',
    [FWorms.Count,   IfThen(FWorms.Count   <> 1, 's', ''),
     FSprites.Count, IfThen(FSprites.Count <> 1, 's', '')]);
end;

procedure TMainForm.BtnAddClick(Sender: TObject);    begin AddWorm;      end;
procedure TMainForm.BtnRemClick(Sender: TObject);    begin RemoveWorm;   end;
procedure TMainForm.BtnAddSprClick(Sender: TObject); begin AddSprite;    end;
procedure TMainForm.BtnRemSprClick(Sender: TObject); begin RemoveSprite; end;

procedure TMainForm.ApplyShockwave(X, Y: Single);
const
  RADIUS   = 220.0;
  STRENGTH = 4.0;
var
  Sp: TSprite;
  DX, DY, Dist, F: Single;
begin
  for Sp in FSprites do
  begin
    DX := Sp.X - X; DY := Sp.Y - Y;
    Dist := Sqrt(DX * DX + DY * DY);
    if (Dist > 0.5) and (Dist < RADIUS) then
    begin
      F := STRENGTH * (1 - Dist / RADIUS);
      Sp.VX := Sp.VX + F * DX / Dist;
      Sp.VY := Sp.VY + F * DY / Dist;
    end;
  end;
end;

procedure TMainForm.ResolveCollision(A, B: TSprite);
const E = 0.82;
var
  DX, DY, Dist, MinDist, NX, NY: Single;
  DVX, DVY, VN, Imp, Corr: Single;
begin
  DX := B.X - A.X; DY := B.Y - A.Y;
  Dist := Sqrt(DX * DX + DY * DY);
  MinDist := A.Radius + B.Radius;
  if (Dist >= MinDist) or (Dist < 0.01) then Exit;
  NX := DX / Dist; NY := DY / Dist;
  DVX := A.VX - B.VX; DVY := A.VY - B.VY;
  VN := DVX * NX + DVY * NY;
  if VN <= 0 then Exit;
  Imp := (1 + E) * VN / (1 / A.Mass + 1 / B.Mass);
  A.VX := A.VX - Imp / A.Mass * NX; A.VY := A.VY - Imp / A.Mass * NY;
  B.VX := B.VX + Imp / B.Mass * NX; B.VY := B.VY + Imp / B.Mass * NY;
  Corr := (MinDist - Dist) * 0.5 + 0.5;
  A.X := A.X - NX * Corr; A.Y := A.Y - NY * Corr;
  B.X := B.X + NX * Corr; B.Y := B.Y + NY * Corr;
end;

procedure TMainForm.OnTick(Sender: TObject);
var
  W:   TWorm;
  I, K, Idx: Integer;
  Pt:  TTrailPt;
begin
  Inc(FFrame);

  for W in FWorms do W.Update;

  // Spawn fireworks from ribbon trail points
  if (FFrame >= FNextFW) and (FWorms.Count > 0) then
  begin
    FNextFW := FFrame + 25 + Random(55);
    K := 1; if Random < 0.35 then K := 2;
    for I := 0 to K - 1 do
    begin
      W := FWorms[Random(FWorms.Count)];
      if W.Trail.Count > 0 then
      begin
        Idx := Random(W.Trail.Count);
        Pt  := W.Trail[Idx];
        FFW.Add(TFirework.Create(Pt.X, Pt.Y, W.ColorR, W.ColorG, W.ColorB));
        ApplyShockwave(Pt.X, Pt.Y);
      end;
    end;
  end;

  for I := FFW.Count - 1 downto 0 do
  begin
    FFW[I].Update;
    if FFW[I].Dead then FFW.Delete(I);
  end;

  for I := 0 to FSprites.Count - 1 do
  begin
    FSprites[I].Update;
    if FSprites[I].Offscreen then
      FSprites[I] := TSprite.Create(Screen.WorkAreaWidth, Screen.WorkAreaHeight, True);
  end;

  for I := 0 to FSprites.Count - 2 do
    for K := I + 1 to FSprites.Count - 1 do
      ResolveCollision(FSprites[I], FSprites[K]);

  FPBox.Repaint;
end;

procedure TMainForm.OnPaint(Sender: TObject; Canvas: TCanvas);
var
  W:  TWorm;
  FW: TFirework;
  Sp: TSprite;
begin
  Canvas.Clear($FF0A0A0F);
  for W  in FWorms   do W.Draw(Canvas);
  for FW in FFW      do FW.Draw(Canvas);
  for Sp in FSprites do Sp.Draw(Canvas);
end;

// ── Button layout after form resize ──────────────────────────────────────────
// Position buttons centered at bottom; called after the form knows its Width.
initialization
  // nothing needed here; form constructor handles init

end.
