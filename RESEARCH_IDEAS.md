# ایده‌های پیشرفته برای بهبود سیستم موقعیت‌یابی Wi-Fi

این سند شامل ایده‌های پژوهشی و پیشنهادات برای بهبود سیستم موقعیت‌یابی داخلی بر اساس Wi-Fi Fingerprinting است.

## 🎯 مشکلات فعلی و راه‌حل‌ها

### 1. مشکل تشخیص مکان جدید
**مشکل**: هنگامی که کاربر به مکان جدیدی می‌رود که قبلاً اثرانگشتی از آن ثبت نشده، سیستم به‌اشتباه موقعیت را نزدیک به خانه (یا مکان قبلی) تخمین می‌زند.

**راه‌حل پیاده‌سازی شده**:
- ✅ سیستم تشخیص اطمینان (`LocationConfidenceService`)
- ✅ مقایسه GPS با KNN برای تشخیص مکان جدید
- ✅ بررسی تعداد APهای مشترک
- ✅ هشدار به کاربر در صورت عدم اطمینان

**راه‌حل‌های پیشنهادی برای آینده**:

#### 1.1. Clustering نقاط مرجع
- استفاده از الگوریتم‌های خوشه‌بندی (K-Means, DBSCAN) برای گروه‌بندی اثرانگشت‌ها
- تشخیص اینکه آیا اسکن فعلی در هیچ خوشه‌ای قرار نمی‌گیرد → مکان جدید

```python
from sklearn.cluster import DBSCAN
import numpy as np

# مثال: خوشه‌بندی اثرانگشت‌ها بر اساس BSSIDها
def detect_new_location(current_scan, fingerprints):
    # تبدیل به بردار
    vectors = [fp_to_vector(fp) for fp in fingerprints]
    vectors.append(scan_to_vector(current_scan))
    
    # خوشه‌بندی
    clustering = DBSCAN(eps=50, min_samples=3).fit(vectors)
    
    # بررسی اینکه اسکن فعلی در خوشه جدیدی است یا نه
    if clustering.labels_[-1] == -1:  # -1 = noise/outlier
        return True  # مکان جدید
    return False
```

#### 1.2. استفاده از مدل One-Class SVM
- آموزش یک مدل فقط بر روی اثرانگشت‌های موجود
- اگر اسکن فعلی outlier باشد → مکان جدید

```python
from sklearn.svm import OneClassSVM

model = OneClassSVM(nu=0.1, kernel="rbf", gamma=0.1)
model.fit(fingerprint_vectors)

def is_new_location(scan_vector):
    prediction = model.predict([scan_vector])
    return prediction[0] == -1  # -1 = outlier
```

### 2. جمع‌آوری داده‌های مشارکتی (Crowdsourcing)

#### 2.1. معماری پیشنهادی

```
┌─────────────┐
│   Mobile    │
│    App      │ ──────┐
└─────────────┘       │
                      │
┌─────────────┐       │     ┌──────────────┐
│   Mobile    │ ──────┼────▶│   Backend    │
│    App      │       │     │   Server     │
└─────────────┘       │     └──────────────┘
                      │             │
┌─────────────┐       │             │
│   Mobile    │ ──────┘             │
│    App      │                     │
└─────────────┘                     │
                                    │
                            ┌───────▼────────┐
                            │   Database     │
                            │  (SQLite/     │
                            │   PostgreSQL) │
                            └───────────────┘
```

**ویژگی‌ها**:
- کاربران می‌توانند اثرانگشت‌های خود را به صورت اختیاری به سرور ارسال کنند
- سرور اثرانگشت‌ها را ترکیب و پردازش می‌کند
- کاربران می‌توانند اثرانگشت‌های محلی را دانلود کنند
- حفظ حریم خصوصی: فقط BSSID و RSSI (بدون GPS دقیق)

#### 2.2. API Backend پیشنهادی

```dart
// Endpoints پیشنهادی
class CrowdsourcingAPI {
  // ارسال اثرانگشت (اختیاری)
  Future<bool> uploadFingerprint(FingerprintEntry fp) async {
    // POST /api/fingerprints
    // Body: { bssids: [...], rssis: [...], zone_label: "...", approximate_location: {...} }
  }
  
  // دانلود اثرانگشت‌های محلی
  Future<List<FingerprintEntry>> downloadLocalFingerprints(double lat, double lon, double radiusKm) async {
    // GET /api/fingerprints?lat=...&lon=...&radius=...
  }
  
  // دریافت آمار کلی
  Future<Map<String, dynamic>> getStatistics() async {
    // GET /api/statistics
  }
}
```

### 3. مدل‌سازی محیط با گراف (Graph-based Modeling)

#### 3.1. ساختار گراف پیشنهادی

```
Nodes (گره‌ها):
- Zone Node: هر ناحیه/اتاق (مثلاً "راهرو طبقه 2", "اتاق 101")
- WiFi AP Node: هر نقطه دسترسی Wi-Fi (BSSID)

Edges (یال‌ها):
- Zone → Zone: احتمال حرکت از یک ناحیه به ناحیه دیگر (Transition Probability)
- Zone → AP: قدرت سیگنال متوسط AP در آن ناحیه (RSSI)
- AP → AP: هم‌زمانی (چه APهایی معمولاً با هم دیده می‌شوند)
```

#### 3.2. مثال کد Python با NetworkX

```python
import networkx as nx
import numpy as np

class WiFiGraphModel:
    def __init__(self):
        self.graph = nx.DiGraph()  # Directed Graph
        
    def add_zone(self, zone_id, label):
        """افزودن یک ناحیه به گراف"""
        self.graph.add_node(zone_id, type='zone', label=label)
        
    def add_wifi_ap(self, bssid):
        """افزودن یک AP به گراف"""
        self.graph.add_node(bssid, type='ap')
        
    def add_transition(self, from_zone, to_zone, probability):
        """افزودن احتمال انتقال از یک ناحیه به ناحیه دیگر"""
        self.graph.add_edge(from_zone, to_zone, 
                          weight=probability, 
                          type='transition')
        
    def add_zone_ap_connection(self, zone_id, bssid, avg_rssi):
        """افزودن ارتباط بین ناحیه و AP"""
        self.graph.add_edge(zone_id, bssid, 
                          weight=avg_rssi, 
                          type='signal')
        
    def predict_next_zone(self, current_zone, observed_aps):
        """پیش‌بینی ناحیه بعدی بر اساس ناحیه فعلی و APهای مشاهده شده"""
        # 1. پیدا کردن همسایه‌های ناحیه فعلی
        neighbors = list(self.graph.neighbors(current_zone))
        
        # 2. فیلتر کردن فقط انتقال‌ها (نه APها)
        transitions = [n for n in neighbors 
                      if self.graph[current_zone][n].get('type') == 'transition']
        
        # 3. محاسبه احتمال بر اساس:
        #    - احتمال انتقال مستقیم
        #    - تطابق APهای مشاهده شده با APهای ناحیه هدف
        scores = {}
        for next_zone in transitions:
            transition_prob = self.graph[current_zone][next_zone]['weight']
            
            # محاسبه تطابق APها
            zone_aps = [n for n in self.graph.neighbors(next_zone) 
                       if self.graph[next_zone][n].get('type') == 'signal']
            observed_bssids = {ap['bssid'] for ap in observed_aps}
            zone_bssids = set(zone_aps)
            ap_match_ratio = len(observed_bssids & zone_bssids) / max(len(zone_bssids), 1)
            
            # ترکیب احتمال انتقال و تطابق AP
            scores[next_zone] = transition_prob * 0.7 + ap_match_ratio * 0.3
            
        # بازگرداندن ناحیه با بیشترین امتیاز
        if scores:
            return max(scores, key=scores.get)
        return None

# مثال استفاده
model = WiFiGraphModel()

# افزودن ناحیه‌ها
model.add_zone("zone1", "راهرو طبقه 2")
model.add_zone("zone2", "اتاق 101")
model.add_zone("zone3", "راهرو طبقه 1")

# افزودن انتقال‌ها (بر اساس تاریخچه حرکت)
model.add_transition("zone1", "zone2", 0.6)  # 60% احتمال حرکت از راهرو به اتاق 101
model.add_transition("zone2", "zone1", 0.4)
model.add_transition("zone1", "zone3", 0.3)

# افزودن APها و ارتباط‌ها
model.add_wifi_ap("aa:bb:cc:dd:ee:ff")
model.add_zone_ap_connection("zone1", "aa:bb:cc:dd:ee:ff", -65)

# پیش‌بینی
predicted_zone = model.predict_next_zone("zone1", [{"bssid": "aa:bb:cc:dd:ee:ff", "rssi": -67}])
print(f"Predicted next zone: {predicted_zone}")
```

#### 3.3. الگوریتم‌های گراف پیشنهادی

1. **PageRank برای پیدا کردن نقاط مهم**
   - کدام ناحیه‌ها بیشترین ترافیک را دارند
   - کدام APها بیشترین تأثیر را دارند

2. **Shortest Path برای پیدا کردن کوتاه‌ترین مسیر**
   - با استفاده از Dijkstra یا A* برای پیدا کردن کوتاه‌ترین مسیر بین دو ناحیه

3. **Community Detection برای پیدا کردن مناطق مشابه**
   - پیدا کردن ناحیه‌هایی که الگوی Wi-Fi مشابه دارند

### 4. بهبود الگوریتم KNN

#### 4.1. Weighted KNN با فاصله جغرافیایی

```python
def weighted_knn_with_geo(scan, fingerprints, k=3):
    distances = []
    
    for fp in fingerprints:
        # فاصله Wi-Fi
        wifi_distance = euclidean_distance(scan, fp)
        
        # اگر GPS در دسترس است، فاصله جغرافیایی را هم در نظر بگیر
        if has_gps(scan) and has_gps(fp):
            geo_distance = haversine_distance(
                scan.gps_lat, scan.gps_lon,
                fp.lat, fp.lon
            )
            
            # ترکیب فاصله Wi-Fi و جغرافیایی
            # اگر فاصله جغرافیایی زیاد است، وزن را کاهش بده
            if geo_distance > 1000:  # بیش از 1 کیلومتر
                wifi_distance *= 1.5  # افزایش فاصله (کاهش وزن)
        
        distances.append((wifi_distance, fp))
    
    # انتخاب k نزدیک‌ترین
    distances.sort(key=lambda x: x[0])
    k_nearest = distances[:k]
    
    # محاسبه موقعیت با وزن معکوس فاصله
    total_weight = sum(1 / (d[0] + 1) for d in k_nearest)
    lat = sum(fp.lat * (1 / (d[0] + 1)) for d, fp in k_nearest) / total_weight
    lon = sum(fp.lon * (1 / (d[0] + 1)) for d, fp in k_nearest) / total_weight
    
    return lat, lon
```

#### 4.2. Adaptive K (انتخاب خودکار k)

```python
def adaptive_k(scan, fingerprints, max_k=10):
    """انتخاب خودکار k بر اساس کیفیت همسایه‌ها"""
    distances = sorted([(euclidean_distance(scan, fp), fp) for fp in fingerprints])
    
    k = 3  # شروع با k=3
    best_k = k
    best_score = -1
    
    for candidate_k in range(3, min(max_k, len(distances)) + 1):
        k_nearest = distances[:candidate_k]
        
        # محاسبه نمره کیفیت
        avg_distance = sum(d[0] for d in k_nearest) / candidate_k
        std_distance = np.std([d[0] for d in k_nearest])
        
        # نمره بهتر = فاصله کمتر + یکنواختی بیشتر
        score = 1 / (avg_distance + std_distance)
        
        if score > best_score:
            best_score = score
            best_k = candidate_k
        else:
            # اگر نمره بدتر شد، توقف
            break
    
    return best_k
```

### 5. پیش‌بینی مسیر با مدل‌های پیشرفته

#### 5.1. LSTM برای پیش‌بینی توالی مسیر

```python
from tensorflow import keras
from tensorflow.keras import layers

def build_lstm_path_predictor(input_dim=20, sequence_length=10):
    """ساخت مدل LSTM برای پیش‌بینی ناحیه بعدی"""
    model = keras.Sequential([
        layers.LSTM(64, return_sequences=True, input_shape=(sequence_length, input_dim)),
        layers.Dropout(0.2),
        layers.LSTM(32, return_sequences=False),
        layers.Dropout(0.2),
        layers.Dense(32, activation='relu'),
        layers.Dense(num_zones, activation='softmax')  # احتمال هر ناحیه
    ])
    
    model.compile(
        optimizer='adam',
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )
    
    return model

# آماده‌سازی داده
def prepare_sequences(path_history, sequence_length=10):
    """تبدیل تاریخچه مسیر به توالی‌های آموزشی"""
    X, y = [], []
    
    for i in range(len(path_history) - sequence_length):
        # ورودی: توالی 10 ناحیه قبلی
        seq = path_history[i:i+sequence_length]
        
        # خروجی: ناحیه بعدی
        next_zone = path_history[i+sequence_length]
        
        X.append([zone_to_vector(z) for z in seq])
        y.append(zone_to_one_hot(next_zone))
    
    return np.array(X), np.array(y)
```

#### 5.2. Attention Mechanism برای تمرکز روی ناحیه‌های مهم

```python
class AttentionPathPredictor(keras.Model):
    def __init__(self, num_zones, embedding_dim=64):
        super().__init__()
        self.embedding = layers.Embedding(num_zones, embedding_dim)
        self.lstm = layers.LSTM(64, return_sequences=True)
        self.attention = layers.Attention()
        self.dense = layers.Dense(num_zones, activation='softmax')
        
    def call(self, inputs):
        x = self.embedding(inputs)
        x = self.lstm(x)
        x = self.attention([x, x])  # Self-attention
        x = tf.reduce_mean(x, axis=1)  # Global average pooling
        return self.dense(x)
```

### 6. ایده‌های پژوهشی دیگر

#### 6.1. Transfer Learning بین ساختمان‌های مختلف
- استفاده از مدل آموزش داده شده در یک ساختمان برای ساختمان دیگر
- Fine-tuning با داده‌های کم

#### 6.2. Federated Learning
- آموزش مدل به صورت توزیع‌شده روی دستگاه‌های مختلف کاربران
- حفظ حریم خصوصی: داده‌ها هرگز دستگاه را ترک نمی‌کنند

#### 6.3. Multi-Modal Fusion
- ترکیب Wi-Fi با داده‌های دیگر:
  - سنسورهای حرکتی (Accelerometer, Gyroscope) - البته شما گفتید نمی‌خواهید
  - فشارسنج (Barometer) برای تشخیص طبقه
  - بلوتوث Beacons

#### 6.4. Real-Time Adaptation
- تطبیق مدل با تغییرات محیط (مثلاً تغییر مکان روترها)
- Online Learning

## 📊 معیارهای ارزیابی پیشنهادی

1. **Mean Localization Error (MLE)**
   - میانگین فاصله بین موقعیت واقعی و تخمین‌شده

2. **90th Percentile Error**
   - 90% تخمین‌ها در چه فاصله‌ای از موقعیت واقعی هستند

3. **Zone Classification Accuracy**
   - درصد مواردی که ناحیه درست تشخیص داده شده

4. **Path Prediction Accuracy**
   - درصد پیش‌بینی‌های درست مسیر

## 🔬 آزمایش‌های پیشنهادی

1. **مقایسه KNN با مدل‌های دیگر**
   - Random Forest
   - Neural Network
   - Gaussian Process Regression

2. **تأثیر تعداد اثرانگشت‌ها**
   - آزمایش با تعداد‌های مختلف اثرانگشت (10, 50, 100, 500)

3. **تأثیر فاصله نقاط مرجع**
   - آزمایش با فاصله‌های مختلف (1m, 2m, 5m)

4. **مقاومت در برابر تغییرات محیط**
   - حذف یک AP و مشاهده تأثیر
   - تغییر قدرت سیگنال‌ها

## 📝 منابع و مراجع

1. **WiFi Fingerprinting**:
   - Youssef, M., & Agrawala, A. (2005). "The Horus location determination system"

2. **Graph-based Approaches**:
   - Liu, H., et al. (2007). "Survey of wireless indoor positioning techniques and systems"

3. **Machine Learning for Localization**:
   - Zheng, V. W., et al. (2013). "Trajectory-based mobile phone localization"

4. **Crowdsourcing**:
   - Rai, A., et al. (2012). "Zee: Zero-effort crowdsourcing for indoor localization"

---

**نکته**: این ایده‌ها برای پروژه‌های آینده و بهبود سیستم هستند. می‌توانید به تدریج آن‌ها را پیاده‌سازی کنید.




