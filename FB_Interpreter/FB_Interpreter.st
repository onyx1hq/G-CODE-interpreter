(**********************************************************************)
(* FB_Interpreter - G-code 인터프리터 (LinuxCNC 기반 구조 반영)        *)
(**********************************************************************)
FUNCTION_BLOCK FB_Interpreter
VAR_INPUT
    stInputBlock     : ST_GcodeBlock;       // 해석 대상 G코드 블록
    stStartPos       : SM3_CNC.SMC_POSINFO; // 현재 좌표
    bEnable          : BOOL;                // 인터프리터 실행 트리거
END_VAR
VAR_OUTPUT
    stGeoOut         : SM3_CNC.SMC_GEOINFO; // 결과 위치 및 모션 정보
    bValid           : BOOL;                // GeoInfo 유효 여부
    bBusy            : BOOL;
    bDone            : BOOL;
    bError           : BOOL;
    eErrorID         : E_InterpreterError;  // 사용자 정의 에러 enum
END_VAR
VAR
    eState           : (IDLE, PARSE, ENHANCE, EXECUTE, DONE, ERROR) := IDLE;
    stCurrentState   : ST_InterpreterState; // 현재 모달 상태 저장 구조체
    stTargetPos      : SM3_CNC.SMC_POSINFO; // 목표 좌표
    dArcC1, dArcC2   : LREAL;               // 원호 중심 계산 변수
    rtTrig           : R_TRIG;
    i                : INT;
END_VAR

// Rising edge trigger
rtTrig(CLK := bEnable);

CASE eState OF

    IDLE:
        bBusy := FALSE;
        bDone := FALSE;
        bError := FALSE;
        bValid := FALSE;
        IF rtTrig.Q THEN
            eState := PARSE;
        END_IF;

    PARSE:
        bBusy := TRUE;
        stTargetPos := stStartPos;

        // 기본 feedrate 및 가속도 설정 (단위: mm/s, mm/s^2)
        stGeoOut.dVel := stCurrentState.fFeedRate;   // mm/s 단위로 전달됨
        stGeoOut.dAccel := 1000.0;
        stGeoOut.dDecel := 1000.0;

        // G90/91 거리 모드에 따른 목표 위치 계산
        IF stInputBlock.bHasX THEN
            IF stCurrentState.eDistanceMode = E_DistanceMode.G90_ABSOLUTE THEN
                stTargetPos.dX := stInputBlock.valX;
            ELSE
                stTargetPos.dX := stTargetPos.dX + stInputBlock.valX;
            END_IF;
        END_IF;
        IF stInputBlock.bHasY THEN
            IF stCurrentState.eDistanceMode = E_DistanceMode.G90_ABSOLUTE THEN
                stTargetPos.dY := stInputBlock.valY;
            ELSE
                stTargetPos.dY := stTargetPos.dY + stInputBlock.valY;
            END_IF;
        END_IF;
        IF stInputBlock.bHasZ THEN
            IF stCurrentState.eDistanceMode = E_DistanceMode.G90_ABSOLUTE THEN
                stTargetPos.dZ := stInputBlock.valZ;
            ELSE
                stTargetPos.dZ := stTargetPos.dZ + stInputBlock.valZ;
            END_IF;
        END_IF;

        eState := ENHANCE;

    ENHANCE:
        // G 코드에 따른 모드 변경 적용
        FOR i := 0 TO stInputBlock.nGCount - 1 DO
            CASE stInputBlock.aGCommands[i] OF
                GVL_Gcode.G00_VAL: stCurrentState.eMoveMode := E_MoveMode.G00_RAPID;
                GVL_Gcode.G01_VAL: stCurrentState.eMoveMode := E_MoveMode.G01_LINEAR;
                GVL_Gcode.G02_VAL: stCurrentState.eMoveMode := E_MoveMode.G02_CW_ARC;
                GVL_Gcode.G03_VAL: stCurrentState.eMoveMode := E_MoveMode.G03_CCW_ARC;
                GVL_Gcode.G17_VAL: stCurrentState.ePlane := E_Plane.G17_XY;
                GVL_Gcode.G18_VAL: stCurrentState.ePlane := E_Plane.G18_XZ;
                GVL_Gcode.G19_VAL: stCurrentState.ePlane := E_Plane.G19_YZ;
                GVL_Gcode.G90_VAL: stCurrentState.eDistanceMode := E_DistanceMode.G90_ABSOLUTE;
                GVL_Gcode.G91_VAL: stCurrentState.eDistanceMode := E_DistanceMode.G91_INCREMENTAL;
            END_CASE;
        END_FOR;

        // Feedrate 갱신 (단위 환산: G코드는 일반적으로 mm/min, 인터폴레이터는 mm/s)
        IF stInputBlock.bHasF THEN
            stCurrentState.fFeedRate := stInputBlock.valF / 60.0; // mm/min → mm/s
        END_IF;

        eState := EXECUTE;

    EXECUTE:
        stGeoOut.piStartPos := stStartPos;
        stGeoOut.piDestPos := stTargetPos;
        stGeoOut.iMoveType := SM3_CNC.SMC_MOVTYP.LIN;
        bValid := TRUE;
        eState := DONE;

    DONE:
        bDone := TRUE;
        bBusy := FALSE;
        IF NOT bEnable THEN eState := IDLE; END_IF;

    ERROR:
        bError := TRUE;
        bBusy := FALSE;
        IF NOT bEnable THEN eState := IDLE; END_IF;

END_CASE;
