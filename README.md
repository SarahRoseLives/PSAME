# PocketSAME

>[!WARNING]
>TRANSMITTING ON FREQUENCIES YOU ARE NOT LICENSED IS ILLEGAL. I AM NOT RESPONSIBE FOR WHAT YOU DO WITH THIS SOFTWARE.

This Flutter app provides a user-friendly interface for transmitting **SAME (Specific Area Message Encoding)** alerts and simple FM tones using a HackRF device.  

⚠️ **Important Requirements:**
- A HackRF device must be connected **before launching the app**.  
- In Addition **USB OTG must be enabled**.  
- Without a HackRF connected, the app will not initialize properly.  

**Want an APK Without Compiling?**
Buy it here: https://sarahsforge.dev/products/pocketsame

---


## Getting Started

### 1. Connect Hardware
- Plug in your HackRF using a USB OTG adapter.
- Ensure it is recognized by the system before launching the app.

### 2. Launch the App
When the app starts:
- It will attempt to initialize the HackRF.  
- Status messages are displayed in the **Status card** at the top.  
- If successful, you will see:  
  `Ready.`

If initialization fails, an error message will be displayed.

---

## UI Walkthrough

### Status
- Shows current state:
  - **Not Initialized**
  - **Initializing...**
  - **Ready. Plug in HackRF.**
  - **Transmitting SAME burst...**
  - **Transmitting 1kHz Tone...**
  - **Stopped. Ready to transmit.**
  - **Error:** with details

---

### Radio Settings
- **WX Frequency (MHz):** Choose from NOAA Weather frequencies (162.400–162.550 MHz).  
- **TX VGA Gain:** Adjust transmit gain (0–47 dB) with a slider.  

---

### SAME Message
Configure your SAME message parameters:  
- **Event Code:** Tap the card to open a searchable list of SAME/EAS event codes (e.g., RWT – Required Weekly Test).  
- **FIPS Code:** 6-digit code for the target area (e.g., `039007`).  
- **Originator:** Select from:
  - `WXR` (Weather Service)  
  - `EAS` (Emergency Alert System)  
  - `CIV` (Civil Authority)  

---

### Timing & Station ID
- **Expiration (Purge Time):** Choose how long the alert remains valid (15 minutes → 6 hours).  
- **Station ID:** Identifier of the transmitting station (e.g., `KCLE-NWR`).  

---

### Action Buttons
At the bottom of the screen:  
- **Transmit SAME Alert**: Sends a SAME burst with your configured parameters.  
  - Runs once and stops automatically when complete.  
- **Transmit Tone**: Sends a continuous 1 kHz audio tone on the selected frequency.  
- **Stop**: Immediately halts any ongoing transmission.  

---

## Example Workflow
1. Connect HackRF with OTG enabled.  
2. Launch the app → Wait for `Ready. Plug in HackRF.`  
3. Choose **162.550 MHz** and set **TX VGA Gain**.  
4. Configure:
   - Event: `RWT – Required Weekly Test`
   - FIPS: `039007`
   - Originator: `WXR`
   - Expiration: `30 Mins`
   - Station ID: `KCLE-NWR`  
5. Press **Transmit SAME Alert**.  
6. Observe status change to `Transmission Complete.`  

---

## Notes
- SAME bursts are **one-shot transmissions** — they end automatically.  
- Tone transmissions continue until manually stopped.  
- Always comply with your radio license and regulatory requirements when transmitting.  

---