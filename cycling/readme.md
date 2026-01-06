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

假設同時連接 8 個 Magene S3+ 感應器，最核心的挑戰在於 **「併發處理 (Concurrency)」** 以及 **「藍牙硬體限制」**。

在 Ubuntu 上，我們依然使用 `bleak` 配合 `asyncio`。為了管理 8 個設備，建議使用 **物件導向 (OOP)** 的方式，為每個感應器建立獨立的實例來維護各自的狀態（如上一次的圈數與時間）。

### 藍牙硬體重要提醒

一般的筆電內建藍牙晶片通常只能穩定連接 **5 到 7 個** 設備。要同時連接 8 個感應器，建議：

1. 使用高品質的 **藍牙 5.0 (或以上) USB 接收器**。
2. 如果連線不穩定，可能需要插兩個藍牙接收器（Ubuntu 的 BlueZ 支援多網卡管理）。

---

### 多設備連接程式範例

```python
import asyncio
import struct
from bleak import BleakClient, BleakScanner

# 標準 CSC UUID
CSC_MEASUREMENT_UUID = "00002a5b-0000-1000-8000-00805f9b34fb"

class MageneSensor:
    def __init__(self, name, address, sensor_type):
        self.name = name          # 例如: Bike1_Speed
        self.address = address
        self.type = sensor_type   # 'speed' 或 'cadence'
        self.last_rev = -1
        self.last_time = -1
        self.client = None

    def notification_handler(self, sender, data):
        flags = data[0]
        offset = 1
        
        # 解析邏輯
        wheel_present = flags & 0x01
        crank_present = flags & 0x02

        current_rev = -1
        current_time = -1

        if self.type == 'speed' and wheel_present:
            current_rev = int.from_bytes(data[offset:offset+4], byteorder='little')
            current_time = int.from_bytes(data[offset+4:offset+6], byteorder='little')
        elif self.type == 'cadence' and crank_present:
            current_rev = int.from_bytes(data[offset:offset+2], byteorder='little')
            current_time = int.from_bytes(data[offset+2:offset+4], byteorder='little')

        if current_rev != -1:
            self.calculate_metrics(current_rev, current_time)

    def calculate_metrics(self, rev, time):
        if self.last_rev != -1 and time != self.last_time:
            rev_delta = (rev - self.last_rev) & (0xFFFFFFFF if self.type == 'speed' else 0xFFFF)
            time_delta = (time - self.last_time) & 0xFFFF
            
            # 物理公式計算 RPM
            # $RPM = \frac{\Delta Revolutions}{\Delta Time / 1024} \times 60$
            rpm = (rev_delta / (time_delta / 1024.0)) * 60
            
            unit = "RPM (踏頻)" if self.type == 'cadence' else "RPM (輪轉速)"
            print(f"[{self.name}] {unit}: {rpm:.2f}")

        self.last_rev = rev
        self.last_time = time

    async def connect_and_run(self):
        print(f"嘗試連接 {self.name} ({self.address})...")
        async with BleakClient(self.address) as client:
            self.client = client
            print(f"成功連接 {self.name}")
            await client.start_notify(CSC_MEASUREMENT_UUID, self.notification_handler)
            
            # 保持連線，直到被外部取消
            while True:
                await asyncio.sleep(1)

async def main():
    # 1. 定義你的 8 個設備清單 (請填入實際的 MAC Address)
    device_configs = [
        {"name": "Bike1_SPD", "addr": "D1:00:00:00:00:01", "type": "speed"},
        {"name": "Bike1_CAD", "addr": "D1:00:00:00:00:02", "type": "cadence"},
        {"name": "Bike2_SPD", "addr": "D1:00:00:00:00:03", "type": "speed"},
        {"name": "Bike2_CAD", "addr": "D1:00:00:00:00:04", "type": "cadence"},
        {"name": "Bike3_SPD", "addr": "D1:00:00:00:00:05", "type": "speed"},
        {"name": "Bike3_CAD", "addr": "D1:00:00:00:00:06", "type": "cadence"},
        {"name": "Bike4_SPD", "addr": "D1:00:00:00:00:07", "type": "speed"},
        {"name": "Bike4_CAD", "addr": "D1:00:00:00:00:08", "type": "cadence"},
    ]

    # 2. 建立實例
    sensors = [MageneSensor(d["name"], d["addr"], d["type"]) for d in device_configs]

    # 3. 使用 asyncio.gather 同時啟動所有連線任務
    tasks = [sensor.connect_and_run() for sensor in sensors]
    
    try:
        await asyncio.gather(*tasks)
    except Exception as e:
        print(f"發生錯誤: {e}")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("程式已手動停止")

```

---

### 解析與優化建議

#### 1. 速度模式的 RPM 轉換

在程式碼中，速度模式算出來的是「輪圈每分鐘轉速 (Wheel RPM)」。若要換算成 **公里/小時 (km/h)**，你需要知道輪胎的周長（例如 700c 輪胎約 2.1 公尺）：


#### 2. 容錯機制 (Reconnection)

在健身房環境中，人體和設備多，藍牙容易斷線。建議在 `connect_and_run` 中加入一個 `while True` 迴圈與 `try-except`，當連線斷開時自動重試：

```python
async def connect_and_run(self):
    while True:
        try:
            async with BleakClient(self.address) as client:
                # ... 訂閱與運行邏輯 ...
        except Exception:
            print(f"{self.name} 斷線，3秒後重試...")
            await asyncio.sleep(3)

```

#### 3. 資料儲存

由於有 8 個設備，終端機噴出的文字會非常快。建議將資料導向 **CSV 檔案** 或 **MQTT Broker**。

* **MQTT:** 非常適合多設備監控，你可以將數據發送到一個 Dashboard（如 Node-RED）來即時觀察 4 台車的狀況。


---

# Magene S3 + **Node-RED** + **MQTT (Message Queuing Telemetry Transport)** 

Python 腳本負責與藍牙硬體溝通（生產者），MQTT Broker 負責轉發訊息（郵局），而 Node-RED 則負責接收並顯示數據（消費者）。

---

## 1. 架構設計

* **Ubuntu 主機**：運行所有服務。
* **Mosquitto**：作為 MQTT Broker，負責在中途傳遞數據。
* **Python 腳本**：連接 8 個 S3+，將解析出的 RPM 轉成 JSON 格式發送到 MQTT Topic。
* **Node-RED**：訂閱這些 Topic，並製作成圖表。

---

## 2. 安裝必要套件

在 Ubuntu 上安裝 MQTT Broker 與 Python 函式庫：

```bash
# 安裝 Mosquitto Broker
sudo apt update
sudo apt install mosquitto mosquitto-clients

# 安裝 Python MQTT 函式庫
pip install paho-mqtt

```

---

## 3. 修改 Python 程式碼 (發送到 MQTT)

我們在原本的類別中加入 MQTT 發送功能。建議 Topic 命名規則為：`fitness/bike{ID}/{type}`。

```python
import asyncio
import json
import paho.mqtt.client as mqtt
from bleak import BleakClient

# MQTT 設定
MQTT_BROKER = "localhost"
MQTT_PORT = 1883

class MageneSensor:
    def __init__(self, bike_id, sensor_type, address, mqtt_client):
        self.bike_id = bike_id      # 車號: 1, 2, 3, 4
        self.type = sensor_type     # 'speed' 或 'cadence'
        self.address = address
        self.mqtt_client = mqtt_client
        self.last_rev = -1
        self.last_time = -1
        # 定義 MQTT Topic
        self.topic = f"fitness/bike{self.bike_id}/{self.type}"

    def calculate_metrics(self, rev, time):
        if self.last_rev != -1 and time != self.last_time:
            rev_delta = (rev - self.last_rev) & (0xFFFFFFFF if self.type == 'speed' else 0xFFFF)
            time_delta = (time - self.last_time) & 0xFFFF
            rpm = (rev_delta / (time_delta / 1024.0)) * 60

            # 封裝成 JSON 格式
            payload = {
                "bike_id": self.bike_id,
                "type": self.type,
                "value": round(rpm, 2),
                "unit": "RPM"
            }
            # 發送到 MQTT
            self.mqtt_client.publish(self.topic, json.dumps(payload))
            print(f"發送至 {self.topic}: {payload}")

        self.last_rev = rev
        self.last_time = time

    # ... (其餘連線與 notification_handler 邏輯同前一版本) ...

async def main():
    # 初始化 MQTT
    mqtt_c = mqtt.Client()
    mqtt_c.connect(MQTT_BROKER, MQTT_PORT, 60)
    mqtt_c.loop_start()

    device_configs = [
        {"id": 1, "type": "speed", "addr": "D1:XX:XX:XX:XX:01"},
        {"id": 1, "type": "cadence", "addr": "D1:XX:XX:XX:XX:02"},
        # ... 依此類推列出 8 個 ...
    ]

    sensors = [MageneSensor(d["id"], d["type"], d["addr"], mqtt_c) for d in device_configs]
    tasks = [sensor.connect_and_run() for sensor in sensors]
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())

```

---

## 4. Node-RED 配置步驟

1. **安裝 Node-RED** (如果還沒安裝)：
```bash
sudo npm install -g --unsafe-perm node-red
node-red  # 啟動後開啟瀏覽器 http://localhost:1880

```


2. **安裝 Dashboard 節點**：
在 Node-RED 右上角選單 -> `Manage palette` -> 搜尋並安裝 `node-red-dashboard`。
3. **拉取節點**：
* **mqtt in**：設定 Server 為 `localhost`，Topic 設為 `fitness/+/+` (使用萬用字元一次接收所有車輛數據)。
* **json**：將收到的字串轉回 JavaScript 物件。
* **switch**：根據 `msg.payload.bike_id` 將數據分流到不同車輛的顯示區。
* **ui chart / ui gauge**：將數據拉到儀表板上顯示。



---

## 5. 進階視覺化建議

在 Node-RED Dashboard 中，你可以設計一個 2x2 的網格，每格代表一台車，內含兩個儀表（時速與踏頻）。

* **即時監控**：使用 **Gauge (儀表板)** 顯示當前踏頻，如果低於 60 RPM 可以變色警告。
* **歷史趨勢**：使用 **Chart (折線圖)** 記錄過去 10 分鐘的運動強度。
* **數據存檔**：你可以多拉一條線到 `file` 節點或 `influxdb` 節點，將 4 台車的運動數據存下來做後續分析。

### 這樣配置的好處

* **低延遲**：MQTT 幾乎是同步傳輸，健身者踩踏的變化會立刻反應在螢幕上。
* **穩定性**：如果 Node-RED 重啟，Python 腳本不需要停止；反之亦然。
* **遠端觀看**：只要手機或平板跟 Ubuntu 主機在同一個區域網路，輸入 `http://<Ubuntu_IP>:1880/ui` 就能看到 4 台車的即時數據。


---

## 配置 Node-RED Flow JSON 範例

設定好接收 `fitness/+/+` 的 MQTT 訊息，並將數據分流到 4 台健身車的儀表板上。
### 準備工作

1. 確保已安裝 **Dashboard** 套件：`右上角選單` -> `Manage palette` -> `Install` -> 搜尋 `node-red-dashboard` 並安裝。
2. 確保 MQTT Broker (Mosquitto) 正在運行。

---

### Node-RED Flow JSON

請複製以下代碼，並在 Node-RED 中點選 **右上角選單 (≡) -> Import**，貼上後按下 **Import**。

```json
[
    {
        "id": "f1a1b1c1.node1",
        "type": "mqtt in",
        "z": "a1b2c3d4.flow1",
        "name": "接收單車數據",
        "topic": "fitness/+/+",
        "qos": "2",
        "datatype": "auto-detect",
        "broker": "b1c2d3e4.mqtt_broker",
        "nl": false,
        "rap": true,
        "rh": 0,
        "inputs": 0,
        "x": 130,
        "y": 240,
        "wires": [
            [
                "f2a2b2c2.json_node"
            ]
        ]
    },
    {
        "id": "f2a2b2c2.json_node",
        "type": "json",
        "z": "a1b2c3d4.flow1",
        "name": "",
        "property": "payload",
        "action": "",
        "pretty": false,
        "x": 310,
        "y": 240,
        "wires": [
            [
                "f3a3b3c3.switch_bike"
            ]
        ]
    },
    {
        "id": "f3a3b3c3.switch_bike",
        "type": "switch",
        "z": "a1b2c3d4.flow1",
        "name": "分流車號 (Bike ID)",
        "property": "payload.bike_id",
        "propertyType": "msg",
        "rules": [
            { "t": "eq", "v": "1", "vt": "num" },
            { "t": "eq", "v": "2", "vt": "num" },
            { "t": "eq", "v": "3", "vt": "num" },
            { "t": "eq", "v": "4", "vt": "num" }
        ],
        "checkall": "true",
        "repair": false,
        "outputs": 4,
        "x": 510,
        "y": 240,
        "wires": [
            ["f4a4_b1_type"],
            ["f4a4_b2_type"],
            ["f4a4_b3_type"],
            ["f4a4_b4_type"]
        ]
    },
    {
        "id": "f4a4_b1_type",
        "type": "switch",
        "z": "a1b2c3d4.flow1",
        "name": "B1 類型",
        "property": "payload.type",
        "propertyType": "msg",
        "rules": [
            { "t": "eq", "v": "speed", "vt": "str" },
            { "t": "eq", "v": "cadence", "vt": "str" }
        ],
        "checkall": "true",
        "repair": false,
        "outputs": 2,
        "x": 700,
        "y": 140,
        "wires": [
            ["b1_spd_gauge"],
            ["b1_cad_gauge"]
        ]
    },
    {
        "id": "b1_spd_gauge",
        "type": "ui_gauge",
        "z": "a1b2c3d4.flow1",
        "name": "Bike 1 輪速",
        "group": "bike1_group",
        "order": 1,
        "width": 0,
        "height": 0,
        "gtype": "gage",
        "title": "Bike 1 輪速 (RPM)",
        "label": "RPM",
        "format": "{{value}}",
        "min": 0,
        "max": "200",
        "colors": ["#00b500", "#e6e600", "#ca3838"],
        "seg1": "",
        "seg2": "",
        "x": 910,
        "y": 120,
        "wires": []
    },
    {
        "id": "b1_cad_gauge",
        "type": "ui_gauge",
        "z": "a1b2c3d4.flow1",
        "name": "Bike 1 踏頻",
        "group": "bike1_group",
        "order": 2,
        "width": 0,
        "height": 0,
        "gtype": "gage",
        "title": "Bike 1 踏頻 (RPM)",
        "label": "RPM",
        "format": "{{value}}",
        "min": 0,
        "max": "150",
        "colors": ["#3366ff", "#00b500", "#ca3838"],
        "seg1": "60",
        "seg2": "100",
        "x": 910,
        "y": 160,
        "wires": []
    },
    {
        "id": "b1c2d3e4.mqtt_broker",
        "type": "mqtt-broker",
        "name": "Local Mosquitto",
        "broker": "localhost",
        "port": "1883",
        "clientid": "",
        "usetls": false,
        "compatmode": false,
        "keepalive": "60",
        "cleansession": true,
        "birthTopic": "",
        "birthQos": "0",
        "birthPayload": "",
        "closeTopic": "",
        "closeQos": "0",
        "closePayload": "",
        "willTopic": "",
        "willQos": "0",
        "willPayload": ""
    },
    {
        "id": "bike1_group",
        "type": "ui_group",
        "name": "健身車 1 號",
        "tab": "fitness_tab",
        "order": 1,
        "disp": true,
        "width": "6",
        "collapse": false
    },
    {
        "id": "fitness_tab",
        "type": "ui_tab",
        "name": "即時訓練監控",
        "icon": "dashboard",
        "order": 1
    }
]

```

---

## 解析此 Flow 的運作方式

1. **MQTT In (`fitness/+/+`)**: 使用萬用字元 `+`。這意味著無論是 `bike1/speed` 還是 `bike4/cadence` 都會被同一個節點接收。
2. **JSON Node**: 將 Python 發過來的字串解析成 JavaScript 物件，方便讀取 `msg.payload.value`。
3. **Switch Bike (ID)**: 根據 Python JSON 裡的 `bike_id` 欄位進行分流。
4. **Switch Type**: 將數據細分為「輪速」或「踏頻」。
5. **UI Gauges**:
* **輪速 (Speed)**: 顯示輪胎轉速。
* **踏頻 (Cadence)**: 顯示使用者踩踏頻率，通常會設定區間（例如 60-100 RPM 為綠色健康區）。



---

## 如何擴充與美化

### 1. 複製節點

範例中我只完整寫了 Bike 1 的末端儀表。對於 Bike 2-4，你只需要：

* 選取 `B1 類型` 和兩個 `Gauge`。
* 按下 `Ctrl+C`, `Ctrl+V`。
* 修改 `Switch` 的輸入來源為 `Switch Bike ID` 的第 2, 3, 4 個輸出點。
* 修改 `Gauge` 節點所屬的 **Group**（為每台車建立一個新的 Group）。

### 2. 計算時速 (Speed)

如果你想把輪圈 RPM 換算成 **km/h**，可以在 Speed Gauge 前面加一個 `Function` 節點：

```javascript
// 假設輪胎周長為 2.1 公尺
let wheel_rpm = msg.payload.value;
let speed_kmh = (wheel_rpm * 2.1 * 60) / 1000;
msg.payload = parseFloat(speed_kmh.toFixed(1));
return msg;

```

### 3. 查看儀表板

部署 (Deploy) 後，開啟瀏覽器前往：
`http://你的Ubuntu_IP:1880/ui`
