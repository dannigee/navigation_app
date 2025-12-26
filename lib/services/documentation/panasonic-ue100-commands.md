# Panasonic AW-UE100 Camera Control API

## Communication Setup

### IP Communication Format

**Pan/Tilt Commands:**
```
http://[IP_Address]/cgi-bin/aw_ptz?cmd=[Command]&res=1
```

**Camera Commands:**
```
http://[IP_Address]/cgi-bin/aw_cam?cmd=[Command]&res=1
```

**Note:** In IP communication, `#` must be URL encoded as `%23`

### Response Format
```
200 OK "[Command Response]"
```

---

## 1. Power & System Control

### Power On/Off
```
Command: #O[Data]
- Data: 0 = Standby, 1 = Power On
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23O1&res=1
Response: p1 (Power On) or p0 (Standby)
```

### Get Camera Info
```
Request: QID
Response: OID:AW-UE100
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=QID&res=1
```

### Get Version
```
Request: QSV
Response: OSV:[Version]
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=QSV&res=1
```

---

## 2. Pan/Tilt Control

### Pan Speed Control
```
Command: #P[Speed]
- Speed: 01-49 (Left), 50 (Stop), 51-99 (Right)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23P75&res=1
Response: pS75
```

### Tilt Speed Control
```
Command: #T[Speed]
- Speed: 01-49 (Down), 50 (Stop), 51-99 (Up)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23T25&res=1
Response: tS25
```

### Pan/Tilt Combined Speed Control
```
Command: #PTS[PanSpeed][TiltSpeed]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23PTS5075&res=1
- Pan: 50 (stop), Tilt: 75 (up)
```

### Absolute Position Control
```
Command: #APC[PanPos][TiltPos]
- Pan: 0000-FFFF (CCW Limit to CW Limit, 8000 = Center)
- Tilt: 0000-FFFF (Up Limit to Down Limit, 8000 = Center)
- Pan Range: 2D09 (-175°) to D2F5 (+175°)
- Tilt Range: 5555 (-30°) to 8E38 (+90°)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23APC80008000&res=1
```

### Absolute Position with Speed
```
Command: #APS[PanPos][TiltPos][Speed][SpeedTable]
- Speed: 00-1D (1-30)
- SpeedTable: 0=SLOW, 1=MID, 2=FAST
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23APS800080001D0&res=1
```

### Install Position (Flip)
```
Command: #INS[Data]
- Data: 0 = Desktop, 1 = Hanging
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23INS1&res=1
```

---

## 3. Zoom Control

### Zoom Speed Control
```
Command: #Z[Speed]
- Speed: 01-49 (Wide), 50 (Stop), 51-99 (Tele)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23Z75&res=1
Response: zS75
```

### Zoom Position Control
```
Command: #AXZ[Position]
- Position: 555-FFF (Wide to Tele)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23AXZ555&res=1
Response: axz555
```

### Digital Zoom
```
Control: OSE:70:[Data]
- Data: 0 = Disable, 1 = Enable
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:70:1&res=1
```

### Digital Zoom Magnification
```
Control: OSE:76:[Data]
- Data: 0100-9999 (x1.00 to x99.99)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:76:0200&res=1
```

---

## 4. Focus Control

### Focus Mode
```
Command: OAF:[Data] or #D1[Data]
- Data: 0 = Manual, 1 = Auto
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OAF:1&res=1
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23D11&res=1
```

### Focus Speed Control (Manual Mode)
```
Command: #F[Speed]
- Speed: 01-49 (Near), 50 (Stop), 51-99 (Far)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23F75&res=1
```

### Focus Position Control
```
Command: #AXF[Position]
- Position: 555-FFF (Near to Far)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23AXF800&res=1
```

### Push Auto Focus
```
Control: OSE:69:1
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:69:1&res=1
```

---

## 5. Iris Control

### Iris Mode
```
Command: ORS:[Data] or #D3[Data]
- Data: 0 = Manual, 1 = Auto
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=ORS:1&res=1
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23D31&res=1
```

### Iris Position Control (Manual Mode)
```
Command: #AXI[Position]
- Position: 555-FFF (Close to Open)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23AXI800&res=1
```

### Iris Speed Control
```
Command: #I[Speed]
- Speed: 01-99 (Close to Open)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23I50&res=1
```

---

## 6. Preset Management

### Recall Preset
```
Command: #R[PresetNum]
- PresetNum: 00-99 (Preset 1-100)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23R07&res=1
Response: s07 (immediate), then q07 (on completion)
```

### Save Preset
```
Command: #M[PresetNum]
- PresetNum: 00-99 (Preset 1-100)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23M07&res=1
```

### Delete Preset
```
Command: #C[PresetNum]
- PresetNum: 00-99 (Preset 1-100)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23C07&res=1
```

### Preset Speed
```
Command: #UPVS[Speed]
- Speed: 001-999 (for Speed mode) or 001-099 seconds (for Time mode)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23UPVS250&res=1
```

### Save Preset Name
```
Control: OSJ:35:[PresetNum]:[Name]
- PresetNum: 00-99
- Name: 15 characters (ASCII)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:35:00:MyPresetName123&res=1
```

---

## 7. Exposure Control

### Gain
```
Control: OGU:[Data]
- Data: 08-32 (0dB to 42dB), 80 (AGC Auto)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OGU:10&res=1
```

### Shutter Mode
```
Control: OSJ:03:[Data]
- Data: 0=Off, 1=Step, 2=Synchro, 3=ELC
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:03:1&res=1
```

### Shutter Speed (Step Mode)
```
Control: OSJ:06:[Data]
- Data: Hexadecimal denominator (e.g., 003C = 1/60)
- Available: 1/60, 1/100, 1/120, 1/250, 1/500, 1/1000, 1/2000, 1/4000, 1/8000, 1/10000
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:06:003C&res=1
```

### ND Filter
```
Control: OFT:[Data]
- Data: 0=Through, 1=1/4 ND, 2=1/16 ND, 3=1/64 ND
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OFT:1&res=1
```

---

## 8. White Balance

### White Balance Mode
```
Control: OAW:[Data]
- Data: 0=ATW, 1=AWC A, 2=AWC B, 4=3200K, 5=5600K, 9=VAR
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OAW:1&res=1
```

### Auto White Balance Execute
```
Control: OWS
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OWS&res=1
Response: OWS (immediate), then OWS (on completion)
```

### Color Temperature (VAR Mode)
```
Control: OSI:20:[Temp]:[Status]
- Temp: 007D0-03A98 (2000K-15000K in hex)
- Status: 0=Valid, 1=Under, 2=Over
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSI:20:0157C:0&res=1
```

### R/B Gain
```
Control: OSG:39:[Data] (R Gain)
Control: OSG:3A:[Data] (B Gain)
- Data: 738-8C8 (-200 to +200, 800 = 0)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSG:39:800&res=1
```

---

## 9. Scene Files

### Scene Selection
```
Control: XSF:[Data]
- Data: 0-4 (Scene 1-5, 0=-)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=XSF:1&res=1
```

---

## 10. Output & Display

### Color Bar
```
Control: DCB:[Data]
- Data: 0=Camera, 1=Color Bar
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=DCB:1&res=1
```

### Tally Control
```
Command: #TAE[Data] (Enable/Disable)
- Data: 0=Disable, 1=Enable
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23TAE1&res=1

Control: TLR:[Data] (Red Tally)
- Data: 0=Off, 1=On
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=TLR:1&res=1

Control: TLG:[Data] (Green Tally)
- Data: 0=Off, 1=On
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=TLG:1&res=1
```

---

## 11. Status Query Commands

### Get Pan/Tilt/Zoom/Focus/Iris
```
Request: #PTV
Response: pTV[Pan][Tilt][Zoom][Focus][Iris]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23PTV&res=1
```

### Get Zoom Position
```
Request: #GZ
Response: gz[Position]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23GZ&res=1
```

### Get Focus Position
```
Request: #GF
Response: gf[Position]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23GF&res=1
```

### Get Iris Position
```
Request: #GI
Response: gi[Position][Mode]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23GI&res=1
```

### Lens Position Information (Continuous)
```
Control: #LPC[Data]
- Data: 0=Off, 1=On (sends updates every 300ms)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23LPC1&res=1
Response: lPI[Zoom][Focus][Iris] (3 digits each)
```

### Error Status
```
Request: #RER
Response: rER[ErrorCode]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23RER&res=1
```

---

## 12. Update Notifications (Event System)

### Start Receiving Notifications
```
http://[IP]/cgi-bin/event?connect=start&my_port=[Port]&uid=0
Response: 204 No Content
```

### Stop Receiving Notifications
```
http://[IP]/cgi-bin/event?connect=stop&my_port=[Port]&uid=0
Response: 204 No Content
```

### Notification Format (TCP)
Notifications are sent to the specified TCP port with the format:
```
[CR][LF][Command Response][CR][LF]
```

---

## 13. Batch Information Retrieval

### Get All Camera Data
```
http://[IP]/live/camdata.html
Response: 200 OK with complete camera status
```

---

## Error Responses

- **ER1**: Unsupported command
- **ER2**: Busy status (e.g., camera in standby)
- **ER3**: Parameter outside acceptable range

---

## Important Restrictions

1. **Pan/Tilt Commands**: Send with 40ms gap between commands
2. **HTTP Keep-Alive**: Not supported - connect/disconnect each time
3. **URL Encoding**: `#` must be encoded as `%23` in IP communication
4. **Command Rate**: Only send setting changes when needed, not at regular intervals

---

## Common Use Case Examples

### Basic Camera Setup
```bash
# Power on
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23O1&res=1

# Set auto focus
http://192.168.0.10/cgi-bin/aw_cam?cmd=OAF:1&res=1

# Set auto iris
http://192.168.0.10/cgi-bin/aw_cam?cmd=ORS:1&res=1

# Set white balance to auto
http://192.168.0.10/cgi-bin/aw_cam?cmd=OAW:0&res=1
```

### Simple PTZ Control
```bash
# Pan right at medium speed
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23P75&res=1

# Stop pan
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23P50&res=1

# Zoom in
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23Z75&res=1

# Zoom stop
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23Z50&res=1
```

### Preset Workflow
```bash
# Move to position
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23APC800080000&res=1

# Save as preset 1
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23M00&res=1

# Recall preset 1
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23R00&res=1
```