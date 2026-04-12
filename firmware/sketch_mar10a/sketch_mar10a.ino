#include <DHT.h>
#include<WiFi.h>
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

const int gasThreshold = 1500;
const int fanSpinDuration = 10000;

int gas = 0;
float temperature = 0;
float humidity = 0;

volatile bool fanSpinActive = false;
volatile unsigned long fanStartTime = 0;
hw_timer_t *timer = NULL;

DHT dht(DHTPIN, DHTTYPE);

void IRAM_ATTR onTimer() {
  gas = analogRead(MQ135);
  if (gas > gasThreshold) {
    digitalWrite(fanPin, HIGH);
    fanSpinActive = true;
    fanStartTime = millis();
  }
}



void setup() {
  pinMode(fanPin, OUTPUT);
  pinMode(MQ135, INPUT);
  dht.begin();
  Serial.begin(115200);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  auth.user.email = EMAIL;
  auth.user.password = PASSWORD;
  Firebase.begin(&config,&auth);
  Firebase.reconnectWiFi(true);
  
  timer = timerBegin(0, 80, true);
  timerAttachInterrupt(timer, &onTimer, true);
  timerAlarmWrite(timer, 1000, true);
  timerAlarmEnable(timer);
}
void sendUpTime() {
  json.clear();

  json.set("temperature", temperature);
  json.set("humidity", humidity);
  json.set("gas", gas);

  Serial.println("Preparing to send data to Firebase...");

  String jsonStr;
  json.toString(jsonStr, true); 

  if (Firebase.setJSON(firebaseData, "/esp32", json)) {
    Serial.println("Firebase OK");
  } else {
    Serial.println("Firebase FAILED");
    String err = firebaseData.errorReason().c_str();
    Serial.println(err);
  }
}
void loop() {
  delay(1000);
  Serial.print("Gas: ");
  Serial.println(gas);
  delay(1000);  //for debug
  temperature = dht.readTemperature();
  humidity = dht.readHumidity();
  if (isnan(temperature) || isnan(humidity)) {
    Serial.println("DHT read failed!");
  } else {
    Serial.print("Temp: ");
    Serial.println(temperature);

    Serial.print("Humidity: ");
    Serial.println(humidity);
  }
  sendUpTime();
  if (fanSpinActive) {
    unsigned long currentMillis = millis();
    if (currentMillis - fanStartTime >= fanSpinDuration) {
      digitalWrite(fanPin, LOW);
      fanSpinActive = false;
    }
  }
 
  
}