# V-160HD Remote Control Guide

**Model:** V-160HD  
**Date:** Apr. 11, 2025  
**Version:** 3.30

© 2021 Roland Corporation

---

## Contents

1. [MIDI Implementation](#midi-implementation)
   - MIDI Messages Received at MIDI IN
   - Parameter Address Map
   - Supplementary Material
   - MIDI Implementation Chart
2. [LAN/RS-232 Command Reference](#lanrs-232-command-reference)
   - LAN Interface
   - RS-232 Interface
   - Command Format
   - List of Commands

---

## MIDI Implementation

### Symbol Item Setting Range

- **n** - MIDI Channel: Fixed at 00H

### 1. MIDI Messages Received at MIDI IN

#### System Exclusive Messages

**Status Data Byte Status**

```
F0H iiH,ddH,...,eeH F7H
```

- **F0H:** Status of system exclusive message
- **ii:** ID number (manufacturer ID) - Roland is 41H
  - 7EH and 7FH are used as universal non-realtime message (7EH) or universal realtime message (7FH)
- **dd,...,ee:** data: 00H–7FH (0–127)
- **F7H:** EOX (end of exclusive)

#### Data Request 1 (RQ1)

This is the message to request "send data" to the connected device. Specify data type and amount using address and size. When this is received, the unit sends the requested data as "Data Set 1 (DT1)" message if the unit is in status where sending of data is possible and requested address and size are appropriate.

**Status Data Byte Status**

```
F0H 41H, 10H, 00H, 00H, 00H, 00H, 02H, 11H, aaH, bbH, ccH, ssH, ttH, uuH, sum F7H
```

| Byte | Explanation |
|------|-------------|
| F0H | Exclusive Status |
| 41H | Manufacturer ID (Roland) |
| 10H | Device ID |
| 00H | 1st byte of model ID (V-160HD) |
| 00H | 2nd byte of model ID (V-160HD) |
| 00H | 3rd byte of model ID (V-160HD) |
| 00H | 4th byte of model ID (V-160HD) |
| 02H | 5th byte of model ID (V-160HD) |
| 11H | Command ID (RQ1) |
| aaH | Address upper byte |
| bbH | Address middle byte |
| ccH | Address lower byte |
| ssH | Size upper byte |
| ttH | Size middle byte |
| uuH | Size lower byte |
| sum | Checksum |
| F7H | EOX (end of exclusive) |

**Notes:**
- Depending on the data type, the amount of single-time transmission is specified
- It is necessary to execute data request according to the specified first address and size
- Refer to the "Parameter Address Map" for address and size
- See "Example of an Exclusive Message and Calculating a Checksum" for checksum

#### Data Set 1 (DT1)

This is the message of actual data transmission. Use this when you want to set data to the unit.

**Status Data Byte Status**

```
F0H 41H, 10H, 00H, 00H, 00H, 00H, 02H, 12H, aaH, bbH, ccH, ddH, ..., eeH, sum F7H
```

| Byte | Explanation |
|------|-------------|
| F0H | Exclusive Status |
| 41H | Manufacturer ID (Roland) |
| 10H | Device ID |
| 00H | 1st byte of model ID (V-160HD) |
| 00H | 2nd byte of model ID (V-160HD) |
| 00H | 3rd byte of model ID (V-160HD) |
| 00H | 4th byte of model ID (V-160HD) |
| 02H | 5th byte of model ID (V-160HD) |
| 12H | Command ID (DT1) |
| aaH | Address upper byte |
| bbH | Address middle byte |
| ccH | Address lower byte |
| ddH | Data: actual data to transmit. Multiple byte data is sent in address order. |
| ... | ... |
| eeH | Data |
| sum | Checksum |
| F7H | EOX (end of exclusive) |

**Notes:**
- Depending on the data type, the amount of single-time transmission is specified
- It is necessary to execute data request according to the specified first address and size
- Refer to the "Parameter Address Map" for address and size
- See "Example of an Exclusive Message and Calculating a Checksum" for checksum
- Data exceeding 256 bytes should be divided into packets of 256 bytes or smaller
- If you send data set 1 successively, set interval of 20 msec or longer between packets

---

## 2. Parameter Address Map

### Address Map Overview

| Start Address | Description |
|--------------|-------------|
| 00H 00H 00H | Video Parameter Area |
| 01H 00H 00H | Audio Parameter Area |
| 02H 00H 00H | System Parameter Area |
| 0AH 00H 00H | Other Parameter Area |
| 0BH 00H 00H | Panel Control Area |
| 0CH 00H 00H | Tally Area |
| 0DH 00H 00H | Camera Control Area |
| 10H 00H 00H | Video Parameter (Memory 1) |
| 11H 00H 00H | Audio Parameter (Memory 1) |
| 12H 00H 00H | Video Parameter (Memory 2) |
| 13H 00H 00H | Audio Parameter (Memory 2) |
| ... | ... |
| 4AH 00H 00H | Video Parameter (Memory 30) |
| 4BH 00H 00H | Audio Parameter (Memory 30) |
| 50H 00H 00H | Macro Area |
| 60H 00H 00H | Memory Name |

---

### Video Parameter Area

#### VIDEO ASSIGN

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H 00H 00H | INPUT 1 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 01H | INPUT 2 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 02H | INPUT 3 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 03H | INPUT 4 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 04H | INPUT 5 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 05H | INPUT 6 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 06H | INPUT 7 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 07H | INPUT 8 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 08H | INPUT 9 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 09H | INPUT 10 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 0AH | HDMI OUTPUT 1 ASSIGN | 00H–0AH | PROGRAM, SUB PROGRAM, PREVIEW, AUX1–3, DSK 1, 2 SOURCE, MULTI-VIEW, 16 INPUT-VIEW, 16 STILL-VIEW |
| 00H 00H 0BH | HDMI OUTPUT 2 ASSIGN | 00H–0AH | PROGRAM, SUB PROGRAM, PREVIEW, AUX1–3, DSK 1, 2 SOURCE, MULTI-VIEW, 16 INPUT-VIEW, 16 STILL-VIEW |
| 00H 00H 0CH | HDMI OUTPUT 3 ASSIGN | 00H–0AH | PROGRAM, SUB PROGRAM, PREVIEW, AUX1–3, DSK 1, 2 SOURCE, MULTI-VIEW, 16 INPUT-VIEW, 16 STILL-VIEW |
| 00H 00H 0DH | SDI OUTPUT 1 ASSIGN | 00H–0AH | PROGRAM, SUB PROGRAM, PREVIEW, AUX1–3, DSK 1, 2 SOURCE, MULTI-VIEW, 16 INPUT-VIEW, 16 STILL-VIEW |
| 00H 00H 0EH | SDI OUTPUT 2 ASSIGN | 00H–0AH | PROGRAM, SUB PROGRAM, PREVIEW, AUX1–3, DSK 1, 2 SOURCE, MULTI-VIEW, 16 INPUT-VIEW, 16 STILL-VIEW |
| 00H 00H 0FH | SDI OUTPUT 3 ASSIGN | 00H–0AH | PROGRAM, SUB PROGRAM, PREVIEW, AUX1–3, DSK 1, 2 SOURCE, MULTI-VIEW, 16 INPUT-VIEW, 16 STILL-VIEW |
| 00H 01H 10H | USB OUTPUT ASSIGN | 00H–0AH | PROGRAM, SUB PROGRAM, PREVIEW, AUX1–3, DSK 1, 2 SOURCE, MULTI-VIEW, 16 INPUT-VIEW, 16 STILL-VIEW |
| 00H 00H 11H | AUX 1 SOURCE | 00H–33H | HDMI 1–8, SDI 1–8, STILL 1–16, INPUT 1–20 |
| 00H 00H 12H | PROGRAM LAYER PinP & KEY 1 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 13H | PROGRAM LAYER PinP & KEY 2 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 14H | PROGRAM LAYER PinP & KEY 3 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 15H | PROGRAM LAYER PinP & KEY 4 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 16H | PROGRAM LAYER DSK 1 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 17H | PROGRAM LAYER DSK 2 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 18H | SUB PROGRAM LAYER PinP & KEY 1 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 19H | SUB PROGRAM LAYER PinP & KEY 2 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 1AH | SUB PROGRAM LAYER PinP & KEY 3 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 1BH | SUB PROGRAM LAYER PinP & KEY 4 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 1CH | SUB PROGRAM LAYER DSK 1 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 1DH | SUB PROGRAM LAYER DSK 2 | 00H–01H | DISABLE, ENABLE |
| 00H 00H 1EH | AUX 1 LAYER PinP & KEY 1 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 1FH | AUX 1 LAYER PinP & KEY 2 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 20H | AUX 1 LAYER PinP & KEY 3 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 21H | AUX 1 LAYER PinP & KEY 4 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 22H | AUX 1 LAYER DSK 1 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 23H | AUX 1 LAYER DSK 2 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 24H | INPUT 11 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 25H | INPUT 12 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 26H | INPUT 13 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 27H | INPUT 14 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 28H | INPUT 15 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 29H | INPUT 16 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 2AH | INPUT 17 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 2BH | INPUT 18 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 2CH | INPUT 19 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 2DH | INPUT 20 ASSIGN | 00H–20H | HDMI 1–8, SDI 1–8, STILL 1–16, N/A |
| 00H 00H 2EH | AUX 2 SOURCE | 00H–33H | HDMI 1–8, SDI 1–8, STILL 1–16, INPUT 1–20 |
| 00H 00H 2FH | AUX 3 SOURCE | 00H–33H | HDMI 1–8, SDI 1–8, STILL 1–16, INPUT 1–20 |
| 00H 00H 30H | AUX 2 LAYER PinP & KEY 1 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 31H | AUX 2 LAYER PinP & KEY 2 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 32H | AUX 2 LAYER PinP & KEY 3 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 33H | AUX 2 LAYER PinP & KEY 4 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 34H | AUX 2 LAYER DSK 1 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 35H | AUX 2 LAYER DSK 2 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 36H | AUX 3 LAYER PinP & KEY 1 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 37H | AUX 3 LAYER PinP & KEY 2 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 38H | AUX 3 LAYER PinP & KEY 3 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 39H | AUX 3 LAYER PinP & KEY 4 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 3AH | AUX 3 LAYER DSK 1 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |
| 00H 00H 3BH | AUX 3 LAYER DSK 2 | 00H–02H | DISABLE, ENABLE, ALWAYS ON |

#### VIDEO INPUT (HDMI)

**xxH: 01H–04H (HDMI IN 1–4)**

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H xxH 00H | FLIP H | 00H–01H | OFF, ON |
| 00H xxH 01H | FLIP V | 00H–01H | OFF, ON |
| 00H xxH 02H | BRIGHTNESS | 60H–00H–1FH | -32–0–31 |
| 00H xxH 03H | CONTRAST | 60H–00H–1FH | -32–0–31 |
| 00H xxH 04H | SATURATION | 60H–00H–1FH | -32–0–31 |
| 00H xxH 05H | COLOR SPACE | 00H–04H | AUTO, RGB (0-255), RGB (16-235), YPbPr (SD), YPbPr (HD) |

#### VIDEO INPUT (SCALER)

**xxH: 05H–08H (HDMI IN 5–8)**

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H xxH 00H | FLICKER FILTER | 00H–01H | OFF, ON |
| 00H xxH 01H | FLIP H | 00H–01H | OFF, ON |
| 00H xxH 02H | FLIP V | 00H–01H | OFF, ON |
| 00H xxH 03H | EDID | 00H–0BH | INTERNAL, SVGA (800 x 600), XGA (1024 x 768), WXGA (1280 x 800), FWXGA (1366 x 768), SXGA (1280 x 1024), SXGA+ (1400 x 1050), UXGA (1600 x 1200), WUXGA (1920 x 1200), 720p, 1080i, 1080p |
| 00H xxH 04H 05H | ZOOM | 00H 64H–4EH 10H | 10.0–1000.0% |
| 00H xxH 06H | SCALING TYPE | 00H–04H | FULL, LETTER BOX, CROP, DOT BY DOT, MANUAL |
| 00H xxH 07H 08H | MANUAL SIZE H | 70H 30H–00H 00H–0FH 50H | -2000–0–2000 |
| 00H xxH 09H 0AH | MANUAL SIZE V | 70H 30H–00H 00H–0FH 50H | -2000–0–2000 |
| 00H xxH 0BH 0CH | POSITION H | 71H 00H–00H 00H–0FH 00H | -1920–0–1920 |
| 00H xxH 0DH 0EH | POSITION V | 76H 50H–00H 00H–09H 30H | -1200–0–1200 |
| 00H xxH 0FH | BRIGHTNESS | 60H–00H–1FH | -32–0–31 |
| 00H xxH 10H | CONTRAST | 60H–00H–1FH | -32–0–31 |
| 00H xxH 11H | SATURATION | 60H–00H–1FH | -32–0–31 |
| 00H xxH 12H | RED | 40H–00H–3FH | -64–0–63 |
| 00H xxH 13H | GREEN | 40H–00H–3FH | -64–0–63 |
| 00H xxH 14H | BLUE | 40H–00H–3FH | -64–0–63 |
| 00H xxH 15H | COLOR SPACE | 00H–04H | AUTO, RGB (0-255), RGB (16-235), YPbPr (SD), YPbPr (HD) |
| 00H xxH 16H | TEST PATTERN | 00H–05H | OFF, 75% COLOR BAR, 100% COLOR BAR, RAMP, STEP, HATCH |

#### VIDEO INPUT (SDI)

**xxH: 09H–10H (SDI IN 1–8)**

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H xxH 00H | FLIP H | 00H–01H | OFF, ON |
| 00H xxH 01H | FLIP V | 00H–01H | OFF, ON |
| 00H xxH 02H | BRIGHTNESS | 60H–00H–1FH | -32–0–31 |
| 00H xxH 03H | CONTRAST | 60H–00H–1FH | -32–0–31 |
| 00H xxH 04H | SATURATION | 60H–00H–1FH | -32–0–31 |

#### VIDEO OUTPUT (HDMI)

**xxH: 11H–13H (HDMI OUT 1–3)**

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H xxH 00H | COLOR SPACE | 00H–03H | YPbPr (4:4:4), YPbPr (4:2:2), RGB (0-255), RGB (16-235) |
| 00H xxH 01H | DVI-D/HDMI SIGNAL | 00H–01H | HDMI, DVI-D |
| 00H xxH 02H | BRIGHTNESS | 40H–00H–3FH | -64–0–63 |
| 00H xxH 03H | CONTRAST | 40H–00H–3FH | -64–0–63 |
| 00H xxH 04H | SATURATION | 40H–00H–3FH | -64–0–63 |
| 00H xxH 05H | RED | 40H–00H–3FH | -64–0–63 |
| 00H xxH 06H | GREEN | 40H–00H–3FH | -64–0–63 |
| 00H xxH 07H | BLUE | 40H–00H–3FH | -64–0–63 |
| 00H xxH 08H | REC CONTROL | 00H–01H | OFF, ON |

#### VIDEO OUTPUT (SDI)

**xxH: 14H–16H (SDI OUT 1–3)**

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H xxH 00H | 3G-SDI MAPPING | 00H–01H | LEVEL-A, LEVEL-B |
| 00H xxH 01H | BRIGHTNESS | 40H–00H–3FH | -64–0–63 |
| 00H xxH 02H | CONTRAST | 40H–00H–3FH | -64–0–63 |
| 00H xxH 03H | SATURATION | 40H–00H–3FH | -64–0–63 |

#### TRANSITION TIME

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H 17H 00H | MIX/WIPE TIME | 00H–28H | 0.0–4.0sec |
| 00H 17H 01H | PinP & KEY 1 TIME | 00H–28H | 0.0–4.0sec |
| 00H 17H 02H | PinP & KEY 2 TIME | 00H–28H | 0.0–4.0sec |
| 00H 17H 03H | PinP & KEY 3 TIME | 00H–28H | 0.0–4.0sec |
| 00H 17H 04H | PinP & KEY 4 TIME | 00H–28H | 0.0–4.0sec |
| 00H 17H 05H | DSK 1 TIME | 00H–28H | 0.0–4.0sec |
| 00H 17H 06H | DSK 2 TIME | 00H–28H | 0.0–4.0sec |
| 00H 17H 07H | OUTPUT FADE TIME | 00H–28H | 0.0–4.0sec |

#### MIX/WIPE

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H 18H 00H | TRANSITION TYPE | 00H–01H | MIX, WIPE |
| 00H 18H 01H | MIX TYPE | 00H–02H | MIX, FAM, NAM |
| 00H 18H 02H | WIPE TYPE | 00H–07H | HORIZONTAL, VERTICAL, UPPER LEFT, UPPER RIGHT, LOWER LEFT, LOWER RIGHT, H-CENTER, V-CENTER |
| 00H 18H 03H | WIPE DIRECTION | 00H–02H | NORMAL, REVERSE, ROUND TRIP |
| 00H 18H 04H | WIPE BORDER COLOR | 00H–09H | WHITE, YELLOW, CYAN, GREEN, MAGENTA, RED, BLUE, BLACK, CUSTOM, SOFT EDGE |
| 00H 18H 05H | WIPE BORDER WIDTH | 00H–0EH | 0–14 |
| 00H xxH 06H 07H | WIPE BORDER COLOR RED | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 08H 09H | WIPE BORDER COLOR GREEN | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 0AH 0BH | WIPE BORDER COLOR BLUE | 00H 00H–01H 7FH | 0–255 |

#### SPLIT

**xxH: 19H–1AH (SPLIT 1, 2)**

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H xxH 00H | SPLIT SW | 00H–01H | OFF, ON |
| 00H xxH 01H | SPLIT TYPE | 00H–01H | SPLIT V, SPLIT H |
| 00H xxH 02H 03H | PGM/A-CENTER | 7CH 0CH–00H 00H–03H 74H | -50.0–0.0–50.0% |
| 00H xxH 04H 05H | PST/B-CENTER | 7CH 0CH–00H 00H–03H 74H | -50.0–0.0–50.0% |
| 00H xxH 06H 07H | CENTER POSITION | 7CH 0CH–00H 00H–03H 74H | -50.0–0.0–50.0% |
| 00H xxH 08H | BORDER COLOR | 00H–08H | WHITE, YELLOW, CYAN, GREEN, MAGENTA, RED, BLUE, BLACK, CUSTOM |
| 00H xxH 09H | BORDER WIDTH | 00H–0EH | 0–14 |
| 00H xxH 0AH 0BH | BORDER COLOR RED | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 0CH 0DH | BORDER COLOR GREEN | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 0EH 0FH | BORDER COLOR BLUE | 00H 00H–01H 7FH | 0–255 |

#### PinP & KEY

**xxH: 1BH–1EH (PinP & KEY 1–4)**

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H xxH 00H | PGM SW | 00H–01H | OFF, ON |
| 00H xxH 01H | PVW SW | 00H–01H | OFF, ON |
| 00H xxH 02H | SOURCE | 00H–33H | HDMI 1–8, SDI 1–8, STILL 1–16, INPUT 1–20 |
| 00H xxH 03H | TYPE | 00H–03H | PinP, LUMINANCE-WHITE KEY, LUMINANCE-BLACK KEY, CHROMA KEY |
| 00H xxH 04H 05H | POSITION H | 78H 18H–00H 00H–07H 68H | -100.0–0.0–100.0% |
| 00H xxH 06H 07H | POSITION V | 78H 18H–00H 00H–07H 68H | -100.0–0.0–100.0% |
| 00H xxH 08H 09H | SIZE | 00H 00H–07H 68H | 0.0–100.0% |
| 00H xxH 0AH 0BH | CROPPING H | 00H 00H–07H 68H | 0.0–100.0% |
| 00H xxH 0CH 0DH | CROPPING V | 00H 00H–07H 68H | 0.0–100.0% |
| 00H xxH 0EH | SHAPE | 00H–02H | RECTANGLE, CIRCLE, DIAMOND |
| 00H xxH 0FH | BORDER COLOR | 00H–09H | WHITE, YELLOW, CYAN, GREEN, MAGENTA, RED, BLUE, BLACK, CUSTOM, SOFT EDGE |
| 00H xxH 10H | BORDER WIDTH | 00H–0EH | 0–14 |
| 00H xxH 11H 12H | VIEW POSITION H | 7CH 0CH–00H 00H–03H 74H | -50.0–0.0–50.0% |
| 00H xxH 13H 14H | VIEW POSITION V | 7CH 0CH–00H 00H–03H 74H | -50.0–0.0–50.0% |
| 00H xxH 15H 16H | VIEW ZOOM | 00H 64H–03H 10H | 100–400% |
| 00H xxH 17H 18H | KEY LEVEL | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 19H 1AH | KEY GAIN | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 1BH 1CH | MIX LEVEL | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 1DH | CHROMA COLOR | 00H–01H | GREEN, BLUE |
| 00H xxH 1EH | HUE WIDTH | 62H–00H–1EH | -30–0–30 |
| 00H xxH 1FH 20H | HUE FINE | 00H 00H–02H 68H | 0–360 |
| 00H xxH 21H 22H | SATURATION WIDTH | 7FH 00H–00H 00H–00H 7FH | -128–0–127 |
| 00H xxH 23H 24H | SATURATION FINE | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 25H 26H | BORDER COLOR RED | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 27H 28H | BORDER COLOR GREEN | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 29H 2AH | BORDER COLOR BLUE | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 2BH 2CH | VALUE WIDTH | 7FH 00H–00H 00H–00H 7FH | -128–0–127 |
| 00H xxH 2DH 2EH | VALUE FINE | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 2FH | DESPILL | 00H–01H | OFF, ON |

#### DSK

**xxH: 1FH–20H (DSK 1, 2)**

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H xxH 00H | PGM SW | 00H–01H | OFF, ON |
| 00H xxH 01H | PVW SW | 00H–01H | OFF, ON |
| 00H xxH 02H | DSK MODE | 00H–02H | SELF KEY, ALPHA KEY, EXTERNAL KEY |
| 00H xxH 03H | KEY SOURCE | 00H–33H | HDMI 1–8, SDI 1–8, STILL 1–16 (*1), INPUT 1–20 |
| 00H xxH 04H | FILL SOURCE (*2) | 00H–33H | HDMI 1–8, SDI 1–8, STILL 1–16, INPUT 1–20 |
| 00H xxH 05H | DSK TYPE (*3) | 00H–02H | LUMINANCE-WHITE KEY, LUMINANCE-BLACK KEY, CHROMA KEY |
| 00H xxH 06H 07H | DSK LEVEL | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 08H 09H | DSK GAIN | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 0AH 0BH | MIX LEVEL | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 0CH | CHROMA COLOR | 00H–01H | GREEN, BLUE |
| 00H xxH 0DH | HUE WIDTH | 62H–00H–1EH | -30–0–30 |
| 00H xxH 0EH 0FH | HUE FINE | 00H 00H–02H 68H | 0–360 |
| 00H xxH 10H 11H | SATURATION WIDTH | 7FH 00H–00H 00H–00H 7FH | -128–0–127 |
| 00H xxH 12H 13H | SATURATION FINE | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 14H | FILL TYPE | 00H–01H | BUS, MATTE |
| 00H xxH 15H | MATTE COLOR | 00H–08H | WHITE, YELLOW, CYAN, GREEN, MAGENTA, RED, BLUE, BLACK, CUSTOM |
| 00H xxH 16H | EDGE TYPE | 00H–04H | OFF, BORDER, DROP, SHADOW, OUTLINE |
| 00H xxH 17H | EDGE COLOR | 00H–08H | WHITE, YELLOW, CYAN, GREEN, MAGENTA, RED, BLUE, BLACK, CUSTOM |
| 00H xxH 18H | EDGE WIDTH | 00H–07H | 0–7 |
| 00H xxH 19H | (reserved) | | |
| 00H xxH 1AH 1BH | MATTE COLOR RED | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 1CH 1DH | MATTE COLOR GREEN | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 1EH 1FH | MATTE COLOR BLUE | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 20H 21H | EDGE COLOR RED | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 22H 23H | EDGE COLOR GREEN | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 24H 25H | EDGE COLOR BLUE | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 26H 27H | VALUE WIDTH | 7FH 00H–00H 00H–00H 7FH | -128–0–127 |
| 00H xxH 28H 29H | VALUE FINE | 00H 00H–01H 7FH | 0–255 |
| 00H xxH 2AH | DESPILL | 00H–01H | OFF, ON |

**Notes:**
- (*1) When "DSK MODE" is set to "ALPHA KEY", only "STILL 1–16" is available
- (*2) This can be set if "DSK MODE" is "EXTERNAL KEY"
- (*3) This can be set if "DSK MODE" is "SELF KEY"

#### Panel

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 00H 21H 00H | PGM Select | 00H–33H | HDMI 1–8, SDI 1–8, STILL 1–16, INPUT 1–20 |
| 00H 21H 01H | PST Select | 00H–33H | HDMI 1–8, SDI 1–8, STILL 1–16, INPUT 1–20 |
| 00H 21H 02H 03H | AB Fader Level | 00H 00H–0FH 7FH | 0–2047 |
| 00H 21H 04H | AB Bus Select | 00H–01H | A bus, B bus |
| 00H 21H 05H | DISSOLVE TAKE TYPE | 00H–01H | CUT, AUTO |

---

### Audio Parameter Area

#### AUDIO INPUT

**xxH: 00H–14H (AUDIO IN 1–3/4, USB IN, Bluetooth IN, HDMI IN 1–8, SDI IN 1–8)**

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 01H xxH 00H | ANALOG GAIN (*1) | 00H–40H | 0–64dB |
| 01H xxH 01H 02H | DIGITAL GAIN | 7CH 5CH–00H 00H–03H 24H | -42.0–0.0–42.0dB |
| 01H xxH 03H 04H 05H | INPUT LEVEL | 7EH 00H 00H, 7FH 79H 60H–00H 00H 00H–00H 00H 64H | -INFdB, -80.0–0.0–10.0dB |
| 01H xxH 06H | INPUT MUTE | 00H–01H | OFF, ON |
| 01H xxH 07H | PHANTOM +48V (*1) | 00H–01H | OFF, ON |
| 01H xxH 08H | PAN (*1) | 00H–32H–64H | LEFT–CENTER–RIGHT |
| 01H xxH 09H | STEREO LINK (*2) | 00H–01H | OFF, ON |
| 01H xxH 0AH | MONO (*3) | 00H–03H | OFF, L ONLY, R ONLY, LR MIX |
| 01H xxH 0BH | SOLO | 00H–01H | OFF, ON |
| 01H xxH 0CH | EFFECT PRESET | 00H–04H | DEFAULT, MEETING, INTERVIEW, AMBIENT MIC, WINDY FIELD |
| 01H xxH 0DH 0EH | DELAY | 00H 00H–27H 08H | 0.0–500.0msec |
| 01H xxH 0FH | REVERB SEND | 00H–7FH | 0–127 |
| 01H xxH 10H | HIGH PASS FILTER 80Hz | 00H–01H | OFF, ON |
| 01H xxH 11H | ECHO CANCELLER SW (*1) | 00H–01H | OFF, ON |
| 01H xxH 12H | ECHO CANCELLER DEPTH (*1) | 01H–0AH | 1–10 |
| 01H xxH 13H | ANTI-FEEDBACK (*1) | 00H–01H | OFF, ON |
| 01H xxH 14H | DE-ESSER SW (*1) | 00H–01H | OFF, ON |
| 01H xxH 15H | DE-ESSER SENS (*1) | 00H–64H | 0–100 |
| 01H xxH 16H | DE-ESSER DEPTH (*1) | 00H–64H | 0–100 |
| 01H xxH 17H | NOISE GATE SW | 00H–01H | OFF, ON |
| 01H xxH 18H | NOISE GATE THRESHOLD | 30H–00H | -80–0dB |
| 01H xxH 19H | NOISE GATE RELEASE | 00H–7FH | 30–5000msec |
| 01H xxH 1AH | COMPRESSOR SW | 00H–01H | OFF, ON |
| 01H xxH 1BH | COMPRESSOR THRESHOLD | 4EH–00H | -50–0dB |
| 01H xxH 1CH | COMPRESSOR RATIO | 00H–0DH | 1.00:1, 1.12:1, 1.25:1, 1.40:1, 1.60:1, 1.80:1, 2.00:1, 2.50:1, 3.20:1, 4.00:1, 5.60:1, 8.00:1, 16.0:1, INF:1 |
| 01H xxH 1DH | COMPRESSOR ATTACK | 00H–73H | 0.0–100msec |
| 01H xxH 1EH | COMPRESSOR RELEASE | 00H–7FH | 30–5000msec |
| 01H xxH 1FH | COMPRESSOR MAKEUP GAIN | 58H–00H–28H | -40–0–40dB |
| 01H xxH 20H | EQUALIZER SW | 00H–01H | OFF, ON |
| 01H xxH 21H | EQUALIZER Hi GAIN | 04H–7CH | -12.0–12dB |
| 01H xxH 22H | EQUALIZER Hi FREQUENCY | 24H–3EH | 1.00–20.0kHz |
| 01H xxH 23H | EQUALIZER Mid GAIN | 04H–7CH | -12.0–12dB |
| 01H xxH 24H | EQUALIZER Mid FREQUENCY | 02H–3EH | 20Hz–20.0kHz |
| 01H xxH 25H | EQUALIZER Mid Q | 00H–05H | 0.5, 1.0, 2.0, 4.0, 8.0, 16.0 |
| 01H xxH 26H | EQUALIZER Lo GAIN | 04H–7CH | -12.0–12dB |
| 01H xxH 27H | EQUALIZER Lo FREQUENCY | 02H–2AH | 20Hz–2.00kHz |
| 01H xxH 28H | VOICE CHANGER SW (*1) | 00H–01H | OFF, ON |
| 01H xxH 29H | VOICE CHANGER PITCH (*1) | 74H–00H–0CH | -12–0–+12 |
| 01H xxH 2AH | VOICE CHANGER FORMANT (*1) | 76H–00H–0AH | -10–0–+10 |
| 01H xxH 2BH | VOICE CHANGER ROBOT (*1) | 00H–01H | OFF, ON |
| 01H xxH 2CH | VOICE CHANGER MIX (*1) | 00H–64H | 0–100 |
| 01H xxH 2DH | EMBEDDED AUDIO SELECT (*4) | 00H–03H | 1/2, 3/4, 5/6, 7/8 |
| 01H xxH 2EH | MAIN SEND | 00H–01H | OFF, ON |

**Notes:**
- (*1) AUDIO IN 1, 2 only
- (*2) AUDIO IN 1 only
- (*3) Stereo audio only
- (*4) HDMI 1–8, SDI 1–8 only

#### AUDIO OUTPUT ASSIGN

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 01H 20H 00H | AUDIO OUT (XLR) | 00H–03H | MASTER OUTPUT, AUX 1–3 |
| 01H 20H 01H | AUDIO OUT (RCA) | 00H–03H | MASTER OUTPUT, AUX 1–3 |
| 01H 20H 02H | PHONES OUT | 00H–03H | MASTER OUTPUT, AUX 1–3 |
| 01H 20H 03H | USB OUT | 00H–04H | AUTO, MASTER OUTPUT, AUX 1–3 |
| 01H 20H 04H | HDMI OUT 1 | 00H–04H | AUTO, MASTER OUTPUT, AUX 1–3 |
| 01H 20H 05H | HDMI OUT 2 | 00H–04H | AUTO, MASTER OUTPUT, AUX 1–3 |
| 01H 20H 06H | HDMI OUT 3 | 00H–04H | AUTO, MASTER OUTPUT, AUX 1–3 |
| 01H 20H 07H | SDI OUT 1 | 00H–04H | AUTO, MASTER OUTPUT, AUX 1–3 |
| 01H 20H 08H | SDI OUT 2 | 00H–04H | AUTO, MASTER OUTPUT, AUX 1–3 |
| 01H 20H 09H | SDI OUT 3 | 00H–04H | AUTO, MASTER OUTPUT, AUX 1–3 |

#### AUDIO MASTER OUTPUT

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 01H 21H 00H 01H 02H | OUTPUT LEVEL | 7EH 00H 00H, 7FH 79H 60H–00H 00H 00H–00H 00H 64H | -INFdB, -80.0–0.0–10.0dB |
| 01H 21H 03H | OUTPUT MUTE | 00H–01H | OFF, ON |
| 01H 21H 04H 05H | OUTPUT DELAY | 00H 00H–27H 08H | 0.0–500.0msec |
| 01H 21H 06H | LIMITER SW | 00H–01H | OFF, ON |
| 01H 21H 07H | LIMITER THRESHOLD | 58H–00H | -40–0dB |
| 01H 21H 08H | REVERB LEVEL | 00H–7FH | 0–127 |
| 01H 21H 09H | REVERB SW | 00H–01H | OFF, ON |
| 01H 21H 0AH | REVERB TYPE | 00H–01H | ROOM, HALL |
| 01H 21H 0BH | REVERB SIZE | 01H–14H | 1–20 |
| 01H 21H 0CH | EQUALIZER SW | 00H–01H | OFF, ON |
| 01H 21H 0DH | EQUALIZER Hi GAIN | 04H–7CH | -12.0–12dB |
| 01H 21H 0EH | EQUALIZER Hi FREQUENCY | 24H–3EH | 1.00–20.0kHz |
| 01H 21H 0FH | EQUALIZER Mid GAIN | 04H–7CH | -12.0–12dB |
| 01H 21H 10H | EQUALIZER Mid FREQUENCY | 02H–3EH | 20Hz–20.0kHz |
| 01H 21H 11H | EQUALIZER Mid Q | 00H–05H | 0.5, 1.0, 2.0, 4.0, 8.0, 16.0 |
| 01H 21H 12H | EQUALIZER Lo GAIN | 04H–7CH | -12.0–12dB |
| 01H 21H 13H | EQUALIZER Lo FREQUENCY | 02H–2AH | 20Hz–2.00kHz |
| 01H 21H 14H | MULTI BAND COMPRESSOR SW | 00H–01H | OFF, ON |
| 01H 21H 15H | MB COMP Hi THRESHOLD | 58H–00H | -40–0dB |
| 01H 21H 16H | MB COMP Hi RATIO | 00H–0DH | 1.00:1, 1.12:1, 1.25:1, 1.40:1, 1.60:1, 1.80:1, 2.00:1, 2.50:1, 3.20:1, 4.00:1, 5.60:1, 8.00:1, 16.0:1, INF:1 |
| 01H 21H 17H | MB COMP Mid THRESHOLD | 58H–00H | -40–0dB |
| 01H 21H 18H | MB COMP Mid RATIO | 00H–0DH | 1.00:1, 1.12:1, 1.25:1, 1.40:1, 1.60:1, 1.80:1, 2.00:1, 2.50:1, 3.20:1, 4.00:1, 5.60:1, 8.00:1, 16.0:1, INF:1 |
| 01H 21H 19H | MB COMP Lo THRESHOLD | 58H–00H | -40–0dB |
| 01H 21H 1AH | MB COMP Lo RATIO | 00H–0DH | 1.00:1, 1.12:1, 1.25:1, 1.40:1, 1.60:1, 1.80:1, 2.00:1, 2.50:1, 3.20:1, 4.00:1, 5.60:1, 8.00:1, 16.0:1, INF:1 |
| 01H 21H 1BH | LOUDNESS AUTO GAIN CONTROL SW | 00H–01H | OFF, ON |
| 01H 21H 1CH | INTEGRATED GAIN CONTROL | 00H–01H | DISABLE, ENABLE |
| 01H 21H 1DH | INTEGRATED GAIN CONTROL SENS | 00H–7FH | 0–127 |
| 01H 21H 1EH | MOMENTARY GAIN CONTROL | 00H–01H | DISABLE, ENABLE |
| 01H 21H 1FH | MOMENTARY GAIN CONTROL SENS | 00H–7FH | 0–127 |
| 01H 21H 20H | TARGET LKFS | 5EH–76H | -34– -10dB |
| 01H 21H 21H | ADAPTIVE NOISE REDUCTION SW | 00H–01H | OFF, ON |
| 01H 21H 22H | ADAPTIVE NOISE REDUCTION DEPTH | 00H–7FH | 0–127 |
| 01H 21H 23H | ADAPTIVE NOISE REDUCTION TALKING DETECTOR | 00H–7FH | 0–127 |
| 01H 21H 24H | ADAPTIVE NOISE REDUCTION AUTO LEARN | 00H–01H | DISABLE, ENABLE |
| 01H 21H 25H | LO FREQUENCY CUT SW | 00H–01H | OFF, ON |
| 01H 21H 26H 27H 28H | REVERB RETURN LEVEL | 7EH 00H 00H, 7FH 79H 60H–00H 00H 00H–00H 00H 64H | -INFdB, -80.0–0.0–10.0dB |
| 01H 21H 29H | SOLO | 00H–01H | OFF, ON |

*Note: For AUX 1-3 outputs, USB output, embedded audio, audio follow, auto mixing, and knob assign parameters, please refer to pages 11-20 of the original document for complete parameter tables.*

---

### System Parameter Area

#### Version

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 02H 00H 00H | System Version Major | 00H–09H | 0–9 |
| 02H 00H 01H | System Version Minor (1) | 00H–09H | 0–9 |
| 02H 00H 02H | System Version Minor (2) | 00H–09H | 0–9 |
| 02H 00H 03H | System Version Build (1) | 00H–09H | 0–9 |
| 02H 00H 04H | System Version Build (2) | 00H–09H | 0–9 |
| 02H 00H 05H | System Version Build (3) | 00H–09H | 0–9 |

#### SYSTEM

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 02H 01H 00H | HDCP | 00H–01H | OFF, ON |
| 02H 01H 01H | FRAME RATE | 00H–07H | 60Hz, 59.94Hz, 50Hz, 30Hz, 29.97Hz, 25Hz, 24Hz, 23.98Hz |
| 02H 01H 02H | USB OUT | 00H–01H | HALF RATE, NORMAL (value differs depending on FRAME RATE setting) |
| 02H 01H 03H | SYSTEM FORMAT | 00H–01H | 1080p, 720p |
| 02H 01H 04H | REFERENCE SOURCE | 00H–09H | INTERNAL, EXTERNAL, SDI 1–8 |
| 02H 01H 09H | Bluetooth SW | 00H–01H | OFF, ON |
| 02H 01H 0AH | PANEL OPERATION | 00H–03H | A/B, PGM/PST, DISSOLVE, PGM/PST(20) |
| 02H 01H 1AH | LED DIMMER | 01H–08H | 1–8 |
| 02H 01H 1BH | LCD DIMMER | 01H–08H | 1–8 |
| 02H 01H 2EH | TEST PATTERN | 00H–05H | OFF, 75% COLOR BAR, 100% COLOR BAR, RAMP, STEP, HATCH |
| 02H 01H 30H | TEST TONE LEVEL | 00H–03H | OFF, -20dB, -10dB, 0dB |

*Note: For complete system parameters including panel lock, preset memory, freeze, auto switching, CTL/EXP, RS-232/TALLY/GPO/GPI/KEY, camera control, and label edit settings, please refer to pages 20-30 of the original document.*

---

### Other Parameter Area

#### Memory

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 0AH 00H 00H | Memory Load Trigger | 00H–1DH | Memory 1–30 (Write only) |
| 0AH 00H 01H | Memory Save Trigger | 00H–1DH | Memory 1–30 (Write only) |
| 0AH 00H 02H | Memory Initialize Trigger | 00H–1DH | Memory 1–30 (Write only) |
| 0AH 00H 03H | Loaded Memory Number | 00H–1DH, 7FH | Memory 1–30, Last Memory (Read only) |

---

### Panel Control Area

#### Button Control

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 0BH 00H 00H | PGM/A cross-point [1] button | 00H–01H | Release, press (Write Only) |
| 0BH 00H 01H | PGM/A cross-point [2] button | 00H–01H | Release, press (Write Only) |
| ... | ... | ... | ... |
| 0BH 00H 1EH | [CUT] button | 00H–01H | Release, press (Write Only) |
| 0BH 00H 1FH | [AUTO] button | 00H–01H | Release, press (Write Only) |

*Note: For complete button control parameters, please refer to pages 31-32 of the original document.*

---

### Tally Area

#### Tally Info

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 0CH 00H 00H | HDMI IN 1 TALLY | 00H–03H | OFF, PGM, PST, PGM&PST (Read only) |
| 0CH 00H 01H | HDMI IN 2 TALLY | 00H–03H | OFF, PGM, PST, PGM&PST (Read only) |
| ... | ... | ... | ... |

#### Tally Audio Send

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 0CH 01H 00H | TALLY AUTO SEND | 00H–01H | OFF, ON |

---

### Camera Control Area

#### Camera Control Command

**xxH: 00H–0FH (CAMERA 1–16)**

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 0DH xxH 00H | PRESET RECALL | 00H–09H | PRESET 1–10 |
| 0DH xxH 01H | PRESET STORE | 00H–09H | PRESET 1–10 |
| 0DH xxH 02H | ZOOM RESET | 01H | Reset the value |

---

### Preset Memory Area

You can load or rewrite the stored contents of the preset memories.

*The ranges for the second and third bytes of the address and the values are shared with Video Parameter Area (00H 00H 00H) and Audio Parameter Area (01H 00H 00H).*

| Address | Parameter name | Meaning of value |
|---------|---------------|------------------|
| 10H 00H 00H | Video Parameter (Memory 1) | Load/rewrite video parameter stored in Memory 1 |
| 11H 00H 00H | Audio Parameter (Memory 1) | Load/rewrite audio parameter stored in Memory 1 |
| 12H 00H 00H | Video Parameter (Memory 2) | Load/rewrite video parameter stored in Memory 2 |
| 13H 00H 00H | Audio Parameter (Memory 2) | Load/rewrite audio parameter stored in Memory 2 |
| ... | ... | ... |
| 4AH 00H 00H | Video Parameter (Memory 30) | Load/rewrite video parameter stored in Memory 30 |
| 4BH 00H 00H | Audio Parameter (Memory 30) | Load/rewrite audio parameter stored in Memory 30 |

---

### Macro Area

#### Macro Command

| Address | Parameter name | SysEx value | Meaning of value |
|---------|---------------|-------------|------------------|
| 50H 05H 04H | EXEC MACRO TRIGGER | 00H–63H | MACRO 1–100 |
| 50H 05H 05H | PREVIEW MACRO TRIGGER | 00H–63H | MACRO 1–100 |

---

### Preset Memory Name Area

**xxH: 00H–1DH (MEMORY 1–30)**

| Address | Parameter Name | Meaning of value |
|---------|---------------|------------------|
| 60H xxH 00H | NAME (0) | Name of preset memory number xx (1st character) |
| 60H xxH 01H | NAME (1) | Name of preset memory number xx (2nd character) |
| 60H xxH 02H | NAME (2) | Name of preset memory number xx (3rd character) |
| 60H xxH 03H | NAME (3) | Name of preset memory number xx (4th character) |
| 60H xxH 04H | NAME (4) | Name of preset memory number xx (5th character) |
| 60H xxH 05H | NAME (5) | Name of preset memory number xx (6th character) |
| 60H xxH 06H | NAME (6) | Name of preset memory number xx (7th character) |
| 60H xxH 07H | NAME (7) | Name of preset memory number xx (8th character) |

---

## 3. Supplementary Material

### Decimal and Hexadecimal Table

In MIDI documentation, data values and addresses/sizes of exclusive messages are expressed as hexadecimal values for each 7 bits. The following table shows how these correspond to decimal numbers.

| D | H | D | H | D | H | D | H |
|---|---|---|---|---|---|---|---|
| 0 | 00H | 32 | 20H | 64 | 40H | 96 | 60H |
| 1 | 01H | 33 | 21H | 65 | 41H | 97 | 61H |
| 2 | 02H | 34 | 22H | 66 | 42H | 98 | 62H |
| 3 | 03H | 35 | 23H | 67 | 43H | 99 | 63H |
| 4 | 04H | 36 | 24H | 68 | 44H | 100 | 64H |
| 5 | 05H | 37 | 25H | 69 | 45H | 101 | 65H |
| ... | ... | ... | ... | ... | ... | ... | ... |
| 127 | 7FH | | | | | | |

**D:** decimal  
**H:** hexadecimal

**Notes:**
- Decimal expressions used for MIDI channel, bank select, and program change are 1 greater than the decimal value shown in the table
- Hexadecimal values in 7-bit units can express a maximum of 128 levels in one byte of data
- If the data requires greater resolution, two or more bytes are used
- For example, a value indicated by a hexadecimal expression in two 7-bit bytes `aa bbH` would be `aa x 128 + bb`

### Examples

**Example 1:** What is the decimal expression of 5AH?
- From the table, 5AH = 90

**Example 2:** What is the decimal expression of the value 12 34H given as hexadecimal for each 7 bits?
- From the table, since 12H = 18 and 34H = 52
- 18 x 128 + 52 = 2356

---

### Example of an Exclusive Message and Calculating a Checksum

Roland Exclusive messages are transmitted with a checksum at the end (before F7) to ensure correct reception. The checksum value is determined by the address and data (or size) of the transmitted exclusive message.

#### How to Calculate the Checksum

The checksum is a value that produces a lower 7 bits of zero when the address, size, and checksum itself are summed.

If the exclusive message has an address of `aa bb ccH` and the data is `dd ee ffH`:

```
aa + bb + cc + dd + ee + ff = sum
sum / 128 = quotient ... remainder
128 - remainder = checksum
```

(However, the checksum will be 0 if the remainder is 0.)

#### Example

When setting PGM Select to INPUT 2 for data set 1:

From the "Parameter Address Map", the address of PGM Select is `00H 21H 00H` and the INPUT 2 parameter is `01H`.

```
F0H 41H 10H 00H 00H 00H 00H 02H 12H 00H 21H 00H 01H ??H F7H
(1) (2) (3) (4) (5) (6) (7) (8) (9)
```

Where:
1. Exclusive Status
2. ID Number (Roland)
3. Device ID
4. Model ID
5. Command ID (DT1)
6. Address
7. Data
8. Checksum
9. EOX

Calculate the checksum by adding (6) to (7):

```
00H + 21H + 00H + 01H = 0 + 33 + 0 + 1 = 34 (sum)
34 (sum) / 128 = 0 (quotient) ... 34 (remainder)
Checksum = 128 - 34 (remainder) = 94 = 5EH
```

Thus, the message to transmit is:

```
F0H 41H 10H 00H 00H 00H 00H 02H 12H 00H 21H 00H 01H 5EH F7H
```

---

## MIDI Implementation Chart

**Model:** V-160HD  
**Date:** Feb 13, 2023  
**Version:** 2.00

| Function | Transmitted | Recognized | Remarks |
|----------|-------------|------------|---------|
| **Basic Channel** | | | |
| Default | 1 | 1 | |
| Changed | 1 | 1 | |
| **Mode** | | | |
| Default | × | × | |
| Messages | × | × | |
| Altered | ************** | ************** | |
| **Note Number** | | | |
| True Voice | × | × | |
| **Velocity** | | | |
| Note On | × | × | |
| Note Off | × | × | |
| **After Touch** | | | |
| Key's | × | × | |
| Channel's | × | × | |
| **Pitch Bend** | × | × | |
| **Control Change** | | | |
| 0–9 | × | × | |
| 10–31 | × | × | |
| 32–46 | × | × | |
| 46–51 | × | × | |
| 52–65 | × | × | |
| 66–119 | × | × | |
| **Program Change** | | | |
| True Number | × | × | |
| **System Exclusive** | O | O | |
| **System Common** | | | |
| Song Position | × | × | |
| Song Select | × | × | |
| Tune Request | × | × | |
| **System Real Time** | | | |
| Clock | × | × | |
| Commands | × | × | |
| **Aux Messages** | | | |
| All Sound Off | × | × | |
| Reset All Controllers | × | × | |
| Local On/Off | × | × | |
| All Notes Off | × | × | |
| Active Sensing | × | × | |
| System Reset | × | × | |

**Mode:**
- Mode 1: OMNI ON, POLY
- Mode 2: OMNI ON, MONO
- Mode 3: OMNI OFF, POLY
- Mode 4: OMNI OFF, MONO

**Legend:**
- O: Yes
- ×: No

---

## LAN/RS-232 Command Reference

The V-160HD supports two types of remote-interface communication: LAN and RS-232. Using the LAN CONTROL port or RS-232 connector to send specific commands to the V-160HD from a controlling device lets you operate the V-160HD remotely.

---

### LAN Interface

This uses the LAN CONTROL port on the V-160HD. You use Telnet to operate the V-160HD remotely over a LAN (TCP/IP protocol).

#### Communication Standards

| Parameter | Value |
|-----------|-------|
| Port | LAN CONTROL port |
| TCP port number | 8023 |

#### Specifying the V-160HD's Network Settings

1. Press [MENU] button → "LAN CONTROL" → select the menu item shown below, and press the [VALUE] knob

| Menu item | Explanation |
|-----------|-------------|
| CONFIGURE | Selects how settings are made for the IP address, subnet mask, and default gateway.<br>**USING DHCP:** The IP address and other information needed for connecting to the network is obtained automatically from the DHCP server of the LAN.<br>**MANUAL:** The IP address, subnet mask, and default gateway are specified manually. |
| IP ADDRESS | Shows the IP address. (*1) |
| SUBNET MASK | Shows the subnet mask. (*1) |
| DEFAULT GATEWAY | Shows the default gateway. (*1) |

(*1) When "CONFIGURE" is set to "MANUAL", set these respectively according to the network.

2. Use the [VALUE] knob to change the value of the setting
3. Use the [VALUE] knob to select "NETWORK PASSWORD", and press the [VALUE] knob
   - The NETWORK PASSWORD screen appears
4. Set a network password (four characters)
   - Input the password that's set here when connecting a computer or other device on the same network to access the V-160HD
5. Press the [MENU] button to close the menu

---

### RS-232 Interface

#### RS-232 Connector Pin Layout

**DB-9 type (male)**

```
1 2 3 4 5
 6 7 8 9
```

#### Pin Assignments

| Pin No | Signal |
|--------|--------|
| 1 | N.C. |
| 2 | RXD |
| 3 | TXD |
| 4 | DTR |
| 5 | GND |
| 6 | DSR |
| 7 | RTS |
| 8 | CTS |
| 9 | N.C. |

#### Communication Standards

| Parameter | Value |
|-----------|-------|
| Communication method | Synchronous (asynchronous), full-duplex |
| Communication speed | 9,600/38,400/115,200 bps |
| Parity | none |
| Data length | 8 bits |
| Stop bit | 1 bit |
| Code set | ASCII |

#### Cable Wiring Diagram

Use an RS-232 crossover cable to connect the V-160HD and the controller (an RS-232-compatible computer or other device).

```
V-160HD          Control device
N.C.: 1 ————————— 1:
RXD: 2 ————————— 2: RXD
TXD: 3 ————————— 3: TXD
DTR: 4 ————————— 4:
GND: 5 ————————— 5: GND
DSR: 6 ————————— 6:
RTS: 7 ————————— 7:
CTS: 8 ————————— 8:
N.C.: 9 ————————— 9:
```

(Crossover connection)

*The connections between 4 and 6 and between 7 and 8 are inside the V-160HD.*

---

### Command Format

Commands are formatted using the configuration shown below. Commands are all in ASCII code.

*Commands are common to the LAN and the RS-232 interface.*

```
stx Command code : Parameter , Parameter ;
```

| Component | Description |
|-----------|-------------|
| **stx** | ASCII code "02H" is a control code indicating the start of a command. "H" indicates that it is a hexadecimal value. |
| **Command code** | This specifies the command type (three single-byte alphanumeric characters). |
| **Parameter** | This is appended to a command that requires one or more parameter. The command and the parameter portion are separated by a ":" (colon). When there are multiple parameters, they are each separated by "," (comma) characters. |
| **;** | This is the code that this unit recognizes as the end of a command. |

*The codes of stx (02H), ack (06H), xon (11H), and xoff (13H) are the control codes.*

---

### List of Commands

See "MIDI Implementation" for the SysEx addresses and setting values.

*When controlling via LAN (Telnet), "stx (02H)" may be omitted.*

#### Commands Sent to the V-160HD

| Item | Sent command | Response command | Parameter |
|------|-------------|------------------|-----------|
| Parameter write (SysEx-supported command) | stxDTH:a,b; | ack | a: SysEx address (hexadecimal, three bytes)<br>b: Setting value (hexadecimal)<br>**Example:** When setting "01H" to address 12H 34H 56H → stxDTH:123456,01; |
| Parameter value retrieve (SysEx-supported command) | stxRQH:a,b; | stxDTH:a,c; | a: SysEx address (hexadecimal, three bytes)<br>b: Request size (hexadecimal, three bytes)<br>c: Setting value (hexadecimal) |
| Version information | stxVER; | stxVER:a,b; | a: V-160HD (Product name)<br>b: Version number (Example: 1.00) |
| Flow control | | xon | |
| Flow control | | xoff | |

#### Commands Spontaneously Sent from the V-160HD

| Item | Sent command | Response command | Parameter |
|------|-------------|------------------|-----------|
| Error detected | | stxERR:a; | a: 0 (syntax error) - The received command contains an error.<br>4 (invalid) - This has no effect because it is controlled by another setting.<br>5 (out of range error) - An argument of the received command is out of range.<br>6 (no stx error) - The command does not have a "stx" prefix. *Only RS-232 |
| Flow control | | xon | |
| Flow control | | xoff | |

---
