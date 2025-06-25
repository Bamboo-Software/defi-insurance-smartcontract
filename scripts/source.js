// Nhận args[0] = lat, args[1] = lon
const lat = args[0];
const lon = args[1];

const apiKey = secrets.apiKey;

// Gọi API realtime từ Tomorrow.io
const apiResponse = await Functions.makeHttpRequest({
  url: `https://api.tomorrow.io/v4/weather/realtime`,
  params: {
    location: `${lat},${lon}`,
    apikey: apiKey,
  },
});

// Check lỗi
if (apiResponse.error) {
  console.error("❌ Request failed:", apiResponse.error);
  throw Error("Request failed");
}

const weather = apiResponse.data?.data?.values;

if (!weather) {
  throw Error("No weather data received");
}

const essentialData = {
  temperature: weather.temperature,
  rainIntensity: weather.rainIntensity,
  precipitationProbability: weather.precipitationProbability,
  humidity: weather.humidity,
  windSpeed: weather.windSpeed,
  timestamp: apiResponse.data?.data?.time,
};

// Log full object ra console (useful for simulation)
console.log("✅ Weather data:", JSON.stringify(essentialData, null, 2));

// Trả về toàn bộ `values` dưới dạng JSON string (encoded)
return Functions.encodeString(JSON.stringify(essentialData));
