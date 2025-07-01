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
        // G코드 파싱 로직 (필요시 별도 함수 사용)
        // 예: 모달 상태 갱신, 거리 모드 확인 등
        // 상태 초기화
        stTargetPos := stStartPos;
        stGeoOut.dVel := stCurrentState.fFeedRate;
        stGeoOut.dAccel := 1000.0;
        stGeoOut.dDecel := 1000.0;

        // 예시: G90/91 거리 모드 해석
        IF stInputBlock.bHasX THEN
            IF stCurrentState.eDistanceMode = E_DistanceMode.G90_ABSOLUTE THEN
                stTargetPos.dX := stInputBlock.valX;
            ELSE
                stTargetPos.dX := stTargetPos.dX + stInputBlock.valX;
            END_IF;
        END_IF;
        // 동일 방식으로 Y, Z 처리 예정

        eState := ENHANCE;

    ENHANCE:
        // 모달 상태 보정 (G00, G01, G02, G03 등 처리)
        // 예: G1 -> LINEAR, G2/G3 -> ARC 등
        // 필요 시 에러 처리 포함
        eState := EXECUTE;

    EXECUTE:
        // GeoInfo 구조체 생성
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
