# MyPages

---

## 🧩 系統架構概覽

```
[ Phone / Tablet / PC ]
           │
           ▼
      MyPages
   (Family Portal)
           │
 ┌─────────┴─────────┐
 │                   │
 ▼                   ▼
Local Server        NAS
(Content & AI)   (Family Memory)
```

### Local Server（家庭內容核心）

* Wikipedia / Wiki Mirror
* 國際新聞（如 CNA Singapore）
* 本地 AI 模型（解釋、摘要、連結知識）
* 學習型遊戲 / 模擬器
* 卡通與教學影片

### NAS（家庭記憶庫）

* 家庭照片
* 音樂
* 長期保存資料


## 🛠️ 技術

* Docker / Docker Compose
* Local-first Web App
* 可插拔內容模組
* API / Feed 設計（RSS++ / JSON）
