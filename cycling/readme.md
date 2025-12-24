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
