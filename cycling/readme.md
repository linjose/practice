# cycling setting

 - Filename: p1.json, p2.json...
 - Path: ../cycling/p1.json
 - Content: speed(km/h)、cadence(RPM)、distance(KM)
```
{"s":0, "c":20, "d":30}
```

 - Add cycling api path and video serial number here
```
<script>
    const CONFIG = {
        apiBaseUrl: "http://127.0.0.1/cycling", 
        playerCount: 3,
        videoList: [
            'IPxNUTvawVE', 'PH-kqdzTgqE', 'mJM_7U2h_Fk', 'QzW3tZyGqRk'
            // ... 這裡可補足到 50 組
        ]
    };
```

# Get data from Magene S3+

要在 Ubuntu 主機上取得 Magene（邁金）S3+ 的數值，最穩定且現代的方法是透過 **Bluetooth Low Energy (BLE)** 進行通訊。Magene S3+ 遵循標準的藍牙 **CSC (Cycling Speed and Cadence)** 協定。

以下是從環境搭建到代碼解析的完整指南：

---

## 1. 環境準備

在 Ubuntu 上，我們建議使用 **Python** 搭配 `bleak` 函式庫，這是目前 Linux 下操作 BLE 最主流且穩定的方式。

### 安裝必要套件

```bash
# 更新系統並安裝藍牙相關套件
sudo apt update
sudo apt install python3-pip bluez

# 安裝 Python BLE 函式庫
pip install bleak

```

---

## 2. 確認 S3+ 工作模式

Magene S3+ 是一顆「二選一」感應器，透過**重新安裝電池**來切換模式：

* **踏頻模式 (Cadence):** 燈號閃爍 **紅色**。
* **時速模式 (Speed):** 燈號閃爍 **綠色**。

> **注意：** 請先確保感應器處於喚醒狀態（搖晃感應器或轉動曲柄），否則藍牙廣播會進入睡眠。

---

## 3. 搜尋設備 (取得 MAC 位址)

你需要先找到 S3+ 的藍牙位址：

```bash
bluetoothctl scan on

```

尋找名稱類似 `S3+ xxxxxx` 的設備，並記錄其 MAC 位址（例如 `D1:23:45:67:89:AB`）。

---

## 4. 解析資料格式 (CSC 協定)

Magene S3+ 遵循標準的 **GATT Service: 0x1816 (Cycling Speed and Cadence)**。
主要讀取的 **Characteristic 是 0x2A5B (CSC Measurement)**。

資料包的結構如下：

1. **Flags (1 byte):** 決定資料包含什麼。
* Bit 0: 1 表示包含輪圈數據 (Wheel Revolution Data) — **時速模式**。
* Bit 1: 1 表示包含曲柄數據 (Crank Revolution Data) — **踏頻模式**。


2. **Cumulative Revolutions (2或4 bytes):** 累積轉圈數。
3. **Last Event Time (2 bytes):** 最後一次感應的時間（單位為  秒）。

---

## 5. Python 實作程式碼

這是一個可以直接運行的腳本，用於連接並自動解析 S3+ 的數值。

```python
import asyncio
from bleak import BleakClient

# 替換成你的 S3+ MAC 位址
ADDRESS = "D1:23:45:67:89:AB"
CSC_MEASUREMENT_UUID = "00002a5b-0000-1000-8000-00805f9b34fb"

# 用於計算差值的全域變數
last_rev = -1
last_time = -1

def callback(sender, data):
    global last_rev, last_time
    
    # 解析 Flags (第0位)
    flags = data[0]
    wheel_present = flags & 0x01
    crank_present = flags & 0x02

    offset = 1
    if wheel_present:
        # 時速模式：4 bytes 累積圈數 + 2 bytes 時間
        wheel_revs = int.from_bytes(data[offset:offset+4], byteorder='little')
        offset += 4
        wheel_time = int.from_bytes(data[offset:offset+2], byteorder='little')
        offset += 2
        process_data("Speed/Wheel", wheel_revs, wheel_time)

    if crank_present:
        # 踏頻模式：2 bytes 累積圈數 + 2 bytes 時間
        crank_revs = int.from_bytes(data[offset:offset+2], byteorder='little')
        offset += 2
        crank_time = int.from_bytes(data[offset:offset+2], byteorder='little')
        offset += 2
        process_data("Cadence/Crank", crank_revs, crank_time)

def process_data(label, current_rev, current_time):
    global last_rev, last_time
    
    if last_rev != -1 and current_time != last_time:
        # 計算差值 (處理 16-bit 時間溢位)
        rev_delta = (current_rev - last_rev) & 0xFFFF
        time_delta = (current_time - last_time) & 0xFFFF
        
        # 轉換為 RPM (圈每分鐘)
        # 公式: (圈數差 / (時間差 / 1024)) * 60
        rpm = (rev_delta / (time_delta / 1024.0)) * 60
        print(f"[{label}] 累積圈數: {current_rev}, 即時 RPM: {rpm:.2f}")

    last_rev = current_rev
    last_time = current_time

async def main():
    print(f"正在連接 {ADDRESS}...")
    async with BleakClient(ADDRESS) as client:
        print("已連接！開始接收數據 (請轉動感應器)...")
        # 訂閱通知
        await client.start_notify(CSC_MEASUREMENT_UUID, callback)
        # 持續運行 1 分鐘
        await asyncio.sleep(60.0)
        await client.stop_notify(CSC_MEASUREMENT_UUID)

if __name__ == "__main__":
    asyncio.run(main())

```

---

## 6. 解析邏輯說明

* **累積值 (Cumulative):** S3+ 傳回的是「總圈數」，而不是當前的 RPM。你需要記錄上一次收到的值，用  來計算速度。
* **時間單位:** 藍牙標準定義的時間單位是  秒，所以計算時要除以  換回秒。
* **溢位處理:** `last_event_time` 是 16-bit（0-65535），大約每 64 秒會歸零一次。程式碼中的 `& 0xFFFF` 可以處理這種自動溢位的計算。

## 7. 同時連接多顆感測器
* 若有多個 S3+（一個測速、一個測踏頻），同時連接多個設備的做法。
