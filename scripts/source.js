// Nhận args[0] = lat, args[1] = lon
const lat = parseFloat(args[0]);
const lng = parseFloat(args[1]);
const apiKey = 'g4u1LPihSPyhQ8GNqnCapQ6LOPQE3W1D';

// Gọi API realtime từ Tomorrow.io
const apiResponse = await Functions.makeHttpRequest({
  url: `https://api.tomorrow.io/v4/weather/realtime`,
  params: {
    location: `${lat},${lng}`,
    apikey: apiKey,
  },
});

// Check lỗi
if (apiResponse.error) {
  const errorDetails = JSON.stringify(apiResponse, null, 2);
  console.error('Request failed:', errorDetails);
  throw Error(`Request failed: ${errorDetails}`);
}

const weather = apiResponse.data?.data?.values;

if (!weather) {
  throw Error('No weather data received');
}

const essentialData = {
  lat,
  lng,
  temperature: weather.temperature,
  rainIntensity: weather.rainIntensity,
  precipitationProbability: weather.precipitationProbability,
  humidity: weather.humidity,
  windSpeed: weather.windSpeed,
  timestamp: apiResponse.data?.data?.time,
};

// Log full object ra console (useful for simulation)
console.log('Weather data:', JSON.stringify(essentialData, null, 2));

// Trả về toàn bộ `values` dưới dạng JSON string (encoded)
return Functions.encodeString(JSON.stringify(essentialData));
