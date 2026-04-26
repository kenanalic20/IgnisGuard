#include <DHT.h>
#include <WiFi.h>
#include <FirebaseESP32.h>
#include "secrets.h"

#define fanPin 14
#define MQ135 34
#define DHTPIN 4
#define DHTTYPE DHT22

FirebaseData firebaseData;
FirebaseConfig config;
FirebaseAuth auth;
FirebaseJson json;

const int gasThreshold = 900;
const int fanSpinDuration = 10000;

float gasBaseline = 2000.0;
float gasMax = 3500.0;

int gas = 0;
float temperature = 0;
float humidity = 0;

volatile bool fanSpinActive = false;
volatile unsigned long fanStartTime = 0;

// ✅ SAFE ISR FLAG
volatile bool readGasFlag = false;

hw_timer_t *timer = NULL;
unsigned long lastSend = 0;

DHT dht(DHTPIN, DHTTYPE);


// 🔧 GAS MAPPING
int mapGas(float gasRaw) {
  float normalized = (gasRaw - gasBaseline) / (gasMax - gasBaseline);

  if (normalized < 0) normalized = 0;
  if (normalized > 1) normalized = 1;

  return 200 + normalized * (1500 - 200);
}



// ✅ SAFE ISR (ONLY FLAG)
void IRAM_ATTR onTimer() {
  readGasFlag = true;
}


void setup() {
  pinMode(fanPin, OUTPUT);
  pinMode(MQ135, INPUT);

  Serial.begin(115200);
  dht.begin();

  // 🔌 WiFi connect
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nWiFi connected!");

  // 🔥 Firebase config
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  auth.user.email = EMAIL;
  auth.user.password = PASSWORD;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  // ⏱️ Timer setup (1 sec)
  timer = timerBegin(0, 80, true);
  timerAttachInterrupt(timer, &onTimer, true);
  timerAlarmWrite(timer, 1000000, true); // 1s
  timerAlarmEnable(timer);
}


// 📡 SEND DATA
void sendUpTime() {

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi not connected!");
    return;
  }

  if (!Firebase.ready()) {
    Serial.println("Firebase not ready!");
    return;
  }

  json.clear();

  json.set("temperature", temperature);
  json.set("humidity", humidity);
  json.set("gas", mapGas(gas));
  json.set("gas_raw", gas); // debug

  Serial.println("Sending to Firebase...");

  if (Firebase.setJSON(firebaseData, "/esp32", json)) {
    Serial.println("Firebase OK");
  } else {
    Serial.println("Firebase FAILED");
    Serial.println(firebaseData.errorReason());
  }
}


void loop() {

  // ✅ HANDLE GAS READ OUTSIDE ISR
  if (readGasFlag) {
    readGasFlag = false;

    gas = analogRead(MQ135);

    if (mapGas(gas) > gasThreshold) {
      digitalWrite(fanPin, HIGH);
      fanSpinActive = true;
      fanStartTime = millis();
    }
  }

  // 🌡️ Read sensors
  temperature = dht.readTemperature();
  humidity = dht.readHumidity();

  // 📤 Send every 5 sec
  if (millis() - lastSend > 1500) {

    Serial.print("Raw Gas: ");
    Serial.print(gas);

    Serial.print(" | Mapped: ");
    Serial.println(mapGas(gas));

    Serial.print("Baseline Gas: ");
    Serial.println(gasBaseline);

    if (isnan(temperature) || isnan(humidity)) {
      Serial.println("DHT read failed!");
    } else {
      Serial.print("Temp: ");
      Serial.println(temperature);

      Serial.print("Humidity: ");
      Serial.println(humidity);
    }

    sendUpTime();
    lastSend = millis();
  }

  // 🌀 Fan control
  if (fanSpinActive) {
    unsigned long currentMillis = millis();
    if (currentMillis - fanStartTime >= fanSpinDuration) {
      digitalWrite(fanPin, LOW);
      fanSpinActive = false;
    }
  }

  // 🔁 WiFi auto-reconnect
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Reconnecting WiFi...");
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  }
}