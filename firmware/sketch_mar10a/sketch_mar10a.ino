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

const int gasThreshold = 1000;
const int fanSpinDuration = 10000;

volatile bool readFlag = false;   

int gas = 0;
float temperature = 0;
float humidity = 0;

bool fanSpinActive = false;
unsigned long fanStartTime = 0;
unsigned long lastSend = 0;

hw_timer_t *timer = NULL;

DHT dht(DHTPIN, DHTTYPE);

void IRAM_ATTR onTimer() {
  readFlag = true;
}

void setup() {
  pinMode(fanPin, OUTPUT);
  pinMode(MQ135, INPUT);
  dht.begin();
  Serial.begin(115200);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nConnected!");

  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  auth.user.email = EMAIL;
  auth.user.password = PASSWORD;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  timer = timerBegin(0, 80, true);
  timerAttachInterrupt(timer, &onTimer, true);
  timerAlarmWrite(timer, 1000000, true);
  timerAlarmEnable(timer);
}

void sendUpTime() {
  json.clear();

  json.set("temperature", temperature);
  json.set("humidity", humidity);
  json.set("gas", gas);

  if (Firebase.setJSON(firebaseData, "/esp32", json)) {
    Serial.println("Firebase OK");
  } else {
    Serial.println("Firebase FAILED");
    Serial.println(firebaseData.errorReason().c_str());
  }
}

void loop() {

  if (readFlag) {
    readFlag = false;

    gas = analogRead(MQ135);
    temperature = dht.readTemperature();
    humidity = dht.readHumidity();

    Serial.print("Gas: "); Serial.println(gas);
    Serial.print("Temp: "); Serial.println(temperature);
    Serial.print("Humidity: "); Serial.println(humidity);

    if (gas > gasThreshold && !fanSpinActive) {
      digitalWrite(fanPin, HIGH);
      fanSpinActive = true;
      fanStartTime = millis();
    }
  }

  if (fanSpinActive && millis() - fanStartTime >= fanSpinDuration) {
    digitalWrite(fanPin, LOW);
    fanSpinActive = false;
  }

  if (millis() - lastSend > 1000) {
    lastSend = millis();
    sendUpTime();
  }
}