unit Main;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  System.Generics.Collections, System.StrUtils,
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

  // ── Sprites (cat, frog, toaster) ─────────────────────────────────────────────
  TSprKind = (skCat, skFrog, skToaster);

  TSprite = class
  private
    FKind: TSprKind;
    FX, FY, FVX, FVY: Single;
    FRadius, FMass, FScl, FT: Single;
    FHopTimer: Integer;
    FSW, FSH: Single;
    procedure DrawToaster(C: TCanvas);
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
    FAddBtn, FRemBtn: TButton;
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
    procedure UpdateCount;
    procedure BtnAddClick(Sender: TObject);
    procedure BtnRemClick(Sender: TObject);
    procedure ResolveCollision(A, B: TSprite);
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
const
  SPR_MASS: array[TSprKind] of Single = (1.0, 1.2, 1.6); // cat, frog, toaster
var
  Spd, Ang: Single;
  GoRight: Boolean;
begin
  inherited Create;
  FSW   := SW; FSH := SH;
  FKind := TSprKind(Random(3));
  FScl  := 0.8 + Random * 0.6;
  FMass := SPR_MASS[FKind];
  FRadius := IfThen(FKind = skToaster, 24, 20) * FScl;
  FT := Random * 300;
  FHopTimer := 0;
  Spd := 1.5 + Random * 2.0;
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
    FVY := (Random - 0.5) * 1.5;
  end;
end;

procedure TSprite.Update;
var
  Spd: Single;
begin
  case FKind of
    skFrog:
    begin
      FVY := FVY + 0.06;
      Inc(FHopTimer);
      if FHopTimer > 65 + Random(40) then
      begin
        FVY := FVY - (4 + Random * 2);
        FHopTimer := 0;
      end;
    end;
    skCat:
      FVY := FVY + Sin(FT * 0.05) * 0.06;
  end;
  Spd := Sqrt(FVX * FVX + FVY * FVY);
  if Spd > 7 then begin FVX := FVX / Spd * 7; FVY := FVY / Spd * 7; end;
  FX := FX + FVX;
  FY := FY + FVY;
  FT := FT + 1;
  if FX < FRadius then begin FX := FRadius; FVX := Abs(FVX); end;
  if FX > FSW - FRadius then begin FX := FSW - FRadius; FVX := -Abs(FVX); end;
  if FY < FRadius then begin FY := FRadius; FVY := Abs(FVY) * 0.85; end;
  if FY > FSH - FRadius then begin FY := FSH - FRadius; FVY := -Abs(FVY) * 0.85; end;
end;

procedure TSprite.DrawToaster(C: TCanvas);
var
  S, CX, CY, WH: Single;
begin
  CX := FX; CY := FY; S := FScl;
  WH := Sin(FT * 0.12) * 7 * S; // wing-flap vertical offset

  C.Fill.Kind   := TBrushKind.Solid;
  C.Stroke.Kind := TBrushKind.Solid;

  // Wings (drawn first so body overlaps the root)
  C.Fill.Color   := RGB(192, 192, 192);
  C.Stroke.Color := RGB(136, 136, 136);
  C.Stroke.Thickness := 0.8;
  C.FillRect(TRectF.Create(CX-(31*S), CY+WH,    CX-(14*S), CY+WH+(8*S)),  0,0,AllCorners,1);
  C.FillRect(TRectF.Create(CX+(14*S), CY+WH,    CX+(31*S), CY+WH+(8*S)),  0,0,AllCorners,1);
  C.DrawRect( TRectF.Create(CX-(31*S), CY+WH,    CX-(14*S), CY+WH+(8*S)),  0,0,AllCorners,1);
  C.DrawRect( TRectF.Create(CX+(14*S), CY+WH,    CX+(31*S), CY+WH+(8*S)),  0,0,AllCorners,1);

  // Body
  C.Fill.Color   := RGB(184, 184, 184);
  C.Stroke.Color := RGB(136, 136, 136);
  C.Stroke.Thickness := 1.0;
  C.FillRect(TRectF.Create(CX-14*S, CY-12*S, CX+14*S, CY+12*S), 3*S, 3*S, AllCorners, 1);
  C.DrawRect( TRectF.Create(CX-14*S, CY-12*S, CX+14*S, CY+12*S), 3*S, 3*S, AllCorners, 1);

  // Slots
  C.Fill.Color := RGB(68, 68, 68);
  C.FillRect(TRectF.Create(CX-8*S, CY-9*S, CX-4*S, CY+5*S), 0,0,AllCorners,1);
  C.FillRect(TRectF.Create(CX+4*S, CY-9*S, CX+8*S, CY+5*S), 0,0,AllCorners,1);

  // Shine
  C.Fill.Color := TAlphaColor($44FFFFFF);
  C.FillRect(TRectF.Create(CX-12*S, CY-10*S, CX-8*S, CY+10*S), 2,2,AllCorners,1);

  // Toast pops out periodically
  if Sin(FT * 0.04) > 0.85 then
  begin
    C.Fill.Color   := RGB(245, 200, 66);
    C.Stroke.Color := RGB(184, 134, 11);
    C.Stroke.Thickness := 0.8;
    C.FillRect(TRectF.Create(CX-5*S, CY-22*S, CX-1*S, CY-13*S), 1,1,AllCorners,1);
    C.DrawRect( TRectF.Create(CX-5*S, CY-22*S, CX-1*S, CY-13*S), 1,1,AllCorners,1);
    C.FillRect(TRectF.Create(CX+2*S, CY-20*S, CX+6*S, CY-11*S), 1,1,AllCorners,1);
    C.DrawRect( TRectF.Create(CX+2*S, CY-20*S, CX+6*S, CY-11*S), 1,1,AllCorners,1);
  end;
end;

procedure TSprite.Draw(C: TCanvas);
var
  Emoji: string;
  Sz: Single;
begin
  if FKind = skToaster then
  begin
    DrawToaster(C);
    Exit;
  end;
  Emoji := IfThen(FKind = skCat, '🐱', '🐸');
  Sz    := Round(36 * FScl);
  C.Font.Size   := Sz;
  {$IFDEF MSWINDOWS}
  C.Font.Family := 'Segoe UI Emoji';
  {$ELSE}
  C.Font.Family := 'Apple Color Emoji';
  {$ENDIF}
  C.Fill.Kind  := TBrushKind.Solid;
  C.Fill.Color := TAlphaColors.White;
  C.FillText(
    TRectF.Create(FX - Sz, FY - Sz, FX + Sz, FY + Sz),
    Emoji, False, 1.0, [], TTextAlign.Center, TTextAlign.Center);
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
  FRemBtn.Text        := '− Remove';
  FRemBtn.Width       := 120;
  FRemBtn.Height      := 40;
  FRemBtn.Position.X  := Screen.WorkAreaWidth / 2 - 135;
  FRemBtn.Position.Y  := 10;
  FRemBtn.OnClick     := BtnRemClick;

  FAddBtn             := TButton.Create(Self);
  FAddBtn.Parent      := FBtnLayout;
  FAddBtn.Text        := '+ Add';
  FAddBtn.Width       := 120;
  FAddBtn.Height      := 40;
  FAddBtn.Position.X  := Screen.WorkAreaWidth / 2 + 15;
  FAddBtn.Position.Y  := 10;
  FAddBtn.OnClick     := BtnAddClick;

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

procedure TMainForm.UpdateCount;
begin
  FCountLbl.Text := Format('%d ribbon%s', [FWorms.Count,
    IfThen(FWorms.Count <> 1, 's', '')]);
end;

procedure TMainForm.BtnAddClick(Sender: TObject); begin AddWorm; end;
procedure TMainForm.BtnRemClick(Sender: TObject); begin RemoveWorm; end;

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
